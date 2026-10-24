/// Waveform helpers for voice notes (MSC3246: values 0..1024).
library;

/// Turns recorder amplitude samples (dBFS, -160..0) into [count] bars.
List<int> downsampleWaveform(List<double> dbfs, {int count = 40}) {
  if (dbfs.isEmpty) return List.filled(count, 0);
  final levels = dbfs.map((db) => ((db + 60) / 60).clamp(0.0, 1.0)).toList();
  return List.generate(count, (i) {
    final start = i * levels.length ~/ count;
    var end = (i + 1) * levels.length ~/ count;
    if (end <= start) end = start + 1;
    final slice = levels.sublist(start, end.clamp(0, levels.length));
    final avg = slice.reduce((a, b) => a + b) / slice.length;
    return (avg * 1024).round();
  });
}

/// Bars in 0..1 for drawing [count] bars from an event's waveform.
List<double> waveformBars(List<int>? waveform, {int count = 40}) {
  if (waveform == null || waveform.isEmpty) return List.filled(count, 0.1);
  return List.generate(count, (i) {
    final v = waveform[i * waveform.length ~/ count];
    return (v / 1024).clamp(0.05, 1.0);
  });
}
