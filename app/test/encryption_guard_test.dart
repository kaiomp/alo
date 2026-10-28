import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:alo/auth/id_client.dart';
import 'package:alo/services/alo_client.dart';
import 'package:alo/services/chat_service.dart';
import 'package:alo/services/chat_session.dart';
import 'package:alo/services/delivery.dart';
import 'package:alo/services/event_mapping.dart';
import 'package:alo/services/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matrix/encryption.dart';
// OlmManager is not exported; the fake encryption needs one.
// ignore: implementation_imports
import 'package:matrix/encryption/olm_manager.dart';
import 'package:matrix/matrix.dart';
// TimelineChunk is not exported, and a Timeline cannot be built without one.
// ignore: implementation_imports
import 'package:matrix/src/models/timeline_chunk.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const me = '@me:alo.test';
const bob = '@bob:alo.test';

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

/// Encryption that only records when the SDK encrypts (makes the room key).
class _FakeEncryption extends Fake implements Encryption {
  _FakeEncryption(this.log);
  final List<String> log;

  @override
  bool get enabled => true;

  @override
  OlmManager get olmManager => _FakeOlm();

  @override
  void handleDeviceOneTimeKeysCount(Map<String, int>? countJson, List<String>? unusedFallbackKeyTypes) {}

  @override
  Future<void> handleEventUpdate(Event event, EventUpdateType type) async {}

  @override
  Future<Map<String, dynamic>> encryptGroupMessagePayload(
    String roomId,
    Map<String, dynamic> payload, {
    String type = EventTypes.Message,
  }) async {
    log.add('encrypt');
    return {'algorithm': AlgorithmTypes.megolmV1AesSha2, 'ciphertext': 'x'};
  }
}

class _FakeOlm extends Fake implements OlmManager {
  @override
  int? get maxNumberOfOneTimeKeys => 100;
}

class _TestClient extends AloClient {
  _TestClient(super.clientName, {required super.database, super.httpClient});

  Encryption? fake;

  @override
  Encryption? get encryption => fake ?? super.encryption;
}

