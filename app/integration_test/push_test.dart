import 'package:chama/chat/chat_screen.dart';
import 'package:chama/chat_list/home_screen.dart';
import 'package:chama/common/deps.dart';
import 'package:chama/common/notifications.dart';
import 'package:chama/main.dart' as app;
import 'package:chama/services/push.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'steps.dart';
import 'wait.dart';

/// M3 "done when" (spec §7): a message arrives as a notification with the app
/// in the background. Needs the ntfy app on the emulator (scripts/ntfy-setup.sh)
/// and scripts/drive.sh, which sends the app to the background when this test asks.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a message arrives as a notification while the app is in the background', (tester) async {
    expect(peerPhone, isNotEmpty, reason: 'run through scripts/e2e.sh android');
    await tester.pumpWidget(await app.bootstrap());
    final t = Steps(tester);
    await t.signIn(appPhone, 'Ana Teste');
    await t.waitFor(find.byType(HomeScreen));
    final deps = Deps.of(tester.element(find.byType(HomeScreen)));
    await until(() => deps.push.active.value, what: 'push registration (is ntfy set up?)');
    // The server has this device's pusher for its ntfy endpoint. Tests may use the SDK directly.
    final pushers = await deps.chat.client.getPushers() ?? [];
    expect(pushers.map((p) => p.appId), [pushAppId]);
    expect(pushers.single.data.format, 'event_id_only');
    expect(pushers.single.data.additionalProperties['endpoint'], startsWith('http://10.0.2.2:8081/up'));

    await t.tap(const Key('new_chat'));
    await t.enter(const Key('new_chat_phone'), peerPhone.substring(2));
    await t.tap(const Key('new_chat_phone_go'));
    await t.waitFor(find.text('oi, entrei'), timeout: const Duration(seconds: 60));
    final roomId = tester.widget<ChatScreen>(find.byType(ChatScreen)).roomId;

    // ignore: avoid_print
    print('E2E_BACKGROUND'); // scripts/drive.sh presses Home, waits for a notification, reopens the app
    await until(() => binding.lifecycleState == AppLifecycleState.paused, what: 'the app in the background');
    // Sent without the UI (it is hidden); the peer answers "eco: push-teste".
    await deps.chat.openChat(roomId).sendText('push-teste');
    await until(
      () => binding.lifecycleState == AppLifecycleState.resumed,
      timeout: const Duration(minutes: 2),
      what: 'the app back on screen',
    );
    final android = FlutterLocalNotificationsPlugin()
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()!;
    final style = await android.getActiveNotificationMessagingStyle(id: notificationId(roomId));
    expect(style?.messages?.map((m) => m.text), contains('eco: push-teste'), reason: 'notification with the reply');
    final message = style!.messages!.firstWhere((m) => m.text == 'eco: push-teste');
    expect(message.person?.name, peerContactName); // the name saved in the address book
  }, timeout: const Timeout(Duration(minutes: 5)));
}
