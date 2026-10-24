import 'dart:convert';
import 'dart:io';

import 'package:chama/auth/id_client.dart';
import 'package:chama/chat/message_bubble.dart';
import 'package:chama/chat_list/chat_list_view.dart';
import 'package:chama/chat_list/chat_tile.dart';
import 'package:chama/common/deps.dart';
import 'package:chama/common/notifications.dart';
import 'package:chama/contacts/address_book.dart';
import 'package:chama/contacts/contacts_service.dart';
import 'package:chama/common/theme.dart';
import 'package:chama/group/group_info_screen.dart';
import 'package:chama/l10n/app_localizations.dart';
import 'package:chama/services/chama_client.dart';
import 'package:chama/services/chat_service.dart';
import 'package:chama/services/chat_session.dart';
import 'package:chama/services/delivery.dart';
import 'package:chama/services/models.dart';
import 'package:chama/services/ticks.dart';
import 'package:chama/services/push.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
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
const carol = '@carol:chama.test';
final base = Uri.parse('http://localhost:8080');

/// A room whose timeline is the one the test gives it.
class _FixedRoom extends Room {
  _FixedRoom({required super.id, required super.client}) : super(membership: Membership.join);

  List<Event> events = [];

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

  Future<ChatService> newService(http.Client server, {String name = 'chat_logic_test'}) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = _prefs = await SharedPreferences.getInstance();
    final db = await MatrixSdkDatabase.init(
      name,
      database: await databaseFactoryFfi.openDatabase(':memory:'),
      sqfliteFactory: databaseFactoryFfi,
    );
    client = ChamaClient(name, database: db, httpClient: server)
      ..homeserver = base
      ..accessToken = 'token'
      ..setUserId(me);
    return ChatService(client, DeliveryTracker(client, prefs), IdClient(base), prefs, homeserver: base);
  }

  setUp(() async {
    requests = [];
    service = await newService(
      MockClient((req) async {
        requests.add('${req.method} ${Uri.decodeComponent(req.url.path)}');
        return http.Response(jsonEncode({'event_id': r'$e'}), 200);
      }),
    );
  });

  Event member(Room room, String userId, int ts, {Map<String, Object?>? prev}) => Event(
    type: EventTypes.RoomMember,
    content: {'membership': 'join'},
    eventId: '\$member_$userId$ts',
    senderId: userId,
    stateKey: userId,
    originServerTs: DateTime.fromMillisecondsSinceEpoch(ts),
    unsigned: prev == null ? null : {'prev_content': prev},
    room: room,
  );

  Event message(Room room, String id, String sender, int ts) => Event(
    type: EventTypes.Message,
    content: {'msgtype': MessageTypes.Text, 'body': id},
    eventId: id,
    senderId: sender,
    originServerTs: DateTime.fromMillisecondsSinceEpoch(ts),
    room: room,
  );

  _FixedRoom chatWith(String sender) {
    final r = _FixedRoom(id: '!r:chama.test', client: client);
    client.rooms.add(r);
    r.setState(member(r, me, 1));
    r.setState(member(r, bob, 1));
    r.events = [message(r, r'$new', sender, 2000)];
    r.lastEvent = r.events.first;
    return r;
  }

  Iterable<String> readMarkers() => requests.where((r) => r.endsWith('/read_markers'));
  Iterable<String> unreadFlags() => requests.where((r) => r.endsWith('/account_data/m.marked_unread'));

  group('read markers (finding 8)', () {
    test('an open chat sends one read marker per new message, not one per redraw', () async {
      final r = chatWith(bob)..notificationCount = 1;
      final session = ChatSession(service, r);
      await session.open();
      // Redraws while the unread count waits for the next sync.
      for (var i = 0; i < 5; i++) {
        service.delivery.revision.value++;
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(readMarkers(), hasLength(1));

      // A newer message is read once more.
      r.events.insert(0, message(r, r'$newer', bob, 3000));
      r.lastEvent = r.events.first;
      service.delivery.revision.value++;
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(readMarkers(), hasLength(2));
      session.dispose();
    });

    test('opening a chat marked unread clears the mark', () async {
      final r = chatWith(bob);
      await r.markUnread(true);
      requests.clear();
      final session = ChatSession(service, r);
      await session.open();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(r.markedUnread, isFalse);
      expect(unreadFlags(), hasLength(1));
      session.dispose();
    });

    test('marking the open chat unread holds until it is shown again', () async {
      final r = chatWith(bob);
      final session = ChatSession(service, r);
      await session.open();
      await r.markUnread(true);
      service.delivery.revision.value++; // a redraw, nothing new
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(r.markedUnread, isTrue);
      session.visible = true; // the app comes back to the chat
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(r.markedUnread, isFalse);
      session.dispose();
    });

    test('"Marcar como lida" in the list clears the mark and reads the newest message', () async {
      final r = chatWith(bob)..notificationCount = 2;
      await r.markUnread(true);
      requests.clear();
      await service.markUnread(r.id, false);
      expect(r.markedUnread, isFalse);
      expect(readMarkers(), hasLength(1));
    });

    testWidgets('the list menu offers "Marcar como lida" for an unread chat', (tester) async {
      service.chats.value = [
        ChatSummary(id: '!r', name: 'Bia', isGroup: false, lastTime: DateTime.now(), markedUnread: true),
      ];
      await tester.pumpWidget(_host(service, ChatListView(onOpen: (_) {})));
      await tester.longPress(find.byKey(const Key('chat_Bia')));
      await tester.pumpAndSettle();
      expect(find.text('Marcar como lida'), findsOneWidget);
      expect(find.text('Marcar como não lida'), findsNothing);
    });
  });

  group('muted chats (finding 9)', () {
    test('a muted chat with new messages counts as unread', () {
      // Muted: the server counts nothing, so the count stays 0.
      expect(service.summaryOf(chatWith(bob)).newMessages, isTrue);
      ChatSummary chat({required bool muted}) =>
          ChatSummary(id: '!r', name: 'G', isGroup: true, lastTime: DateTime(2026), isMuted: muted, newMessages: true);
      expect(chat(muted: true).isUnread, isTrue);
      // Not muted, the server's count decides (it skips what does not notify).
      expect(chat(muted: false).isUnread, isFalse);
    });

    test('my own last message is not new', () {
      expect(service.summaryOf(chatWith(me)).newMessages, isFalse);
    });

    testWidgets('a muted unread chat shows a grey badge', (tester) async {
      await tester.pumpWidget(
        _host(
          service,
          ChatTile(
            chat: ChatSummary(
              id: '!m',
              name: 'Grupo',
              isGroup: true,
              lastTime: DateTime.now(),
              isMuted: true,
              newMessages: true,
            ),
            onTap: () {},
            onActions: (_, _) {},
          ),
        ),
      );
      final badge = tester.widget<Container>(find.byKey(const Key('unread_badge')));
      final color = (badge.decoration! as ShapeDecoration).color;
      final context = tester.element(find.byKey(const Key('unread_badge')));
      expect(color, Theme.of(context).colorScheme.onSurfaceVariant);
    });
  });

  test('a cold start offline lists the chats kept on this device (finding 10)', () async {
    SharedPreferences.setMockInitialValues({});
    final db = await MatrixSdkDatabase.init(
      'cold_start_test',
      database: await databaseFactoryFfi.openDatabase(':memory:'),
      sqfliteFactory: databaseFactoryFfi,
    );
    await db.storeClient(homeserverUrl: '$base', token: 'token', userId: me, deviceId: 'DEVICE');
    final offline = ChamaClient(
      'cold_start_test',
      database: db,
      httpClient: MockClient((_) async => throw const SocketException('no network')),
    );
    await db.storeRoomUpdate('!r:chama.test', JoinedRoomUpdate(), null, offline);

    final cold = await ChatService.restore(offline, id: IdClient(base), homeserver: base);
    expect(cold.chats.value.map((c) => c.id), ['!r:chama.test']);
    await cold.dispose();
    await offline.dispose(closeDatabase: true);
  });

  group('group ticks (finding 21)', () {
    late _FixedRoom r;
    late Event mine;
    setUp(() {
      r = chatWith(me);
      mine = r.events.first; // sent at 2000
      r.receiptState.global.otherUsers[bob] = LatestReceiptStateData(mine.eventId, 2100);
    });

    test('someone who joins later does not take the blue ticks back', () {
      r.setState(member(r, carol, 3000));
      expect(service.tickOf(r, mine, {mine.eventId: 2000}), Tick.read);
    });

    test('a member who only changed their name later still counts', () {
      r.setState(member(r, carol, 3000, prev: {'membership': 'join'}));
      expect(service.tickOf(r, mine, {mine.eventId: 2000}), Tick.sent);
    });

    test('someone invited when the message went out and who joins later gets it and reads it (final review 3)', () {
      r.setState(member(r, bob, 3000, prev: {'membership': 'invite'}));
      r.receiptState.global.otherUsers[bob] = LatestReceiptStateData(mine.eventId, 3100);
      expect(service.tickOf(r, mine, {mine.eventId: 2000}), Tick.read);
    });
  });

  test('file sizes use the decimal comma in Portuguese (finding 25)', () {
    expect(fileSize(1536 * 1024, 'pt'), '1,5 MB');
    expect(fileSize(1536 * 1024, 'en'), '1.5 MB');
    expect(fileSize(2048, 'pt'), '2 KB');
    expect(fileSize(10, 'pt'), '10 B');
  });

  testWidgets('a deleted message stays on one line on a phone, the time below if needed (finding 26)', (tester) async {
    await tester.runAsync(() async {
      await (FontLoader('Inter')..addFont(rootBundle.load('assets/fonts/Inter-400.ttf'))).load();
    });
    final session = ChatSession(service, chatWith(bob));
    // 411 dp phone: the bubble is 78% wide; large text as many phones set it.
    for (final scale in [1.0, 1.15]) {
      await tester.pumpWidget(
        _host(
          service,
          MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: MessageBubble(
              message: Message(
                id: r'$d',
                senderId: me,
                senderName: 'Eu',
                isMine: true,
                time: DateTime(2026, 10, 24, 7, 29),
                kind: MessageKind.deleted,
                tick: Tick.read,
              ),
              session: session,
              onActions: (_, _) {},
              maxWidth: 411 * 0.78,
            ),
          ),
        ),
      );
      final text = tester.renderObject<RenderParagraph>(find.text('Você apagou esta mensagem'));
      expect(
        text.getBoxesForSelection(const TextSelection(baseOffset: 0, extentOffset: 25)).map((b) => b.top).toSet(),
        hasLength(1),
        reason: 'scale $scale',
      );
      final textBox = tester.getRect(find.text('Você apagou esta mensagem'));
      final time = tester.getRect(find.text('07:29'));
      expect(time.top >= textBox.bottom - 1 || time.left >= textBox.right + 8, isTrue, reason: 'scale $scale');
    }
  });

  testWidgets('the group info action tiles line up (finding 27)', (tester) async {
    final r = chatWith(bob);
    await tester.pumpWidget(_host(service, GroupInfoScreen(session: ChatSession(service, r))));
    await tester.pumpAndSettle();
    final message = tester.getTopLeft(find.byIcon(Icons.chat_bubble_outline)).dy;
    expect(tester.getTopLeft(find.byIcon(Icons.call_outlined)).dy, message);
    expect(tester.getTopLeft(find.byIcon(Icons.search)).dy, message);
  });
}

late SharedPreferences _prefs;

Widget _host(ChatService service, Widget child) => Deps(
  chat: service,
  id: service.id,
  contacts: ContactsService(service, NoAddressBook(), _prefs),
  notifications: Notifications(),
  push: PushService(service, _prefs),
  newRecorder: () => throw UnimplementedError(),
  pickFile: ({required bool image}) async => null,
  shareText: (_) async {},
  child: MaterialApp(
    theme: chamaTheme(Brightness.light),
    locale: const Locale('pt'),
    supportedLocales: L10n.supportedLocales,
    localizationsDelegates: L10n.localizationsDelegates,
    home: Scaffold(body: child),
  ),
);
