import 'package:alo/common/notifications.dart';
import 'package:alo/l10n/app_localizations.dart';
import 'package:alo/services/chat_service.dart';
import 'package:alo/services/models.dart' hide Message;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/encryption.dart';
// OlmManager is not exported; a sync through the fake encryption needs one.
// ignore: implementation_imports
import 'package:matrix/encryption/olm_manager.dart';
import 'package:matrix/matrix.dart';
// SessionKey is not exported, and the fake key manager hands one out.
// ignore: implementation_imports
import 'package:matrix/encryption/utils/session_key.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes.dart';

const me = '@me:alo.test';
const ana = '@ana:alo.test';
const roomId = '!r:alo.test';

/// Encryption with the Megolm sessions a test gives it.
class _FakeEncryption extends Fake implements Encryption {
  _FakeEncryption(this.keyManager);

  @override
  final KeyManager keyManager;

  @override
  bool get enabled => true;

  @override
  OlmManager get olmManager => _FakeOlm();

  @override
  void handleDeviceOneTimeKeysCount(Map<String, int>? countJson, List<String>? unusedFallbackKeyTypes) {}
}

class _FakeOlm extends Fake implements OlmManager {
  @override
  int? get maxNumberOfOneTimeKeys => 100;
}

class _FakeKeyManager extends Fake implements KeyManager {
  final sessions = <String, SessionKey>{};

  @override
  SessionKey? getInboundGroupSession(String roomId, String sessionId) => sessions[sessionId];
}

