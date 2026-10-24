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
List<TimelineItem> buildTimelineItems(List<Message> input) {
  final newestFirst = collapseSystemLines(input);
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

/// Group creation reads as one line, as in WhatsApp: the creator's own
/// "entrou" right after "criou o grupo" is dropped, and a rename by the
/// creator within the same minute folds into it ("criou o grupo "Almoço"").
/// Newest first in and out.
List<Message> collapseSystemLines(List<Message> newestFirst) {
  final oldest = newestFirst.reversed.toList();
  final out = <Message>[];
  for (var i = 0; i < oldest.length; i++) {
    var m = oldest[i];
    if (m.systemKind == SystemKind.created) {
      bool next(SystemKind kind) =>
          i + 1 < oldest.length && oldest[i + 1].systemKind == kind && oldest[i + 1].senderId == m.senderId;
      if (next(SystemKind.joined)) i++;
      if (next(SystemKind.renamed) && oldest[i + 1].time.difference(m.time).abs() < const Duration(minutes: 1)) {
        i++;
        m = Message(
          id: m.id,
          senderId: m.senderId,
          senderName: m.senderName,
          isMine: m.isMine,
          time: m.time,
          kind: m.kind,
          systemKind: SystemKind.created,
          systemTarget: oldest[i].systemTarget,
        );
      }
    }
    out.add(m);
  }
  return out.reversed.toList();
}
