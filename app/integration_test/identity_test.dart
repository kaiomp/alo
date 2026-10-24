import 'package:chama/auth/id_client.dart';
import 'package:chama/config.dart';
import 'package:chama/services/chat_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:matrix/encryption.dart';

import 'wait.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('new device: reset identity, then unlock with the recovery key', (tester) async {
    expect(appPhone, isNotEmpty, reason: 'run through scripts/e2e.sh');
    final id = IdClient(chamaBaseUrl);
    Future<ChatService> device(String name) async {
      final chat = await ChatService.start(homeserver: chamaBaseUrl, id: id, clientName: name);
      await id.requestCode(appPhone);
      await chat.signIn(await id.verifyCode(appPhone, '000000'));
      return chat;
    }

    final first = await device('first');
    expect(await first.setUpEncryption(), isNotEmpty);

    // Second device without the key: SMS code again, keys replaced.
    final second = await device('second');
    expect(await second.cryptoStatus(), CryptoStatus.unlock);
    await second.requestResetCode();
    // A refused reset reaches the app as the chama-id error, not as the SDK's wrapper.
    await expectLater(
      second.resetEncryption('111111'),
      throwsA(isA<IdError>().having((e) => e.code, 'code', 'invalid_code')),
    );
    final key = await second.resetEncryption('000000');
    expect(await second.cryptoStatus(), CryptoStatus.ready);
    // chama-id signed out the first device.
    await until(() => !first.loggedIn.value, what: 'first device signed out');

    // Third device with the recovery key: verified without a reset.
    final third = await device('third');
    expect(await third.cryptoStatus(), CryptoStatus.unlock);
    await expectLater(third.unlockEncryption('EsTc wrong key'), throwsA(anything));
    await third.unlockEncryption(key);
    expect(await third.cryptoStatus(), CryptoStatus.ready);
  }, timeout: const Timeout(Duration(minutes: 3)));

  testWidgets('setup cut off after the master key upload: repaired with the SMS reset', (tester) async {
    expect(appPhone, isNotEmpty, reason: 'run through scripts/e2e.sh');
    // Another number than the test above: this account starts with no keys.
    final last = int.parse(appPhone[appPhone.length - 1]);
    final phone = '${appPhone.substring(0, appPhone.length - 1)}${(last + 1) % 10}';
    final id = IdClient(chamaBaseUrl);
    Future<ChatService> device(String name) async {
      final chat = await ChatService.start(homeserver: chamaBaseUrl, id: id, clientName: name);
      await id.requestCode(phone);
      await chat.signIn(await id.verifyCode(phone, '000000'));
      return chat;
    }

    // The master key reached the server, then the app died before the key
    // backup was made. Running setup again would need a password.
    final first = await device('cut');
    await first.client.initCryptoIdentity(setupOnlineKeyBackup: false);
    expect(await first.cryptoStatus(), CryptoStatus.repair);

    final again = await device('cut_again');
    expect(await again.cryptoStatus(), CryptoStatus.repair);
    await again.requestResetCode();
    expect(await again.resetEncryption('000000'), isNotEmpty);
    expect(await again.cryptoStatus(), CryptoStatus.ready);
  }, timeout: const Timeout(Duration(minutes: 3)));
}
