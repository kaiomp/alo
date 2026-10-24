import 'dart:async';

import 'package:flutter/foundation.dart';
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
}

/// The only door from the UI to the Matrix SDK. Widgets get plain models and
/// call methods here or on [ChatSession]; they never import package:matrix.
class ChatService {
  ChatService(this.client, this.delivery, this.id, this._prefs, {required this.homeserver}) {
    _subs.add(client.onSync.stream.listen((_) => _onSync()));
    _subs.add(
      client.onSyncStatus.stream.listen((s) {
        if (s.status == SyncStatus.error) connected.value = false;
        if (s.status == SyncStatus.finished) connected.value = true;
      }),
    );
    _subs.add(client.onLoginStateChanged.stream.listen((s) => loggedIn.value = s == LoginState.loggedIn));
    loggedIn.value = client.isLogged();
    _onSync();
  }

  /// Builds the SDK client, opens the local database and restores a saved
  /// session. Mirrors FluffyChat lib/main.dart + lib/utils/client_manager.dart.
  static bool _vodozemacReady = false;

  /// [clientName] names the local database; tests use several per process.
  static Future<ChatService> start({required Uri homeserver, required IdClient id, String clientName = 'chama'}) async {
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
    await client.init(waitForFirstSync: false, waitUntilLoadCompletedLoaded: false);
    final prefs = await SharedPreferences.getInstance();
    return ChatService(client, DeliveryTracker(client, prefs), id, prefs, homeserver: homeserver);
  }

  final ChamaClient client;
  final DeliveryTracker delivery;
  final IdClient id;
  final SharedPreferences _prefs;
  final Uri homeserver;
  final _subs = <StreamSubscription>[];
  final _thumbs = <String, Future<Uint8List?>>{};
  final _joining = <String>{};

  final loggedIn = ValueNotifier<bool>(false);

  /// False while sync fails; drives the "Conectando…" banner.
  final connected = ValueNotifier<bool>(true);

  /// All chats, newest activity first, pinned on top. Includes archived ones.
  final chats = ValueNotifier<List<ChatSummary>>(const []);

  String get myUserId => client.userID ?? '';

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

  Future<void> signOut() async {
    try {
      await client.logout();
    } catch (_) {
      // The SDK clears the local session even when the server refuses the
      // logout (an expired session does). Only a failed clear is an error.
      if (client.isLogged()) rethrow;
    }
    await _prefs.remove(_phoneKey);
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
    if (!s.initialized) return CryptoStatus.setUp;
    return s.connected ? CryptoStatus.ready : CryptoStatus.unlock;
  }

  /// Creates cross-signing keys, secret storage and the online key backup,
  /// and signs this device. Returns the recovery key to show the user once.
  Future<String> setUpEncryption() => client.initCryptoIdentity();

  /// Verifies this new device with the recovery key; it then gets old keys
  /// from the backup and new keys from contacts.
  Future<void> unlockEncryption(String recoveryKey) => client.restoreCryptoIdentity(recoveryKey.trim());

  /// Step 1 of a reset when the recovery key is lost: SMS code to the phone.
  Future<void> requestResetCode() => id.requestCode(phone!);

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
      return await client.initCryptoIdentity();
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
      // WhatsApp has no invites: people you are added to just appear.
      if (room.membership == Membership.invite) {
        if (_joining.add(room.id)) {
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
      list.add(summaryOf(room));
    }
    list.sort((a, b) {
      if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
      return b.lastTime.compareTo(a.lastTime);
    });
    chats.value = list;
  }

  ChatSummary summaryOf(Room room) {
    final last = room.lastEvent;
    final mine = last != null && last.senderId == myUserId;
    final lastKind = last == null ? MessageKind.system : kindOf(last);
    return ChatSummary(
      id: room.id,
      name: room.getLocalizedDisplayname(),
      isGroup: !room.isDirectChat,
      avatar: room.avatar,
      lastTime: room.latestEventReceivedTime,
      preview: last == null || lastKind == MessageKind.system ? null : previewText(last),
      previewKind: lastKind,
      previewSender: last == null || mine || room.isDirectChat
          ? null
          : last.senderFromMemoryOrFallback.calcDisplayname(),
      lastTick: mine ? tickOf(room, last, {last.eventId: last.originServerTs.millisecondsSinceEpoch}) : null,
      unread: room.notificationCount,
      markedUnread: room.markedUnread,
      isPinned: room.tags.containsKey(pinnedTag),
      isArchived: room.tags.containsKey(archivedTag),
      isFavourite: room.isFavourite,
      isMuted: room.pushRuleState != PushRuleState.notify,
    );
  }

  /// Tick for my [event]. [knownTs] maps event IDs to server timestamps for
  /// the events the caller has loaded, so a receipt on a later event counts.
  Tick tickOf(Room room, Event event, Map<String, int> knownTs) {
    final others = room.getParticipants([Membership.join]).map((u) => u.id).where((id) => id != myUserId).toList();
    final receipts = {...room.receiptState.global.otherUsers, ...?room.receiptState.mainThread?.otherUsers};
    final delivered = others.length < deliveryMaxMembers ? delivery.deliveredUpTo(room.id) : const <String, int>{};
    return deriveTick(
      failed: event.status.isError,
      sent: event.status.isSent,
      sentAt: event.originServerTs.millisecondsSinceEpoch,
      deliveredUpTo: {for (final u in others) u: delivered[u]},
      readUpTo: {
        for (final u in others) u: receipts[u] == null ? null : (knownTs[receipts[u]!.eventId] ?? receipts[u]!.ts),
      },
      showRead: readReceipts,
    );
  }

  Room _room(String roomId) => client.getRoomById(roomId)!;

  Future<void> setPinned(String roomId, bool on) =>
      on ? _room(roomId).addTag(pinnedTag) : _room(roomId).removeTag(pinnedTag);

  Future<void> setArchived(String roomId, bool on) =>
      on ? _room(roomId).addTag(archivedTag) : _room(roomId).removeTag(archivedTag);

  Future<void> setFavourite(String roomId, bool on) => _room(roomId).setFavourite(on);

  Future<void> setMuted(String roomId, bool on) =>
      _room(roomId).setPushRuleState(on ? PushRuleState.dontNotify : PushRuleState.notify);

  Future<void> markUnread(String roomId, bool on) => _room(roomId).markUnread(on);

  // ---- new chats and groups ----

  /// The Chama account for [phoneDigits], or null when the number has none.
  Future<String?> findByPhone(String phoneDigits) async =>
      (await id.lookup([phoneDigits], accessToken: client.accessToken!))[phoneDigits];

  /// Opens (or creates) the encrypted 1:1 chat with [userId].
  Future<String> startDirectChat(String userId) => client.startDirectChat(userId, enableEncryption: true);

  Future<String> createGroup(String name, List<String> userIds) =>
      client.createGroupChat(groupName: name, invite: userIds, enableEncryption: true);

  ChatSession openChat(String roomId) => ChatSession(this, _room(roomId));

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
  }
}
