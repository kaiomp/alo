import 'dart:ui' as ui;

import 'package:chama/chat/chat_screen.dart';
import 'package:chama/chat_list/chat_tile.dart';
import 'package:chama/chat_list/home_screen.dart';
import 'package:chama/common/deps.dart';
import 'package:chama/config.dart';
import 'package:chama/main.dart' as app;
import 'package:chama/services/models.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'fakes.dart';
import 'wait.dart';

/// Screenshot name prefix, `<platform>-<size>-<theme>` (e.g. web-phone-dark).
/// Set by scripts/screenshots.sh.
const prefix = String.fromEnvironment('CHAMA_SHOT', defaultValue: 'local-phone-light');

/// Walks the app for design review: signs in a fresh number, chats with the
/// test peer (tools/peer), makes a group, and takes a screenshot of each
/// screen. Run through scripts/screenshots.sh.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('screenshots', (tester) async {
    expect(appPhone, isNotEmpty, reason: 'run through scripts/screenshots.sh');
    binding.platformDispatcher.platformBrightnessTestValue = prefix.endsWith('-dark')
        ? Brightness.dark
        : Brightness.light;
    binding.platformDispatcher.localesTestValue = const [Locale('pt', 'BR')];
    final photo = await _photo();
    await tester.pumpWidget(
      await app.bootstrap(
        newRecorder: FakeRecorder.new,
        pickFile: ({required image}) async => image
            ? PickedFile(name: 'praia.png', bytes: photo, mimeType: 'image/png')
            : PickedFile(
                name: 'Cardápio de domingo.pdf',
                bytes: [...'%PDF-1.4\n'.codeUnits, ...List.filled(48 * 1024, 32)],
                mimeType: 'application/pdf',
              ),
      ),
    );
    final t = _Shots(tester, binding);
    try {
      await _walk(tester, t);
    } catch (_) {
      await t.shot('failure'); // where it stopped
      rethrow;
    }
  }, timeout: const Timeout(Duration(minutes: 10)));
}