void main() {
  late ChatService service;
  late Room room;
  late _FakeKeyManager keys;
  final l = lookupL10n(const Locale('pt'));

  Event member(String user, Map<String, Object?> content) => Event(
    type: EventTypes.RoomMember,
    content: content,
    eventId: '\$m$user',
    senderId: user,
    stateKey: user,
    originServerTs: DateTime(2026),
    room: room,
  );

  /// Ana's device [deviceId]; [signed]: by her master key.
  DeviceKeys device(String deviceId, {required bool signed}) {
    final d = DeviceKeys.fromJson({
      'user_id': ana,
      'device_id': deviceId,
      'algorithms': [AlgorithmTypes.olmV1Curve25519AesSha2, AlgorithmTypes.megolmV1AesSha2],
      'keys': {'curve25519:$deviceId': 'curve-$deviceId', 'ed25519:$deviceId': 'ed-$deviceId'},
      'signatures': {
        ana: {'ed25519:$deviceId': 'self', if (signed) 'ed25519:MASTER': 'sig'},
      },
    }, service.client);
    // The signature counts as checked (no vodozemac in unit tests).
    d.validSignatures = {
      ana: {'ed25519:MASTER': true},
    };
    return d;
  }

  /// Ana's Megolm session [sessionId], from her device [deviceId].
  void session(String sessionId, String deviceId) => keys.sessions[sessionId] = SessionKey(
    content: const {},
    inboundGroupSession: null,
    key: me,
    roomId: roomId,
    sessionId: sessionId,
    senderKey: 'curve-$deviceId',
    senderClaimedKeys: {'ed25519': 'ed-$deviceId'},
  );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    service = await testService(await SharedPreferences.getInstance());
    keys = _FakeKeyManager();
    final client = (service.client as TestClient)
      ..setUserId(me)
      ..fakeEncryption = _FakeEncryption(keys);
    client.accountData['m.direct'] = BasicEvent(
      type: 'm.direct',
      content: {
        ana: [roomId],
      },
    );
    room = Room(id: roomId, client: client, membership: Membership.join);
    client.rooms.add(room);
    room.setState(
      Event(
        type: EventTypes.Encryption,
        content: {'algorithm': AlgorithmTypes.megolmV1AesSha2},
        eventId: r'$enc',
        senderId: me,
        stateKey: '',
        originServerTs: DateTime(2026),
        room: room,
      ),
    );
    for (final (user, name) in [(ana, 'Ana'), (me, 'Eu')]) {
      room.setState(member(user, {'membership': 'join', 'displayname': name}));
    }
    client.userDeviceKeys[ana] = DeviceKeysList(
      ana,
      client,
      outdated: false,
      deviceKeys: {'PHONE': device('PHONE', signed: true), 'SIMSWAP': device('SIMSWAP', signed: false)},
      crossSigningKeys: {
        'MASTER': CrossSigningKey.fromJson({
          'user_id': ana,
          'usage': ['master'],
          'keys': {'ed25519:MASTER': 'MASTER'},
        }, client),
      },
    );
    session('s-phone', 'PHONE');
    session('s-simswap', 'SIMSWAP');
    await pushRules(client);
  });

  /// A message from Ana as decrypted from Megolm session [sessionId]; with
  /// no session, it arrived in clear.
  Event message(
    String id, {
    String sender = ana,
    String type = EventTypes.Message,
    Map<String, Object?>? content,
    String? sessionId = 's-phone',
    DateTime? at,
  }) => Event(
    type: type,
    content: content ?? {'msgtype': MessageTypes.Text, 'body': 'oi'},
    eventId: id,
    senderId: sender,
    originServerTs: at ?? DateTime(2026, 10, 24),
    room: room,
    originalSource: sessionId == null
        ? null
        : MatrixEvent(
            type: EventTypes.Encrypted,
            content: {'algorithm': AlgorithmTypes.megolmV1AesSha2, 'ciphertext': 'x', 'session_id': sessionId},
            senderId: sender,
            eventId: id,
            originServerTs: at ?? DateTime(2026, 10, 24),
          ),
  );

  void expectHidden(IncomingMessage? m) {
    expect(m, isNotNull);
    expect((m!.senderName, m.chatName, m.senderId, m.body, m.isGroup), ('', '', '', '', false));
    expect(notificationBody(m, l), 'Nova mensagem');
    expect(notificationMessage(m, l).person!.name, 'Alô');
  }

  test('a message from someone else shows sender and text', () {
    final m = service.incomingFor(message(r'$a'))!;
    expect((m.senderName, m.chatName, m.body, m.kind, m.isGroup), ('Ana', 'Ana', 'oi', MessageKind.text, false));
  });

  test('my own message, an edit and a reaction show nothing', () {
    expect(service.incomingFor(message(r'$own', sender: me)), isNull);
    final edit = message(
      r'$edit',
      content: {
        'msgtype': MessageTypes.Text,
        'body': '* oi!',
        'm.new_content': {'msgtype': MessageTypes.Text, 'body': 'oi!'},
        'm.relates_to': {'rel_type': RelationshipTypes.edit, 'event_id': r'$a'},
      },
    );
    expect(service.incomingFor(edit), isNull);
    final reaction = message(
      r'$react',
      type: EventTypes.Reaction,
      content: {
        'm.relates_to': {'rel_type': RelationshipTypes.reaction, 'event_id': r'$a', 'key': '👍'},
      },
    );
    expect(service.incomingFor(reaction), isNull);
  });

  test('a muted chat shows nothing, not even a message it cannot decrypt', () async {
    await pushRules(service.client, muted: roomId);
    expect(service.incomingFor(message(r'$a')), isNull);
    expect(service.incomingFor(encrypted(room, r'$x')), isNull);
  });

  test('a message it cannot decrypt shows "Nova mensagem" and no names, IDs or ciphertext', () {
    final m = service.incomingFor(encrypted(room, r'$x'))!;
    expect(m.kind, MessageKind.undecryptable);
    expectHidden(m);
    for (final shown in [m.body, m.chatName, m.senderName, notificationBody(m, l)]) {
      expect(shown, isNot(anyOf(contains('@'), contains(r'$'), contains('!'), contains('secret'))));
    }
  });

  test('a chat without encryption shows nothing (its reply would go out in clear)', () {
    room.states.remove(EventTypes.Encryption);
    expect(room.encrypted, isFalse);
    expect(service.incomingFor(message(r'$a')), isNull);
  });

  test('plaintext slipped into an encrypted chat shows no name and no text', () {
    expectHidden(service.incomingFor(message(r'$a', sessionId: null)));
  });

  test('a message from a device its sender never cross-signed (SIM swap, server login) shows no name or text', () {
    expectHidden(service.incomingFor(message(r'$a', sessionId: 's-simswap')));
    // A session this device has no record of proves nothing either.
    expectHidden(service.incomingFor(message(r'$a', sessionId: 's-unknown')));
  });

  test('a session claiming a device key of another device shows no name', () {
    keys.sessions['s-forged'] = SessionKey(
      content: const {},
      inboundGroupSession: null,
      key: me,
      roomId: roomId,
      sessionId: 's-forged',
      senderKey: 'curve-PHONE',
      senderClaimedKeys: {'ed25519': 'ed-SIMSWAP'},
    );
    expectHidden(service.incomingFor(message(r'$a', sessionId: 's-forged')));
  });

  test('a sender known only by user ID is never named by it; a saved contact name is', () {
    room.setState(member(ana, {'membership': 'join'}));
    expectHidden(service.incomingFor(message(r'$a')));
    service.contactNames = {ana: 'Ana Paula'};
    expect(service.incomingFor(message(r'$a'))!.senderName, 'Ana Paula');
  });

  group('a message already read', () {
    final sent = DateTime(2026, 10, 24, 12);
    void receipt(String eventId, DateTime at) => room.receiptState = LatestReceiptState(
      global: LatestReceiptStateForTimeline(
        ownPrivate: null,
        ownPublic: null,
        latestOwnReceipt: LatestReceiptStateData(eventId, at.millisecondsSinceEpoch),
        otherUsers: {},
      ),
    );

    test('on another device (my receipt on it or on a later one) shows nothing', () {
      receipt(r'$a', sent);
      expect(service.incomingFor(message(r'$a', at: sent)), isNull);
      receipt(r'$later', sent.add(const Duration(minutes: 1)));
      expect(service.incomingFor(message(r'$a', at: sent)), isNull);
    });

    test('up to my read marker shows nothing', () {
      room.roomAccountData['m.fully_read'] = BasicEvent(type: 'm.fully_read', content: {'event_id': r'$a'});
      expect(service.incomingFor(message(r'$a', at: sent)), isNull);
    });

    test('but a receipt from before it leaves it unread', () {
      receipt(r'$older', sent.subtract(const Duration(minutes: 1)));
      expect(service.incomingFor(message(r'$a', at: sent)), isNotNull);
    });
  });
}

