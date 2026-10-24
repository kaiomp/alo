import 'package:chama/auth/id_client.dart';
import 'package:chama/contacts/contact_sync.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A fake chama-id: [accounts] maps E.164 digits to user IDs; every call is
/// recorded; [refuseAfter] calls are answered, then rate_limited.
class FakeLookup {
  FakeLookup(this.accounts, {this.refuseAfter});
  final Map<String, String> accounts;
  final int? refuseAfter;
  final calls = <List<String>>[];

  Future<Map<String, String>> call(List<String> digits) async {
    if (refuseAfter != null && calls.length >= refuseAfter!) {
      throw const IdError('rate_limited', retryAfter: 600);
    }
    calls.add(digits);
    return {for (final d in digits) d: ?accounts[d]};
  }
}

String mobile(int i) => '55119${i.toString().padLeft(8, '0')}';

void main() {
  late SharedPreferences prefs;
  var clock = DateTime(2026, 10, 24, 12);
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    clock = DateTime(2026, 10, 24, 12);
  });
  ContactSync sync(FakeLookup f) => ContactSync(prefs, f.call, now: () => clock);

  test('sends each number once, in batches of at most 1000', () async {
    final book = [
      for (var i = 0; i < 2500; i++) BookContact('C$i', ['+${mobile(i)}']),
    ];
    final f = FakeLookup({});
    await sync(f).run([
      ...book,
      BookContact('Duplicate', ['(11) 9${'0'.padLeft(8, '0')}']),
    ]);
    expect(f.calls.map((c) => c.length), [1000, 1000, 500]);
    expect(f.calls.expand((c) => c).toSet().length, 2500);
  });

  test('checks again only after a day, and new numbers right away', () async {
    final f = FakeLookup({mobile(1): '@u1:chama.test'});
    final book = [
      BookContact('Ana', [mobile(1)]),
      BookContact('Bia', [mobile(2)]),
    ];
    await sync(f).run(book);
    expect(f.calls, hasLength(1));

    clock = clock.add(const Duration(hours: 23));
    await sync(f).run(book);
    expect(f.calls, hasLength(1), reason: 'nothing is due yet');

    await sync(f).run([
      ...book,
      BookContact('Caio', [mobile(3)]),
    ]);
    expect(f.calls.last, [mobile(3)], reason: 'only the new number');

    clock = clock.add(const Duration(hours: 1));
    await sync(f).run(book);
    expect(f.calls.last, unorderedEquals([mobile(1), mobile(2)]), reason: 'a day later, all again');
  });

  test('rate_limited stops the run, keeps what was learned, and waits retry_after', () async {
    final book = [
      for (var i = 0; i < 1500; i++) BookContact('C$i', [mobile(i)]),
    ];
    final f = FakeLookup({mobile(0): '@u0:chama.test'}, refuseAfter: 1);
    final first = await sync(f).run(book);
    expect(f.calls, hasLength(1));
    expect(first.onChama.single.userId, '@u0:chama.test');

    // Before retry_after (600 s): no call at all.
    clock = clock.add(const Duration(seconds: 599));
    final g = FakeLookup({});
    await sync(g).run(book);
    expect(g.calls, isEmpty);

    // After it: only the 500 numbers the first run could not check.
    clock = clock.add(const Duration(seconds: 1));
    await sync(g).run(book);
    expect(g.calls.single, hasLength(500));
  });

  test('a book bigger than the daily quota: the next day, the unchecked numbers go first', () async {
    final book = [
      for (var i = 0; i < 12000; i++) BookContact('C$i', [mobile(i)]),
    ];
    // 10 000 hashes a day: the 11th batch is refused.
    final f = FakeLookup({}, refuseAfter: 10);
    await sync(f).run(book);
    expect(f.calls, hasLength(10));

    clock = clock.add(const Duration(days: 1));
    final g = FakeLookup({}, refuseAfter: 2);
    await sync(g).run(book);
    final checked = f.calls.expand((c) => c).toSet();
    expect(g.calls.expand((c) => c).toSet(), {
      for (final c in book)
        if (!checked.contains(c.numbers.single)) c.numbers.single,
    });
  });

  test('a network error keeps the cache and makes no further calls in that run', () async {
    var n = 0;
    final s = ContactSync(prefs, (d) async {
      if (n++ > 0) throw const IdError('network');
      return {};
    }, now: () => clock);
    await s.run([
      for (var i = 0; i < 1500; i++) BookContact('C$i', [mobile(i)]),
    ]);
    expect(n, 2);
  });

  test('result: contacts on Chama by name, invites only for checked numbers without an account', () async {
    final f = FakeLookup({mobile(1): '@u1:chama.test', mobile(2): '@u2:chama.test'});
    final r = await sync(f).run([
      BookContact('Zé', [mobile(1)]),
      BookContact('Ágata', ['+55 11 8000-0000', mobile(2)]), // one of two numbers has an account
      BookContact('Bruno', [mobile(3)]),
      BookContact('Ana trabalho', [mobile(1)]), // same account under a second name
      BookContact('Sem número', ['190']),
    ]);
    expect(r.onChama.map((c) => c.name), ['Ágata', 'Zé']);
    expect(r.onChama.first.phone, mobile(2));
    expect(r.invite.map((c) => c.name), ['Bruno']);
  });

  test('saved names are available without the address book; removed contacts are forgotten', () async {
    final f = FakeLookup({mobile(1): '@u1:chama.test', mobile(2): '@u2:chama.test'});
    await sync(f).run([
      BookContact('Ana', [mobile(1)]),
      BookContact('Bia', [mobile(2)]),
    ]);
    expect(sync(f).cachedNames(), {'@u1:chama.test': 'Ana', '@u2:chama.test': 'Bia'});
    await sync(f).run([
      BookContact('Ana', [mobile(1)]),
    ]);
    expect(sync(f).cachedNames(), {'@u1:chama.test': 'Ana'});
    await sync(f).clear();
    expect(sync(f).cachedNames(), isEmpty);
  });
}
