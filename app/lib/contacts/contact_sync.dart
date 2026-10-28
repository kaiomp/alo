import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../auth/id_client.dart';
import '../auth/phone.dart';
import '../chat_list/chat_filter.dart';

/// One address-book entry: the name the user saved and its numbers as typed.
class BookContact {
  const BookContact(this.name, this.numbers);
  final String name;
  final List<String> numbers;
}

/// A saved contact with a Alô account.
class AloContact {
  const AloContact({required this.name, required this.phone, required this.userId, this.moved = false});
  final String name;

  /// E.164 digits without '+'.
  final String phone;
  final String userId;

  /// The number now answers for another account than the one it was saved
  /// for: [name] is empty, the saved name is not attached to [userId].
  final bool moved;
}

/// A saved contact without an account, for "Convidar para o Alô".
class InviteContact {
  const InviteContact({required this.name, required this.phone});
  final String name;
  final String phone;
}

class ContactSyncResult {
  const ContactSyncResult(this.onAlo, this.invite, [this.moved = const []]);
  final List<AloContact> onAlo;
  final List<InviteContact> invite;

  /// Numbers found answering for another account in this run: the account
  /// they were saved for, and the saved name (or the number).
  final List<({String userId, String name})> moved;
}

/// One cached number: its account at the last check (or null), when that
/// was, the saved name, and the account the saved name belongs to (the first
/// one seen for it, kept while the number has none).
typedef _Entry = ({String? userId, int checkedAt, String name, String? trusted});

/// Asks alo-id which of these numbers (up to 1000) have an account.
typedef LookupPhones = Future<Map<String, String>> Function(List<String> phoneDigits);

/// Matches the address book against Alô accounts and remembers the answers.
///
/// The server sees each number's SHA-256 hash (docs/alo-id-api.md). To spend
/// few lookups (alo-id allows 30 per hour and 10 000 hashes per day per
/// account), only numbers that were never checked, or were checked over a day
/// ago, are sent, at most [maxBatch] per request. A refusal (rate_limited) or a
/// network error stops the run; what was learned is kept and the next run
/// continues where this one stopped.
///
/// The number-to-account map stays in the system keystore (secure storage),
/// not in plain SharedPreferences: opaque IDs keep it off the server, so it
/// must not sit readable on the phone either.
class ContactSync {
  ContactSync(this._prefs, this._lookup, {DateTime Function()? now}) : _now = now ?? DateTime.now;

  static const _secure = FlutterSecureStorage();

  // Limit: alo-id takes at most 1000 hashes per lookup.
  static const maxBatch = 1000;
  static const refreshAfter = Duration(days: 1);
  static const _cacheKey = 'alo.contacts.v1';
  static const _retryKey = 'alo.contacts.retry_at';

  final SharedPreferences _prefs;
  final LookupPhones _lookup;
  final DateTime Function() _now;

  /// digits -> entry. A copy left in SharedPreferences by an older build
  /// moves to secure storage and is deleted.
  Future<Map<String, _Entry>> _load() async {
    var raw = await _secure.read(key: _cacheKey);
    final plain = _prefs.getString(_cacheKey);
    if (plain != null) {
      if (raw == null) await _secure.write(key: _cacheKey, value: raw = plain);
      await _prefs.remove(_cacheKey);
    }
    if (raw == null) return {};
    return (jsonDecode(raw) as Map<String, dynamic>).map(
      (digits, v) => MapEntry(digits, (
        userId: v['u'] as String?,
        checkedAt: v['t'] as int,
        name: v['n'] as String,
        // Older caches trust the account they had.
        trusted: (v as Map).containsKey('k') ? v['k'] as String? : v['u'] as String?,
      )),
    );
  }

  Future<void> _save(Map<String, _Entry> cache) => _secure.write(
    key: _cacheKey,
    value: jsonEncode({
      for (final MapEntry(key: d, value: e) in cache.entries)
        d: {'u': e.userId, 't': e.checkedAt, 'n': e.name, 'k': e.trusted},
    }),
  );

  /// Saved names of known accounts, from the last run. Needs no address book,
  /// so a push in the background can name the sender. A number that now
  /// answers for another account names no one.
  Future<Map<String, String>> cachedNames() async => {
    for (final e in (await _load()).values)
      if (e.userId != null && e.userId == e.trusted) e.userId!: e.name,
  };

