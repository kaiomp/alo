import 'dart:convert';

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

/// A saved contact with a Chama account.
class ChamaContact {
  const ChamaContact({required this.name, required this.phone, required this.userId});
  final String name;

  /// E.164 digits without '+'.
  final String phone;
  final String userId;
}

/// A saved contact without an account, for "Convidar para o Chama".
class InviteContact {
  const InviteContact({required this.name, required this.phone});
  final String name;
  final String phone;
}

class ContactSyncResult {
  const ContactSyncResult(this.onChama, this.invite);
  final List<ChamaContact> onChama;
  final List<InviteContact> invite;
}

/// Asks chama-id which of these numbers (up to 1000) have an account.
typedef LookupPhones = Future<Map<String, String>> Function(List<String> phoneDigits);

/// Matches the address book against Chama accounts and remembers the answers.
///
/// The server sees each number's SHA-256 hash (docs/chama-id-api.md). To spend
/// few lookups (chama-id allows 30 per hour and 10 000 hashes per day per
/// account), only numbers that were never checked, or were checked over a day
/// ago, are sent, at most [maxBatch] per request. A refusal (rate_limited) or a
/// network error stops the run; what was learned is kept and the next run
/// continues where this one stopped.
class ContactSync {
  ContactSync(this._prefs, this._lookup, {DateTime Function()? now}) : _now = now ?? DateTime.now;

  // Limit: chama-id takes at most 1000 hashes per lookup.
  static const maxBatch = 1000;
  static const refreshAfter = Duration(days: 1);
  static const _cacheKey = 'chama.contacts.v1';
  static const _retryKey = 'chama.contacts.retry_at';

  final SharedPreferences _prefs;
  final LookupPhones _lookup;
  final DateTime Function() _now;

  /// digits -> (user ID or null, last check in ms, saved name)
  Map<String, ({String? userId, int checkedAt, String name})> _load() {
    final raw = _prefs.getString(_cacheKey);
    if (raw == null) return {};
    return (jsonDecode(raw) as Map<String, dynamic>).map(
      (digits, v) => MapEntry(digits, (userId: v['u'] as String?, checkedAt: v['t'] as int, name: v['n'] as String)),
    );
  }

  Future<void> _save(Map<String, ({String? userId, int checkedAt, String name})> cache) => _prefs.setString(
    _cacheKey,
    jsonEncode({
      for (final MapEntry(key: d, value: e) in cache.entries) d: {'u': e.userId, 't': e.checkedAt, 'n': e.name},
    }),
  );

  /// Saved names of known accounts, from the last run. Needs no address book,
  /// so a push in the background can name the sender.
  Map<String, String> cachedNames() => {
    for (final e in _load().values)
      if (e.userId != null) e.userId!: e.name,
  };

  /// Forgets everything (sign-out).
  Future<void> clear() async {
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
    final old = _load();
    // Numbers no longer in the address book are dropped.
    final cache = {
      for (final MapEntry(key: d, value: name) in names.entries)
        if (old[d] case final e?) d: (userId: e.userId, checkedAt: e.checkedAt, name: name),
    };
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
            cache[d] = (userId: found[d], checkedAt: now, name: names[d]!);
          }
          await _save(cache);
        } on IdError catch (e) {
          if (e.code == 'rate_limited') await _prefs.setInt(_retryKey, now + (e.retryAfter ?? 3600) * 1000);
          break;
        }
      }
    }
    await _save(cache);
    return _result(book, cache);
  }

  ContactSyncResult _result(List<BookContact> book, Map<String, ({String? userId, int checkedAt, String name})> cache) {
    final onChama = <String, ChamaContact>{};
    final invite = <InviteContact>[];
    for (final c in book) {
      final digits = c.numbers.map(normalizeContactPhone).whereType<String>().toSet();
      if (digits.isEmpty) continue;
      final registered = digits.where((d) => cache[d]?.userId != null).toList();
      for (final d in registered) {
        final e = cache[d]!;
        onChama.putIfAbsent(e.userId!, () => ChamaContact(name: e.name, phone: d, userId: e.userId!));
      }
      // Only numbers already checked: an unchecked one may still have an account.
      if (registered.isEmpty && digits.every(cache.containsKey)) {
        invite.add(InviteContact(name: c.name, phone: digits.first));
      }
    }
    int byName(String a, String b) => foldText(a).compareTo(foldText(b));
    return ContactSyncResult(
      onChama.values.toList()..sort((a, b) => byName(a.name, b.name)),
      invite..sort((a, b) => byName(a.name, b.name)),
    );
  }
}
