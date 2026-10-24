import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:matrix/matrix.dart';

import 'chat_service.dart';
import 'event_mapping.dart';
import 'models.dart';

/// One open chat: its timeline as [Message]s plus every action on it.
class ChatSession extends ChangeNotifier {
  ChatSession(this._service, this._room);

  final ChatService _service;
  final Room _room;
  Timeline? _timeline;
  final _subs = <StreamSubscription>[];
  DateTime _lastTypingSent = DateTime(0);
  bool _visible = true;
  bool _disposed = false;

  /// Newest first, as the SDK keeps them.
  List<Message> messages = const [];
  bool loading = true;
  OnlineStatus? presence;

  String get roomId => _room.id;
  String get name => _service.chatName(_room);
  Uri? get avatar => _room.avatar;
  bool get isGroup => !_room.isDirectChat;

  /// Messages here are end-to-end encrypted. False for a chat whose
  /// encryption I cannot switch on: the screen says so and sending is off.
  bool get encrypted => _room.encrypted && _service.client.encryptionEnabled;
  bool get canLoadMore => _timeline?.canRequestHistory ?? false;

  /// Older messages remain on the server, not just in the local database
  /// (whose pages load within a few frames).
  bool get moreOnServer => canLoadMore && _room.prev_batch != null;

  /// Display names of members typing right now (me excluded).
  List<String> get typing => _room.typingUsers.where((u) => u.id != _service.myUserId).map(_service.nameOf).toList();

  List<Member> get members => _room
      .getParticipants([Membership.join])
      .map(
        (u) => Member(
          userId: u.id,
          name: _service.nameOf(u),
          isAdmin: _room.getPowerLevelByUserId(u.id).level >= 100,
          avatar: u.avatarUrl,
        ),
      )
      .toList();

  bool get iAmAdmin => _room.getPowerLevelByUserId(_service.myUserId).level >= 100;

  Future<void> open() async {
    final timeline = await _room.getTimeline(onUpdate: _rebuild);
    // The user may leave the chat before the timeline loads.
    if (_disposed) return timeline.cancelSubscriptions();
    _timeline = timeline;
    _subs.add(
      _service.client.onSync.stream
          .where((s) => s.rooms?.join?.containsKey(_room.id) ?? false)
          .listen((_) => notifyListeners()),
    );
    _service.delivery.revision.addListener(_rebuild);
    _service.securityCodes.revision.addListener(_rebuild);
    _service.namesRevision.addListener(_rebuild);
    final other = _room.directChatMatrixID;
    if (other != null) {
      _subs.add(_service.client.onPresenceChanged.stream.where((p) => p.userid == other).listen(_setPresence));
      unawaited(
        _service.client
            .fetchCurrentPresence(other)
            .then(_setPresence)
            .catchError((Object e) => Logs().w('Presence fetch failed', e)),
      );
    }
    loading = false;
    _rebuild();
  }

  void _setPresence(CachedPresence p) {
    if (_disposed) return;
    presence = OnlineStatus(
      online: p.currentlyActive == true || p.presence == PresenceType.online,
      lastSeen: p.lastActiveTimestamp,
    );
    notifyListeners();
  }

  /// Called by the chat screen when it is shown or hidden (app paused,
  /// another chat selected). Read receipts go out only while visible.
  set visible(bool v) {
    _visible = v;
    if (!v) return;
    _shown = true;
    unawaited(markRead());
  }

  void _rebuild() {
    final timeline = _timeline;
    if (timeline == null || _disposed) return;
    final hidden = hiddenEventIds(_room);
    final knownTs = {for (final e in timeline.events) e.eventId: e.originServerTs.millisecondsSinceEpoch};
    messages = [
      for (final e in timeline.events)
        if (isVisible(e, isGroup: isGroup, hidden: hidden)) _toMessage(e, timeline, knownTs),
    ];
    _insertSecurityNotices();
    notifyListeners();
    if (_visible) unawaited(markRead());
  }

