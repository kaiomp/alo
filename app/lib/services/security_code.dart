import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// `O código de segurança de <nome> mudou` (spec §5): pins the last master
/// key seen for each contact and, when it changes (an identity reset, or
/// someone else installing keys for that account), records a notice in every
/// chat shared with that person. Pinning is local, so it does not depend on
/// the operator.
class SecurityCodeWatch {
  SecurityCodeWatch(this._client, this._prefs) {
    final pins = _prefs.getString(_pinsKey);
    if (pins != null) _pins.addAll((jsonDecode(pins) as Map<String, dynamic>).cast<String, String>());
    final notices = _prefs.getString(_noticesKey);
    if (notices != null) {
      (jsonDecode(notices) as Map<String, dynamic>).forEach((room, list) {
        _notices[room] = [for (final n in list as List) (userId: n[0] as String, ts: n[1] as int)];
      });
    }
    _sub = _client.onSync.stream.listen((_) => check());
  }

  static const _pinsKey = 'chama.master_keys';
  static const _noticesKey = 'chama.security_notices';
  final Client _client;
  final SharedPreferences _prefs;
  late final StreamSubscription _sub;
  final Map<String, String> _pins = {};
  final Map<String, List<({String userId, int ts})>> _notices = {};

  /// Bumps when a notice is added, so open chats can redraw.
  final revision = ValueNotifier<int>(0);

  /// Notices for [roomId], oldest first.
  List<({String userId, int ts})> noticesIn(String roomId) => _notices[roomId] ?? const [];

  /// Compares every known master key with its pin. Runs after each sync,
  /// when the SDK has refreshed the device lists.
  void check() {
    final me = _client.userID;
    var pinsChanged = false;
    var noticesChanged = false;
    for (final MapEntry(key: userId, value: list) in _client.userDeviceKeys.entries) {
      final key = list.masterKey?.publicKey;
      if (userId == me || key == null || _pins[userId] == key) continue;
      final known = _pins[userId] != null;
      _pins[userId] = key;
      pinsChanged = true;
      if (!known) continue; // first sight: trust on first use
      final ts = DateTime.now().millisecondsSinceEpoch;
      for (final room in _client.rooms) {
        if (room.membership != Membership.join) continue;
        if (room.getState(EventTypes.RoomMember, userId)?.content['membership'] != Membership.join.name) continue;
        (_notices[room.id] ??= []).add((userId: userId, ts: ts));
        noticesChanged = true;
      }
    }
    if (pinsChanged) _prefs.setString(_pinsKey, jsonEncode(_pins));
    if (noticesChanged) {
      _prefs.setString(
        _noticesKey,
        jsonEncode({
          for (final MapEntry(:key, :value) in _notices.entries)
            key: [
              for (final n in value) [n.userId, n.ts],
            ],
        }),
      );
      revision.value++;
    }
  }

  /// Sign-out: the next account starts with no pins and no notices.
  Future<void> clear() async {
    _pins.clear();
    _notices.clear();
    await _prefs.remove(_pinsKey);
    await _prefs.remove(_noticesKey);
  }

  Future<void> dispose() => _sub.cancel();
}
