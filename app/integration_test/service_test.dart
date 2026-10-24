import 'package:chama/auth/id_client.dart';
import 'package:chama/config.dart';
import 'package:chama/services/chat_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'wait.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('service: sign in, keys, encrypted 1:1 with the peer, delivered acks', (tester) async {
    expect(appPhone, isNotEmpty, reason: 'run through scripts/e2e.sh');
    final id = IdClient(chamaBaseUrl);
    final chat = await ChatService.start(homeserver: chamaBaseUrl, id: id);
    expect(chat.client.encryptionEnabled, isFalse); // not signed in yet

    await id.requestCode(appPhone);
    final login = await id.verifyCode(appPhone, '000000');
    expect(login.newAccount, isTrue);
    expect(login.userId, isNot(contains(appPhone.substring(4)))); // opaque ID (spec §4)
    await chat.signIn(login);
    expect(chat.loggedIn.value, isTrue);
    expect(chat.myUserId, login.userId);
    expect(chat.client.encryptionEnabled, isTrue, reason: 'vodozemac did not load');

    // First device: create cross-signing keys and the recovery key (spec §5).
    expect(await chat.cryptoStatus(), CryptoStatus.setUp);
    expect(await chat.setUpEncryption(), isNotEmpty);
    expect(await chat.cryptoStatus(), CryptoStatus.ready);

    expect(await chat.needsProfile(), isTrue);
    await chat.saveProfile(name: 'Ana Teste');
    expect(await chat.needsProfile(), isFalse);

    final peer = await chat.findByPhone(peerPhone);
    expect(peer, isNotNull);
    expect(await chat.findByPhone('5511900000000'), isNull);

    final roomId = await chat.startDirectChat(peer!);
    String? preview() => chat.chats.value.where((c) => c.id == roomId).firstOrNull?.preview;
    await until(() => preview() == 'oi, entrei', what: 'peer joined');

    await chat.client.getRoomById(roomId)!.sendTextEvent('ping', parseCommands: false);
    await until(() => preview() == 'eco: ping', what: 'peer echo (both directions decrypt)');
    await until(() => chat.delivery.deliveredUpTo(roomId).containsKey(peer), what: 'delivered ack');

    await chat.setPinned(roomId, true);
    await until(() => chat.chats.value.firstWhere((c) => c.id == roomId).isPinned, what: 'pin tag');
  }, timeout: const Timeout(Duration(minutes: 3)));
}