Future<void> _walk(WidgetTester tester, _Shots t) async {
  final wide = tester.view.physicalSize.width / tester.view.devicePixelRatio >= wideLayoutMinWidth;

  // Sign-in, SMS code, recovery key, profile.
  final d = appPhone.substring(2);
  await t.enter(const Key('phone_number'), '(${d.substring(0, 2)}) ${d.substring(2, 7)}-${d.substring(7)}');
  await t.shot('signin');
  await t.tap(const Key('sign_in_next'));
  await t.waitFor(find.byKey(const Key('sms_code')));
  await t.shot('sms-code');
  await t.enter(const Key('sms_code'), '000000'); // 6 digits submit on their own
  await t.waitFor(find.byKey(const Key('recovery_key')), timeout: const Duration(seconds: 60));
  await t.shot('recovery-key');
  await t.tap(const Key('recovery_key_saved'));
  await t.tap(const Key('recovery_key_done'));
  await t.enter(const Key('profile_name'), 'Ana Souza');
  await t.shot('profile');
  await t.tap(const Key('profile_done'));
  await t.waitFor(find.byType(HomeScreen));
  await t.shot('chat-list-empty');

  if (!wide) {
    for (final (icon, name) in [
      (Icons.update, 'tab-updates'),
      (Icons.groups_outlined, 'tab-communities'),
      (Icons.call_outlined, 'tab-calls'),
    ]) {
      await t.tapFinder(find.byIcon(icon));
      await t.shot(name);
    }
    await t.tapFinder(find.byIcon(Icons.chat_outlined));
  }

  // 1:1 chat with the peer, found by phone number.
  await t.tap(const Key('new_chat'));
  if (!kIsWeb) {
    // READ_CONTACTS was granted by scripts/drive.sh: the button asks nothing.
    if (find.byKey(const Key('contacts_allow')).evaluate().isNotEmpty) await t.tap(const Key('contacts_allow'));
    await t.waitFor(find.byKey(const Key('contacts_invite')), timeout: const Duration(seconds: 60));
  }
  await t.enter(const Key('new_chat_phone'), peerPhone.substring(2));
  await t.shot('new-chat');
  await t.tap(const Key('new_chat_phone_go'));
  await t.waitFor(find.text('oi, entrei'), timeout: const Duration(seconds: 60));
  final chats = Deps.of(tester.element(find.byType(ChatScreen))).chat;
  final dmId = tester.widget<ChatScreen>(find.byType(ChatScreen)).roomId;

  await t.send('Oi, Bruno! Tudo bem?');
  await t.waitFor(find.text('eco: Oi, Bruno! Tudo bem?'));

  // Reaction and reply on the peer's message.
  await t.longPress(find.text('oi, entrei'));
  await t.choose(find.byKey(const Key('react_❤️')));
  await t.longPress(find.text('oi, entrei'));
  await t.choose(find.widgetWithIcon(ListTile, Icons.reply));
  await t.send('Que bom que você entrou no Chama 🔥');
  await t.waitFor(find.text('eco: Que bom que você entrou no Chama 🔥'));

  // A photo, a file and a voice note through the composer.
  await t.tap(const Key('attach'));
  await t.tap(const Key('attach_photo'));
  await t.waitFor(find.text('recebi: foto criptografada'), timeout: const Duration(seconds: 60));
  await t.tap(const Key('attach'));
  await t.tap(const Key('attach_document'));
  await t.waitFor(find.text('Cardápio de domingo.pdf'));
  await t.holdMic(const Duration(milliseconds: 1500));
  await t.waitFor(find.text('recebi: voz criptografada'), timeout: const Duration(seconds: 60));
  await t.ticksRead();
  await t.shot('chat-media');

  // Edit (message actions sheet on my own message).
  await t.send('Chego às 12h30');
  await t.waitFor(find.text('eco: Chego às 12h30'));
  await t.longPress(find.text('Chego às 12h30'));
  await t.shot('message-actions');
  await t.choose(find.widgetWithIcon(ListTile, Icons.edit));
  await t.send('Chego às 13h');

  // Delete for everyone.
  await t.send('Mensagem errada');
  await t.waitFor(find.text('eco: Mensagem errada'));
  await t.longPress(find.text('Mensagem errada'));
  await t.choose(find.widgetWithIcon(ListTile, Icons.delete_outline));
  await t.shot('delete-dialog');
  await t.tap(const Key('delete_everyone'));

  await t.ticksRead();
  await t.shot('chat');
  await t.tap(const Key('chat_header'));
  await t.shot('contact-info');
  await t.closeInfo(wide);

  if (!wide) await t.back();

  // Group with the peer.
  await t.tap(const Key('new_chat'));
  await t.tap(const Key('new_group'));
  await t.enter(const Key('group_name'), 'Almoço de domingo');
  await t.enter(const Key('group_member_phone'), peerPhone.substring(2));
  await t.tap(const Key('group_member_phone_go'));
  await t.waitFor(find.byKey(const Key('group_members')));
  await t.shot('new-group');
  await t.tap(const Key('create_group'));
  await t.waitFor(find.text('oi, entrei'), timeout: const Duration(seconds: 60));
  await t.send('Quem leva a sobremesa? 🍰');
  await t.waitFor(find.text('eco: Quem leva a sobremesa? 🍰'));
  await t.ticksRead();
  await t.shot('group-chat');

  // One more 1:1 message, sent while the group is open: the peer's echo
  // gives the 1:1 chat an unread badge in the list.
  final dm = chats.openChat(dmId);
  await dm.sendText('Até amanhã! 👋');
  dm.dispose();
  await t.tap(const Key('chat_header'));
  await t.shot('group-info');
  await t.closeInfo(wide);
  if (!wide) await t.back();

  // Chat list with the unread badge, then the filters.
  await t.until(() => tester.widgetList<ChatTile>(find.byType(ChatTile)).any((c) => c.chat.isUnread));
  await t.shot('chat-list');
  for (final f in ['unread', 'groups']) {
    await t.tap(Key('filter_$f'));
    await t.shot('chat-list-$f');
  }
  await t.tap(const Key('filter_all'));

  // Chat actions sheet; archive the group and open "Arquivadas".
  await t.longPress(find.byKey(const Key('chat_Almoço de domingo')));
  await t.shot('chat-actions');
  await t.choose(find.widgetWithIcon(ListTile, Icons.archive_outlined));
  await t.tap(const Key('archived_row'));
  await t.shot('archived');
  await t.back();

  // Settings.
  tester.state<PopupMenuButtonState<void>>(find.byType(PopupMenuButton<void>).first).showButtonMenu();
  await t.settle();
  final item = find.widgetWithText(PopupMenuItem<void>, 'Configurações');
  await t.waitFor(item);
  final openSettings = tester.widget<PopupMenuItem<void>>(item).onTap!;
  Navigator.of(tester.element(item)).pop(); // what selecting the item does first
  openSettings();
  await t.settle();
  await t.shot('settings');
  await t.back();

  if (wide) {
    await t.tapFinder(find.byKey(const Key('chat_Bruno Lima')));
    await t.ticksRead();
    await t.shot('two-pane');
  }
}

