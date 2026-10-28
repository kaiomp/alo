import 'package:alo/chat/chat_screen.dart';
import 'package:alo/chat_list/chat_list_view.dart';
import 'package:alo/chat_list/chat_tile.dart';
import 'package:alo/config.dart';

import 'dart:io';

import 'package:alo/main.dart' as app;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

import 'fakes.dart';
import 'steps.dart';

// Set by scripts/e2e.sh: fresh random numbers each run, E.164 digits.
const appPhone = String.fromEnvironment('ALO_TEST_PHONE');
const peerPhone = String.fromEnvironment('ALO_PEER_PHONE');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('chat with the peer: ticks turn blue, photo, file and voice note arrive', (tester) async {
    expect(appPhone, isNotEmpty, reason: 'run through scripts/e2e.sh');
    await tester.pumpWidget(await app.bootstrap(newRecorder: FakeRecorder.new, pickFile: fakePickFile));
    final t = Steps(tester);
    await t.signIn(appPhone, 'Ana Teste');

    // New chat by phone number.
    await t.tap(const Key('new_chat'));
    await t.enter(const Key('new_chat_phone'), peerPhone.substring(2));
    await t.tap(const Key('new_chat_phone_go'));

    // Text, sent the moment the new chat opens: the peer is only invited and
    // its device list may still be loading, and it must still be able to
    // read it. Clock → ✓ → grey ✓✓ → blue ✓✓, and the peer's echo decrypts here.
    await t.enter(const Key('composer_text'), 'Olá, peer!');
    await t.tap(const Key('send'));
    await t.waitFor(find.text('oi, entrei'), timeout: const Duration(seconds: 60));
    await t.waitFor(find.byKey(const Key('tick_delivered')));
    await t.waitFor(find.byKey(const Key('tick_read')));
    await t.waitFor(find.text('eco: Olá, peer!'));

    // Photo (encrypted attachment): the peer decrypts it, and the thumbnail
    // decrypts and shows here.
    await t.tap(const Key('attach'));
    await t.tap(const Key('attach_photo'));
    await t.waitFor(find.text('recebi: foto criptografada'), timeout: const Duration(seconds: 60));
    await t.waitFor(_keyPrefix('image_'));

    // File: name and size with a download button.
    await t.tap(const Key('attach'));
    await t.tap(const Key('attach_document'));
    await t.waitFor(find.text('nota.txt'));
    await t.waitFor(_keyPrefix('download_'));

    // Voice note: hold the mic, release to send.
    await t.waitFor(find.byKey(const Key('mic')).hitTestable()); // attach sheet gone
    final hold = await tester.startGesture(tester.getCenter(find.byKey(const Key('mic'))));
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    await tester.pump();
    expect(find.byKey(const Key('recording_timer')), findsOneWidget);
    await hold.up();
    await t.waitFor(find.text('recebi: voz criptografada'), timeout: const Duration(seconds: 60));
    await t.waitFor(_keyPrefix('voice_play_'));

    // Play it: download, decrypt, load into the player.
    final play = _keyPrefix('voice_play_').last;
    final voiceId = (tester.widget(play).key! as ValueKey<String>).value.substring('voice_play_'.length);
    await t.waitFor(play.hitTestable());
    await tester.tap(play);
    await t.waitFor(find.byIcon(Icons.pause_rounded));
    // Native: the decrypted copy sits in the temp folder while the player lives.
    if (!kIsWeb) expect(await _voiceTempFiles(voiceId), hasLength(1));

    // Archive the chat, then open it from "Arquivadas". Wide: the archived
    // list closes and the chat shows in the right pane. Phone: the chat was
    // pushed over the list, so go back first; it then opens over "Arquivadas".
    final wide = tester.view.physicalSize.width / tester.view.devicePixelRatio >= wideLayoutMinWidth;
    if (!wide) {
      Navigator.of(tester.element(find.byType(ChatScreen))).pop();
      await t.until(() => find.byType(ChatScreen).evaluate().isEmpty, 'the chat to close');
      // The popped route disposes the player a few frames later.
      if (!kIsWeb) {
        for (var i = 0; i < 20 && (await _voiceTempFiles(voiceId)).isNotEmpty; i++) {
          await tester.pump(const Duration(milliseconds: 250));
        }
        expect(await _voiceTempFiles(voiceId), isEmpty, reason: 'decrypted voice note left behind');
      }
    }
    await t.waitFor(find.byType(ChatTile).hitTestable());
    await tester.longPress(find.byType(ChatTile));
    final archive = find.widgetWithIcon(ListTile, Icons.archive_outlined).hitTestable();
    await t.waitFor(archive); // sheet slid in
    await tester.tap(archive);
    await t.tap(const Key('archived_row'));
    await t.waitFor(find.byType(ChatTile).hitTestable());
    await tester.tap(find.byType(ChatTile));
    await t.waitFor(find.byType(ChatScreen));
    final archivedList = find.byWidgetPredicate((w) => w is ChatListView && w.archived);
    if (wide) await t.until(() => archivedList.evaluate().isEmpty, 'the archived list to close');
    expect(find.byType(ChatScreen), findsOneWidget);
  }, timeout: const Timeout(Duration(minutes: 5)));
}

/// The player's decrypted copies of voice note [id] (voice_player.dart).
Future<List<FileSystemEntity>> _voiceTempFiles(String id) async {
  final prefix = 'voz_${id.hashCode.toUnsigned(32)}.';
  final dir = await getTemporaryDirectory();
  return dir.listSync().where((f) => f.uri.pathSegments.last.startsWith(prefix)).toList();
}

/// Widgets whose string key starts with [prefix] (keys that carry a message ID).
Finder _keyPrefix(String prefix) =>
    find.byWidgetPredicate((w) => w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.startsWith(prefix));
