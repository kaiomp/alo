import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../services/chat_service.dart';
import '../services/chat_session.dart';
import '../services/models.dart';
import '../services/social_service.dart';
import '../services/ticks.dart';
import 'demo_data.dart';

/// Bytes of a file served next to the demo (web/demo/…), fetched once.
/// Once loaded they come back synchronously, so avatars and photos show in
/// the first frame of a screen (no placeholder flash in the videos).
final _loading = <String, Future<Uint8List>>{};
final _loaded = <String, Uint8List>{};
Future<Uint8List> demoBytes(Uri path) {
  final done = _loaded['$path'];
  if (done != null) return SynchronousFuture(done);
  return _loading.putIfAbsent('$path', () async {
    final bytes = (await http.get(Uri.base.resolveUri(path))).bodyBytes;
    return _loaded['$path'] = bytes;
  });
}

Message _copy(Message m, {Tick? tick, List<Reaction>? reactions}) => Message(
  id: m.id,
  senderId: m.senderId,
  senderName: m.senderName,
  isMine: m.isMine,
  time: m.time,
  kind: m.kind,
  body: m.body,
  edited: m.edited,
  tick: tick ?? m.tick,
  reply: m.reply,
  reactions: reactions ?? m.reactions,
  durationMs: m.durationMs,
  waveform: m.waveform,
  width: m.width,
  height: m.height,
  size: m.size,
  mimeType: m.mimeType,
);

/// ChatService on [DemoWorld]: no server, no SDK. Members the demo never
/// reaches fall through to [noSuchMethod] and throw.
class DemoChatService implements ChatService {
  DemoChatService(this.world) {
    _publish();
  }

  final DemoWorld world;
  final _open = <String, DemoChatSession>{};

  @override
  final loggedIn = ValueNotifier<bool>(true);
  @override
  final connected = ValueNotifier<bool>(true);
  @override
  final chats = ValueNotifier<List<ChatSummary>>(const []);
  @override
  final namesRevision = ValueNotifier<int>(0);

  @override
  String get myUserId => me.id;
  @override
  String? get phone => '5581987654321';
  @override
  bool get readReceipts => true;

  void _publish() {
    final list = world.chats.map(_summary).toList()
      ..sort((a, b) {
        if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
        return b.lastTime.compareTo(a.lastTime);
      });
    chats.value = list;
  }

  ChatSummary _summary(DemoChat c) {
    final last = c.messages.firstOrNull;
    final kind = last?.kind ?? MessageKind.system;
    return ChatSummary(
      id: c.id,
      name: c.name,
      isGroup: c.isGroup,
      lastTime: last?.time ?? world.now,
      avatar: c.isGroup ? c.avatar : c.other.avatar,
      preview: kind == MessageKind.text || kind == MessageKind.file ? last?.body : null,
      previewKind: kind,
      previewSender: last == null || last.isMine || !c.isGroup ? null : last.senderName.split(' ').first,
      lastTick: last != null && last.isMine ? last.tick : null,
      unread: c.unread,
      markedUnread: c.markedUnread,
      newMessages: c.unread > 0,
      isPinned: c.pinned,
      isArchived: c.archived,
      isFavourite: c.favourite,
      isMuted: c.muted,
    );
  }

  // ---- what scenes and the session drive ----

  /// A message from someone else arrives in [chatId].
  void receive(String chatId, Message m) {
    final c = world.chat(chatId);
    c.messages.insert(0, m);
    if (!_open.containsKey(chatId)) c.unread++;
    _changed(chatId);
  }

  /// Puts [photo] into [chatId] from [from].
  Message receivePhoto(String chatId, Person from, String photo) {
    final m = world.image(world.chat(chatId), from, photo, DateTime.now());
    receive(chatId, m);
    return m;
  }

  void setTyping(String chatId, Person who, bool on) {
    final s = _open[chatId];
    if (s == null) return;
    on ? s._typing.add(who.name) : s._typing.remove(who.name);
    s._rebuild();
  }

  void setTick(String chatId, String messageId, Tick tick) => _replace(chatId, messageId, (m) => _copy(m, tick: tick));

  void _replace(String chatId, String messageId, Message Function(Message) change) {
    final list = world.chat(chatId).messages;
    final i = list.indexWhere((m) => m.id == messageId);
    if (i < 0) return;
    list[i] = change(list[i]);
    _changed(chatId);
  }

  void _changed(String chatId) {
    _open[chatId]?._rebuild();
    _publish();
  }

