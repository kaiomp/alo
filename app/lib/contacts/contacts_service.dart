import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../chat_list/chat_filter.dart';
import '../services/chat_service.dart';
import 'address_book.dart';
import 'contact_sync.dart';

/// The address book as the app shows it: who is on Alô, who to invite, and
/// the saved names that replace display names everywhere (spec §4, Privacy).
class ContactsService extends ChangeNotifier {
  ContactsService(this._chat, this._book, SharedPreferences prefs) {
    _sync = ContactSync(prefs, _chat.lookupPhones);
    ready = _loadCached();
    _chat.loggedIn.addListener(_onLoginChanged);
  }

  /// Done when the names saved at the last run are in place: a push in the
  /// background waits for it to name the sender.
  late final Future<void> ready;

  final ChatService _chat;
  final AddressBook _book;
  late final ContactSync _sync;
  StreamSubscription<void>? _changes;
  bool _running = false;

  /// Counts sign-outs, so a lookup that outlived its account is dropped.
  int _signOuts = 0;

  Future<void> _loadCached() async {
    final signOuts = _signOuts;
    try {
      final names = await _sync.cachedNames();
      if (signOuts == _signOuts) _chat.contactNames = names;
    } catch (e) {
      // The keystore could not be read: names come with the next run.
      debugPrint('Saved contact names not read: $e');
    }
  }

  ContactsAccess access = ContactsAccess.notGranted;
  List<AloContact> onAlo = const [];
  List<InviteContact> invite = const [];

  /// Reads the permission without asking and syncs when it is granted. Safe
  /// to call again (app resumed, back from the system settings).
  Future<void> start() async {
    access = await _book.access();
    notifyListeners();
    if (access != ContactsAccess.granted) return;
    _changes ??= _book.changes.listen((_) => unawaited(refresh()));
    await refresh();
  }

  /// The rationale card's button: the system dialog, or the settings page
  /// once the user chose "don't ask again".
  Future<void> allow() async {
    if (access == ContactsAccess.blocked) return _book.openSettings();
    access = await _book.requestAccess();
    notifyListeners();
    if (access == ContactsAccess.granted) await start();
  }

  Future<void> refresh() async {
    if (_running || access != ContactsAccess.granted || !_chat.loggedIn.value) return;
    _running = true;
    final signOuts = _signOuts;
    try {
      await ready; // the cached names must not land over this run's
      final r = await _sync.run(await _book.read());
      // A number that now answers for another account shows that account's
      // own profile name, with the number under it.
      final shown = [
        for (final c in r.onAlo)
          c.moved
              ? AloContact(name: await _chat.profileName(c.userId), phone: c.phone, userId: c.userId, moved: true)
              : c,
      ]..sort((a, b) => foldText(a.name).compareTo(foldText(b.name)));
      if (signOuts != _signOuts) return;
      for (final m in r.moved) {
        _chat.numberMoved(m.userId, m.name);
      }
      onAlo = shown;
      invite = r.invite;
      _chat.contactNames = {
        for (final c in shown)
          if (!c.moved) c.userId: c.name,
      };
      notifyListeners();
    } finally {
      // Signed out while the lookup ran, or it failed half-way: that
      // account's answers must not stay.
      if (signOuts != _signOuts) await _sync.clear();
      _running = false;
    }
  }

  void _onLoginChanged() {
    if (_chat.loggedIn.value) return;
    _signOuts++;
    unawaited(_sync.clear());
    onAlo = const [];
    invite = const [];
    _chat.contactNames = const {};
    notifyListeners();
  }

  @override
  void dispose() {
    _changes?.cancel();
    _chat.loggedIn.removeListener(_onLoginChanged);
    super.dispose();
  }
}
