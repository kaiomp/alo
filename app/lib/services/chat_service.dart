import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_vodozemac/flutter_vodozemac.dart' as vod;
import 'package:matrix/encryption.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../auth/id_client.dart';
import 'chama_client.dart';
import 'chat_session.dart';
import 'database.dart';
import 'delivery.dart';
import 'event_mapping.dart';
import 'models.dart';
import 'security_code.dart';
import 'ticks.dart';

const jwtLoginType = 'org.matrix.login.jwt';
const pinnedTag = 'chat.chama.pinned';
const archivedTag = 'chat.chama.archived';
const privacyType = 'chat.chama.privacy';

/// What this device must do before it can read and send messages (spec §5).
enum CryptoStatus {
  /// Keys are set up and this device is verified.
  ready,

  /// First device of the account: create cross-signing keys and a recovery key.
  setUp,

  /// The account has keys but this device is new: recovery key or reset.
  unlock,

  /// A setup was cut off after the master key reached the server (network
  /// drop, app killed). Running setup again needs a password Chama accounts
  /// do not have, so the only way on is the SMS reset.
  repair,
}

/// [CryptoStatus] from the SDK's identity state and whether the server
/// already holds a master key for this account.
CryptoStatus cryptoStatusOf({required bool initialized, required bool connected, required bool hasMasterKey}) {
  if (!initialized) return hasMasterKey ? CryptoStatus.repair : CryptoStatus.setUp;
  return connected ? CryptoStatus.ready : CryptoStatus.unlock;
}

/// The only door from the UI to the Matrix SDK. Widgets get plain models and
/// call methods here or on [ChatSession]; they never import package:matrix.
class ChatService {
  ChatService(this.client, this.delivery, this.id, this._prefs, {required this.homeserver})
    : securityCodes = SecurityCodeWatch(client, _prefs) {
    _subs.add(client.onSync.stream.listen((_) => _onSync()));
    _subs.add(
      client.onSyncStatus.stream.listen((s) {
        if (s.status == SyncStatus.error) connected.value = false;
        if (s.status == SyncStatus.finished) connected.value = true;
      }),
    );
    _subs.add(
      client.onLoginStateChanged.stream.listen((s) {
        loggedIn.value = s == LoginState.loggedIn;
        // The next account must not see this one's chats while its first
        // sync loads (or fails).
        if (s == LoginState.loggedOut) {
          chats.value = const [];
          _thumbs.clear();
        }
      }),
    );
    loggedIn.value = client.isLogged();
    _onSync();
  }

  /// Builds the SDK client, opens the local database and restores a saved
  /// session. Mirrors FluffyChat lib/main.dart + lib/utils/client_manager.dart.
  static bool _vodozemacReady = false;

  /// [clientName] names the local database; tests use several per process.
  /// [background]: started by a push with no screen, so one sync only and no
  /// "online" presence.
  static Future<ChatService> start({
    required Uri homeserver,
    required IdClient id,
    String clientName = 'chama',
    bool background = false,
  }) async {
    if (!_vodozemacReady) {
      await vod.init();
      _vodozemacReady = true;
    }
    final client = ChamaClient(
      clientName,
      database: await openDatabase(clientName),
      supportedLoginTypes: {jwtLoginType},
      nativeImplementations: kIsWeb
          ? NativeImplementations.dummy
          : NativeImplementationsIsolate(compute, vodozemacInit: () => vod.init()),
      // Security invariant (spec §5): message keys only go to devices their
      // owner verified. Never ShareKeysWith.all.
      shareKeysWith: ShareKeysWith.crossVerifiedIfEnabled,
      // The SDK retries a failed send every second until this passes, then
      // marks it failed and the user retries by hand (spec section 9).
      sendTimelineEventTimeout: const Duration(seconds: 30),
    );
    if (background) {
      client.backgroundSync = false;
      client.syncPresence = PresenceType.offline;
    }
    return restore(client, id: id, homeserver: homeserver);
  }

