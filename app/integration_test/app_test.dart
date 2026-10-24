import 'package:chama/main.dart' as app;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

// Set by scripts/e2e.sh: fresh random numbers each run, E.164 digits.
const appPhone = String.fromEnvironment('CHAMA_TEST_PHONE');
const peerPhone = String.fromEnvironment('CHAMA_PEER_PHONE');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('chat with the peer: ticks turn blue', (tester) async {
    expect(appPhone, isNotEmpty, reason: 'run through scripts/e2e.sh');
    await tester.pumpWidget(await app.bootstrap());
    final t = _Steps(tester);

    // Sign in (country code field already says +55) and set the profile.
    await t.enter(const Key('phone_number'), appPhone.substring(2));
    await t.tap(const Key('sign_in_next'));
    await t.enter(const Key('sms_code'), '000000'); // 6 digits submit on their own
    await t.waitFor(find.byKey(const Key('recovery_key')), timeout: const Duration(seconds: 60));
    await t.tap(const Key('recovery_key_done'));
    await t.enter(const Key('profile_name'), 'Ana Teste');
    await t.tap(const Key('profile_done'));

    // New chat by phone number.
    await t.tap(const Key('new_chat'));
    await t.enter(const Key('new_chat_phone'), peerPhone.substring(2));
    await t.tap(const Key('new_chat_phone_go'));
    await t.waitFor(find.text('oi, entrei'), timeout: const Duration(seconds: 60));

    // Text: clock → ✓ → grey ✓✓ → blue ✓✓, and the peer's echo decrypts here.
    await t.enter(const Key('composer_text'), 'Olá, peer!');
    await t.tap(const Key('send'));
    await t.waitFor(find.byKey(const Key('tick_delivered')));
    await t.waitFor(find.byKey(const Key('tick_read')));
    await t.waitFor(find.text('eco: Olá, peer!'));
  }, timeout: const Timeout(Duration(minutes: 5)));
}

/// Small helpers in the style of FluffyChat integration_test/utils/fluffy_chat_tester.dart.
/// No pumpAndSettle: spinners never settle.
class _Steps {
  _Steps(this.tester);
  final WidgetTester tester;

  Future<void> waitFor(Finder finder, {Duration timeout = const Duration(seconds: 30)}) async {
    final end = DateTime.now().add(timeout);
    while (finder.evaluate().isEmpty) {
      if (DateTime.now().isAfter(end)) throw TestFailure('Timed out waiting for $finder');
      await tester.pump(const Duration(milliseconds: 250));
    }
  }

  /// Taps, then lets page and sheet animations finish (real time: the app
  /// runs live against the server).
  Future<void> tap(Key key) async {
    await waitFor(find.byKey(key));
    await tester.tap(find.byKey(key));
    await Future<void>.delayed(const Duration(milliseconds: 600));
    await tester.pump();
  }

  Future<void> enter(Key key, String text) async {
    await waitFor(find.byKey(key));
    await tester.enterText(find.byKey(key), text);
    await tester.pump();
  }
}
