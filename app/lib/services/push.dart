import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:unifiedpush/unifiedpush.dart';

import '../config.dart';
import 'chat_service.dart';

/// app_id of Chama pushers. Sygnal sends it to its Web Push pushkin
/// (server/sygnal/sygnal.yaml).
const pushAppId = 'chat.chama.app';

/// Room and event of a push from Sygnal's Web Push pushkin (event_id_only:
/// no content), or null for anything else.
({String roomId, String eventId})? parsePush(List<int> content) {
  try {
    final json = jsonDecode(utf8.decode(content));
    final roomId = json['room_id'], eventId = json['event_id'];
    if (roomId is String && eventId is String) return (roomId: roomId, eventId: eventId);
  } catch (_) {
    // Not JSON: not ours.
  }
  return null;
}

/// UnifiedPush (spec §6): the user's distributor app (ntfy, or the embedded
/// FCM distributor in the Play build) gives an endpoint; the server's pusher
/// sends an encrypted Web Push there through Sygnal; [onPush] gets the room
/// and event of each one. Endpoints and keys are never logged.
class PushService {
  PushService(this._chat, this._prefs, {http.Client? httpClient}) : _http = httpClient ?? http.Client() {
    _chat.loggedIn.addListener(_onLoginChanged);
    _chat.onSigningOut = _dropPusher;
  }

  final ChatService _chat;
  final SharedPreferences _prefs;
  final http.Client _http;
  static const _pushkeyKey = 'chama.push.pushkey';

  /// True while this device has a pusher on the server.
  final active = ValueNotifier<bool>(false);

  /// Called for each push. Set before [init]: a push that started the app is
  /// delivered right after it.
  Future<void> Function(String roomId, String eventId)? onPush;

  /// Runs at every start, also in the background: UnifiedPush holds the
  /// message that woke the app until this registers the callbacks.
  Future<void> init() async {
    if (!onAndroid) return;
    active.value = _prefs.getString(_pushkeyKey) != null;
    await UnifiedPush.initialize(
      onNewEndpoint: (e, _) => unawaited(_onNewEndpoint(e)),
      onUnregistered: (_) => unawaited(_dropPusher()),
      onRegistrationFailed: (reason, _) => Logs().w('Push registration failed: ${reason.name}'),
      onMessage: (m, _) => unawaited(_onMessage(m)),
    );
  }

  /// With the app on screen (the distributor may show a chooser): uses the
  /// distributor the user has and registers. False when there is none, or
  /// when the server has no push gateway. Calls made while one runs share it,
  /// so the distributor's chooser opens once.
  Future<bool> register() => _registering ??= _register().whenComplete(() => _registering = null);
  Future<bool>? _registering;

  /// Back on screen with no pusher: the user may just have installed a
  /// distributor, as Settings tells them to, so registration runs again.
  /// Limit: with several distributors and none picked, the chooser opens on
  /// each return until the user picks one.
  void resumed() {
    if (onAndroid && !active.value && _chat.loggedIn.value) unawaited(register());
  }

  Future<bool> _register() async {
    if (!onAndroid) return false;
    final config = await _config();
    if (config == null) return false;
    try {
      if (!await UnifiedPush.tryUseCurrentOrDefaultDistributor()) return false;
      await UnifiedPush.register(vapid: config.vapid);
      return true;
    } on PlatformException catch (e) {
      // The distributor app can be gone or its binder dead: no push, no crash.
      Logs().w('Push registration failed (${e.code})');
      return false;
    }
  }

  /// Settings: whether the server still has this device's pusher (Synapse
  /// drops pushers whose endpoint keeps failing). Offline, the last known
  /// state stays.
  Future<void> refresh() async {
    final key = _prefs.getString(_pushkeyKey);
    if (key == null || !_chat.client.isLogged()) return;
    try {
      final pushers = await _chat.client.getPushers() ?? const [];
      active.value = pushers.any((p) => p.appId == pushAppId && p.pushkey == key);
    } catch (e) {
      Logs().w('Could not check the pusher (${e.runtimeType})');
    }
  }

  /// The server's push gateway (as Synapse reaches it) and Sygnal's VAPID key.
  Future<({Uri gateway, String vapid})?> _config() async {
    try {
      final res = await _http.get(_chat.homeserver.resolve('/push/v1/config')).timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return null;
      final json = jsonDecode(res.body) as Map<String, dynamic>;
      return (gateway: Uri.parse(json['gateway'] as String), vapid: json['vapid'] as String);
    } catch (e) {
      Logs().w('No push config', e);
      return null;
    }
  }

  Future<void> _onNewEndpoint(PushEndpoint e) async {
    final keys = e.pubKeySet;
    if (keys == null) return;
    try {
      await postPusher(endpoint: e.url, pubKey: keys.pubKey, auth: keys.auth);
    } catch (err) {
      // Not the error itself: a failed request could carry the endpoint.
      Logs().w('Could not register the pusher (${err.runtimeType})');
    }
  }

  /// Posts this device's pusher for a distributor [endpoint] and its Web Push
  /// keys. Security (spec §5): `event_id_only`, so Sygnal gets room and event
  /// IDs only, never the sender, the room name or the message.
  @visibleForTesting
  Future<void> postPusher({required String endpoint, required String pubKey, required String auth}) async {
    final config = await _config();
    if (config == null || !_chat.client.isLogged()) return;
    final old = _prefs.getString(_pushkeyKey);
    if (old != null && old != pubKey) await _deletePusher(old);
    // Posted at every start: the server drops pushers whose endpoint failed.
    await _chat.client.postPusher(
      Pusher(
        appId: pushAppId,
        pushkey: pubKey,
        appDisplayName: 'Chama',
        deviceDisplayName: _chat.client.deviceName ?? 'Chama',
        lang: 'pt-BR',
        kind: 'http',
        data: PusherData(
          url: config.gateway,
          format: 'event_id_only',
          // Limit: no badge-only pushes (events_only), so a chat read on another
          // device keeps its notification here until this app opens; sending
          // them would wake the phone for every read.
          additionalProperties: {'endpoint': endpoint, 'auth': auth, 'events_only': true},
        ),
      ),
    );
    await _prefs.setString(_pushkeyKey, pubKey);
    active.value = true;
  }

  Future<void> _deletePusher(String pushkey) async {
    try {
      await _chat.client.deletePusher(PusherId(appId: pushAppId, pushkey: pushkey));
    } catch (e) {
      Logs().w('Could not delete old pusher (${e.runtimeType})');
    }
  }

  Future<void> _dropPusher() async {
    final old = _prefs.getString(_pushkeyKey);
    if (old != null && _chat.client.isLogged()) await _deletePusher(old);
    await _prefs.remove(_pushkeyKey);
    active.value = false;
  }

  Future<void> _onMessage(PushMessage m) async {
    final push = m.decrypted ? parsePush(m.content) : null;
    if (push != null) await onPush?.call(push.roomId, push.eventId);
  }

  /// Sign-out: [_dropPusher] deletes the server pusher first (a refused or
  /// offline logout must not leave it pushing); here the distributor forgets
  /// the endpoint, so nothing reaches it again.
  void _onLoginChanged() {
    if (_chat.loggedIn.value || !onAndroid) return;
    active.value = false;
    unawaited(_prefs.remove(_pushkeyKey));
    unawaited(
      UnifiedPush.unregister().catchError((Object e) => Logs().w('Could not unregister push (${e.runtimeType})')),
    );
  }
}