  Message _toMessage(Event raw, Timeline timeline, Map<String, int> knownTs) {
    final e = raw.getDisplayEvent(timeline);
    final kind = kindOf(raw.redacted ? raw : e);
    final mine = raw.senderId == _service.myUserId;
    final audio = e.content.tryGetMap<String, Object?>('org.matrix.msc1767.audio');
    final info = e.infoMap;
    final replyId = raw.inReplyToEventId();
    final replyEvent = replyId == null ? null : timeline.events.where((x) => x.eventId == replyId).firstOrNull;
    return Message(
      id: raw.eventId,
      senderId: raw.senderId,
      senderName: _service.nameOf(raw.senderFromMemoryOrFallback),
      isMine: mine,
      time: raw.originServerTs,
      kind: kind,
      body: _bodyWithoutReplyFallback(e),
      edited: raw.hasAggregatedEvents(timeline, RelationshipTypes.edit),
      tick: mine && kind != MessageKind.system ? _service.tickOf(_room, raw, knownTs) : null,
      reply: replyEvent == null
          ? null
          : ReplyPreview(
              eventId: replyEvent.eventId,
              senderName: _service.nameOf(replyEvent.senderFromMemoryOrFallback),
              body: _bodyWithoutReplyFallback(replyEvent.getDisplayEvent(timeline)),
              kind: kindOf(replyEvent),
            ),
      reactions: _reactions(raw, timeline),
      durationMs: (audio?['duration'] as int?) ?? (info['duration'] as int?),
      waveform: (audio?['waveform'] as List?)?.whereType<int>().toList(),
      width: info['w'] as int?,
      height: info['h'] as int?,
      size: info['size'] as int?,
      mimeType: info['mimetype'] as String?,
      systemKind: kind == MessageKind.system ? systemKindOf(raw) : null,
      systemTarget: switch (raw.type) {
        EventTypes.RoomName => raw.content['name'] as String?,
        EventTypes.RoomMember => _service.nameOf(_room.unsafeGetUserFromMemoryOrFallback(raw.stateKey ?? '')),
        _ => null,
      },
      systemTargetId: raw.type == EventTypes.RoomMember ? raw.stateKey : null,
    );
  }

  /// Local "security code changed" and "number moved" lines, placed by time among the messages
  /// (newest first). Only those within the loaded range, so they do not
  /// pile up above the oldest loaded message.
  void _insertSecurityNotices() {
    final notices = _service.securityCodes.noticesIn(_room.id);
    if (notices.isEmpty) return;
    final list = [...messages];
    for (final n in notices) {
      final time = DateTime.fromMillisecondsSinceEpoch(n.ts);
      if (list.isNotEmpty && canLoadMore && time.isBefore(list.last.time)) continue;
      final at = list.indexWhere((m) => !m.time.isAfter(time));
      list.insert(
        at < 0 ? list.length : at,
        Message(
          id: 'security_${n.userId}_${n.ts}',
          senderId: n.userId,
          senderName: n.name ?? _service.nameOf(_room.unsafeGetUserFromMemoryOrFallback(n.userId)),
          isMine: false,
          time: time,
          kind: MessageKind.system,
          systemKind: n.name == null ? SystemKind.securityCodeChanged : SystemKind.numberMoved,
          systemTargetId: n.userId,
        ),
      );
    }
    messages = list;
  }

  /// Old clients put "> quoted text" in the body of replies; drop it.
  String _bodyWithoutReplyFallback(Event e) {
    final body = previewText(e);
    if (e.inReplyToEventId() == null || !body.startsWith('> ')) return body;
    final lines = body.split('\n');
    final start = lines.indexWhere((l) => !l.startsWith('>'));
    return start < 0 ? '' : lines.sublist(start).join('\n').trimLeft();
  }

  List<Reaction> _reactions(Event e, Timeline timeline) {
    final byKey = <String, List<Event>>{};
    for (final r in e.aggregatedEvents(timeline, RelationshipTypes.reaction)) {
      final key = reactionKey(r);
      if (key != null) (byKey[key] ??= []).add(r);
    }
    return [
      for (final MapEntry(:key, value: events) in byKey.entries)
        Reaction(
          key,
          events.length,
          mine: events.any((r) => r.senderId == _service.myUserId),
          senders: [for (final r in events) _service.nameOf(r.senderFromMemoryOrFallback)],
        ),
    ];
  }

  Event? _event(String id) => _timeline?.events.where((e) => e.eventId == id).firstOrNull;

  // ---- actions ----

  bool _loadingMore = false;

  /// Older messages; safe to call repeatedly while scrolling.
  Future<void> loadMore() async {
    if (_loadingMore || !canLoadMore) return;
    _loadingMore = true;
    try {
      await _timeline!.requestHistory();
    } finally {
      _loadingMore = false;
    }
  }

  /// The event my last read marker went to. The unread count and my own
  /// receipt change only with the next sync, so without this every redraw
  /// until then would send the marker again.
  String? _readUpTo;

  /// The chat was just opened or the app came back to it: a "não lida" mark
  /// goes. A mark set while the chat is open holds until then (or until a
  /// new message is read).
  bool _shown = true;

