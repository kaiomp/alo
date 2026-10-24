import 'package:flutter/foundation.dart';

/// Server base URL. Override with `--dart-define=CHAMA_BASE_URL=https://…`.
/// Dev default: the M1 stack on port 8080; the Android emulator reaches the
/// host machine as 10.0.2.2. Release builds need an https URL: Android's
/// network security config does not cover Dart's own HTTP client, so nothing
/// else stops SMS codes and tokens from going out in clear.
Uri get chamaBaseUrl => baseUrlFor(
  const String.fromEnvironment('CHAMA_BASE_URL'),
  release: !kDebugMode, // profile builds too
  android: onAndroid,
);

/// [chamaBaseUrl] for a given build. Throws [StateError] for a non-debug build
/// without an https URL.
Uri baseUrlFor(String fromEnv, {required bool release, required bool android}) {
  if (release) {
    final url = Uri.tryParse(fromEnv);
    if (url == null || url.scheme != 'https' || url.host.isEmpty) {
      throw StateError('Release builds need --dart-define=CHAMA_BASE_URL=https://…');
    }
    return url;
  }
  if (fromEnv.isNotEmpty) return Uri.parse(fromEnv);
  return Uri.parse(android ? 'http://10.0.2.2:8080' : 'http://localhost:8080');
}

/// Below this width the app uses the phone layout; above it, two panes.
const wideLayoutMinWidth = 900.0;

/// Push notifications and the address book: Android only for now (spec §7,
/// M3). The web app has neither.
bool get onAndroid => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
