import 'dart:math' as math;

import '../chat/voice/voice_recorder.dart';
import 'demo_chat.dart';

/// A microphone that records silence: the demo never asks the browser for
/// the real one.
class DemoRecorder implements VoiceRecorder {
  DateTime? _since;

  @override
  Future<bool> start() async {
    _since = DateTime.now();
    return true;
  }

  @override
  Future<RecordedVoice?> stop() async {
    final ms = DateTime.now().difference(_since ?? DateTime.now()).inMilliseconds;
    final r = math.Random(ms);
    return RecordedVoice(
      bytes: silentWav(ms),
      mimeType: 'audio/wav',
      durationMs: ms,
      waveform: [for (var i = 0; i < 40; i++) 150 + r.nextInt(800)],
    );
  }

  @override
  Future<void> cancel() async {}

  @override
  void dispose() {}
}
