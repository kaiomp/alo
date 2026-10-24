import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:chama/chat/voice/voice_recorder.dart';
import 'package:chama/chat/voice/waveform.dart';
import 'package:chama/services/models.dart';

/// 1×1 PNG.
final testPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
);

Future<PickedFile?> fakePickFile({required bool image}) async => PickedFile(
  name: image ? 'foto.png' : 'nota.txt',
  bytes: image ? testPng : utf8.encode('olá'),
  mimeType: image ? 'image/png' : 'text/plain',
);

/// One second of a 440 Hz tone as 16 kHz mono 16-bit WAV.
Uint8List testWav() {
  const rate = 16000, seconds = 1;
  final samples = rate * seconds;
  final data = ByteData(44 + samples * 2);
  void ascii(int at, String s) {
    for (var i = 0; i < s.length; i++) {
      data.setUint8(at + i, s.codeUnitAt(i));
    }
  }

  ascii(0, 'RIFF');
  data.setUint32(4, 36 + samples * 2, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little); // PCM
  data.setUint16(22, 1, Endian.little); // mono
  data.setUint32(24, rate, Endian.little);
  data.setUint32(28, rate * 2, Endian.little);
  data.setUint16(32, 2, Endian.little);
  data.setUint16(34, 16, Endian.little);
  ascii(36, 'data');
  data.setUint32(40, samples * 2, Endian.little);
  for (var i = 0; i < samples; i++) {
    data.setInt16(44 + i * 2, (sin(2 * pi * 440 * i / rate) * 12000).round(), Endian.little);
  }
  return data.buffer.asUint8List();
}

/// Stands in for the microphone (no mic on CI, no permission prompt in Chrome).
class FakeRecorder implements VoiceRecorder {
  @override
  Future<bool> start() async => true;

  @override
  Future<RecordedVoice?> stop() async => RecordedVoice(
    bytes: testWav(),
    mimeType: 'audio/wav',
    durationMs: 1000,
    waveform: downsampleWaveform([for (var i = 0; i < 10; i++) -60.0 + i * 6]),
  );

  @override
  Future<void> cancel() async {}

  @override
  void dispose() {}
}