  Future<void> markRead() async {
    final t = _timeline;
    if (t == null) return;
    final shown = _shown;
    _shown = false;
    final newest = newestReadable(t.events);
    final post =
        newest != null &&
        newest.eventId != _readUpTo &&
        (_room.notificationCount > 0 || _room.hasNewMessages || _room.markedUnread);
    // Set before any await: redraws come in bursts.
    if (post) _readUpTo = newest.eventId;
    try {
      if (_room.markedUnread && (shown || post)) await _room.markUnread(false);
      if (post) await t.setReadMarker(eventId: newest.eventId, public: _service.readReceipts);
    } catch (e) {
      if (post) _readUpTo = null; // the next update tries again
      Logs().w('Could not mark the chat read', e);
    }
  }

  /// Spec §5: nothing goes out in clear. The SDK would send plaintext into a
  /// room without m.room.encryption, or when its encryption is off.
  void _mustBeEncrypted() {
    if (!encrypted) throw StateError('Chat ${_room.id} is not end-to-end encrypted');
  }

  /// First pause before device lists that did not load are asked for
  /// again; it doubles up to [_deviceListCap].
  @visibleForTesting
  static Duration deviceListRetry = const Duration(seconds: 1);

  /// Bound on the device-list refresh before "typing": on a stalled network
  /// the key query would wait the SDK's 35 s request timeout.
  @visibleForTesting
  static const typingDeviceListTimeout = Duration(seconds: 5);

  /// Longest pause between two tries, and longest wait for one /keys/query.
  static const _deviceListCap = Duration(seconds: 30);

  /// One refresh of the members' device lists that are missing or outdated,
  /// bounded by [timeout]. True once none is left. Members are the joined and
  /// the invited (a new chat's peer is only invited at first).
  Future<bool> _refreshDeviceLists(Duration timeout) async {
    final client = _service.client;
    bool stale(String userId) => client.userDeviceKeys[userId]?.outdated != false;
    try {
      return await () async {
        final members = await _room.requestParticipants(const [Membership.join, Membership.invite], true);
        final outdated = {
          for (final u in members)
            if (stale(u.id)) u.id,
        };
        if (outdated.isEmpty) return true;
        // Swallows its errors, and a list it could not load stays outdated.
        await client.updateUserDeviceKeys(additionalUsers: outdated);
        return !outdated.any(stale);
      }().timeout(timeout);
    } catch (e) {
      Logs().w('Could not refresh device lists', e);
      return false;
    }
  }

  /// The SDK makes the room key for the devices in the members' device
  /// lists, and a list still loading (or whose /keys/query failed) counts as
  /// "no devices". A member left out then can never read the message: the
  /// first message of a room key is never re-shared. So a send waits until
  /// every list has loaded, asking again after a pause that doubles up to
  /// 30 s, for as long as it takes. Meanwhile the message shows as pending
  /// (the clock), also offline. Signed out, it stops waiting.
  Future<void> _deviceListsReady() async {
    var pause = deviceListRetry;
    while (!await _refreshDeviceLists(_deviceListCap)) {
      if (!_service.client.isLogged()) return;
      await Future<void>.delayed(pause);
      pause = pause * 2 > _deviceListCap ? _deviceListCap : pause * 2;
    }
  }

  /// Runs [send] (an SDK send) while the room's send queue is held until the
  /// device lists are ready: the SDK shows (and stores) the pending message
  /// at once, and encrypts it, making the room key, only once released.
  Future<T> _send<T>(Future<T> Function() send) async {
    _mustBeEncrypted();
    final hold = Completer<void>();
    _room.sendingQueue.add(hold);
    final ready = _deviceListsReady().whenComplete(() {
      _room.sendingQueue.remove(hold);
      hold.complete();
    });
    try {
      return await send();
    } finally {
      await ready;
    }
  }

  Future<void> sendText(String text, {String? replyTo, String? editOf}) async {
    await _send(
      () => _room.sendTextEvent(
        text,
        inReplyTo: replyTo == null ? null : _event(replyTo),
        editEventId: editOf,
        parseCommands: false,
        parseMarkdown: false,
      ),
    );
    await setTyping(false);
  }

  Future<void> sendImage(PickedFile file, {String? replyTo}) async {
    await _send(() async {
      final image = await MatrixImageFile.create(
        bytes: Uint8List.fromList(file.bytes),
        name: file.name,
        mimeType: file.mimeType,
        nativeImplementations: _service.client.nativeImplementations,
      );
      return _room.sendFileEvent(
        image,
        shrinkImageMaxDimension: 1600,
        inReplyTo: replyTo == null ? null : _event(replyTo),
      );
    });
  }

  Future<void> sendFile(PickedFile file, {String? replyTo}) async {
    await _send(
      () => _room.sendFileEvent(
        MatrixFile(bytes: Uint8List.fromList(file.bytes), name: file.name, mimeType: file.mimeType),
        inReplyTo: replyTo == null ? null : _event(replyTo),
      ),
    );
  }

