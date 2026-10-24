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
  final factory = createDatabaseFactoryFfi();
  final dir = await getApplicationSupportDirectory();
  final path = p.join(dir.path, '$name.sqlite');
  final key = await databaseKey(
    path,
    read: () => storage.read(key: 'db_key'),
    write: (k) => storage.write(key: 'db_key', value: k),
  );
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

/// The SQLCipher key for the database at [path], made on first run. A
/// database whose key is gone (keystore wiped, or the file restored without
/// it) can never be opened again, so it is deleted and a fresh local store
/// starts: the user signs in again and unlocks with the recovery key.
Future<String> databaseKey(
  String path, {
  required Future<String?> Function() read,
  required Future<void> Function(String key) write,
}) async {
  String? key;
  try {
    key = await read();
  } catch (e) {
    Logs().w('Database key unreadable, starting a new local store', e);
  }
  if (key != null) return key;
  for (final suffix in ['', '-wal', '-shm', '-journal']) {
    final f = File('$path$suffix');
    if (f.existsSync()) await f.delete();
  }
  final rng = Random.secure();
  key = base64UrlEncode(List.generate(32, (_) => rng.nextInt(256)));
  await write(key);
  return key;
}
