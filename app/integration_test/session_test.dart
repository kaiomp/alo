import 'package:chama/auth/id_client.dart';
import 'package:chama/config.dart';
import 'package:chama/services/chat_service.dart';
import 'package:chama/services/models.dart';
import 'package:chama/services/ticks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'wait.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('session: ticks to blue, reply, reaction, edit, delete', (tester) async {
    expect(appPhone, isNotEmpty, reason: 'run through scripts/e2e.sh');
    final id = IdClient(chamaBaseUrl);
    final chat = await ChatService.start(homeserver: chamaBaseUrl, id: id);
    await id.requestCode(appPhone);
    await chat.signIn(await id.verifyCode(appPhone, '000000'));
    await chat.setUpEncryption();

    final roomId = await chat.startDirectChat((await chat.findByPhone(peerPhone))!);
    final s = chat.openChat(roomId);
    await s.open();
    Message? byBody(String b) => s.messages.where((m) => m.body == b).firstOrNull;
    await until(() => byBody('oi, entrei') != null, what: 'peer joined');

    await s.sendText('Olá, peer!');
    expect(byBody('Olá, peer!')!.isMine, isTrue);
    await until(() => byBody('Olá, peer!')!.tick == Tick.delivered, what: 'grey ticks');
    await until(() => byBody('Olá, peer!')!.tick == Tick.read, what: 'blue ticks');
    await until(() => byBody('eco: Olá, peer!') != null, what: 'echo');

    final echo = byBody('eco: Olá, peer!')!;
    await s.sendText('respondendo', replyTo: echo.id);
    await until(() => byBody('respondendo')?.reply?.eventId == echo.id, what: 'reply preview');

    await s.toggleReaction(echo.id, '👍');
    await until(() => byBody('eco: Olá, peer!')!.reactions.any((r) => r.key == '👍' && r.mine), what: 'reaction');

    final mine = byBody('respondendo')!;
    await s.sendText('editado', editOf: mine.id);
    await until(() => s.messages.any((m) => m.id == mine.id && m.body == 'editado' && m.edited), what: 'edit');

    await s.deleteForEveryone(mine.id);
    await until(() => s.messages.any((m) => m.id == mine.id && m.kind == MessageKind.deleted), what: 'redaction');

    await s.deleteForMe(echo.id);
    expect(s.messages.any((m) => m.id == echo.id), isFalse);
    s.dispose();
  }, timeout: const Timeout(Duration(minutes: 3)));
}
