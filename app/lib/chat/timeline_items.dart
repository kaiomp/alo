import '../common/time_format.dart';
import '../services/models.dart';

sealed class TimelineItem {}

class DayDivider extends TimelineItem {
  DayDivider(this.day);
  final DateTime day;
}

class MessageItem extends TimelineItem {
  MessageItem(this.message, {required this.startsGroup});
  final Message message;

  /// First message of a run from one sender: draws the bubble tail and, in
  /// groups, the sender name.
  final bool startsGroup;
}

/// Items for a `ListView(reverse: true)`. Input is newest first (SDK order);
/// each day's divider comes right after that day's oldest message.
List<TimelineItem> buildTimelineItems(List<Message> newestFirst) {
  final items = <TimelineItem>[];
  for (var i = 0; i < newestFirst.length; i++) {
    final m = newestFirst[i];
    final older = i + 1 < newestFirst.length ? newestFirst[i + 1] : null;
    final newDay = older == null || !sameDay(older.time, m.time);
    items.add(MessageItem(m, startsGroup: newDay || older.senderId != m.senderId || older.kind == MessageKind.system));
    if (newDay) {
      final t = m.time.toLocal();
      items.add(DayDivider(DateTime(t.year, t.month, t.day)));
    }
  }
  return items;
}
