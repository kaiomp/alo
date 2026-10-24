import 'package:chama/services/ticks.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Tick tick({
    bool failed = false,
    bool sent = true,
    Map<String, int?> delivered = const {},
    Map<String, int?> read = const {},
    bool showRead = true,
  }) =>
      deriveTick(failed: failed, sent: sent, sentAt: 100, deliveredUpTo: delivered, readUpTo: read, showRead: showRead);

  test('pending, failed and sent', () {
    expect(tick(sent: false), Tick.pending);
    expect(tick(failed: true), Tick.failed);
    expect(tick(delivered: {'@b': null}), Tick.sent);
    expect(tick(delivered: {'@b': 99}), Tick.sent);
  });

  test('delivered once the peer confirmed this message or a newer one', () {
    expect(tick(delivered: {'@b': 100}), Tick.delivered);
    expect(tick(delivered: {'@b': 150}), Tick.delivered);
  });

  test('read implies delivered and wins', () {
    expect(tick(read: {'@b': 120}), Tick.read);
    expect(tick(delivered: {'@b': 200}, read: {'@b': 100}), Tick.read);
  });

  test('groups need every member', () {
    expect(tick(delivered: {'@b': 100, '@c': 50}), Tick.sent);
    expect(tick(delivered: {'@b': 100, '@c': 100}, read: {'@b': 100}), Tick.delivered);
    expect(tick(read: {'@b': 100, '@c': 101}), Tick.read);
  });

  test('no blue ticks when my own read receipts are off', () {
    expect(tick(read: {'@b': 120}, showRead: false), Tick.delivered);
  });
}