  /// Sends as me into [chatId]. The ticks then go sent → delivered → read,
  /// as from a contact who is online.
  Message sendMine(
    String chatId,
    MessageKind kind, {
    String body = '',
    int? durationMs,
    List<int>? waveform,
    int? size,
    String? mime,
  }) {
    final m = Message(
      id: world.nextId(),
      senderId: me.id,
      senderName: me.name,
      isMine: true,
      time: DateTime.now(),
      kind: kind,
      body: body,
      tick: Tick.pending,
      durationMs: durationMs,
      waveform: waveform,
      size: size,
      mimeType: mime,
    );
    world.chat(chatId).messages.insert(0, m);
    _changed(chatId);
    for (final (ms, tick) in [(350, Tick.sent), (900, Tick.delivered), (2200, Tick.read)]) {
      Timer(Duration(milliseconds: ms), () => setTick(chatId, m.id, tick));
    }
    return m;
  }

  // ---- ChatService ----

  @override
  ChatSession openChat(String roomId) => DemoChatSession(this, world.chat(roomId));

  @override
  Future<bool> hasChat(String roomId) async => world.chats.any((c) => c.id == roomId);

  @override
  Future<Uint8List?> thumbnail(Uri mxc, {int size = 96}) => demoBytes(mxc);

  @override
  Future<({String name, Uri? avatar})> myProfile() async => (name: me.name, avatar: me.avatar);

  @override
  Future<String> myName() async => me.name;

  @override
  Future<bool> needsProfile() async => false;

  @override
  Future<CryptoStatus> cryptoStatus() async => CryptoStatus.ready;

  @override
  Future<String?> pendingRecoveryKey(CryptoStatus crypto) async => null;

  @override
  Future<void> saveProfile({required String name, PickedFile? photo}) async {}

  /// The demo stays signed in: there is no server to sign in to again.
  @override
  Future<void> signOut() async {}

  @override
  bool isBlocked(String userId) => false;

  @override
  Future<void> setBlocked(String userId, bool on) async {}

  @override
  Future<void> setReadReceipts(bool on) async {}

  @override
  set contactNames(Map<String, String> all) {}

  @override
  void setForeground(bool on, {required bool pushActive}) {}

  Future<void> _edit(String id, void Function(DemoChat) change) async {
    change(world.chat(id));
    _publish();
  }

  @override
  Future<void> setPinned(String roomId, bool on) => _edit(roomId, (c) => c.pinned = on);
  @override
  Future<void> setArchived(String roomId, bool on) => _edit(roomId, (c) => c.archived = on);
  @override
  Future<void> setFavourite(String roomId, bool on) => _edit(roomId, (c) => c.favourite = on);
  @override
  Future<void> setMuted(String roomId, bool on) => _edit(roomId, (c) => c.muted = on);
  @override
  Future<void> markUnread(String roomId, bool on) => _edit(roomId, (c) {
    c.markedUnread = on;
    if (!on) c.unread = 0;
  });

  @override
  Future<String> startDirectChat(String userId) async =>
      world.chats.firstWhere((c) => !c.isGroup && c.other.id == userId, orElse: () => world.chats.first).id;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// One open demo chat. Sends go pending → sent → delivered → read.
class DemoChatSession extends ChangeNotifier implements ChatSession {
  DemoChatSession(this._service, this._chat);

  final DemoChatService _service;
  final DemoChat _chat;
  final _typing = <String>[];
  bool _disposed = false;

  @override
  List<Message> messages = const [];
  @override
  bool loading = true;
  @override
  OnlineStatus? presence;

  @override
  String get roomId => _chat.id;
  @override
  String get name => _chat.name;
  @override
  Uri? get avatar => _chat.isGroup ? _chat.avatar : _chat.other.avatar;
  @override
  bool get isGroup => _chat.isGroup;
  @override
  bool get encrypted => true;
  @override
  bool get canLoadMore => false;
  @override
  bool get moreOnServer => false;
  @override
  List<String> get typing => List.unmodifiable(_typing);
  @override
  bool get iAmAdmin => _chat.isGroup;

  @override
  List<Member> get members => [
    for (final p in _chat.members)
      Member(userId: p.id, name: p.name, isAdmin: p == _chat.members.first, avatar: p.avatar),
    Member(userId: me.id, name: me.name, isAdmin: true, avatar: me.avatar),
  ];

  @override
  Future<void> open() async {
    _service._open[_chat.id] = this;
    _chat.unread = 0;
    _chat.markedUnread = false;
    final seen = _chat.lastSeen;
    if (!_chat.isGroup && seen != null) {
      final online = DateTime.now().difference(seen) < const Duration(minutes: 3);
      presence = OnlineStatus(online: online, lastSeen: seen);
    }
    loading = false;
    _service._publish();
    _rebuild();
  }

