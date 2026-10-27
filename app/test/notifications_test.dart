import 'dart:async';

import 'package:chama/common/notifications.dart';
import 'package:chama/l10n/app_localizations.dart';
import 'package:chama/services/models.dart' hide Message;
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes.dart';

class _Captured extends Notifications {
  final shown = <IncomingMessage>[];
  var cancelledAll = 0;

  @override
  Future<void> show(IncomingMessage m, L10n l) async => shown.add(m);

  @override
  Future<void> cancelAll() async => cancelledAll++;
}

const roomId = '!r:chama.test';
const secret = '0123456789abcdef0123456789abcdef';

NotificationResponse reply(String text, {String payload = '$secret|$roomId'}) => NotificationResponse(
  notificationResponseType: NotificationResponseType.selectedNotificationAction,
  id: 1,
  actionId: replyActionId,
  input: text,
  payload: payload,
);

IncomingMessage from(String senderId, String name) => IncomingMessage(
  roomId: roomId,
  eventId: r'$e',
  chatName: 'Família',
  senderId: senderId,
  senderName: name,
  kind: MessageKind.text,
  isGroup: true,
  time: DateTime(2026, 10, 24),
  body: 'oi',
);

void main() {
  final l = lookupL10n(const Locale('pt'));

  testWidgets('a push it cannot load shows only the app name and "Nova mensagem"', (tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    SharedPreferences.setMockInitialValues({});
    // No session on the client: loading the event fails.
    final chat = (await tester.runAsync(() async => testService(await SharedPreferences.getInstance())))!;
    chat.loggedIn.value = true;
    final notifications = _Captured();
    await tester.runAsync(() => notifications.showPush(chat, roomId, r'$e'));

    final m = notifications.shown.single;
    expect((m.chatName, m.senderName, m.senderId, m.body), ('', '', '', ''));
    expect(notificationMessage(m, l).person!.name, 'Alô');
    expect(notificationBody(m, l), 'Nova mensagem');
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });

  testWidgets('signed out, a push shows nothing and every notification goes', (tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    SharedPreferences.setMockInitialValues({});
    final chat = (await tester.runAsync(() async => testService(await SharedPreferences.getInstance())))!;
    chat.loggedIn.value = true;
    final notifications = _Captured()..clearOnSignOut(chat.loggedIn);
    chat.loggedIn.value = false;
    expect(notifications.cancelledAll, 1);
    await tester.runAsync(() => notifications.showPush(chat, roomId, r'$e'));
    expect(notifications.shown, isEmpty);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });

  testWidgets('no notification while the app is on screen', (tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    SharedPreferences.setMockInitialValues({});
    final chat = (await tester.runAsync(() async => testService(await SharedPreferences.getInstance())))!;
    final notifications = _Captured();
    await tester.runAsync(() => notifications.showPush(chat, roomId, r'$e'));
    expect(notifications.shown, isEmpty);
  });

  test('the notification names the sender, keyed by an opaque per-sender key', () {
    final ana = notificationMessage(from('@ana:chama.test', 'Ana'), l).person!;
    final otherAna = notificationMessage(from('@ana2:chama.test', 'Ana'), l).person!;
    expect(ana.name, 'Ana');
    expect(ana.key, notificationMessage(from('@ana:chama.test', 'Ana Paula'), l).person!.key);
    expect(ana.key, isNot(otherAna.key));
    expect(ana.key, isNot(anyOf(contains('Ana'), contains('@'), contains('chama.test'))));
  });

  group('a reply typed in a notification', () {
    late Notifications notifications;
    late List<String> sent;
    late DateTime now;

    setUp(() {
      notifications = Notifications()
        ..secret = secret
        ..clock = (() => now);
      sent = [];
      now = DateTime(2026, 10, 24, 12);
    });

    test('opens the chat at once and sends the reply in the background', () async {
      final sending = Completer<void>();
      notifications.onReply = (room, text) {
        sent.add(text);
        return sending.future;
      };
      await notifications.handleResponse(reply('já vou'));
      expect(notifications.opened.value, roomId);
      expect(sent, ['já vou']);
      sending.complete();
    });

    test('a failed send still opens the chat and throws nowhere', () async {
      notifications.onReply = (room, text) async => throw StateError('offline: $text');
      await notifications.handleResponse(reply('já vou'));
      await Future<void>.delayed(Duration.zero);
      expect(notifications.opened.value, roomId);
    });

    test('only from a notification this app posted: another app cannot make it send', () async {
      notifications.onReply = (room, text) async => sent.add(text);
      for (final payload in [roomId, 'guess|$roomId', '$secret|', '']) {
        await notifications.handleResponse(reply('manda o PIX', payload: payload));
      }
      expect(sent, isEmpty);
      expect(notifications.opened.value, isNull);
      expect(notifications.roomOf('$secret|$roomId'), roomId);
    });

    test('is sent once when Android hands it over twice, and again when typed again later', () async {
      notifications.onReply = (room, text) async => sent.add(text);
      await notifications.handleResponse(reply('ok'));
      now = now.add(const Duration(seconds: 2));
      await notifications.handleResponse(reply('ok'));
      expect(sent, ['ok']);
      now = now.add(const Duration(seconds: 6));
      await notifications.handleResponse(reply('ok'));
      expect(sent, ['ok', 'ok']);
    });
  });
}
