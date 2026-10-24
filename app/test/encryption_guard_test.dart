import 'dart:convert';
import 'dart:typed_data';

import 'package:chama/auth/id_client.dart';
import 'package:chama/services/chama_client.dart';
import 'package:chama/services/chat_service.dart';
import 'package:chama/services/chat_session.dart';
import 'package:chama/services/delivery.dart';
import 'package:chama/services/event_mapping.dart';
import 'package:chama/services/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matrix/matrix.dart';
// TimelineChunk is not exported, and a Timeline cannot be built without one.
// ignore: implementation_imports
import 'package:matrix/src/models/timeline_chunk.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const me = '@me:chama.test';
const bob = '@bob:chama.test';

/// A room whose timeline is the one the test gives it.
class _FixedRoom extends Room {
  _FixedRoom({required super.id, required super.client}) : super(membership: Membership.join);

  late List<Event> events;

  @override
  Future<Timeline> getTimeline({
    void Function(int index)? onChange,
    void Function(int index)? onRemove,
    void Function(int insertID)? onInsert,
    void Function()? onNewEvent,
    void Function()? onUpdate,
    String? eventContextId,
    int? limit = Room.defaultHistoryCount,
  }) async => Timeline(
    room: this,
    chunk: TimelineChunk(events: events),
  );
}