  /// Restores the saved session of [client] from its local database.
  static Future<ChatService> restore(ChamaClient client, {required IdClient id, required Uri homeserver}) async {
    // Waits only for the local database (rooms, account data, device keys),
    // so the chats show at once, also offline. The first sync runs on.
    await client.init(waitForFirstSync: false);
    final prefs = await SharedPreferences.getInstance();
    return ChatService(client, DeliveryTracker(client, prefs), id, prefs, homeserver: homeserver);
  }

  final ChamaClient client;
  final DeliveryTracker delivery;
  final SecurityCodeWatch securityCodes;
  final IdClient id;
  final SharedPreferences _prefs;
  final Uri homeserver;
  final _subs = <StreamSubscription>[];
  final _thumbs = <String, Future<Uint8List?>>{};
  final _joining = <String>{};
  final _encrypting = <String>{};
  static const _secrets = FlutterSecureStorage();
  static const _pendingKey = 'pending_recovery_key';

  final loggedIn = ValueNotifier<bool>(false);

  /// False while sync fails; drives the "Conectando…" banner.
  final connected = ValueNotifier<bool>(true);

  /// All chats, newest activity first, pinned on top. Includes archived ones.
  final chats = ValueNotifier<List<ChatSummary>>(const []);

  String get myUserId => client.userID ?? '';

  /// Android, app in the background: presence says "unavailable" instead of
  /// online, and when push works the sync loop stops (a push wakes the app).
  void setForeground(bool on, {required bool pushActive}) {
    client.syncPresence = on ? null : PresenceType.unavailable;
    client.backgroundSync = on || !pushActive;
  }

  // ---- names (spec §4, Privacy: a contact's saved name wins) ----

  Map<String, String> _contactNames = const {};

  /// Bumps when the address-book names change, so open chats redraw.
  final namesRevision = ValueNotifier<int>(0);

  /// Address-book names by user ID, from ContactsService.
  /// Names saved empty are left out: the profile name stays.
  set contactNames(Map<String, String> all) {
    final names = {
      for (final MapEntry(:key, :value) in all.entries)
        if (value.trim().isNotEmpty) key: value,
    };
    if (mapEquals(names, _contactNames)) return;
    _contactNames = names;
    namesRevision.value++;
    _onSync();
  }

  String nameOf(User u) => _contactNames[u.id] ?? u.calcDisplayname();

  /// A 1:1 chat is named after the other person as saved in the address book.
  String chatName(Room room) => _contactNames[room.directChatMatrixID] ?? room.getLocalizedDisplayname();

  // ---- sign-in and profile ----

  static const _phoneKey = 'chama.phone';

  /// The signed-in phone (E.164 digits); needed again for an identity reset.
  String? get phone => _prefs.getString(_phoneKey);

  Future<void> signIn(IdLogin login) async {
    await client.checkHomeserver(homeserver, checkWellKnown: false, fetchAuthMetadata: false);
    await client.login(
      jwtLoginType,
      token: login.loginToken,
      initialDeviceDisplayName: kIsWeb ? 'Chama Web' : 'Chama ${defaultTargetPlatform.name}',
    );
    // Only once signed in: a failed login must not leave a phone behind.
    await _prefs.setString(_phoneKey, login.phone);
  }

  /// Runs before the logout while the session still works: PushService
  /// deletes this device's pusher.
  Future<void> Function()? onSigningOut;

  Future<void> signOut() async {
    await onSigningOut?.call();
    try {
      await client.logout();
    } catch (_) {
      // The SDK clears the local session even when the server refuses the
      // logout (an expired session does). Only a failed clear is an error.
      if (client.isLogged()) rethrow;
    }
    await _prefs.remove(_phoneKey);
    await _secrets.delete(key: _pendingKey);
    await securityCodes.clear();
  }

