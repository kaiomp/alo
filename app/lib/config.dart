import 'package:flutter/foundation.dart';

/// Server base URL. Override with `--dart-define=CHAMA_BASE_URL=https://…`.
/// Dev default: the M1 stack on port 8080; the Android emulator reaches the
/// host machine as 10.0.2.2.
Uri get chamaBaseUrl {
  const fromEnv = String.fromEnvironment('CHAMA_BASE_URL');
  if (fromEnv.isNotEmpty) return Uri.parse(fromEnv);
  final android = !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  return Uri.parse(android ? 'http://10.0.2.2:8080' : 'http://localhost:8080');
}

/// Below this width the app uses the phone layout; above it, two panes.
const wideLayoutMinWidth = 900.0;
