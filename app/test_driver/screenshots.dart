import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

/// Saves each screenshot as `$SCREENSHOT_DIR/<name>.png` (default build/screenshots).
Future<void> main() => integrationDriver(
  onScreenshot: (name, bytes, [args]) async {
    final dir = Platform.environment['SCREENSHOT_DIR'] ?? 'build/screenshots';
    final file = await File('$dir/$name.png').create(recursive: true);
    await file.writeAsBytes(bytes);
    return true;
  },
);
