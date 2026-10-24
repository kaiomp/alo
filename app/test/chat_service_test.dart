import 'dart:convert';

import 'package:chama/auth/encryption_screen.dart';
import 'package:chama/auth/id_client.dart';
import 'package:chama/common/deps.dart';
import 'package:chama/l10n/app_localizations.dart';
import 'package:chama/services/chama_client.dart';
import 'package:chama/services/chat_service.dart';
import 'package:chama/services/delivery.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

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
    final service = await _service(prefs, server);

    const login = IdLogin(phone: '5511987654321', userId: '@u1:chama.test', loginToken: 'jwt', newAccount: false);
    await expectLater(service.signIn(login), throwsA(isA<MatrixException>()));
    expect(service.phone, isNull);
  });

  testWidgets('the key screen can sign out even when the server refuses', (tester) async {
    SharedPreferences.setMockInitialValues({'chama.phone': '5511987654321'});
    final prefs = await SharedPreferences.getInstance();
    // An expired session: the server refuses everything, logout included.
    final server = MockClient(
      (_) async => http.Response(jsonEncode({'errcode': 'M_UNKNOWN_TOKEN', 'error': 'expired'}), 401),
    );
    final service = (await tester.runAsync(() => _service(prefs, server)))!;
    service.client
      ..homeserver = _base
      ..accessToken = 'expired';
    await tester.pumpWidget(
      Deps(
        chat: service,
        id: service.id,
        newRecorder: () => throw UnimplementedError(),
        pickFile: ({required bool image}) async => null,
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
}

final _base = Uri.parse('http://localhost:8080');

Future<ChatService> _service(SharedPreferences prefs, http.Client server) async {
  final db = await MatrixSdkDatabase.init(
    'chat_service_test',
    database: await databaseFactoryFfi.openDatabase(':memory:'),
    sqfliteFactory: databaseFactoryFfi,
  );
  final client = ChamaClient(
    'chat_service_test',
    database: db,
    supportedLoginTypes: {jwtLoginType},
    httpClient: server,
  );
  return ChatService(client, DeliveryTracker(client, prefs), IdClient(_base), prefs, homeserver: _base);
}
