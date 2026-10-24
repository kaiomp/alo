import 'package:chama/auth/id_client.dart';
import 'package:chama/services/chama_client.dart';
import 'package:chama/services/chat_service.dart';
import 'package:chama/services/delivery.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

final testBase = Uri.parse('http://localhost:8080');

/// A ChatService on an in-memory database. [matrix] answers the Matrix API,
/// [chamaId] the chama-id API; both refuse everything by default.
Future<ChatService> testService(SharedPreferences prefs, {http.Client? matrix, http.Client? chamaId}) async {
  final refuse = MockClient((_) async => http.Response('{"errcode":"M_UNKNOWN","error":"no"}', 400));
  final db = await MatrixSdkDatabase.init(
    'test',
    database: await databaseFactoryFfi.openDatabase(':memory:'),
    sqfliteFactory: databaseFactoryFfi,
  );
  final client = ChamaClient('test', database: db, supportedLoginTypes: {jwtLoginType}, httpClient: matrix ?? refuse);
  return ChatService(
    client,
    DeliveryTracker(client, prefs),
    IdClient(testBase, httpClient: chamaId ?? refuse),
    prefs,
    homeserver: testBase,
  );
}
