import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// To-device event a recipient sends back when messages reach its device
/// (spec section 6, "Ticks ✓✓ delivered").
const deliveredEventType = 'chat.chama.delivered';

/// Above this many members a group sends and shows no grey ✓✓ (spec §6, ticks).
const deliveryMaxMembers = 32;

/// Sends and receives `chat.chama.delivered`.
///
/// Outgoing: every message from someone else that arrives by sync is acked to
/// the sender's devices, batched per sender and room once a second.
/// Incoming: keeps, per room and member, the newest message timestamp that
/// member confirmed, saved in shared preferences so ticks survive a restart.
class DeliveryTracker {
  DeliveryTracker(this._client, this._prefs) {
    final saved = _prefs.getString(_prefsKey);
    if (saved != null) {
      final json = jsonDecode(saved) as Map<String, dynamic>;
      json.forEach((room, users) {
        _upTo[room] = (users as Map<String, dynamic>).map((u, ts) => MapEntry(u, ts as int));
      });
    }
    _subs.add(_client.onTimelineEvent.stream.listen(_onTimelineEvent));
    _subs.add(_client.onToDeviceEvent.stream.where((e) => e.type == deliveredEventType).listen(_onDelivered));
  }

  static const _prefsKey = 'chama.delivered';
  final Client _client;
  final SharedPreferences _prefs;
  final _subs = <StreamSubscription>[];
  final Map<String, Map<String, int>> _upTo = {};

  /// sender -> room -> (event IDs, newest timestamp)
  final Map<String, Map<String, ({List<String> ids, int ts})>> _queue = {};
  Timer? _flush;

  /// Bumps whenever any delivery state changes, so open chats can redraw.
  final revision = ValueNotifier<int>(0);

  /// Newest confirmed timestamp per member of [roomId].
  Map<String, int> deliveredUpTo(String roomId) => _upTo[roomId] ?? const {};

  void _onTimelineEvent(Event e) {
    if (e.senderId == _client.userID) return;
    if (e.type != EventTypes.Message && e.type != EventTypes.Encrypted) return;
    // Large groups get no delivery acks (spec §6): too many to-device messages.
    if ((e.room.summary.mJoinedMemberCount ?? 0) > deliveryMaxMembers) return;
    final perRoom = _queue.putIfAbsent(e.senderId, () => {});
    final prev = perRoom[e.room.id];
    final ts = e.originServerTs.millisecondsSinceEpoch;
    perRoom[e.room.id] = (ids: [...?prev?.ids, e.eventId], ts: prev == null || ts > prev.ts ? ts : prev.ts);
    _flush ??= Timer(const Duration(seconds: 1), _send);
  }

  Future<void> _send() async {
    _flush = null;
    final batch = Map.of(_queue);
    _queue.clear();
    for (final MapEntry(key: sender, value: rooms) in batch.entries) {
      for (final MapEntry(key: roomId, value: item) in rooms.entries) {
        try {
          await _client.sendToDevicesOfUserIds(
            {sender},
            deliveredEventType,
            {'room_id': roomId, 'event_ids': item.ids, 'ts': item.ts},
          );
        } catch (e, s) {
          Logs().w('Could not send delivery receipt', e, s);
        }
      }
    }
  }

  Future<void> _onDelivered(ToDeviceEvent e) async {
    final roomId = e.content['room_id'];
    final ts = e.content['ts'];
    final room = roomId is String ? _client.getRoomById(roomId) : null;
    if (room == null || ts is! int || e.sender == _client.userID) return;
    // A forged ack only changes a tick colour, so a membership check is
    // enough. Memory or the local database (rooms load partially): encrypted
    // rooms keep their full member list, so no server call is needed.
    final member = await room.requestUser(e.sender, ignoreErrors: true, requestState: false, requestProfile: false);
    if (member?.membership != Membership.join) return;
    final users = _upTo.putIfAbsent(room.id, () => {});
    if ((users[e.sender] ?? -1) >= ts) return;
    users[e.sender] = ts;
    _prefs.setString(_prefsKey, jsonEncode(_upTo));
    revision.value++;
  }

  Future<void> dispose() async {
    _flush?.cancel();
    for (final s in _subs) {
      await s.cancel();
    }
  }
}