void main() {
  late List<String> requests; // "METHOD path"
  late ChatService service;
  late ChamaClient client;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    requests = [];
    final server = MockClient((req) async {
      requests.add('${req.method} ${Uri.decodeComponent(req.url.path)}');
      if (req.url.path.endsWith('/keys/query')) {
        return http.Response(jsonEncode({'device_keys': <String, Object>{}}), 200);
      }
      if (req.url.path.endsWith('/members')) {
        return http.Response(
          jsonEncode({
            'chunk': [
              {
                'type': EventTypes.RoomMember,
                'content': {'membership': 'invite'},
                'event_id': r'$m',
                'sender': me,
                'state_key': bob,
                'origin_server_ts': 0,
              },
            ],
          }),
          200,
        );
      }
      if (req.url.path.contains('/join')) return http.Response(jsonEncode({'room_id': '!x:chama.test'}), 200);
      return http.Response(jsonEncode({'event_id': r'$e'}), 200);
    });
    final db = await MatrixSdkDatabase.init(
      'encryption_guard_test',
      database: await databaseFactoryFfi.openDatabase(':memory:'),
      sqfliteFactory: databaseFactoryFfi,
    );
    client = ChamaClient('encryption_guard_test', database: db, httpClient: server)
      ..homeserver = Uri.parse('http://localhost:8080')
      ..accessToken = 'token'
      ..setUserId(me);
    service = ChatService(
      client,
      DeliveryTracker(client, prefs),
      IdClient(Uri.parse('http://localhost:8080')),
      prefs,
      homeserver: Uri.parse('http://localhost:8080'),
    );
  });

  Event state(Room room, String type, Map<String, Object?> content, {String stateKey = ''}) => Event(
    type: type,
    content: content,
    eventId: '\$$type$stateKey',
    senderId: me,
    stateKey: stateKey,
    originServerTs: DateTime(2026),
    room: room,
  );

  Room room(String id, {required Membership membership, required bool encrypted}) {
    final r = Room(id: id, client: client, membership: membership);
    if (encrypted) r.setState(state(r, EventTypes.Encryption, {'algorithm': AlgorithmTypes.megolmV1AesSha2}));
    client.rooms.add(r);
    return r;
  }

  Future<void> sync() async {
    client.onSync.add(SyncUpdate(nextBatch: 'next'));
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }

  test('only invites to encrypted chats are joined', () async {
    room('!plain:chama.test', membership: Membership.invite, encrypted: false);
    room('!e2e:chama.test', membership: Membership.invite, encrypted: true);
    await sync();
    expect(requests.where((r) => r.contains('/join')), [contains('!e2e:chama.test')]);
  });

  test('a joined chat without encryption gets it switched on when I may, and is marked until then', () async {
    room('!plain:chama.test', membership: Membership.join, encrypted: false);
    await sync();
    await sync(); // once per run, not on every sync
    expect(requests.where((r) => r.contains('m.room.encryption')), hasLength(1));
    expect(service.chats.value.single.encrypted, isFalse);
  });

  test('a joined chat without encryption I may not change stays marked and is left alone', () async {
    final r = room('!plain:chama.test', membership: Membership.join, encrypted: false);
    r.setState(
      state(r, EventTypes.RoomPowerLevels, {
        'users': {bob: 100},
        'state_default': 50,
      }),
    );
    await sync();
    expect(requests.where((r) => r.contains('m.room.encryption')), isEmpty);
    expect(service.chats.value.single.encrypted, isFalse);
  });

  test('nothing is sent into a chat without encryption', () async {
    final plain = ChatSession(service, room('!plain:chama.test', membership: Membership.join, encrypted: false));
    expect(plain.encrypted, isFalse);
    await expectLater(plain.sendText('oi'), throwsStateError);
    await expectLater(plain.sendFile(const PickedFile(name: 'a.txt', bytes: [1])), throwsStateError);
    await expectLater(
      plain.sendVoice(bytes: Uint8List(1), mimeType: 'audio/ogg', durationMs: 1, waveform: const []),
      throwsStateError,
    );
    // An encrypted room with the client's encryption off would go out in
    // clear too (the SDK falls back to plaintext).
    final off = ChatSession(service, room('!e2e:chama.test', membership: Membership.join, encrypted: true));
    expect(off.encrypted, isFalse);
    await expectLater(off.sendText('oi'), throwsStateError);
    expect(requests.where((r) => r.contains('/send/')), isEmpty);
  });

  test('typing waits for device lists that are still loading', () async {
    final r = room('!e2e:chama.test', membership: Membership.join, encrypted: true);
    // Bob is invited (the /members answer above). What the sync loop leaves while /keys/query is in flight: an empty,
    // outdated list. The SDK would build the room key without Bob.
    client.userDeviceKeys[bob] = DeviceKeysList(bob, client);
    await ChatSession(service, r).setTyping(true);
    final keys = requests.indexWhere((r) => r.endsWith('/keys/query'));
    final typing = requests.indexWhere((r) => r.contains('/typing/'));
    expect(keys, isNonNegative);
    expect(typing, greaterThan(keys));
  });

  test('signing out drops the chat list and cached avatars', () async {
    room('!e2e:chama.test', membership: Membership.join, encrypted: true);
    await sync();
    expect(service.chats.value, hasLength(1));
    client.onLoginStateChanged.add(LoginState.loggedOut);
    await Future<void>.delayed(Duration.zero);
    expect(service.chats.value, isEmpty);
  });

  test('read receipts skip messages this device cannot decrypt', () {
    final r = room('!e2e:chama.test', membership: Membership.join, encrypted: true);
    Event msg(String id, String type) =>
        Event(type: type, content: const {}, eventId: id, senderId: bob, originServerTs: DateTime(2026), room: r);
    // Newest first, as the timeline keeps them.
    expect(newestReadable([msg(r'$2', EventTypes.Encrypted), msg(r'$1', EventTypes.Message)])?.eventId, r'$1');
    expect(newestReadable([msg(r'$2', EventTypes.Encrypted)]), isNull);
  });

  group('reaction emoji', () {
    Event reaction(String type, Map<String, Object?> content) => Event(
      type: type,
      content: content,
      eventId: r'$r',
      senderId: bob,
      originServerTs: DateTime(2026),
      room: room('!e2e:chama.test', membership: Membership.join, encrypted: true),
    );
    const relates = {'rel_type': RelationshipTypes.reaction, 'event_id': r'$m', 'key': 'placeholder'};

    test('comes from the ciphertext, not the cleartext placeholder', () {
      expect(reactionKey(reaction(EventTypes.Reaction, {'m.relates_to': relates, reactionKeyField: '👍'})), '👍');
    });

    test('of a plaintext reaction is its key', () {
      expect(
        reactionKey(
          reaction(EventTypes.Reaction, {
            'm.relates_to': {...relates, 'key': '❤️'},
          }),
        ),
        '❤️',
      );
    });

    test('is unknown until the reaction decrypts', () {
      expect(reactionKey(reaction(EventTypes.Encrypted, {'m.relates_to': relates})), isNull);
    });
  });

  test('a security code notice sits among the messages by time', () async {
    final r = _FixedRoom(id: '!dm:chama.test', client: client);
    client.rooms.add(r);
    r.setState(state(r, EventTypes.RoomMember, {'membership': 'join'}, stateKey: bob));
    Event msg(String id, DateTime at) => Event(
      type: EventTypes.Message,
      content: {'msgtype': MessageTypes.Text, 'body': id},
      eventId: id,
      senderId: bob,
      originServerTs: at,
      room: r,
    );
    final now = DateTime.now();
    r.events = [msg('new', now.add(const Duration(hours: 1))), msg('old', now.subtract(const Duration(hours: 1)))];
    DeviceKeysList keys(String key) => DeviceKeysList(
      bob,
      client,
      outdated: false,
      crossSigningKeys: {
        key: CrossSigningKey.fromJson({
          'user_id': bob,
          'usage': ['master'],
          'keys': {'ed25519:$key': key},
        }, client),
      },
    );
    client.userDeviceKeys[bob] = keys('KEY1');
    service.securityCodes.check();
    client.userDeviceKeys[bob] = keys('KEY2');
    service.securityCodes.check();

    final session = ChatSession(service, r);
    await session.open();
    expect(session.messages.map((m) => m.systemKind ?? m.body), ['new', SystemKind.securityCodeChanged, 'old']);
    session.dispose();
  });
}
