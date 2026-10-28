import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:ui';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';
import '../l10n/app_localizations.dart';
import '../services/chat_service.dart';
import '../services/models.dart' hide Message;
import 'theme.dart';

/// Notification text for [m]: the message, a label for media (never the
/// file name, which is often the sender's camera roll), or "Nova mensagem"
/// when it cannot be shown.
String notificationBody(IncomingMessage m, L10n l) => switch (m.kind) {
  MessageKind.undecryptable => l.newMessage,
  MessageKind.image => '📷 ${l.photo}',
  MessageKind.voice => '🎤 ${l.voiceMessage}',
  MessageKind.file => '📎 ${l.file}',
  _ => m.body,
};

/// The first 32 bits of the SHA-256 of [roomId]: Android's notification ID,
/// one per chat. Stable across runs (String.hashCode is not guaranteed to
/// be), so a later start of the app can still replace or cancel it.
/// Limit: Android IDs are 32-bit, so two chats can still share one, about
/// once in 4 billion pairs.
int notificationId(String roomId) {
  final h = sha256.convert(utf8.encode(roomId)).bytes;
  return (h[0] << 24 | h[1] << 16 | h[2] << 8 | h[3]).toSigned(32);
}

const replyActionId = 'reply';

/// One line of a chat's notification. Android tells people apart by the
/// person key: a hash of the user ID, so two senders with the same name stay
/// apart and no Matrix ID goes into the system's notification store.
Message notificationMessage(IncomingMessage m, L10n l) => Message(
  notificationBody(m, l),
  m.time,
  Person(
    name: m.senderName.isEmpty ? l.appName : m.senderName,
    key: m.senderId.isEmpty ? null : 's${notificationId(m.senderId)}',
  ),
);

/// Android notifications for new messages: one per chat, Android's
/// conversation style, a reply field and a tap that opens the chat.
class Notifications {
  final _plugin = FlutterLocalNotificationsPlugin();

  /// Chat to open, set when the user taps a notification or replies from one.
  final opened = ValueNotifier<String?>(null);

  /// Sends a reply typed in a notification. Set by the app before [init].
  Future<void> Function(String roomId, String text)? onReply;

  static const _secretKey = 'alo.notifications.secret';

  /// Marks the notifications this app posts, in their payload. MainActivity
  /// is exported (it is the launcher) and the plugin acts on any intent with
  /// its action and extras, so without it another app on the phone could
  /// make Alô send a reply. Random per install, kept in app-private storage.
  @visibleForTesting
  String? secret;

  /// Payload of [roomId]'s notifications.
  String _payload(String roomId) => '$secret|$roomId';

  /// The chat of a notification [payload], or null when it does not carry
  /// [secret] (not a notification of this app, or one from before it).
  @visibleForTesting
  String? roomOf(String? payload) {
    final s = secret;
    if (s == null || payload == null || !payload.startsWith('$s|')) return null;
    final roomId = payload.substring(s.length + 1);
    return roomId.isEmpty ? null : roomId;
  }

  Future<void> init() async {
    if (!onAndroid) return;
    final prefs = await SharedPreferences.getInstance();
    secret = prefs.getString(_secretKey);
    if (secret == null) {
      final r = Random.secure();
      secret = List.generate(16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
      await prefs.setString(_secretKey, secret!);
    }
    await _plugin.initialize(
      settings: const InitializationSettings(android: AndroidInitializationSettings('ic_notification')),
      onDidReceiveNotificationResponse: handleResponse,
    );
  }

  bool _launchChecked = false;

  /// With the screen up: a tap (or a reply) that started the activity. Once
  /// per process, so a second home screen does not send a reply again.
  Future<void> checkLaunch() async {
    if (!onAndroid || _launchChecked) return;
    _launchChecked = true;
    try {
      final launch = await _plugin.getNotificationAppLaunchDetails();
      final response = launch?.notificationResponse;
      if (launch?.didNotificationLaunchApp == true && response != null) await handleResponse(response);
    } catch (e) {
      debugPrint('Notifications: no launch details (${e.runtimeType})');
    }
  }

  String? _lastResponse;
  DateTime _lastResponseAt = DateTime(0);

  @visibleForTesting
  DateTime Function() clock = DateTime.now;

  /// A tap on a notification, or a reply typed in one.
  @visibleForTesting
  Future<void> handleResponse(NotificationResponse r) async {
    // Android can hand one tap over twice, a moment apart, when it restores
    // the app's task: as a new intent and as the launch intent. A reply must
    // be sent once; the same text typed again later is a new reply.
    final key = '${r.id}|${r.actionId}|${r.input}';
    final now = clock();
    if (key == _lastResponse && now.difference(_lastResponseAt) < const Duration(seconds: 5)) return;
    _lastResponse = key;
    _lastResponseAt = now;
    final roomId = roomOf(r.payload);
    if (roomId == null) return;
    // The chat opens at once; a reply goes out meanwhile and shows there,
    // as sending or failed.
    opened.value = roomId;
    final text = r.input?.trim() ?? '';
    // The reply action opens the app (showsUserInterface), so the message is
    // sent here, by the one client this process runs.
    if (r.actionId == replyActionId && text.isNotEmpty) unawaited(_sendReply(roomId, text));
  }

  /// The notification shows the reply at once: the send can wait a while
  /// for device lists (or the network), and the chat, opening, shows it as
  /// sending or failed.
  Future<void> _sendReply(String roomId, String text) async {
    final sent = () async {
      try {
        await onReply?.call(roomId, text);
      } catch (e) {
        // The type only: an error can quote the message.
        debugPrint('Notification reply failed (${e.runtimeType})');
      }
    }();
    try {
      await _showReply(roomId, text);
    } catch (e) {
      debugPrint('Notification update failed (${e.runtimeType})');
    }
    await sent;
  }

  /// Signed out (here, or remotely after an identity reset): no message
  /// preview stays on the shade or the lock screen.
  void clearOnSignOut(ValueListenable<bool> loggedIn) => loggedIn.addListener(() {
    if (!loggedIn.value) unawaited(cancelAll());
  });

  @visibleForTesting
  Future<void> cancelAll() async {
    if (onAndroid) await _plugin.cancelAll();
  }

  /// A push arrived ([PushService.onPush]): fetch, decrypt and show the
  /// message, unless the app is on screen (the chat list shows it already).
  Future<void> showPush(ChatService chat, String roomId, String eventId) async {
    if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed || !chat.loggedIn.value) return;
    // Limit: a closed app gets about 5-10 s from the distributor's wake-up
    // before Android may freeze it again, so a very slow network can delay the
    // notification. A short foreground service lifts that (FluffyChat starts one).
    final l = _strings();
    IncomingMessage? message;
    try {
      message = await chat.notificationFor(roomId, eventId);
    } catch (e) {
      // The type only: an error can quote the event.
      debugPrint('Push: could not load the message (${e.runtimeType})');
      // Still tell the user something arrived, without names or IDs.
      message = IncomingMessage.hidden(roomId: roomId, eventId: eventId, time: DateTime.now());
    }
    // Signed out while it loaded: cancelAll has run already.
    if (message != null && chat.loggedIn.value) await show(message, l);
  }

