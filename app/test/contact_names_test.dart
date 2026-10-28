import 'dart:async';
import 'dart:convert';

import 'package:alo/contacts/address_book.dart';
import 'package:alo/contacts/contact_sync.dart';
import 'package:alo/contacts/contacts_service.dart';
import 'package:alo/services/chat_service.dart';
import 'package:alo/services/chat_session.dart';
import 'package:alo/services/models.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
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
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test('a saved contact name replaces the display name; others keep theirs', () async {
    SharedPreferences.setMockInitialValues({});
    final service = await testService(await SharedPreferences.getInstance());
    final room = Room(id: '!r:alo.test', client: service.client);
    final ana = User('@ana:alo.test', displayName: 'ana_profile', room: room);
    final bia = User('@bia:alo.test', displayName: 'Bia', room: room);
    var redraws = 0;
    service.namesRevision.addListener(() => redraws++);

    service.contactNames = {'@ana:alo.test': 'Ana (trabalho)'};
    expect(service.nameOf(ana), 'Ana (trabalho)');
    expect(service.nameOf(bia), 'Bia');

    service.contactNames = {'@ana:alo.test': 'Ana (trabalho)'}; // same names: open chats do not redraw
    expect(redraws, 1);
  });

  test('a 1:1 chat, its members and its security-code line use the saved name', () async {
    const ana = '@ana:alo.test';
    const roomId = '!r:alo.test';
    SharedPreferences.setMockInitialValues({
      'alo.security_notices': jsonEncode({
        roomId: [
          [ana, DateTime(2026).millisecondsSinceEpoch],
        ],
      }),
    });
    final service = await testService(await SharedPreferences.getInstance());
    final client = service.client..setUserId('@me:alo.test');
    client.accountData['m.direct'] = BasicEvent(
      type: 'm.direct',
      content: {
        ana: [roomId],
      },
    );
    final room = _ReadyRoom(id: roomId, client: client);
    for (final user in [ana, '@me:alo.test']) {
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

  test('the address book names Alô accounts, and sign-out forgets them', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final anaHash = sha256.convert(utf8.encode('5511987654321')).toString();
    final aloId = MockClient(
      (req) async => http.Response(
        jsonEncode({
          'registered': [
            {'hash': anaHash, 'user_id': '@ana:alo.test'},
          ],
        }),
        200,
      ),
    );
    final service = await testService(prefs, aloId: aloId);
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
    expect([for (final c in contacts.onAlo) c.name], ['Ana (trabalho)']);
    expect([for (final c in contacts.invite) c.name], ['Caio']);
    final ana = User(
      '@ana:alo.test',
      displayName: 'ana_profile',
      room: Room(id: '!r', client: service.client),
    );
    expect(service.nameOf(ana), 'Ana (trabalho)');

    service.loggedIn.value = false;
    expect(service.nameOf(ana), 'ana_profile');
    expect(contacts.onAlo, isEmpty);
    await Future<void>.delayed(Duration.zero);
    expect(await ContactSync(prefs, (_) async => {}).cachedNames(), isEmpty);
  });

  test('a lookup still running at sign-out leaves nothing behind', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final lookup = Completer<void>();
    final anaHash = sha256.convert(utf8.encode('5511987654321')).toString();
    final aloId = MockClient((req) async {
      await lookup.future;
      return http.Response(
        jsonEncode({
          'registered': [
            {'hash': anaHash, 'user_id': '@ana:alo.test'},
          ],
        }),
        200,
      );
    });
    final service = await testService(prefs, aloId: aloId);
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
    expect(contacts.onAlo, isEmpty);
    expect(await ContactSync(prefs, (_) async => {}).cachedNames(), isEmpty);
  });

  test('an empty saved name is skipped: the profile name stays', () async {
    SharedPreferences.setMockInitialValues({});
    final service = await testService(await SharedPreferences.getInstance());
    final room = Room(id: '!r:alo.test', client: service.client);
    final ana = User('@ana:alo.test', displayName: 'ana_profile', room: room);

    service.contactNames = {'@ana:alo.test': '  '};
    expect(service.nameOf(ana), 'ana_profile');
  });

  test('a sign-out between batches leaves nothing behind, even when the next batch fails', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    const first = '5511900000000';
    late final ChatService service;
    var calls = 0;
    final aloId = MockClient((req) async {
      calls++;
      // Signed out while the first of two batches is on its way.
      service.loggedIn.value = false;
      service.client.accessToken = null;
      return http.Response(
        jsonEncode({
          'registered': [
            {'hash': sha256.convert(utf8.encode(first)).toString(), 'user_id': '@ana:alo.test'},
          ],
        }),
        200,
      );
    });
    service = await testService(prefs, aloId: aloId);
    service.client.accessToken = 'token';
    service.loggedIn.value = true;
    final contacts = ContactsService(
      service,
      _Book([
        for (var i = 0; i < ContactSync.maxBatch + 1; i++) BookContact('C$i', ['+55119${'$i'.padLeft(8, '0')}']),
      ]),
      prefs,
    );

    await contacts.start();
    expect(calls, 1, reason: 'no lookup without an access token');
    expect(contacts.onAlo, isEmpty);
    expect(await ContactSync(prefs, (_) async => {}).cachedNames(), isEmpty);
  });

  test('a lookup answered after sign-out and a new sign-in is not kept', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    late final ChatService service;
    final aloId = MockClient((req) async {
      service.loggedIn.value = false; // the old account signs out...
      service.loggedIn.value = true; // ...and another signs in
      return http.Response(
        jsonEncode({
          'registered': [
            {'hash': sha256.convert(utf8.encode('5511987654321')).toString(), 'user_id': '@ana:alo.test'},
          ],
        }),
        200,
      );
    });
    service = await testService(prefs, aloId: aloId);
    service.client.accessToken = 'token';
    service.loggedIn.value = true;
    final contacts = ContactsService(
      service,
      _Book(const [
        BookContact('Ana (trabalho)', ['(11) 98765-4321']),
      ]),
      prefs,
    );

    await contacts.start();
    expect(contacts.onAlo, isEmpty);
    expect(await ContactSync(prefs, (_) async => {}).cachedNames(), isEmpty);
  });
  test('a number that now answers for another account: that account shows by its profile name and number, and the chat with the old one says so (final review 6)', () async {
    const a = '@a:alo.test';
    const b = '@b:alo.test';
    const digits = '5511987654321';
    const roomId = '!r:alo.test';
    SharedPreferences.setMockInitialValues({});
    // Mãe's number answered for A at the last check, over a day ago.
    FlutterSecureStorage.setMockInitialValues({
      'alo.contacts.v1': jsonEncode({
        digits: {'u': a, 't': 0, 'n': 'Mãe', 'k': a},
      }),
    });
    final prefs = await SharedPreferences.getInstance();
    final aloId = MockClient(
      (req) async => http.Response(
        jsonEncode({
          'registered': [
            {'hash': sha256.convert(utf8.encode(digits)).toString(), 'user_id': b},
          ],
        }),
        200,
      ),
    );
    final matrix = MockClient(
      (req) async => Uri.decodeComponent(req.url.path).endsWith('/profile/$b')
          ? http.Response(jsonEncode({'displayname': 'Bia Nova'}), 200)
          : http.Response('{"errcode":"M_UNKNOWN","error":"no"}', 400),
    );
    final service = await testService(prefs, matrix: matrix, aloId: aloId);
    final client = service.client
      ..setUserId('@me:alo.test')
      ..homeserver = testBase;
    service.client.accessToken = 'token';
    service.loggedIn.value = true;
    final room = _ReadyRoom(id: roomId, client: client);
    for (final user in [a, '@me:alo.test']) {
      room.setState(
        Event(
          type: EventTypes.RoomMember,
          content: {'membership': 'join', 'displayname': user == a ? 'a_profile' : 'Eu'},
          eventId: '\$$user',
          senderId: user,
          stateKey: user,
          originServerTs: DateTime(2026),
          room: room,
        ),
      );
    }
    client.rooms.add(room);
    final contacts = ContactsService(
      service,
      _Book(const [
        BookContact('Mãe', ['(11) 98765-4321']),
      ]),
      prefs,
    );
    await contacts.ready;
    expect(
      service.nameOf(User(a, displayName: 'a_profile', room: room)),
      'Mãe',
      reason: 'cached before the check',
    );
    final session = ChatSession(service, room);
    await session.open();

    await contacts.start();
    expect([for (final c in contacts.onAlo) (c.userId, c.name, c.phone)], [(b, 'Bia Nova', digits)]);
    expect(service.nameOf(User(b, displayName: 'b_profile', room: room)), 'b_profile');
    expect(service.nameOf(User(a, displayName: 'a_profile', room: room)), 'a_profile');
    final line = session.messages.singleWhere((m) => m.systemKind == SystemKind.numberMoved);
    expect(line.senderName, 'Mãe');
    session.dispose();
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
