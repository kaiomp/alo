import 'package:chama/chat_list/home_screen.dart';
import 'package:chama/common/deps.dart';
import 'package:chama/main.dart' as app;
import 'package:chama/services/push.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'steps.dart';
import 'wait.dart';

/// The phone registers for push: ntfy (scripts/ntfy-setup.sh) gives a
/// UnifiedPush endpoint, and the server gets this device's pusher.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the device registers a pusher for its ntfy endpoint', (tester) async {
    expect(appPhone, isNotEmpty, reason: 'run through scripts/e2e.sh android');
    await tester.pumpWidget(await app.bootstrap());
    final t = Steps(tester);
    await t.signIn(appPhone, 'Ana Teste');
    await t.waitFor(find.byType(HomeScreen));
    final deps = Deps.of(tester.element(find.byType(HomeScreen)));
    await until(() => deps.push.active.value, what: 'push registration (is ntfy set up?)');
    // Tests may use the SDK directly.
    final pushers = await deps.chat.client.getPushers() ?? [];
    expect(pushers.map((p) => p.appId), [pushAppId]);
    expect(pushers.single.data.format, 'event_id_only');
    expect(pushers.single.data.additionalProperties['endpoint'], startsWith('http://10.0.2.2:8081/up'));
  }, timeout: const Timeout(Duration(minutes: 5)));
}
