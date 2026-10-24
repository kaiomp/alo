import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:matrix/matrix.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Android, iOS, desktop: SQLCipher database, key kept in the system keystore.
/// Same approach as FluffyChat (lib/utils/matrix_sdk_extensions/
/// flutter_matrix_dart_sdk_database/builder.dart and cipher.dart).
Future<DatabaseApi> openDatabase(String name) async {
  const storage = FlutterSecureStorage();
  var key = await storage.read(key: 'db_key');
  if (key == null) {
    final rng = Random.secure();
    key = base64UrlEncode(List.generate(32, (_) => rng.nextInt(256)));
    await storage.write(key: 'db_key', value: key);
  }
  final factory = createDatabaseFactoryFfi();
  final dir = await getApplicationSupportDirectory();
  final path = p.join(dir.path, '$name.sqlite');
  final helper = SQfLiteEncryptionHelper(factory: factory, path: path, cipher: key);
  final db = await factory.openDatabase(
    path,
    options: OpenDatabaseOptions(version: 1, onConfigure: helper.applyPragmaKey),
  );
  final media = await Directory(p.join((await getTemporaryDirectory()).path, 'chama_media')).create(recursive: true);
  return MatrixSdkDatabase.init(
    name,
    database: db,
    maxFileSize: 10 * 1000 * 1000,
    fileStorageLocation: media.uri,
    deleteFilesAfterDuration: const Duration(days: 30),
  );
}
