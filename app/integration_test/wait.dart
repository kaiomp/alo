/// Polls [ok] until it is true. For tests that talk to the real server.
Future<void> until(bool Function() ok, {Duration timeout = const Duration(seconds: 60), String? what}) async {
  final end = DateTime.now().add(timeout);
  while (!ok()) {
    if (DateTime.now().isAfter(end)) throw StateError('Timed out waiting for ${what ?? 'condition'}');
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }
}

// Set by scripts/e2e.sh: fresh random numbers each run, E.164 digits.
const appPhone = String.fromEnvironment('ALO_TEST_PHONE');
const peerPhone = String.fromEnvironment('ALO_PEER_PHONE');
