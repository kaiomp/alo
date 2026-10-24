import 'package:chama/common/notifications.dart';
import 'package:chama/l10n/app_localizations.dart';
import 'package:chama/services/chat_service.dart';
import 'package:chama/services/models.dart' hide Message;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes.dart';

const me = '@me:chama.test';
const ana = '@ana:chama.test';
const roomId = '!r:chama.test';

void main() {
  late ChatService service;
  late Room room;
  final l = lookupL10n(const Locale('pt'));

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    service = await testService(await SharedPreferences.getInstance());
    final client = service.client..setUserId(me);
    client.accountData['m.direct'] = BasicEvent(
      type: 'm.direct',
      content: {
        ana: [roomId],
      },
    );
    room = Room(id: roomId, client: client, membership: Membership.join);
    client.rooms.add(room);
    for (final (user, name) in [(ana, 'Ana'), (me, 'Eu')]) {
      room.setState(
        Event(
          type: EventTypes.RoomMember,
          content: {'membership': 'join', 'displayname': name},
          eventId: '\$m$user',
          senderId: user,
          stateKey: user,
          originServerTs: DateTime(2026),
          room: room,
        ),
      );
    }
    await pushRules(client);
  });

  Event message(String id, {String sender = ana, String type = EventTypes.Message, Map<String, Object?>? content}) =>
      Event(
        type: type,
        content: content ?? {'msgtype': MessageTypes.Text, 'body': 'oi'},
        eventId: id,
        senderId: sender,
        originServerTs: DateTime(2026, 10, 24),
        room: room,
      );

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

  test('a message it cannot decrypt shows "Nova mensagem" and no IDs or ciphertext', () {
    final m = service.incomingFor(encrypted(room, r'$x'))!;
    expect(m.kind, MessageKind.undecryptable);
    expect(notificationBody(m, l), 'Nova mensagem');
    for (final shown in [m.body, m.chatName, m.senderName, notificationBody(m, l)]) {
      expect(shown, isNot(anyOf(contains('@'), contains(r'$'), contains('!'), contains('secret'))));
    }
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
