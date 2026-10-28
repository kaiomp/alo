import 'dart:convert';

import 'package:alo/common/deps.dart';
import 'package:alo/common/notifications.dart';
import 'package:alo/common/theme.dart';
import 'package:alo/contacts/address_book.dart';
import 'package:alo/contacts/contact_sync.dart';
import 'package:alo/contacts/contacts_service.dart';
import 'package:alo/group/new_chat_screen.dart';
import 'package:alo/l10n/app_localizations.dart';
import 'package:alo/services/push.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes.dart';

class FakeBook implements AddressBook {
  FakeBook(this.state, this.contacts);
  ContactsAccess state;
  final List<BookContact> contacts;

  @override
  Future<ContactsAccess> access() async => state;
  @override
  Future<ContactsAccess> requestAccess() async => state = ContactsAccess.granted;
  @override
  Future<void> openSettings() async {}
  @override
  Future<List<BookContact>> read() async => contacts;
  @override
  Stream<void> get changes => const Stream.empty();
}

void main() {
  testWidgets('rationale first; once allowed, contacts on Alô, invites and search', (tester) async {
    // A phone screen (360 x 800), tall enough for every row.
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    // alo-id: of the numbers, only Ana's has an account.
    final ana = sha256.convert(utf8.encode('5511912340001')).toString();
    final aloId = MockClient(
      (req) async => http.Response(
        jsonEncode({
          'registered': [
            {'hash': ana, 'user_id': '@ana:alo.test'},
          ],
        }),
        200,
      ),
    );
    final service = (await tester.runAsync(() => testService(prefs, aloId: aloId)))!;
    service.client.accessToken = 'tok';
    service.loggedIn.value = true;
    final contacts = ContactsService(
      service,
      FakeBook(ContactsAccess.notGranted, [
        const BookContact('Ana Souza', ['(11) 91234-0001']),
        const BookContact('Bia Lima', ['+55 11 95555-0002']),
        const BookContact('', ['(21) 3456-7890']), // saved without a name
      ]),
      prefs,
    );
    final shared = <String>[];
    await tester.pumpWidget(
      Deps(
        chat: service,
        id: service.id,
        contacts: contacts,
        notifications: Notifications(),
        push: PushService(service, prefs),
        newRecorder: () => throw UnimplementedError(),
        pickFile: ({required bool image}) async => null,
        shareText: (text) async => shared.add(text),
        child: MaterialApp(
          theme: aloTheme(Brightness.light),
          locale: const Locale('pt'),
          supportedLocales: L10n.supportedLocales,
          localizationsDelegates: L10n.localizationsDelegates,
          home: const NewChatScreen(),
        ),
      ),
    );
    await tester.runAsync(contacts.start);
    await tester.pump();
    expect(find.text('Encontre seus contatos no Alô'), findsOneWidget);
    expect(find.byKey(const Key('new_chat_phone')), findsOneWidget, reason: 'by number works without contacts');
    expect(find.byKey(const Key('contact_search')), findsNothing);
    expect(find.text('Ana Souza'), findsNothing);

    await tester.tap(find.byKey(const Key('contacts_allow')));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pump();
    expect(find.byKey(const Key('contacts_allow')), findsNothing);
    expect(find.byKey(const Key('contacts_on_alo')), findsOneWidget);
    expect(find.byKey(const ValueKey('contact_@ana:alo.test')), findsOneWidget);
    expect(find.byKey(const ValueKey('invite_5511955550002')), findsOneWidget);
    // No saved name: the number stands in for it.
    expect(
      find.descendant(of: find.byKey(const ValueKey('invite_552134567890')), matching: find.text('+55 21 3456-7890')),
      findsOneWidget,
    );

    // Rows, the search box and the invite button are at least 48 dp tall.
    expect(tester.getSize(find.byKey(const Key('contact_search'))).height, greaterThanOrEqualTo(48));
    expect(tester.getSize(find.byKey(const ValueKey('contact_@ana:alo.test'))).height, greaterThanOrEqualTo(48));
    final inviteBia = find.descendant(
      of: find.byKey(const ValueKey('invite_5511955550002')),
      matching: find.byType(TextButton),
    );
    expect(tester.getSize(inviteBia).height, greaterThanOrEqualTo(48));
    // A screen reader hears whom the button invites.
    expect(tester.getSemantics(inviteBia), isSemantics(label: 'Convidar Bia Lima', isButton: true, hasTapAction: true));

    await tester.tap(inviteBia);
    expect(shared.single, contains('https://usealo.app'));

    await tester.enterText(find.byKey(const Key('contact_search')), 'bia');
    await tester.pump();
    expect(find.text('Ana Souza'), findsNothing);
    expect(find.text('Bia Lima'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('contact_search')), '3456');
    await tester.pump();
    expect(find.text('Bia Lima'), findsNothing);
    expect(find.byKey(const ValueKey('invite_552134567890')), findsOneWidget);
  });
}
