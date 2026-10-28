import 'dart:io';

import 'package:alo/chat/voice/voice_recorder.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory dir;
  setUp(() async => dir = await Directory.systemTemp.createTemp('voice_files_test'));
  tearDown(() => dir.delete(recursive: true));

  test('a finished recording is read and its plaintext file deleted', () async {
    final file = File(p.join(dir.path, 'voz_1.ogg'))..writeAsBytesSync([1, 2, 3]);
    expect(await readAndDelete(file.path), [1, 2, 3]);
    expect(file.existsSync(), isFalse);
  });

  test('startup removes leftover voice files and nothing else', () async {
    File(p.join(dir.path, 'voz_1.ogg')).writeAsBytesSync([1]);
    File(p.join(dir.path, 'voz_2961.m4a')).writeAsBytesSync([1]);
    final other = File(p.join(dir.path, 'other.txt'))..writeAsBytesSync([1]);
    await sweepVoiceFiles(dir);
    expect(dir.listSync().map((f) => f.path), [other.path]);
  });
}
