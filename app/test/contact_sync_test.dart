import 'dart:convert';

import 'package:alo/auth/id_client.dart';
import 'package:alo/contacts/contact_sync.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A fake alo-id: [accounts] maps E.164 digits to user IDs; every call is
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
    FlutterSecureStorage.setMockInitialValues({});
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
    final f = FakeLookup({mobile(1): '@u1:alo.test'});
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
    final f = FakeLookup({mobile(0): '@u0:alo.test'}, refuseAfter: 1);
    final first = await sync(f).run(book);
    expect(f.calls, hasLength(1));
    expect(first.onAlo.single.userId, '@u0:alo.test');

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

  test('result: contacts on Alô by name, invites only for checked numbers without an account', () async {
    final f = FakeLookup({mobile(1): '@u1:alo.test', mobile(2): '@u2:alo.test'});
    final r = await sync(f).run([
      BookContact('Zé', [mobile(1)]),
      BookContact('Ágata', ['+55 11 8000-0000', mobile(2)]), // one of two numbers has an account
      BookContact('Bruno', [mobile(3)]),
      BookContact('Ana trabalho', [mobile(1)]), // same account under a second name
      BookContact('Sem número', ['190']),
    ]);
    expect(r.onAlo.map((c) => c.name), ['Ágata', 'Zé']);
    expect(r.onAlo.first.phone, mobile(2));
    expect(r.invite.map((c) => c.name), ['Bruno']);
  });

  test('saved names are available without the address book; removed contacts are forgotten', () async {
    final f = FakeLookup({mobile(1): '@u1:alo.test', mobile(2): '@u2:alo.test'});
    await sync(f).run([
      BookContact('Ana', [mobile(1)]),
      BookContact('Bia', [mobile(2)]),
    ]);
    expect(await sync(f).cachedNames(), {'@u1:alo.test': 'Ana', '@u2:alo.test': 'Bia'});
    await sync(f).run([
      BookContact('Ana', [mobile(1)]),
    ]);
    expect(await sync(f).cachedNames(), {'@u1:alo.test': 'Ana'});
    await sync(f).clear();
    expect(await sync(f).cachedNames(), isEmpty);
  });

  test('a number saved once without a name takes the name it has elsewhere', () async {
    final f = FakeLookup({mobile(1): '@u1:alo.test'});
    final r = await sync(f).run([
      BookContact('', [mobile(1)]),
      BookContact('Ana', ['+${mobile(1)}']),
    ]);
    expect([for (final c in r.onAlo) c.name], ['Ana']);
    expect(await sync(f).cachedNames(), {'@u1:alo.test': 'Ana'});
  });

  group('a number that now answers for another account (final review 6)', () {
    const a = '@a:alo.test';
    const b = '@b:alo.test';
    final book = [
      BookContact('Mãe', [mobile(1)]),
    ];

    test('the saved name does not move to the new account, and the change is reported once', () async {
      final f = FakeLookup({mobile(1): a});
      expect((await sync(f).run(book)).moved, isEmpty);
      expect(await sync(f).cachedNames(), {a: 'Mãe'});

      f.accounts[mobile(1)] = b;
      clock = clock.add(ContactSync.refreshAfter);
      final r = await sync(f).run(book);
      expect(r.moved, [(userId: a, name: 'Mãe')]);
      expect([for (final c in r.onAlo) (c.userId, c.name, c.phone, c.moved)], [(b, '', mobile(1), true)]);
      expect(await sync(f).cachedNames(), isEmpty);

      clock = clock.add(ContactSync.refreshAfter);
      expect((await sync(f).run(book)).moved, isEmpty, reason: 'reported once');
      expect(await sync(f).cachedNames(), isEmpty, reason: 'still not attached');
    });

    test('also when the number had no account in between (a recycled number)', () async {
      final f = FakeLookup({mobile(1): a});
      await sync(f).run(book);
      f.accounts.remove(mobile(1));
      clock = clock.add(ContactSync.refreshAfter);
      expect((await sync(f).run(book)).moved, isEmpty);
      f.accounts[mobile(1)] = b;
      clock = clock.add(ContactSync.refreshAfter);
      expect((await sync(f).run(book)).moved, [(userId: a, name: 'Mãe')]);
      expect(await sync(f).cachedNames(), isEmpty);
    });

    test('the number taken off the address book and saved again trusts the new account', () async {
      final f = FakeLookup({mobile(1): a});
      await sync(f).run(book);
      f.accounts[mobile(1)] = b;
      clock = clock.add(ContactSync.refreshAfter);
      await sync(f).run(book);
      await sync(f).run(const []);
      clock = clock.add(ContactSync.refreshAfter);
      expect((await sync(f).run(book)).moved, isEmpty);
      expect(await sync(f).cachedNames(), {b: 'Mãe'});
    });
  });

  group('the number-to-account map is kept encrypted (final review 13)', () {
    const secure = FlutterSecureStorage();

    test('it goes to secure storage, not to SharedPreferences', () async {
      final f = FakeLookup({mobile(1): '@u1:alo.test'});
      await sync(f).run([
        BookContact('Ana', [mobile(1)]),
      ]);
      expect(prefs.getString('alo.contacts.v1'), isNull);
      expect(await secure.read(key: 'alo.contacts.v1'), contains('@u1:alo.test'));
      await sync(f).clear();
      expect(await secure.read(key: 'alo.contacts.v1'), isNull);
    });

    test('an old plain copy moves over and is deleted; its accounts stay trusted', () async {
      SharedPreferences.setMockInitialValues({
        'alo.contacts.v1': jsonEncode({
          mobile(1): {'u': '@a:alo.test', 't': clock.millisecondsSinceEpoch, 'n': 'Mãe'},
        }),
      });
      prefs = await SharedPreferences.getInstance();
      final f = FakeLookup({mobile(1): '@b:alo.test'});
      expect(await sync(f).cachedNames(), {'@a:alo.test': 'Mãe'});
      expect(prefs.getString('alo.contacts.v1'), isNull);
      expect(await secure.read(key: 'alo.contacts.v1'), contains('@a:alo.test'));

      clock = clock.add(ContactSync.refreshAfter);
      final r = await sync(f).run([
        BookContact('Mãe', [mobile(1)]),
      ]);
      expect(r.moved, [(userId: '@a:alo.test', name: 'Mãe')]);
    });
  });
}
