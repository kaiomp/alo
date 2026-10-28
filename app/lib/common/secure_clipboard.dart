import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const _channel = MethodChannel('app.usealo.app/clipboard');
Timer? _clearTimer;

/// Copies a secret (the recovery key). On Android it is flagged sensitive
/// (MainActivity.kt), so the copy preview and keyboard clipboard histories
/// hide it. It is cleared after [clearAfter] if still on the clipboard.
/// Limit: Android 10+ lets an app read the clipboard only while it is in
/// front, so when Alô is in the background at that moment the key stays
/// until [clearSecret] runs (Continuar) or the system expires it. On the web
/// reading the clipboard asks the user for permission, so it is not cleared.
Future<void> copySecret(String text, {Duration clearAfter = const Duration(seconds: 60)}) async {
  try {
    await _channel.invokeMethod<void>('copySensitive', text);
  } on MissingPluginException {
    await Clipboard.setData(ClipboardData(text: text)); // web, tests
  }
  _clearTimer?.cancel();
  if (!kIsWeb) _clearTimer = Timer(clearAfter, () => clearSecret(text));
}

/// Empties the clipboard if it still holds [text]: something the user
/// copied since stays.
Future<void> clearSecret(String text) async {
  _clearTimer?.cancel();
  _clearTimer = null;
  if (kIsWeb) return;
  try {
    final now = await Clipboard.getData(Clipboard.kTextPlain);
    if (now?.text == text) await Clipboard.setData(const ClipboardData(text: ''));
  } on PlatformException {
    // Clipboard not readable now: the system clears it eventually.
  }
}