  /// True until the user picks a name: Synapse starts the display name as
  /// the opaque localpart (`u7k3…`).
  Future<bool> needsProfile() async {
    final name = await myName();
    return name.isEmpty || name == myUserId.localpart;
  }

  // ---- encryption identity (spec §5) ----

  Future<CryptoStatus> cryptoStatus() async {
    final s = await client.getCryptoIdentityState();
    var hasMasterKey = false;
    if (!s.initialized) {
      // Ask the server: the local copy of my keys may not be loaded yet.
      await client.updateUserDeviceKeys(additionalUsers: {myUserId});
      hasMasterKey = client.userDeviceKeys[myUserId]?.masterKey != null;
    }
    return cryptoStatusOf(initialized: s.initialized, connected: s.connected, hasMasterKey: hasMasterKey);
  }

  /// Creates cross-signing keys, secret storage and the online key backup,
  /// and signs this device. Returns the recovery key to show the user once.
  Future<String> setUpEncryption() async => _keepUntilSaved(await client.initCryptoIdentity());

  /// A recovery key the user has not confirmed saving yet. Kept in the
  /// system keystore so it survives Android killing the app while the user
  /// copies it elsewhere; shown again on the next launch. Only while
  /// [crypto] is ready: otherwise it is from an identity that is no longer
  /// this device's (reset elsewhere, or set up again), so it is deleted rather
  /// than kept until sign-out.
  Future<String?> pendingRecoveryKey(CryptoStatus crypto) async {
    if (crypto == CryptoStatus.ready) return _secrets.read(key: _pendingKey);
    await _secrets.delete(key: _pendingKey);
    return null;
  }

  /// The user ticked "Guardei" and continued.
  Future<void> recoveryKeySaved() => _secrets.delete(key: _pendingKey);

  Future<String> _keepUntilSaved(String key) async {
    await _secrets.write(key: _pendingKey, value: key);
    return key;
  }

  /// Verifies this new device with the recovery key; it then gets old keys
  /// from the backup and new keys from contacts.
  Future<void> unlockEncryption(String recoveryKey) => client.restoreCryptoIdentity(recoveryKey.trim());

  /// Step 1 of a reset when the recovery key is lost: SMS code to the phone.
  /// Returns the seconds until a new code may be asked, or null when the
  /// phone is unknown (the app was killed between login and saving it): the
  /// user is then signed out to sign in again, which saves it.
  Future<int?> requestResetCode() async {
    final p = phone;
    if (p == null) {
      await signOut();
      return null;
    }
    return (await id.requestCode(p)).retryAfter;
  }

  /// Step 2: new keys are made here and chama-id installs the public half
  /// (and signs out the account's other devices). Old messages stay
  /// unreadable on this device. Returns the new recovery key.
  /// A chama-id refusal is thrown as its [IdError] so the screen can say why.
  Future<String> resetEncryption(String code) async {
    IdError? refused;
    client.resetUpload = (keys) async {
      try {
        await id.resetIdentity(phone!, code, keys, accessToken: client.accessToken!);
      } on IdError catch (e) {
        refused = e;
        rethrow;
      }
    };
    try {
      return await _keepUntilSaved(await client.initCryptoIdentity());
    } catch (_) {
      // The SDK's bootstrap wraps the upload error; ChamaClient recovers
      // from no_identity by itself.
      final e = refused;
      if (e != null && e.code != 'no_identity') throw e;
      rethrow;
    } finally {
      client.resetUpload = null;
    }
  }

  Future<void> saveProfile({required String name, PickedFile? photo}) async {
    await client.setProfileField(myUserId, 'displayname', {'displayname': name});
    if (photo != null) {
      await client.setAvatar(
        MatrixImageFile(bytes: Uint8List.fromList(photo.bytes), name: photo.name, mimeType: photo.mimeType),
      );
    }
  }

