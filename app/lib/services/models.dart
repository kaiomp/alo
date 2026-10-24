import 'ticks.dart';

/// One row of the chat list. Plain data so widgets and tests need no SDK.
class ChatSummary {
  const ChatSummary({
    required this.id,
    required this.name,
    required this.isGroup,
    required this.lastTime,
    this.encrypted = true,
    this.avatar,
    this.preview,
    this.previewSender,
    this.previewKind = MessageKind.text,
    this.lastTick,
    this.unread = 0,
    this.markedUnread = false,
    this.newMessages = false,
    this.isPinned = false,
    this.isArchived = false,
    this.isFavourite = false,
    this.isMuted = false,
  });

  final String id;
  final String name;
  final bool isGroup;
  final DateTime lastTime;

  /// False for a chat without end-to-end encryption that I cannot switch
  /// on: shown as "not encrypted", and nothing can be sent into it.
  final bool encrypted;
  final Uri? avatar;
  final String? preview;

  /// "Você" is decided by the widget; this is null for my own messages in
  /// chats and the sender's name in groups.
  final String? previewSender;
  final MessageKind previewKind;

  /// Tick of the last message when I sent it, else null.
  final Tick? lastTick;
  final int unread;
  final bool markedUnread;

  /// Messages after my read receipt. The server's [unread] count skips
  /// messages that do not notify, so a muted chat needs this.
  final bool newMessages;
  final bool isPinned;
  final bool isArchived;
  final bool isFavourite;
  final bool isMuted;

  bool get isUnread => unread > 0 || markedUnread || (isMuted && newMessages);
}

enum MessageKind { text, image, file, voice, deleted, undecryptable, system }

enum SystemKind {
  created,
  joined,
  left,
  invited,
  removed,
  renamed,

  /// Local line: a contact's master key changed (identity reset).
  securityCodeChanged,
}

class Reaction {
  const Reaction(this.key, this.count, {this.mine = false, this.senders = const []});
  final String key;
  final int count;
  final bool mine;

  /// Display names of who reacted (for the "who reacted" list).
  final List<String> senders;
}

class ReplyPreview {
  const ReplyPreview({required this.eventId, required this.senderName, required this.body, required this.kind});
  final String eventId;
  final String senderName;
  final String body;
  final MessageKind kind;
}

/// One timeline item, already resolved (edits applied, reactions grouped).
class Message {
  const Message({
    required this.id,
    required this.senderId,
    required this.senderName,
    required this.isMine,
    required this.time,
    required this.kind,
    this.body = '',
    this.edited = false,
    this.tick,
    this.reply,
    this.reactions = const [],
    this.durationMs,
    this.waveform,
    this.width,
    this.height,
    this.size,
    this.mimeType,
    this.systemKind,
    this.systemTarget,
    this.systemTargetId,
  });

  /// Event ID, or the transaction ID while it is still sending.
  final String id;
  final String senderId;
  final String senderName;
  final bool isMine;
  final DateTime time;
  final MessageKind kind;

  /// Text, or the file name for attachments.
  final String body;
  final bool edited;
  final Tick? tick;
  final ReplyPreview? reply;
  final List<Reaction> reactions;
  final int? durationMs;
  final List<int>? waveform;
  final int? width;
  final int? height;
  final int? size;
  final String? mimeType;
  final SystemKind? systemKind;

  /// Name of the member a system line is about, or the new group name.
  final String? systemTarget;

  /// User ID of the member a system line is about.
  final String? systemTargetId;
}

/// Online state of the other person in a 1:1 chat.
class OnlineStatus {
  const OnlineStatus({required this.online, this.lastSeen});
  final bool online;
  final DateTime? lastSeen;
}

class Member {
  const Member({required this.userId, required this.name, required this.isAdmin, this.avatar});
  final String userId;
  final String name;
  final bool isAdmin;
  final Uri? avatar;
}

/// A new message to show as a notification, resolved from a push.
class IncomingMessage {
  const IncomingMessage({
    required this.roomId,
    required this.eventId,
    required this.chatName,
    required this.senderId,
    required this.senderName,
    required this.kind,
    required this.isGroup,
    required this.time,
    this.body = '',
  });

  final String roomId;
  final String eventId;
  final String chatName;

  /// Matrix user ID; empty when unknown. Never shown.
  final String senderId;
  final String senderName;
  final MessageKind kind;
  final bool isGroup;
  final DateTime time;

  /// Text, or the file name; empty when it could not be decrypted.
  final String body;
}

/// A file the user picked to send.
class PickedFile {
  const PickedFile({required this.name, required this.bytes, this.mimeType});
  final String name;
  final List<int> bytes;
  final String? mimeType;
}
