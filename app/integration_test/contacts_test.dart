import 'package:chama/chat/chat_screen.dart';
import 'package:chama/main.dart' as app;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'steps.dart';
import 'wait.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('address book: the peer is under "Contatos no Chama" and opens a chat', (tester) async {
    expect(peerPhone, isNotEmpty, reason: 'run through scripts/e2e.sh android');
    await tester.pumpWidget(await app.bootstrap());
    final t = Steps(tester);
    await t.signIn(appPhone, 'Ana Teste');

    await t.tap(const Key('new_chat'));
    // READ_CONTACTS was granted by scripts/drive.sh; the rationale button then asks nothing.
    if (find.byKey(const Key('contacts_allow')).evaluate().isNotEmpty) await t.tap(const Key('contacts_allow'));
    await t.waitFor(find.byKey(const Key('contacts_on_chama')), timeout: const Duration(seconds: 60));
    expect(find.text(peerContactName), findsOneWidget);
    await t.waitFor(find.byKey(const Key('contacts_invite')));
    expect(find.text(inviteContactName), findsOneWidget);

    await tester.tap(find.text(peerContactName));
    await t.waitFor(find.text('oi, entrei'), timeout: const Duration(seconds: 60));
    // The chat carries the saved name, not the peer's display name ("Peer").
    expect(
      find.descendant(of: find.byKey(const Key('chat_header')), matching: find.text(peerContactName)),
      findsOneWidget,
    );
    expect(find.byType(ChatScreen), findsOneWidget);
  }, timeout: const Timeout(Duration(minutes: 5)));
}