  /// pt-BR unless the phone uses another language the app has (no screen,
  /// so no BuildContext, in the background).
  L10n _strings() {
    final lang = PlatformDispatcher.instance.locale.languageCode;
    return lookupL10n(Locale(L10n.supportedLocales.any((s) => s.languageCode == lang) ? lang : 'pt'));
  }

  /// Android 13+ asks the user once; earlier versions allow it by default.
  Future<void> requestPermission() async {
    if (onAndroid) await _android?.requestNotificationsPermission();
  }

  /// False when Android blocks this app's notifications: the permission
  /// denied (Android 13+), or turned off in the system settings.
  Future<bool> enabled() async => !onAndroid || (await _android?.areNotificationsEnabled() ?? true);

  /// The system screen where the user turns this app's notifications on.
  Future<void> openSettings() async {
    if (onAndroid) await _android?.openAppNotificationSettings();
  }

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

  Future<void> show(IncomingMessage m, L10n l) =>
      _post(m.roomId, notificationMessage(m, l), l, isGroup: m.isGroup, chatName: m.chatName);

  /// After a reply typed in the notification: Android 15+ keeps that
  /// notification (with a spinner) until the app updates it, and ignores a
  /// [cancel] until then; a cancel right after the update still loses that
  /// race (seen on API 36). So the update shows the reply as mine, silently,
  /// and Android drops it a moment later; the chat is opening anyway.
  Future<void> _showReply(String roomId, String text) async {
    final id = notificationId(roomId);
    final shown = (await _android?.getActiveNotifications() ?? const []).where((n) => n.id == id).firstOrNull;
    if (shown == null) return;
    // A message with no person is the user's own.
    await _post(
      roomId,
      Message(text, DateTime.now(), null),
      _strings(),
      isGroup: shown.channelId == 'groups',
      dropAfter: const Duration(seconds: 2),
    );
  }

  Future<void> _post(
    String roomId,
    Message message,
    L10n l, {
    required bool isGroup,
    String chatName = '',
    Duration? dropAfter,
  }) async {
    final id = notificationId(roomId);
    // Earlier messages of the same chat that are still showing stay above it.
    final style = await _android?.getActiveNotificationMessagingStyle(id: id);
    style?.messages?.add(message);
    await _plugin.show(
      id: id,
      payload: _payload(roomId),
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          isGroup ? 'groups' : 'messages',
          isGroup ? l.channelGroups : l.channelMessages,
          importance: Importance.high,
          priority: Priority.high,
          category: AndroidNotificationCategory.message,
          color: Tokens.acai,
          silent: dropAfter != null,
          timeoutAfter: dropAfter?.inMilliseconds,
          when: message.timestamp.millisecondsSinceEpoch,
          styleInformation:
              style ??
              MessagingStyleInformation(
                Person(name: l.you),
                conversationTitle: isGroup ? chatName : null,
                groupConversation: isGroup,
                messages: [message],
              ),
          actions: [
            AndroidNotificationAction(
              replyActionId,
              l.reply,
              showsUserInterface: true,
              inputs: [AndroidNotificationActionInput(label: l.messageHint)],
              semanticAction: SemanticAction.reply,
            ),
          ],
        ),
      ),
    );
  }

  /// Removes the chat's notification (the chat was opened).
  Future<void> cancel(String roomId) async {
    if (onAndroid) await _plugin.cancel(id: notificationId(roomId));
  }
}
