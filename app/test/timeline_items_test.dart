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

  test('group creation folds into one line', () {
    final t = DateTime(2026, 10, 24, 9);
    Message sys(String id, SystemKind k, String sender, {String? target, int sec = 0}) => Message(
      id: id,
      senderId: sender,
      senderName: sender,
      isMine: false,
      time: t.add(Duration(seconds: sec)),
      kind: MessageKind.system,
      systemKind: k,
      systemTarget: target,
    );
    final out = collapseSystemLines([
      sys('e', SystemKind.joined, '@b', sec: 5),
      sys('d', SystemKind.invited, '@a', target: 'B', sec: 3),
      sys('c', SystemKind.renamed, '@a', target: 'Almoço', sec: 2),
      sys('b', SystemKind.joined, '@a', sec: 1),
      sys('a', SystemKind.created, '@a'),
    ]);
    expect(out.map((m) => m.id), ['e', 'd', 'a']);
    expect(out.last.systemTarget, 'Almoço');
  });
}
