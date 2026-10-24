import 'package:matrix/matrix.dart';

import 'models.dart';

const hiddenEventsType = 'chat.chama.hidden';

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
