/// Message ticks, WhatsApp style.
enum Tick { pending, failed, sent, delivered, read }

/// Works out the tick for one of my messages.
///
/// [sentAt] is the message's server timestamp in ms. For every other member
/// of the chat, [deliveredUpTo] and [readUpTo] hold the newest message
/// timestamp (ms) that member's devices confirmed, or null if none.
/// A message counts as delivered/read only when every other member got there
/// (groups behave like WhatsApp). When [showRead] is false (I turned my own
/// read receipts off) blue ticks are never shown.
Tick deriveTick({
  required bool failed,
  required bool sent,
  required int sentAt,
  required Map<String, int?> deliveredUpTo,
  required Map<String, int?> readUpTo,
  bool showRead = true,
}) {
  if (failed) return Tick.failed;
  if (!sent) return Tick.pending;
  final others = {...deliveredUpTo.keys, ...readUpTo.keys};
  if (others.isEmpty) return Tick.sent;
  bool reached(String user, {required bool readOnly}) {
    final read = readUpTo[user] ?? -1;
    final delivered = readOnly ? -1 : (deliveredUpTo[user] ?? -1);
    return (read > delivered ? read : delivered) >= sentAt;
  }

  if (showRead && others.every((u) => reached(u, readOnly: true))) return Tick.read;
  if (others.every((u) => reached(u, readOnly: false))) return Tick.delivered;
  return Tick.sent;
}