Event encrypted(Room room, String id) => Event(
  type: EventTypes.Encrypted,
  content: {'algorithm': AlgorithmTypes.megolmV1AesSha2, 'ciphertext': 'secret', 'session_id': 's', 'sender_key': 'k'},
  eventId: id,
  senderId: ana,
  originServerTs: DateTime(2026, 10, 24),
  room: room,
);

/// Synapse's default rules for messages, plus a mute (an override with no
/// actions) for [muted].
Future<void> pushRules(Client client, {String? muted}) => client.handleSync(
  SyncUpdate(
    nextBatch: 'n',
    accountData: [
      BasicEvent(
        type: EventTypes.PushRules,
        content: {
          'global': {
            'override': [
              if (muted != null)
                {
                  'rule_id': muted,
                  'default': false,
                  'enabled': true,
                  'actions': <Object>[],
                  'conditions': [
                    {'kind': 'event_match', 'key': 'room_id', 'pattern': muted},
                  ],
                },
            ],
            'underride': [
              for (final (id, type) in [
                ('.m.rule.message', 'm.room.message'),
                ('.m.rule.encrypted', 'm.room.encrypted'),
              ])
                {
                  'rule_id': id,
                  'default': true,
                  'enabled': true,
                  'actions': ['notify'],
                  'conditions': [
                    {'kind': 'event_match', 'key': 'type', 'pattern': type},
                  ],
                },
            ],
          },
        },
      ),
    ],
  ),
);