  void _rebuild() {
    if (_disposed) return;
    messages = List.of(_chat.messages);
    notifyListeners();
  }

  @override
  set visible(bool v) {}

  @override
  Future<void> markRead() async {}

  @override
  Future<void> loadMore() async {}

  @override
  Future<void> sendText(String text, {String? replyTo, String? editOf}) async =>
      _service.sendMine(_chat.id, MessageKind.text, body: text);

  @override
  Future<void> sendImage(PickedFile file, {String? replyTo}) async {
    final m = _service.sendMine(_chat.id, MessageKind.image, body: file.name, mime: file.mimeType);
    _uploads[m.id] = Uint8List.fromList(file.bytes);
  }

  @override
  Future<void> sendFile(PickedFile file, {String? replyTo}) async {
    final m = _service.sendMine(
      _chat.id,
      MessageKind.file,
      body: file.name,
      size: file.bytes.length,
      mime: file.mimeType,
    );
    _uploads[m.id] = Uint8List.fromList(file.bytes);
  }

  @override
  Future<void> sendVoice({
    required Uint8List bytes,
    required String mimeType,
    required int durationMs,
    required List<int> waveform,
    String? replyTo,
  }) async {
    final m = _service.sendMine(
      _chat.id,
      MessageKind.voice,
      body: 'voz',
      durationMs: durationMs,
      waveform: waveform,
      mime: mimeType,
    );
    _uploads[m.id] = bytes;
  }

  final _uploads = <String, Uint8List>{};

  @override
  Future<void> toggleReaction(String messageId, String key) async => _service._replace(_chat.id, messageId, (m) {
    Reaction toggle(Reaction r) => r.mine
        ? Reaction(key, r.count - 1, senders: [...r.senders]..remove('Você'))
        : Reaction(key, r.count + 1, mine: true, senders: [...r.senders, 'Você']);
    final had = m.reactions.any((r) => r.key == key);
    return _copy(
      m,
      reactions: [
        for (final r in m.reactions) r.key == key ? toggle(r) : r,
        if (!had) Reaction(key, 1, mine: true, senders: const ['Você']),
      ].where((r) => r.count > 0).toList(),
    );
  });

  @override
  Future<void> deleteForEveryone(String messageId) => deleteForMe(messageId);

  @override
  Future<void> deleteForMe(String messageId) async {
    _chat.messages.removeWhere((m) => m.id == messageId);
    _service._changed(_chat.id);
  }

  @override
  Future<void> setTyping(bool on) async {}

  @override
  Future<Uint8List> download(String messageId, {bool thumbnail = false}) {
    final upload = _uploads[messageId];
    if (upload != null) return SynchronousFuture(upload);
    final photo = _chat.photos[messageId];
    if (photo != null) return demoBytes(photo);
    final m = _chat.messages.firstWhere((m) => m.id == messageId);
    if (m.kind == MessageKind.voice) return SynchronousFuture(silentWav(m.durationMs ?? 1000));
    return SynchronousFuture(Uint8List.fromList(utf8.encode('%PDF-1.4\n% Chama demo\n')));
  }

  @override
  Future<void> leave() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  void dispose() {
    _disposed = true;
    if (_service._open[_chat.id] == this) _service._open.remove(_chat.id);
    super.dispose();
  }
}

/// A silent 8 kHz mono WAV of [ms] milliseconds, so the voice player has
/// something to play.
Uint8List silentWav(int ms) {
  const rate = 8000;
  final samples = rate * ms ~/ 1000;
  final data = ByteData(44 + samples);
  void str(int at, String s) {
    for (var i = 0; i < s.length; i++) {
      data.setUint8(at + i, s.codeUnitAt(i));
    }
  }

  str(0, 'RIFF');
  data.setUint32(4, 36 + samples, Endian.little);
  str(8, 'WAVEfmt ');
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little); // PCM
  data.setUint16(22, 1, Endian.little); // mono
  data.setUint32(24, rate, Endian.little);
  data.setUint32(28, rate, Endian.little);
  data.setUint16(32, 1, Endian.little);
  data.setUint16(34, 8, Endian.little);
  str(36, 'data');
  data.setUint32(40, samples, Endian.little);
  for (var i = 0; i < samples; i++) {
    data.setUint8(44 + i, 128); // 8-bit silence
  }
  return data.buffer.asUint8List();
}
