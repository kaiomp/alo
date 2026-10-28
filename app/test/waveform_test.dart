import 'package:alo/chat/voice/waveform.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('downsamples to the requested count in 0..1024', () {
    final samples = [for (var i = 0; i < 400; i++) i.isEven ? -60.0 : 0.0];
    final w = downsampleWaveform(samples, count: 40);
    expect(w, hasLength(40));
    expect(w.every((v) => v >= 0 && v <= 1024), isTrue);
    expect(w.first, 512); // average of silence and full scale
  });

  test('short recordings still give count bars', () {
    expect(downsampleWaveform([0, -30], count: 40), hasLength(40));
    expect(downsampleWaveform([], count: 40), List.filled(40, 0));
  });

  test('clamps out-of-range dBFS', () {
    expect(downsampleWaveform([-160, -160], count: 1), [0]);
    expect(downsampleWaveform([10, 10], count: 1), [1024]);
  });

  test('bars for drawing', () {
    expect(waveformBars(null, count: 3), [0.1, 0.1, 0.1]);
    expect(waveformBars([0, 512, 1024, 2048], count: 4), [0.05, 0.5, 1.0, 1.0]);
  });
}