  /// Fresh from the server: the SDK caches profiles for a day.
  Future<String> myName() async =>
      (await client.getUserProfile(myUserId, maxCacheAge: Duration.zero)).displayname ?? '';

  /// My name and photo for the settings row and the wide header.
  Future<({String name, Uri? avatar})> myProfile() async {
    final p = await client.getUserProfile(myUserId, maxCacheAge: Duration.zero);
    return (name: p.displayname ?? '', avatar: p.avatarUrl);
  }

  // ---- blocking (Matrix ignore list) ----

  bool isBlocked(String userId) => client.ignoredUsers.contains(userId);

  /// Blocking hides the person's messages and invites; the chat stays.
  Future<void> setBlocked(String userId, bool on) =>
      on ? client.ignoreUser(userId, leaveRooms: false) : client.unignoreUser(userId);

  // ---- privacy ----

  /// When off, read receipts are private (`m.read.private`) and blue ticks
  /// are hidden (WhatsApp behaviour). Stored in account data so it follows
  /// the account to other devices.
  bool get readReceipts => client.accountData[privacyType]?.content['read_receipts'] != false;

  Future<void> setReadReceipts(bool on) async {
    client.receiptsPublicByDefault = on;
    await client.setAccountData(myUserId, privacyType, {'read_receipts': on});
  }

  // ---- chat list ----

  void _onSync() {
    client.receiptsPublicByDefault = readReceipts;
    final list = <ChatSummary>[];
    for (final room in client.rooms) {
      // WhatsApp has no invites: people you are added to just appear. Only
      // into encrypted chats (spec §5): an invite to an unencrypted room
      // (server setting turned off, or someone acting for a contact) stays
      // unanswered and out of the list.
      if (room.membership == Membership.invite) {
        if (room.encrypted && _joining.add(room.id)) {
          unawaited(
            room
                .join()
                .catchError((Object e) => Logs().w('Auto-join failed', e))
                .whenComplete(() => _joining.remove(room.id)),
          );
        }
        continue;
      }
      if (room.membership != Membership.join) continue;
      _encrypt(room);
      list.add(summaryOf(room));
    }
    list.sort((a, b) {
      if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
      return b.lastTime.compareTo(a.lastTime);
    });
    chats.value = list;
  }

  /// An unencrypted chat I am already in gets encryption switched on when my
  /// power level allows it, once per run. Otherwise it stays marked "not
  /// encrypted" and the app sends nothing into it.
  void _encrypt(Room room) {
    if (room.encrypted || !room.canChangeStateEvent(EventTypes.Encryption) || !_encrypting.add(room.id)) return;
    unawaited(room.enableEncryption().catchError((Object e) => Logs().w('Could not enable encryption', e)));
  }

  ChatSummary summaryOf(Room room) {
    final last = room.lastEvent;
    final mine = last != null && last.senderId == myUserId;
    final lastKind = last == null ? MessageKind.system : kindOf(last);
    return ChatSummary(
      id: room.id,
      name: chatName(room),
      isGroup: !room.isDirectChat,
      encrypted: room.encrypted,
      avatar: room.avatar,
      lastTime: room.latestEventReceivedTime,
      preview: last == null || lastKind == MessageKind.system ? null : previewText(last),
      previewKind: lastKind,
      previewSender: last == null || mine || room.isDirectChat ? null : nameOf(last.senderFromMemoryOrFallback),
      lastTick: mine ? tickOf(room, last, {last.eventId: last.originServerTs.millisecondsSinceEpoch}) : null,
      unread: room.notificationCount,
      markedUnread: room.markedUnread,
      newMessages: room.hasNewMessages,
      isPinned: room.tags.containsKey(pinnedTag),
      isArchived: room.tags.containsKey(archivedTag),
      isFavourite: room.isFavourite,
      isMuted: room.pushRuleState != PushRuleState.notify,
    );
  }

