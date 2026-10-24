import 'dart:convert';

import 'package:chama/auth/id_client.dart';
import 'package:chama/services/chama_client.dart';
import 'package:chama/services/chat_service.dart';
import 'package:chama/services/delivery.dart';
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
    final base = Uri.parse('http://localhost:8080');
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
    final service = ChatService(client, DeliveryTracker(client, prefs), IdClient(base), prefs, homeserver: base);

    const login = IdLogin(phone: '5511987654321', userId: '@u1:chama.test', loginToken: 'jwt', newAccount: false);
    await expectLater(service.signIn(login), throwsA(isA<MatrixException>()));
    expect(service.phone, isNull);
  });
}
