import 'dart:convert';

import 'package:chama/auth/encryption_screen.dart';
import 'package:chama/auth/id_client.dart';
import 'package:chama/common/deps.dart';
import 'package:chama/common/notifications.dart';
import 'package:chama/contacts/address_book.dart';
import 'package:chama/contacts/contacts_service.dart';
import 'package:chama/common/theme.dart';
import 'package:chama/l10n/app_localizations.dart';
import 'package:chama/services/chama_client.dart';
import 'package:chama/services/chat_service.dart';
import 'package:chama/services/delivery.dart';
import 'package:chama/services/push.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const key = 'EsTc abcd efgh ijkl mnop qrst uvwx yz12 3456 7890 abcd efgh';

void main() {
  test('a setup cut off after the master key upload is repaired, not set up again', () {
    expect(cryptoStatusOf(initialized: false, connected: false, hasMasterKey: false), CryptoStatus.setUp);
    expect(cryptoStatusOf(initialized: false, connected: false, hasMasterKey: true), CryptoStatus.repair);
    expect(cryptoStatusOf(initialized: true, connected: false, hasMasterKey: true), CryptoStatus.unlock);
    expect(cryptoStatusOf(initialized: true, connected: true, hasMasterKey: true), CryptoStatus.ready);
  });

  testWidgets('a recovery key not confirmed yet comes back, and goes once confirmed', (tester) async {
    FlutterSecureStorage.setMockInitialValues({'pending_recovery_key': key});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (_) async => null,
    );
    final service = (await tester.runAsync(() => _service(MockClient((_) async => http.Response('{}', 200)))))!;
    expect(await tester.runAsync(() => service.pendingRecoveryKey(CryptoStatus.ready)), key);
    var done = false;
    await tester.pumpWidget(
      _app(service, EncryptionScreen(status: CryptoStatus.ready, recoveryKey: key, onDone: () => done = true)),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('recovery_key')), findsOneWidget);
    expect(find.text('abcd'), findsNWidgets(2));

    await tester.ensureVisible(find.byKey(const Key('recovery_key_saved')));
    await tester.tap(find.byKey(const Key('recovery_key_saved')));
    await tester.pump();
    expect(tester.widget<CheckboxListTile>(find.byKey(const Key('recovery_key_saved'))).value, isTrue);
    await tester.ensureVisible(find.byKey(const Key('recovery_key_done')));
    await tester.tap(find.byKey(const Key('recovery_key_done')));
    for (var i = 0; i < 50 && !done; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
    expect(done, isTrue);
    expect(await tester.runAsync(() => service.pendingRecoveryKey(CryptoStatus.ready)), isNull);
  });

  test('a key left while encryption is not ready is deleted, not kept until sign-out', () async {
    FlutterSecureStorage.setMockInitialValues({'pending_recovery_key': key});
    final service = await _service(MockClient((_) async => http.Response('{}', 200)));
    expect(await service.pendingRecoveryKey(CryptoStatus.unlock), isNull);
    expect(await service.pendingRecoveryKey(CryptoStatus.ready), isNull);
  });

  testWidgets('repair goes straight to the SMS reset', (tester) async {
    var requests = 0;
    final idServer = MockClient((req) async {
      requests++;
      return http.Response(jsonEncode({'phone': '5511987654321', 'retry_after': 60}), 200);
    });
    final service = (await tester.runAsync(
      () => _service(MockClient((_) async => http.Response('{}', 200)), id: IdClient(_base, httpClient: idServer)),
    ))!;
    await tester.pumpWidget(_app(service, EncryptionScreen(status: CryptoStatus.repair, onDone: () {})));
    for (var i = 0; i < 50 && requests == 0; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
    await tester.pump();
    expect(requests, 1);
    expect(find.text('Termine de proteger sua conta'), findsOneWidget);
    expect(find.text('Código'), findsOneWidget);
    expect(find.text('Redefinir e continuar'), findsOneWidget);
    await tester.pump(const Duration(seconds: 60)); // let the resend countdown finish
  });
}

Widget _app(ChatService service, Widget home) => Deps(
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
    home: home,
  ),
);

final _base = Uri.parse('http://localhost:8080');
late SharedPreferences _prefs;

Future<ChatService> _service(http.Client server, {IdClient? id}) async {
  SharedPreferences.setMockInitialValues({'chama.phone': '5511987654321'});
  final prefs = _prefs = await SharedPreferences.getInstance();
  final db = await MatrixSdkDatabase.init(
    'recovery_key_test',
    database: await databaseFactoryFfi.openDatabase(':memory:'),
    sqfliteFactory: databaseFactoryFfi,
  );
  final client = ChamaClient('recovery_key_test', database: db, httpClient: server);
  return ChatService(client, DeliveryTracker(client, prefs), id ?? IdClient(_base), prefs, homeserver: _base);
}
