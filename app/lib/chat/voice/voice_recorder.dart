import 'dart:async';
import 'dart:io';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/foundation.dart';
import 'package:mime/mime.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import 'waveform.dart';

class RecordedVoice {
  const RecordedVoice({required this.bytes, required this.mimeType, required this.durationMs, required this.waveform});
  final Uint8List bytes;
  final String mimeType;
  final int durationMs;
  final List<int> waveform;
}

/// Microphone access for voice notes. The real one wraps package:record;
/// integration tests pass a fake that returns a ready-made clip.
abstract class VoiceRecorder {
  /// False when the user denied the microphone.
  Future<bool> start();
  Future<RecordedVoice?> stop();
  Future<void> cancel();
  void dispose();
}

/// Same setup as FluffyChat lib/pages/chat/recording_view_model.dart:
/// Opus where the platform supports it, else AAC; a temp file on native,
/// a blob on web.
class RecordVoiceRecorder implements VoiceRecorder {
  final _rec = AudioRecorder();
  final _samples = <double>[];
  StreamSubscription<Amplitude>? _amp;
  DateTime? _startedAt;
  String _ext = 'm4a';
  String? _mime;

  @override
  Future<bool> start() async {
    if (!await _rec.hasPermission()) return false;
    final opus =
        await _rec.isEncoderSupported(AudioEncoder.opus) &&
        !(defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.macOS);
    // The web records through MediaRecorder: Opus comes in a WebM container
    // (Chrome, Firefox), AAC in MP4 (Safari).
    _ext = opus ? (kIsWeb ? 'webm' : 'ogg') : 'm4a';
    _mime = kIsWeb ? (opus ? 'audio/webm' : 'audio/mp4') : null;
    final name = 'voz_${DateTime.now().millisecondsSinceEpoch}.$_ext';
    final path = kIsWeb ? '' : p.join((await getTemporaryDirectory()).path, name);
    await _rec.start(
      RecordConfig(encoder: opus ? AudioEncoder.opus : AudioEncoder.aacLc, numChannels: 1, bitRate: 64000),
      path: path,
    );
    _samples.clear();
    _amp = _rec.onAmplitudeChanged(const Duration(milliseconds: 100)).listen((a) => _samples.add(a.current));
    _startedAt = DateTime.now();
    return true;
  }

  @override
  Future<RecordedVoice?> stop() async {
    await _amp?.cancel();
    final path = await _rec.stop();
    final started = _startedAt;
    if (path == null || started == null) return null;
    final bytes = await readAndDelete(path);
    return RecordedVoice(
      bytes: bytes,
      mimeType: _mime ?? lookupMimeType('x.$_ext', headerBytes: bytes) ?? 'audio/ogg',
      durationMs: DateTime.now().difference(started).inMilliseconds,
      waveform: downsampleWaveform(_samples),
    );
  }

  @override
  Future<void> cancel() async {
    await _amp?.cancel();
    _startedAt = null;
    await _rec.cancel();
  }

  @override
  void dispose() {
    _amp?.cancel();
    _rec.dispose();
  }
}

/// Reads the recording at [path], then deletes the file on native: a voice
/// note must not stay in the cache in clear once it is sent. (On the web the
/// path is a blob URL that goes away with the page.)
Future<Uint8List> readAndDelete(String path) async {
  final bytes = await XFile(path).readAsBytes();
  if (!kIsWeb) {
    try {
      await File(path).delete();
    } on FileSystemException {
      // Gone already.
    }
  }
  return bytes;
}

/// Startup on native: deletes the voice files ("voz_…") left in [dir] by a
/// crash or a killed app: recordings and the player's decrypted copies.
Future<void> sweepVoiceFiles(Directory dir) async {
  try {
    await for (final f in dir.list()) {
      if (f is File && p.basename(f.path).startsWith('voz_')) await f.delete();
    }
  } on FileSystemException {
    // A file in use or gone already: the next start tries again.
  }
}
