import 'package:chama/chat/timeline_items.dart';
import 'package:chama/services/models.dart';
import 'package:flutter_test/flutter_test.dart';

Message msg(String id, String sender, DateTime t) =>
    Message(id: id, senderId: sender, senderName: sender, isMine: false, time: t, kind: MessageKind.text);

void main() {
  test('one divider per day, after the oldest message of that day', () {
    final items = buildTimelineItems([
      msg('c', '@a', DateTime(2026, 10, 24, 9)),
      msg('b', '@a', DateTime(2026, 10, 24, 8)),
      msg('a', '@b', DateTime(2026, 10, 23, 22)),
    ]);
    String describe(TimelineItem i) => switch (i) {
      DayDivider(:final day) => 'day ${day.day}',
      MessageItem(:final message, :final startsGroup) => '${message.id}${startsGroup ? '*' : ''}',
    };
    expect(items.map(describe), ['c', 'b*', 'day 24', 'a*', 'day 23']);
  });

  test('sender change starts a group', () {
    final items = buildTimelineItems([
      msg('b', '@b', DateTime(2026, 10, 24, 9)),
      msg('a', '@a', DateTime(2026, 10, 24, 8)),
    ]);
    expect((items[0] as MessageItem).startsGroup, isTrue);
  });
}
