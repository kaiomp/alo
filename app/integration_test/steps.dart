import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Contacts scripts/e2e.sh saves in the emulator's address book: the peer
/// under this name, and one number without an account.
const peerContactName = 'Peer Agenda';
const inviteContactName = 'Sem Chama';

/// Small helpers in the style of FluffyChat integration_test/utils/fluffy_chat_tester.dart.
/// No pumpAndSettle: spinners never settle.
class Steps {
  Steps(this.tester);
  final WidgetTester tester;

  Future<void> waitFor(Finder finder, {Duration timeout = const Duration(seconds: 30)}) =>
      until(() => finder.evaluate().isNotEmpty, '$finder', timeout: timeout);

  /// Pumps until [done] holds (real time: the app runs live against the server).
  Future<void> until(bool Function() done, String what, {Duration timeout = const Duration(seconds: 30)}) async {
    final end = DateTime.now().add(timeout);
    while (!done()) {
      if (DateTime.now().isAfter(end)) throw TestFailure('Timed out waiting for $what');
      await tester.pump(const Duration(milliseconds: 250));
    }
  }

  /// Taps once the widget can take the tap: built, on screen, and no page or
  /// sheet animation covering it.
  Future<void> tap(Key key) async {
    final target = find.byKey(key).hitTestable();
    await waitFor(target);
    await tester.tap(target);
    await tester.pump();
  }

  Future<void> enter(Key key, String text) async {
    await waitFor(find.byKey(key));
    await tester.enterText(find.byKey(key), text);
    await tester.pump();
  }

  /// Signs in [phoneDigits] (E.164) with the dev code and sets the profile name.
  Future<void> signIn(String phoneDigits, String name) async {
    await enter(const Key('phone_number'), phoneDigits.substring(2)); // the field already says +55
    await tap(const Key('sign_in_next'));
    await enter(const Key('sms_code'), '000000'); // 6 digits submit on their own
    await waitFor(find.byKey(const Key('recovery_key')), timeout: const Duration(seconds: 60));
    await tap(const Key('recovery_key_saved'));
    await tap(const Key('recovery_key_done'));
    await enter(const Key('profile_name'), name);
    await tap(const Key('profile_done'));
  }
}
