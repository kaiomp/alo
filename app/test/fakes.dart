import 'package:alo/auth/id_client.dart';
import 'package:alo/services/alo_client.dart';
import 'package:alo/services/chat_service.dart';
import 'package:alo/services/delivery.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matrix/encryption.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

final testBase = Uri.parse('http://localhost:8080');

/// A client whose end-to-end encryption a test can replace with a fake.
class TestClient extends AloClient {
  TestClient(super.clientName, {required super.database, super.supportedLoginTypes, super.httpClient});

  Encryption? fakeEncryption;

  @override
  Encryption? get encryption => fakeEncryption ?? super.encryption;
}

/// A ChatService on an in-memory database. [matrix] answers the Matrix API,
/// [aloId] the alo-id API; both refuse everything by default.
Future<ChatService> testService(SharedPreferences prefs, {http.Client? matrix, http.Client? aloId}) async {
  final refuse = MockClient((_) async => http.Response('{"errcode":"M_UNKNOWN","error":"no"}', 400));
  final db = await MatrixSdkDatabase.init(
    'test',
    database: await databaseFactoryFfi.openDatabase(':memory:'),
    sqfliteFactory: databaseFactoryFfi,
  );
  final client = TestClient('test', database: db, supportedLoginTypes: {jwtLoginType}, httpClient: matrix ?? refuse);
  return ChatService(
    client,
    DeliveryTracker(client, prefs),
    IdClient(testBase, httpClient: aloId ?? refuse),
    prefs,
    homeserver: testBase,
  );
}