  /// Tick for my [event]. [knownTs] maps event IDs to server timestamps for
  /// the events the caller has loaded, so a receipt on a later event counts.
  Tick tickOf(Room room, Event event, Map<String, int> knownTs) {
    final sentAt = event.originServerTs.millisecondsSinceEpoch;
    final members = room.getParticipants([Membership.join]).map((u) => u.id).where((id) => id != myUserId).toList();
    // Someone who joined after the message never had it: they do not take
    // its ticks back. Limit: only the current member event is known, so
    // someone who joined later and then renamed counts again, and someone
    // who left no longer counts (a message they never got can go up).
    final others = members.where((id) => !_joinedAfter(room, id, sentAt)).toList();
    final receipts = {...room.receiptState.global.otherUsers, ...?room.receiptState.mainThread?.otherUsers};
    final delivered = members.length < deliveryMaxMembers ? delivery.deliveredUpTo(room.id) : const <String, int>{};
    return deriveTick(
      failed: event.status.isError,
      sent: event.status.isSent,
      sentAt: sentAt,
      deliveredUpTo: {for (final u in others) u: delivered[u]},
      readUpTo: {
        for (final u in others) u: receipts[u] == null ? null : (knownTs[receipts[u]!.eventId] ?? receipts[u]!.ts),
      },
      showRead: readReceipts,
    );
  }

  /// [userId]'s join came after [ts]. A later member event that only
  /// changed the name or photo (it was "join" before too) does not count.
  bool _joinedAfter(Room room, String userId, int ts) {
    final state = room.getState(EventTypes.RoomMember, userId);
    return state is Event &&
        state.originServerTs.millisecondsSinceEpoch > ts &&
        state.prevContent?['membership'] != Membership.join.name;
  }

  Room _room(String roomId) => client.getRoomById(roomId)!;

  Future<void> setPinned(String roomId, bool on) =>
      on ? _room(roomId).addTag(pinnedTag) : _room(roomId).removeTag(pinnedTag);

  Future<void> setArchived(String roomId, bool on) =>
      on ? _room(roomId).addTag(archivedTag) : _room(roomId).removeTag(archivedTag);

  Future<void> setFavourite(String roomId, bool on) => _room(roomId).setFavourite(on);

  Future<void> setMuted(String roomId, bool on) =>
      _room(roomId).setPushRuleState(on ? PushRuleState.dontNotify : PushRuleState.notify);

  /// On: "Marcar como não lida". Off: "Marcar como lida", which also moves
  /// my read receipt to the newest message.
  Future<void> markUnread(String roomId, bool on) async {
    final room = _room(roomId);
    await room.markUnread(on);
    final last = room.lastEvent;
    if (on || last == null || !last.status.isSynced || (room.notificationCount == 0 && !room.hasNewMessages)) return;
    // One this device cannot decrypt gets a private receipt only: the
    // sender sees no blue ticks for a message nobody could read.
    final public = readReceipts && newestReadable([last]) != null;
    await room.setReadMarker(last.eventId, mRead: last.eventId, public: public);
  }

  // ---- new chats and groups ----

  /// Chama accounts for up to 1000 numbers (E.164 digits), as {digits: user ID}.
  /// Signed out (no access token): [IdError] `invalid_token`.
  Future<Map<String, String>> lookupPhones(List<String> phoneDigits) async {
    final token = client.accessToken;
    if (token == null) throw const IdError('invalid_token');
    return id.lookup(phoneDigits, accessToken: token);
  }

  /// The Chama account for [phoneDigits], or null when the number has none.
  Future<String?> findByPhone(String phoneDigits) async => (await lookupPhones([phoneDigits]))[phoneDigits];