  /// Voice note as FluffyChat sends it (lib/pages/chat/chat.dart,
  /// onVoiceMessageSend): m.audio + MSC3245 voice flag + MSC1767 waveform.
  Future<void> sendVoice({
    required Uint8List bytes,
    required String mimeType,
    required int durationMs,
    required List<int> waveform,
    String? replyTo,
  }) async {
    final ext = ['wav', 'ogg', 'webm'].firstWhere(mimeType.contains, orElse: () => 'm4a');
    final file = MatrixAudioFile(
      bytes: bytes,
      name: 'voz_${DateTime.now().millisecondsSinceEpoch}.$ext',
      mimeType: mimeType,
      duration: durationMs,
    );
    await _send(
      () => _room.sendFileEvent(
        file,
        inReplyTo: replyTo == null ? null : _event(replyTo),
        extraContent: {
          'info': {...file.info, 'duration': durationMs},
          'org.matrix.msc3245.voice': <String, Object?>{},
          'org.matrix.msc1767.audio': {'duration': durationMs, 'waveform': waveform},
        },
      ),
    );
  }

  /// Adds my reaction [key], or removes it when I already reacted with it.
  Future<void> toggleReaction(String messageId, String key) async {
    final e = _event(messageId);
    final t = _timeline;
    if (e == null || t == null) return;
    final mine = e
        .aggregatedEvents(t, RelationshipTypes.reaction)
        .where((r) => r.senderId == _service.myUserId && reactionKey(r) == key)
        .firstOrNull;
    if (mine != null) {
      await _room.redactEvent(mine.eventId);
      return;
    }
    // The SDK sends a reaction (only m.relates_to) unencrypted, emoji in
    // clear. With another field it encrypts, keeping m.relates_to outside the
    // ciphertext; Synapse needs a key there, so it gets a random one.
    // Limit: the server still sees who reacted to which message, and other
    // Matrix clients show the placeholder instead of the emoji.
    await _send(
      () => _room.sendEvent({
        'm.relates_to': {
          'rel_type': RelationshipTypes.reaction,
          'event_id': messageId,
          'key': _service.client.generateUniqueTransactionId(),
        },
        reactionKeyField: key,
      }, type: EventTypes.Reaction),
    );
  }

  Future<void> deleteForEveryone(String messageId) => _room.redactEvent(messageId);

  Future<void> deleteForMe(String messageId) async {
    final ids = {...hiddenEventIds(_room), messageId};
    _room.roomAccountData[hiddenEventsType] = BasicEvent(type: hiddenEventsType, content: {'event_ids': ids.toList()});
    _rebuild();
    await _service.client.setAccountDataPerRoom(_service.myUserId, _room.id, hiddenEventsType, {
      'event_ids': ids.toList(),
    });
  }

  /// Manual retry for a message that failed after the automatic attempts.
  Future<void> retry(String messageId) async {
    final e = _event(messageId);
    if (e != null) await _send(e.sendAgain);
  }

  Future<void> discard(String messageId) async => _event(messageId)?.cancelSend();

  /// Sends "typing" at most every 10 s while the user types.
  Future<void> setTyping(bool on) async {
    final now = DateTime.now();
    if (on && now.difference(_lastTypingSent) < const Duration(seconds: 10)) return;
    _lastTypingSent = on ? now : DateTime(0);
    try {
      // The SDK prepares the room key when typing starts: device lists first.
      // One try only: the send shares that key with devices found later.
      if (on) await _refreshDeviceLists(typingDeviceListTimeout);
      await _room.setTyping(on, timeout: 15000);
    } catch (e) {
      Logs().v('Typing notice failed', e);
    }
  }

  /// Decrypted bytes of an image, file or voice note.
  Future<Uint8List> download(String messageId, {bool thumbnail = false}) async {
    final e = _event(messageId);
    if (e == null) throw StateError('message not loaded');
    final file = await e
        .getDisplayEvent(_timeline!)
        .downloadAndDecryptAttachment(getThumbnail: thumbnail && e.hasThumbnail);
    return file.bytes;
  }

  // ---- group ----

  Future<void> addMembers(List<String> userIds) async {
    for (final id in userIds) {
      await _room.invite(id);
    }
  }

  Future<void> makeAdmin(String userId) => _room.setPower(userId, 100);

  Future<void> removeMember(String userId) => _room.kick(userId);

  Future<void> leave() => _room.leave();

  @override
  void dispose() {
    _disposed = true;
    _service.delivery.revision.removeListener(_rebuild);
    _service.securityCodes.revision.removeListener(_rebuild);
    _service.namesRevision.removeListener(_rebuild);
    for (final s in _subs) {
      s.cancel();
    }
    _timeline?.cancelSubscriptions();
    super.dispose();
  }
}
