import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/chat_service.dart';
import 'address_book.dart';
import 'contact_sync.dart';

/// The address book as the app shows it: who is on Chama, who to invite, and
/// the saved names that replace display names everywhere (spec §4, Privacy).
class ContactsService extends ChangeNotifier {
  ContactsService(this._chat, this._book, SharedPreferences prefs) {
    _sync = ContactSync(prefs, _chat.lookupPhones);
    _chat.contactNames = _sync.cachedNames();
    _chat.loggedIn.addListener(_onLoginChanged);
  }

  final ChatService _chat;
  final AddressBook _book;
  late final ContactSync _sync;
  StreamSubscription<void>? _changes;
  bool _running = false;

  /// Counts sign-outs, so a lookup that outlived its account is dropped.
  int _signOuts = 0;

  ContactsAccess access = ContactsAccess.notGranted;
  List<ChamaContact> onChama = const [];
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
      final r = await _sync.run(await _book.read());
      if (signOuts != _signOuts) return;
      onChama = r.onChama;
      invite = r.invite;
      _chat.contactNames = {for (final c in r.onChama) c.userId: c.name};
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
    onChama = const [];
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
