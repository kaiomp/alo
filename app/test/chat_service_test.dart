import 'dart:convert';

import 'package:alo/auth/encryption_screen.dart';
import 'package:alo/auth/id_client.dart';
import 'package:alo/auth/sign_in_screen.dart';
import 'package:alo/common/deps.dart';
import 'package:alo/common/notifications.dart';
import 'package:alo/contacts/address_book.dart';
import 'package:alo/contacts/contacts_service.dart';
import 'package:alo/l10n/app_localizations.dart';
import 'package:alo/services/chat_service.dart';
import 'package:alo/services/push.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes.dart';

void main() {
  test('a failed login leaves no phone behind', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    // The homeserver check passes; the login itself is refused.
    final server = MockClient((req) async {
      final path = req.url.path;
      if (path.endsWith('/versions')) {
        return http.Response(
          jsonEncode({
            'versions': ['v1.11'],
          }),
          200,
        );
      }
      if (path.endsWith('/login') && req.method == 'GET') {
        return http.Response(
          jsonEncode({
            'flows': [
              {'type': jwtLoginType},
            ],
          }),
          200,
        );
      }
      return http.Response(jsonEncode({'errcode': 'M_FORBIDDEN', 'error': 'bad token'}), 403);
    });
    final service = await testService(prefs, matrix: server);

    const login = IdLogin(phone: '5511987654321', userId: '@u1:alo.test', loginToken: 'jwt', newAccount: false);
    await expectLater(service.signIn(login), throwsA(isA<MatrixException>()));
    expect(service.phone, isNull);
  });

  testWidgets('the key screen can sign out even when the server refuses', (tester) async {
    SharedPreferences.setMockInitialValues({'alo.phone': '5511987654321'});
    final prefs = await SharedPreferences.getInstance();
    // An expired session: the server refuses everything, logout included.
    final server = MockClient(
      (_) async => http.Response(jsonEncode({'errcode': 'M_UNKNOWN_TOKEN', 'error': 'expired'}), 401),
    );
    final service = (await tester.runAsync(() => testService(prefs, matrix: server)))!;
    service.client
      ..homeserver = testBase
      ..accessToken = 'expired';
    await tester.pumpWidget(
      Deps(
        chat: service,
        id: service.id,
        contacts: ContactsService(service, NoAddressBook(), prefs),
        notifications: Notifications(),
        push: PushService(service, prefs),
        newRecorder: () => throw UnimplementedError(),
        pickFile: ({required bool image}) async => null,
        shareText: (_) async {},
        child: MaterialApp(
          locale: const Locale('pt'),
          supportedLocales: L10n.supportedLocales,
          localizationsDelegates: L10n.localizationsDelegates,
          home: EncryptionScreen(status: CryptoStatus.unlock, onDone: () {}),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sair'));
    for (var i = 0; i < 50 && service.phone != null; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump();
    }
    expect(service.phone, isNull);
    expect(service.client.isLogged(), isFalse);
    expect(find.text('Algo deu errado. Tente de novo.'), findsNothing);
  });

  testWidgets('"Reenviar SMS" on the key screen counts down like sign-in', (tester) async {
    SharedPreferences.setMockInitialValues({'alo.phone': '5511987654321'});
    final prefs = await SharedPreferences.getInstance();
    var requests = 0;
    final idServer = MockClient((req) async {
      requests++;
      return http.Response(jsonEncode({'phone': '5511987654321', 'retry_after': 60}), 200);
    });
    final service = (await tester.runAsync(
      () => testService(prefs, matrix: MockClient((_) async => http.Response('{}', 200)), aloId: idServer),
    ))!;
    await tester.pumpWidget(_keyScreen(tester, service, prefs));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('request_reset_code')));
    for (var i = 0; i < 50 && find.text('Reenviar SMS em 60 s').evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump();
    }
    expect(requests, 1);
    expect(find.text('Reenviar SMS em 60 s'), findsOneWidget);
    await tester.tap(find.byKey(const Key('request_reset_code')));
    await tester.pump(const Duration(seconds: 1));
    expect(requests, 1); // disabled while counting
    expect(find.text('Reenviar SMS em 59 s'), findsOneWidget);
    await tester.pump(const Duration(seconds: 59));
    expect(find.text('Reenviar SMS'), findsOneWidget);
  });

  testWidgets('screen readers find the SMS code field', (tester) async {
    final handle = tester.ensureSemantics();
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final idServer = MockClient(
      (req) async => http.Response(jsonEncode({'phone': '5511987654321', 'retry_after': 60}), 200),
    );
    final service = (await tester.runAsync(
      () => testService(prefs, matrix: MockClient((_) async => http.Response('{}', 200)), aloId: idServer),
    ))!;
    await tester.pumpWidget(
      Deps(
        chat: service,
        id: service.id,
        contacts: ContactsService(service, NoAddressBook(), prefs),
        notifications: Notifications(),
        push: PushService(service, prefs),
        newRecorder: () => throw UnimplementedError(),
        pickFile: ({required bool image}) async => null,
        shareText: (_) async {},
        child: MaterialApp(
          locale: const Locale('pt'),
          supportedLocales: L10n.supportedLocales,
          localizationsDelegates: L10n.localizationsDelegates,
          home: const SignInScreen(),
        ),
      ),
    );
    await tester.enterText(find.byKey(const Key('phone_number')), '11987654321');
    await tester.tap(find.byKey(const Key('sign_in_next')));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
    await tester.enterText(find.byKey(const Key('sms_code')), '12');
    await tester.pump();

    final field = find.bySemanticsLabel('Código do SMS');
    expect(field, findsOneWidget);
    expect(tester.getSemantics(field), isSemantics(isTextField: true, value: '12'));
    // The six boxes are drawing only: no stray "1" and "2" nodes.
    expect(find.bySemanticsLabel('1'), findsNothing);
    handle.dispose();
  });

  testWidgets('a phone lost to a killed sign-in sends the user back to sign in', (tester) async {
    SharedPreferences.setMockInitialValues({}); // app killed between login and saving the phone
    final prefs = await SharedPreferences.getInstance();
    final service = (await tester.runAsync(
      () => testService(prefs, matrix: MockClient((_) async => http.Response('{}', 200))),
    ))!;
    service.client
      ..homeserver = testBase
      ..accessToken = 'token';
    await tester.pumpWidget(_keyScreen(tester, service, prefs));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('request_reset_code')));
    for (var i = 0; i < 50 && service.client.isLogged(); i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump();
    }
    expect(service.client.isLogged(), isFalse);
    expect(find.text('Algo deu errado. Tente de novo.'), findsNothing);
  });
}

/// The new-device key screen on a phone-sized window.
Widget _keyScreen(WidgetTester tester, ChatService service, SharedPreferences prefs) {
  tester.view
    ..physicalSize = const Size(390, 844)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  return Deps(
    chat: service,
    id: service.id,
    contacts: ContactsService(service, NoAddressBook(), prefs),
    notifications: Notifications(),
    push: PushService(service, prefs),
    newRecorder: () => throw UnimplementedError(),
    pickFile: ({required bool image}) async => null,
    shareText: (_) async {},
    child: MaterialApp(
      locale: const Locale('pt'),
      supportedLocales: L10n.supportedLocales,
      localizationsDelegates: L10n.localizationsDelegates,
      home: EncryptionScreen(status: CryptoStatus.unlock, onDone: () {}),
    ),
  );
}