  /// Opens (or creates) the encrypted 1:1 chat with [userId]. An existing
  /// chat without encryption is reused only when I can switch it on; an
  /// invite to one is never joined (spec §5).
  Future<String> startDirectChat(String userId) async {
    final existing = client.getRoomById(client.getDirectChatFromUserId(userId) ?? '');
    final reuse = existing == null || existing.encrypted || existing.canChangeStateEvent(EventTypes.Encryption);
    final roomId = await client.startDirectChat(userId, enableEncryption: true, skipExistingChat: !reuse);
    final room = client.getRoomById(roomId);
    if (room != null && !room.encrypted) await room.enableEncryption();
    return roomId;
  }

  Future<String> createGroup(String name, List<String> userIds) =>
      client.createGroupChat(groupName: name, invite: userIds, enableEncryption: true);

  ChatSession openChat(String roomId) => ChatSession(this, _room(roomId));

  /// True once [roomId] is a chat this device has joined. Rooms load from the
  /// database after start, and a notification tap can come first.
  Future<bool> hasChat(String roomId) async {
    await client.roomsLoading;
    return client.getRoomById(roomId)?.membership == Membership.join;
  }

  /// A reply typed in a notification.
  Future<void> sendQuickReply(String roomId, String text) async {
    final room = client.getRoomById(roomId);
    if (room == null) return;
    await room.sendTextEvent(text, parseCommands: false, parseMarkdown: false);
  }

  // ---- push (spec §6: event_id_only, the phone decrypts) ----

  /// What to show for a push about [eventId], or null when nothing should
  /// show: a muted chat, my own message, one already read, or no message
  /// (edits, reactions, state). A message this device cannot decrypt yet
  /// comes back as [MessageKind.undecryptable], with no body.
  Future<IncomingMessage?> notificationFor(String roomId, String eventId) async {
    // One sync brings the room key (to-device) and sends the delivery ack.
    await client.oneShotSync(timeout: Duration.zero).timeout(const Duration(seconds: 10)).catchError((_) {});
    final event = await client.getEventByPushNotification(
      PushNotification(roomId: roomId, eventId: eventId),
      storeInDatabase: false,
    );
    if (event == null || event.senderId == myUserId) return null;
    final room = event.room;
    if (room.pushRuleState != PushRuleState.notify) return null;
    if (!isVisible(event, isGroup: !room.isDirectChat, hidden: const {})) return null;
    final kind = kindOf(event);
    if (kind == MessageKind.system || kind == MessageKind.deleted) return null;
    if (kind != MessageKind.undecryptable && !client.pushruleEvaluator.match(event).notify) return null;
    return IncomingMessage(
      roomId: roomId,
      eventId: eventId,
      chatName: chatName(room),
      senderName: nameOf(event.senderFromMemoryOrFallback),
      kind: kind,
      isGroup: !room.isDirectChat,
      time: event.originServerTs,
      // Never the ciphertext or the SDK's decryption error.
      body: kind == MessageKind.undecryptable ? '' : previewText(event),
    );
  }

  // ---- media ----

  /// Avatar thumbnail bytes (authenticated media), cached in memory and in
  /// the SDK database. Same approach as FluffyChat
  /// lib/utils/client_download_content_extension.dart.
  Future<Uint8List?> thumbnail(Uri mxc, {int size = 96}) => _thumbs.putIfAbsent('$mxc@$size', () async {
    try {
      final cacheKey = Uri.parse('$mxc?size=$size');
      final cached = await client.database.getFile(cacheKey);
      if (cached != null) return cached;
      final url = await mxc.getThumbnailUri(client, width: size, height: size);
      final res = await client.httpClient.get(url, headers: {'authorization': 'Bearer ${client.accessToken}'});
      if (res.statusCode != 200) return null;
      await client.database.storeFile(cacheKey, res.bodyBytes, DateTime.now().millisecondsSinceEpoch);
      return res.bodyBytes;
    } catch (e) {
      Logs().w('Avatar download failed', e);
      return null;
    }
  });

  Future<void> dispose() async {
    for (final s in _subs) {
      await s.cancel();
    }
    await delivery.dispose();
    await securityCodes.dispose();
  }
}