  /// Forgets everything (sign-out).
  Future<void> clear() async {
    await _secure.delete(key: _cacheKey);
    await _prefs.remove(_cacheKey);
    await _prefs.remove(_retryKey);
  }

  Future<ContactSyncResult> run(List<BookContact> book) async {
    // Each number once, with the first name it is saved under.
    final names = <String, String>{};
    for (final c in book) {
      for (final n in c.numbers) {
        final digits = normalizeContactPhone(n);
        // An entry saved without a name does not hide the name it has elsewhere.
        if (digits != null && (names[digits] ?? '').trim().isEmpty) names[digits] = c.name;
      }
    }
    final now = _now().millisecondsSinceEpoch;
    final old = await _load();
    // Numbers no longer in the address book are dropped. Saved again later,
    // a number trusts whatever account it then answers for.
    final cache = <String, _Entry>{
      for (final MapEntry(key: d, value: name) in names.entries)
        if (old[d] case final e?) d: (userId: e.userId, checkedAt: e.checkedAt, name: name, trusted: e.trusted),
    };
    final moved = <({String userId, String name})>[];
    final due = [
      for (final d in names.keys)
        if (now - (cache[d]?.checkedAt ?? 0) >= refreshAfter.inMilliseconds) d,
    ];
    // Oldest check first, never-checked numbers before all: a book bigger than
    // the daily quota then gets through in a few days instead of re-checking
    // its first numbers every day.
    due.sort((a, b) => (cache[a]?.checkedAt ?? 0).compareTo(cache[b]?.checkedAt ?? 0));
    final retryAt = _prefs.getInt(_retryKey) ?? 0;
    if (now >= retryAt) {
      for (var i = 0; i < due.length; i += maxBatch) {
        final batch = due.sublist(i, i + maxBatch > due.length ? due.length : i + maxBatch);
        try {
          final found = await _lookup(batch);
          for (final d in batch) {
            final was = cache[d];
            final userId = found[d];
            final trusted = was?.trusted ?? userId;
            // A recycled number (alo-id gives it a fresh account) or a
            // directory answering wrongly: the saved name stays off the new
            // account, and the chats with the old one say so, once.
            // Limit: it stays off until the number answers for the trusted
            // account again, or is taken off the address book and saved again.
            if (userId != null && userId != trusted && userId != was?.userId) {
              moved.add((userId: trusted!, name: names[d]!.trim().isEmpty ? formatPhone(d) : names[d]!));
            }
            cache[d] = (userId: userId, checkedAt: now, name: names[d]!, trusted: trusted);
          }
          await _save(cache);
        } on IdError catch (e) {
          if (e.code == 'rate_limited') await _prefs.setInt(_retryKey, now + (e.retryAfter ?? 3600) * 1000);
          break;
        }
      }
    }
    await _save(cache);
    return _result(book, cache, moved);
  }

  ContactSyncResult _result(
    List<BookContact> book,
    Map<String, _Entry> cache,
    List<({String userId, String name})> moved,
  ) {
    final onAlo = <String, AloContact>{};
    final invite = <InviteContact>[];
    for (final c in book) {
      final digits = c.numbers.map(normalizeContactPhone).whereType<String>().toSet();
      if (digits.isEmpty) continue;
      final registered = digits.where((d) => cache[d]?.userId != null).toList();
      for (final d in registered) {
        final e = cache[d]!;
        final isMoved = e.userId != e.trusted;
        onAlo.putIfAbsent(
          e.userId!,
          () => AloContact(name: isMoved ? '' : e.name, phone: d, userId: e.userId!, moved: isMoved),
        );
      }
      // Only numbers already checked: an unchecked one may still have an account.
      if (registered.isEmpty && digits.every(cache.containsKey)) {
        invite.add(InviteContact(name: c.name, phone: digits.first));
      }
    }
    int byName(String a, String b) => foldText(a).compareTo(foldText(b));
    return ContactSyncResult(
      onAlo.values.toList()..sort((a, b) => byName(a.name, b.name)),
      invite..sort((a, b) => byName(a.name, b.name)),
      moved,
    );
  }
}