void main() {
  late List<String> requests; // "METHOD path"
  late ChatService service;
  late _TestClient client;
  late Future<void> keysAnswer; // when /keys/query answers
  late int keysFailures; // /keys/query answers 502 this many times first

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    requests = [];
    keysAnswer = Future.value();
    keysFailures = 0;
    final server = MockClient((req) async {
      requests.add('${req.method} ${Uri.decodeComponent(req.url.path)}');
      if (req.url.path.endsWith('/keys/query')) {
        if (keysFailures > 0) {
          keysFailures--;
          return http.Response('{"errcode":"M_UNKNOWN","error":"bad gateway"}', 502);
        }
        await keysAnswer;
        requests.add('keys answered');
        // Every user asked for, with no devices.
        final asked = (jsonDecode(req.body)['device_keys'] as Map<String, dynamic>).keys;
        return http.Response(
          jsonEncode({
            'device_keys': {for (final u in asked) u: <String, Object>{}},
          }),
          200,
        );
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
      if (req.url.path.contains('/join')) return http.Response(jsonEncode({'room_id': '!x:alo.test'}), 200);
      return http.Response(jsonEncode({'event_id': r'$e'}), 200);
    });
    final db = await MatrixSdkDatabase.init(
      'encryption_guard_test',
      database: await databaseFactoryFfi.openDatabase(':memory:'),
      sqfliteFactory: databaseFactoryFfi,
    );
    client = _TestClient('encryption_guard_test', database: db, httpClient: server)
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
    room('!plain:alo.test', membership: Membership.invite, encrypted: false);
    room('!e2e:alo.test', membership: Membership.invite, encrypted: true);
    await sync();
    expect(requests.where((r) => r.contains('/join')), [contains('!e2e:alo.test')]);
  });

  test('a joined chat without encryption gets it switched on when I may, and is marked until then', () async {
    room('!plain:alo.test', membership: Membership.join, encrypted: false);
    await sync();
    await sync(); // once per run, not on every sync
    expect(requests.where((r) => r.contains('m.room.encryption')), hasLength(1));
    expect(service.chats.value.single.encrypted, isFalse);
  });

  test('a joined chat without encryption I may not change stays marked and is left alone', () async {
    final r = room('!plain:alo.test', membership: Membership.join, encrypted: false);
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
    final plain = ChatSession(service, room('!plain:alo.test', membership: Membership.join, encrypted: false));
    expect(plain.encrypted, isFalse);
    await expectLater(plain.sendText('oi'), throwsStateError);
    await expectLater(plain.sendFile(const PickedFile(name: 'a.txt', bytes: [1])), throwsStateError);
    await expectLater(
      plain.sendVoice(bytes: Uint8List(1), mimeType: 'audio/ogg', durationMs: 1, waveform: const []),
      throwsStateError,
    );
    // An encrypted room with the client's encryption off would go out in
    // clear too (the SDK falls back to plaintext).
    final off = ChatSession(service, room('!e2e:alo.test', membership: Membership.join, encrypted: true));
    expect(off.encrypted, isFalse);
    await expectLater(off.sendText('oi'), throwsStateError);
    // Nor from a notification's reply field.
    await expectLater(service.sendQuickReply('!plain:alo.test', 'oi'), throwsStateError);
    await expectLater(service.sendQuickReply('!unknown:alo.test', 'oi'), throwsA(anything));
    expect(requests.where((r) => r.contains('/send/')), isEmpty);
  });

  test('typing waits for device lists that are still loading', () async {
    final r = room('!e2e:alo.test', membership: Membership.join, encrypted: true);
    // Bob is invited (the /members answer above). What the sync loop leaves while /keys/query is in flight: an empty,
    // outdated list. The SDK would build the room key without Bob.
    client.userDeviceKeys[bob] = DeviceKeysList(bob, client);
    await ChatSession(service, r).setTyping(true);
    final keys = requests.indexWhere((r) => r.endsWith('/keys/query'));
    final typing = requests.indexWhere((r) => r.contains('/typing/'));
    expect(keys, isNonNegative);
    expect(typing, greaterThan(keys));
  });

  group('a send', () {
    setUp(() {
      client.fake = _FakeEncryption(requests);
      // Bob's list as the sync loop leaves it while /keys/query is in flight.
      client.userDeviceKeys[bob] = DeviceKeysList(bob, client);
      ChatSession.deviceListRetry = const Duration(milliseconds: 20);
    });
    tearDown(() => ChatSession.deviceListRetry = const Duration(seconds: 1));

    Iterable<String> sends() => requests.where((r) => r.contains('/send/${EventTypes.Encrypted}/'));

    test('on a slow key query shows and stores the message at once, waits, then goes out once it answers', () async {
      final answer = Completer<void>();
      keysAnswer = answer.future;
      final r = room('!e2e:alo.test', membership: Membership.join, encrypted: true);
      var done = false;
      final sending = ChatSession(service, r).sendText('oi').whenComplete(() => done = true);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(r.lastEvent?.body, 'oi');
      expect(r.lastEvent?.status, EventStatus.sending);
      // Stored: it survives the app being killed now.
      expect((await client.database.getEventList(r)).map((e) => e.body), contains('oi'));
      expect(requests, contains(endsWith('/keys/query')));

      // Well past the old 5 s give-up (scaled): still waiting, no room key.
      await Future<void>.delayed(const Duration(milliseconds: 600));
      expect(done, isFalse);
      expect(r.lastEvent?.status, EventStatus.sending);
      expect(requests, isNot(contains('encrypt')));
      expect(sends(), isEmpty);

      answer.complete();
      await sending;
      expect(requests.indexOf('encrypt'), greaterThan(requests.indexOf('keys answered')));
      expect(sends(), hasLength(1));
    });

    test('after a failed key query asks again, and makes the room key only once it answers', () async {
      keysFailures = 2; // e.g. a 502 from the edge, a dropped mobile connection
      final r = room('!e2e:alo.test', membership: Membership.join, encrypted: true);
      await ChatSession(service, r).sendText('oi');
      expect(requests.where((r) => r.endsWith('/keys/query')), hasLength(3));
      expect(requests.indexOf('encrypt'), greaterThan(requests.indexOf('keys answered')));
      expect(sends(), hasLength(1));
    });

    test('a reply from a notification waits for device lists too', () async {
      keysAnswer = Future<void>.delayed(const Duration(milliseconds: 100));
      room('!e2e:alo.test', membership: Membership.join, encrypted: true);
      await service.sendQuickReply('!e2e:alo.test', 'já vou');
      expect(requests, contains('keys answered'));
      expect(requests.indexOf('encrypt'), greaterThan(requests.indexOf('keys answered')));
      expect(sends(), hasLength(1));
    });

    test('makes the room key only after device lists that answer in time', () async {
      keysAnswer = Future<void>.delayed(const Duration(milliseconds: 100));
      final r = room('!e2e:alo.test', membership: Membership.join, encrypted: true);
      await ChatSession(service, r).sendText('oi');
      expect(requests.indexOf('encrypt'), greaterThan(requests.indexOf('keys answered')));
      expect(sends(), hasLength(1));
    });

    test('again (retry) waits for device lists too, and is refused in a chat without encryption', () async {
      final r = _FixedRoom(id: '!e2e:alo.test', client: client);
      client.rooms.add(r);
      r.setState(state(r, EventTypes.RoomMember, {'membership': 'invite'}, stateKey: bob));
      r.events = [
        Event(
          type: EventTypes.Message,
          content: {'msgtype': MessageTypes.Text, 'body': 'oi'},
          eventId: 'txn1',
          senderId: me,
          originServerTs: DateTime(2026),
          status: EventStatus.error,
          room: r,
        ),
      ];
      final plain = ChatSession(service, r);
      await plain.open();
      await expectLater(plain.retry('txn1'), throwsStateError);
      expect(requests, isNot(contains(endsWith('/keys/query'))));
      plain.dispose();

      r.setState(state(r, EventTypes.Encryption, {'algorithm': AlgorithmTypes.megolmV1AesSha2}));
      final session = ChatSession(service, r);
      await session.open();
      await session.retry('txn1');
      expect(requests.indexOf('encrypt'), greaterThan(requests.indexOf('keys answered')));
      expect(sends(), hasLength(1));
      session.dispose();
    });
  });

  test('signing out drops the chat list and cached avatars', () async {
    room('!e2e:alo.test', membership: Membership.join, encrypted: true);
    await sync();
    expect(service.chats.value, hasLength(1));
    client.onLoginStateChanged.add(LoginState.loggedOut);
    await Future<void>.delayed(Duration.zero);
    expect(service.chats.value, isEmpty);
  });

  test('read receipts skip messages this device cannot decrypt', () {
    final r = room('!e2e:alo.test', membership: Membership.join, encrypted: true);
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
      room: room('!e2e:alo.test', membership: Membership.join, encrypted: true),
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
    final r = _FixedRoom(id: '!dm:alo.test', client: client);
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
