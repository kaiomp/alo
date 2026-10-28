import 'dart:io';

import 'package:alo/services/database_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory dir;
  late File db;
  setUp(() {
    dir = Directory.systemTemp.createTempSync('alo_db_key');
    db = File(p.join(dir.path, 'alo.sqlite'));
  });
  tearDown(() => dir.deleteSync(recursive: true));

  void makeStore() {
    for (final suffix in ['', '-wal', '-shm', '-journal']) {
      File('${db.path}$suffix').writeAsStringSync('x');
    }
  }

  test('a stored key opens the existing store', () async {
    makeStore();
    final key = await databaseKey(db.path, read: () async => 'k1', write: (_) async => fail('no new key'));
    expect(key, 'k1');
    expect(db.existsSync(), isTrue);
  });

  test('a store without its key is deleted and a new key made', () async {
    makeStore();
    String? written;
    final key = await databaseKey(db.path, read: () async => null, write: (k) async => written = k);
    expect(key, written);
    expect(key, hasLength(44)); // 32 bytes, base64url
    expect(dir.listSync(), isEmpty);
  });

  test('an unreadable key counts as lost', () async {
    makeStore();
    final key = await databaseKey(db.path, read: () => throw Exception('keystore'), write: (_) async {});
    expect(key, isNotEmpty);
    expect(dir.listSync(), isEmpty);
  });
}