/// A 640x480 "sunset" PNG drawn in code, so the test needs no asset.
Future<List<int>> _photo() async {
  final rec = ui.PictureRecorder();
  const size = Size(640, 480);
  Canvas(rec)
    ..drawRect(
      Offset.zero & size,
      Paint()
        ..shader = ui.Gradient.linear(Offset.zero, Offset(0, size.height), [
          const Color(0xFFFFC27A),
          const Color(0xFFE8590C),
        ]),
    )
    ..drawCircle(const Offset(460, 300), 70, Paint()..color = const Color(0xFFFFF1C9))
    ..drawRect(const Rect.fromLTWH(0, 360, 640, 120), Paint()..color = const Color(0xFF2B6C8F));
  final image = await rec.endRecording().toImage(size.width.toInt(), size.height.toInt());
  return (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
}

/// Steps against the live app (no pumpAndSettle: spinners never settle) plus
/// screenshots named `<prefix>-<screen>`.
class _Shots {
  _Shots(this.tester, this.binding);
  final WidgetTester tester;
  final IntegrationTestWidgetsFlutterBinding binding;
  bool _surfaceConverted = false;

  Future<void> settle() async {
    await Future<void>.delayed(const Duration(milliseconds: 700));
    await tester.pump();
  }

  Future<void> until(bool Function() ok, {Duration timeout = const Duration(seconds: 30)}) async {
    final end = DateTime.now().add(timeout);
    while (!ok()) {
      if (DateTime.now().isAfter(end)) throw TestFailure('Timed out');
      await tester.pump(const Duration(milliseconds: 250));
    }
  }

  Future<void> waitFor(Finder finder, {Duration timeout = const Duration(seconds: 30)}) async {
    final end = DateTime.now().add(timeout);
    while (finder.evaluate().isEmpty) {
      if (DateTime.now().isAfter(end)) throw TestFailure('Timed out waiting for $finder');
      await tester.pump(const Duration(milliseconds: 250));
    }
  }

  /// The callback a tap on [w] would run, for widgets that have one.
  static VoidCallback? _onTap(Widget w) => switch (w) {
    ButtonStyleButton() => w.onPressed,
    FloatingActionButton() => w.onPressed,
    IconButton() => w.onPressed,
    ListTile() => w.onTap,
    InkWell() => w.onTap,
    ChoiceChip(:final onSelected?) => () => onSelected(true),
    CheckboxListTile(:final onChanged?) => () => onChanged(true),
    _ => null,
  };

  /// Taps through the widget's own callback when it has one: synthetic taps
  /// are sometimes lost on web. Waits for a disabled button to enable.
  Future<void> tapFinder(Finder finder) async {
    await waitFor(finder);
    final w = tester.widget(finder.last);
    if (w is ButtonStyleButton ||
        w is FloatingActionButton ||
        w is IconButton ||
        w is CheckboxListTile ||
        _onTap(w) != null) {
      await until(() => _onTap(tester.widget(finder.last)) != null, timeout: const Duration(seconds: 10));
      _onTap(tester.widget(finder.last))!();
    } else {
      await tester.tap(finder.last);
    }
    await settle();
  }

  Future<void> tap(Key key) => tapFinder(find.byKey(key));

  // Synthetic taps and long presses on and into bottom sheets are sometimes
  // lost on web, so these two call the handlers the gestures would call.

  /// Opens the actions of a message bubble or chat tile (a sheet on phones,
  /// a menu on wide screens).
  Future<void> longPress(Finder finder) async {
    await waitFor(finder);
    final target = find.ancestor(
      of: finder.last,
      matchRoot: true,
      matching: find.byWidgetPredicate(
        (w) =>
            (w is GestureDetector && w.onLongPress != null) ||
            (w is InkWell && w.onLongPress != null) ||
            (w is ListTile && w.onLongPress != null),
      ),
    );
    final w = tester.widget(target.first);
    (switch (w) {
      ListTile() => w.onLongPress,
      InkWell() => w.onLongPress,
      _ => (w as GestureDetector).onLongPress,
    })!();
    await settle();
    await waitFor(find.byKey(const Key('actions')));
  }

  /// Records a voice note: calls the mic's long-press handlers the way a
  /// hold of [duration] would.
  Future<void> holdMic(Duration duration) async {
    final mic = find.ancestor(
      of: find.byKey(const Key('mic')),
      matching: find.byWidgetPredicate((w) => w is GestureDetector && w.onLongPressStart != null),
    );
    await waitFor(mic);
    final w = tester.widget<GestureDetector>(mic.first);
    w.onLongPressStart!(const LongPressStartDetails());
    final end = DateTime.now().add(duration);
    while (DateTime.now().isBefore(end)) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    await shot('recording');
    w.onLongPressEnd!(const LongPressEndDetails());
    await settle();
  }

  /// Picks an item (list tile or reaction) in the open sheet.
  Future<void> choose(Finder finder) async {
    await waitFor(finder);
    final w = tester.widget(finder.last);
    (w is ListTile ? w.onTap : (w as InkWell).onTap)!();
    await settle();
  }

  /// Types into a field the way the keyboard would: sets the text, then
  /// calls onChanged (focusing through a synthetic tap is flaky on web).
  Future<void> enter(Key key, String text) async {
    await waitFor(find.byKey(key));
    final field = tester.widget<TextField>(find.byKey(key));
    field.controller!.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    field.onChanged?.call(text);
    await tester.pump();
  }

  Future<void> send(String text) async {
    await enter(const Key('composer_text'), text);
    await tap(const Key('send'));
  }

  /// Contact/group info: a side pane with an X on wide screens, a page on phones.
  Future<void> closeInfo(bool wide) => wide ? tap(const Key('info_close')) : back();

  /// The app bar back arrow (tester.pageBack looks for the English tooltip).
  Future<void> back() async {
    final button = find.byType(BackButton);
    await waitFor(button);
    await Navigator.of(tester.element(button.last)).maybePop();
    await settle();
  }

  /// Best effort: gives the peer's read receipts up to 20 s to turn the ticks blue.
  Future<void> ticksRead() async {
    final end = DateTime.now().add(const Duration(seconds: 20));
    while (['tick_pending', 'tick_sent', 'tick_delivered'].any((k) => find.byKey(Key(k)).evaluate().isNotEmpty) &&
        DateTime.now().isBefore(end)) {
      await tester.pump(const Duration(milliseconds: 250));
    }
  }

  Future<void> shot(String name) async {
    FocusManager.instance.primaryFocus?.unfocus(); // no blinking cursor, no keyboard
    final android = !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
    if (android && !_surfaceConverted) {
      await binding.convertFlutterSurfaceToImage();
      _surfaceConverted = true;
    }
    // Android's image surface shows an older frame: render a few more first.
    for (var i = 0; i < (android ? 3 : 1); i++) {
      await settle();
    }
    await binding.takeScreenshot('$prefix-$name');
  }
}
