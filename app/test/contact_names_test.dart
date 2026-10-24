import 'dart:async';
import 'dart:convert';

import 'package:chama/contacts/address_book.dart';
import 'package:chama/contacts/contact_sync.dart';
import 'package:chama/contacts/contacts_service.dart';
import 'package:chama/services/chat_session.dart';
import 'package:chama/services/models.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matrix/matrix.dart';
// TimelineChunk is not exported, and a Timeline cannot be built without one.
// ignore: implementation_imports
import 'package:matrix/src/models/timeline_chunk.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes.dart';

void main() {
  test('a saved contact name replaces the display name; others keep theirs', () async {
    SharedPreferences.setMockInitialValues({});
    final service = await testService(await SharedPreferences.getInstance());
    final room = Room(id: '!r:chama.test', client: service.client);
    final ana = User('@ana:chama.test', displayName: 'ana_profile', room: room);
    final bia = User('@bia:chama.test', displayName: 'Bia', room: room);
    var redraws = 0;
    service.namesRevision.addListener(() => redraws++);

    service.contactNames = {'@ana:chama.test': 'Ana (trabalho)'};
    expect(service.nameOf(ana), 'Ana (trabalho)');
    expect(service.nameOf(bia), 'Bia');

    service.contactNames = {'@ana:chama.test': 'Ana (trabalho)'}; // same names: open chats do not redraw
    expect(redraws, 1);
  });

  test('a 1:1 chat, its members and its security-code line use the saved name', () async {
    const ana = '@ana:chama.test';
    const roomId = '!r:chama.test';
    SharedPreferences.setMockInitialValues({
      'chama.security_notices': jsonEncode({
        roomId: [
          [ana, DateTime(2026).millisecondsSinceEpoch],
        ],
      }),
    });
    final service = await testService(await SharedPreferences.getInstance());
    final client = service.client..setUserId('@me:chama.test');
    client.accountData['m.direct'] = BasicEvent(
      type: 'm.direct',
      content: {
        ana: [roomId],
      },
    );
    final room = _ReadyRoom(id: roomId, client: client);
    for (final user in [ana, '@me:chama.test']) {
      room.setState(
        Event(
          type: EventTypes.RoomMember,
          content: {'membership': 'join', 'displayname': user == ana ? 'ana_profile' : 'Eu'},
          eventId: '\$user',
          senderId: user,
          stateKey: user,
          originServerTs: DateTime(2026),
          room: room,
        ),
      );
    }
    room.setState(
      Event(
        type: EventTypes.Encryption,
        content: {'algorithm': AlgorithmTypes.megolmV1AesSha2},
        eventId: '\$e',
        senderId: ana,
        stateKey: '',
        originServerTs: DateTime(2026),
        room: room,
      ),
    );
    client.rooms.add(room);
    final session = ChatSession(service, room);
    await session.open();
    String securityLine() =>
        session.messages.singleWhere((m) => m.systemKind == SystemKind.securityCodeChanged).senderName;
    expect(session.name, 'ana_profile');
    expect(securityLine(), 'ana_profile');

    service.contactNames = {ana: 'Ana (trabalho)'};
    expect(session.name, 'Ana (trabalho)');
    expect(service.summaryOf(room).name, 'Ana (trabalho)');
    expect(session.members.firstWhere((m) => m.userId == ana).name, 'Ana (trabalho)');
    expect(securityLine(), 'Ana (trabalho)'); // redrawn without a sync
    session.dispose();
  });

  test('the address book names Chama accounts, and sign-out forgets them', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final anaHash = sha256.convert(utf8.encode('5511987654321')).toString();
    final chamaId = MockClient(
      (req) async => http.Response(
        jsonEncode({
          'registered': [
            {'hash': anaHash, 'user_id': '@ana:chama.test'},
          ],
        }),
        200,
      ),
    );
    final service = await testService(prefs, chamaId: chamaId);
    service.client.accessToken = 'token';
    service.loggedIn.value = true;
    final contacts = ContactsService(
      service,
      _Book(const [
        BookContact('Ana (trabalho)', ['(11) 98765-4321']),
        BookContact('Caio', ['(21) 3456-7890']),
      ]),
      prefs,
    );

    await contacts.start();
    expect([for (final c in contacts.onChama) c.name], ['Ana (trabalho)']);
    expect([for (final c in contacts.invite) c.name], ['Caio']);
    final ana = User(
      '@ana:chama.test',
      displayName: 'ana_profile',
      room: Room(id: '!r', client: service.client),
    );
    expect(service.nameOf(ana), 'Ana (trabalho)');

    service.loggedIn.value = false;
    expect(service.nameOf(ana), 'ana_profile');
    expect(contacts.onChama, isEmpty);
    await Future<void>.delayed(Duration.zero);
    expect(ContactSync(prefs, (_) async => {}).cachedNames(), isEmpty);
  });

  test('a lookup still running at sign-out leaves nothing behind', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final lookup = Completer<void>();
    final anaHash = sha256.convert(utf8.encode('5511987654321')).toString();
    final chamaId = MockClient((req) async {
      await lookup.future;
      return http.Response(
        jsonEncode({
          'registered': [
            {'hash': anaHash, 'user_id': '@ana:chama.test'},
          ],
        }),
        200,
      );
    });
    final service = await testService(prefs, chamaId: chamaId);
    service.client.accessToken = 'token';
    service.loggedIn.value = true;
    final contacts = ContactsService(
      service,
      _Book(const [
        BookContact('Ana (trabalho)', ['(11) 98765-4321']),
      ]),
      prefs,
    );

    final running = contacts.start();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    service.loggedIn.value = false;
    lookup.complete();
    await running;
    expect(contacts.onChama, isEmpty);
    expect(ContactSync(prefs, (_) async => {}).cachedNames(), isEmpty);
  });
}

/// A granted address book with fixed entries.
class _Book implements AddressBook {
  _Book(this.entries);
  final List<BookContact> entries;
  @override
  Future<ContactsAccess> access() async => ContactsAccess.granted;
  @override
  Future<ContactsAccess> requestAccess() async => ContactsAccess.granted;
  @override
  Future<void> openSettings() async {}
  @override
  Future<List<BookContact>> read() async => entries;
  @override
  Stream<void> get changes => const Stream.empty();
}

/// A room whose (empty) timeline loads at once.
class _ReadyRoom extends Room {
  _ReadyRoom({required super.id, required super.client}) : super(membership: Membership.join);

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
    chunk: TimelineChunk(events: []),
  );
}
