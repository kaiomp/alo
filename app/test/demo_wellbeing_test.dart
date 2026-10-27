import 'package:chama/demo/demo_wellbeing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the pause comes at the daily limit, and again 5 minutes after a snooze', () {
    final w = DemoWellbeing(ticking: false)..dailyLimit.value = 25;
    expect(w.pauseDue.value, isFalse); // 24 min today
    w.elapse(1);
    expect(w.pauseDue.value, isTrue);
    w.snooze();
    expect(w.pauseDue.value, isFalse);
    w.elapse(4);
    expect(w.pauseDue.value, isFalse);
    w.elapse(1);
    expect(w.pauseDue.value, isTrue);
    w.dailyLimit.value = null;
    expect(w.pauseDue.value, isFalse);
  });
}
