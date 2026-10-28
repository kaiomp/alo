import 'package:matrix/matrix.dart';

import 'models.dart';

const hiddenEventsType = 'app.usealo.hidden';

MessageKind kindOf(Event e) {
  if (e.redacted) return MessageKind.deleted;
  if (e.type == EventTypes.Encrypted) return MessageKind.undecryptable;
  if (e.type != EventTypes.Message) return MessageKind.system;
  return switch (e.messageType) {
    MessageTypes.Image => MessageKind.image,
    MessageTypes.Audio => MessageKind.voice,
    MessageTypes.File || MessageTypes.Video => MessageKind.file,
    _ => MessageKind.text,
  };
}

/// Body text for previews and replies: the text itself, or the file name.
String previewText(Event e) => e.redacted ? '' : e.body;

/// Event IDs I deleted "for me" in this room (room account data).
Set<String> hiddenEventIds(Room room) {
  final ids = room.roomAccountData[hiddenEventsType]?.content['event_ids'];
  return ids is List ? ids.whereType<String>().toSet() : const {};
}

SystemKind? systemKindOf(Event e) {
  switch (e.type) {
    case EventTypes.RoomCreate:
      return SystemKind.created;
    case EventTypes.RoomName:
      return SystemKind.renamed;
    case EventTypes.RoomMember:
      return switch (e.roomMemberChangeType) {
        RoomMemberChangeType.join || RoomMemberChangeType.acceptInvite => SystemKind.joined,
        RoomMemberChangeType.leave || RoomMemberChangeType.rejectInvite => SystemKind.left,
        RoomMemberChangeType.invite => SystemKind.invited,
        RoomMemberChangeType.kick || RoomMemberChangeType.ban => SystemKind.removed,
        _ => null,
      };
  }
  return null;
}

/// Whether [e] gets its own row in the chat. Edits and reactions are folded
/// into the message they belong to; groups show a few system lines.
bool isVisible(Event e, {required bool isGroup, required Set<String> hidden}) {
  if (hidden.contains(e.eventId)) return false;
  if (e.type == EventTypes.Message || e.type == EventTypes.Encrypted) {
    // m.relates_to stays in cleartext, so this also works before decryption.
    final rel = e.relationshipType;
    return rel != RelationshipTypes.edit && rel != RelationshipTypes.reaction;
  }
  return isGroup && systemKindOf(e) != null;
}

/// Where an encrypted reaction keeps its emoji, inside the ciphertext.
const reactionKeyField = 'app.usealo.reaction';

/// The emoji of reaction [r], or null while it cannot be decrypted. In
/// encrypted rooms the cleartext `m.relates_to.key` is a random placeholder
/// (the server needs one) and the emoji travels encrypted in
/// [reactionKeyField]; plaintext reactions carry it in `m.relates_to.key`.
String? reactionKey(Event r) {
  if (r.type == EventTypes.Encrypted) return null;
  final own = r.content[reactionKeyField];
  if (own is String) return own;
  final key = r.content.tryGetMap<String, Object?>('m.relates_to')?['key'];
  return key is String ? key : null;
}

/// Where my read receipt goes: the newest message this device has and can
/// read (timeline order, newest first). One it cannot decrypt yet is not
/// read, so the sender gets no blue ticks for it.
Event? newestReadable(Iterable<Event> events) =>
    events.where((e) => e.status.isSynced && e.type != EventTypes.Encrypted).firstOrNull;
