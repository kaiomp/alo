import 'package:alo/common/secure_clipboard.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late String? clipboard;
  late List<String> sensitive;

  setUp(() {
    clipboard = null;
    sensitive = [];
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') clipboard = (call.arguments as Map)['text'] as String?;
      if (call.method == 'Clipboard.getData') return {'text': clipboard};
      return null;
    });
    // Android: MainActivity copies with the sensitive flag.
    messenger.setMockMethodCallHandler(const MethodChannel('app.usealo.app/clipboard'), (call) async {
      sensitive.add(call.arguments as String);
      clipboard = call.arguments as String;
      return null;
    });
  });

  testWidgets('the recovery key is copied as sensitive and cleared a minute later', (tester) async {
    await copySecret('EsTc key');
    expect(sensitive, ['EsTc key']);
    await tester.pump(const Duration(seconds: 59));
    expect(clipboard, 'EsTc key');
    await tester.pump(const Duration(seconds: 2));
    expect(clipboard, '');
  });

  testWidgets('something the user copied since is left alone', (tester) async {
    await copySecret('EsTc key');
    clipboard = 'endereço da padaria';
    await tester.pump(const Duration(seconds: 61));
    expect(clipboard, 'endereço da padaria');
  });

  testWidgets('without the Android channel it falls back to a plain copy', (tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('app.usealo.app/clipboard'),
      (_) async => throw MissingPluginException(),
    );
    await copySecret('EsTc key');
    expect(clipboard, 'EsTc key');
    await clearSecret('EsTc key');
    expect(clipboard, '');
  });
}
