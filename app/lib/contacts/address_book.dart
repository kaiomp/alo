import 'package:flutter_contacts/flutter_contacts.dart' as fc;

import 'contact_sync.dart';

/// READ_CONTACTS state as the screens need it.
enum ContactsAccess {
  granted,

  /// Not granted yet; asking shows the system dialog.
  notGranted,

  /// "Don't ask again": only the system settings can grant it.
  blocked,

  /// No address book on this platform (web).
  unavailable,
}

/// The phone's address book. Tests use a fake.
abstract interface class AddressBook {
  Future<ContactsAccess> access();
  Future<ContactsAccess> requestAccess();
  Future<void> openSettings();
  Future<List<BookContact>> read();

  /// Fires when the address book changes.
  Stream<void> get changes;
}

/// Android address book through flutter_contacts (read-only).
class DeviceAddressBook implements AddressBook {
  static ContactsAccess _map(fc.PermissionStatus s) => switch (s) {
    fc.PermissionStatus.granted || fc.PermissionStatus.limited => ContactsAccess.granted,
    fc.PermissionStatus.permanentlyDenied || fc.PermissionStatus.restricted => ContactsAccess.blocked,
    _ => ContactsAccess.notGranted,
  };

  @override
  Future<ContactsAccess> access() async => _map(await fc.FlutterContacts.permissions.check(fc.PermissionType.read));

  @override
  Future<ContactsAccess> requestAccess() async =>
      _map(await fc.FlutterContacts.permissions.request(fc.PermissionType.read));

  @override
  Future<void> openSettings() => fc.FlutterContacts.permissions.openSettings();

  @override
  Future<List<BookContact>> read() async {
    final all = await fc.FlutterContacts.getAll(properties: {fc.ContactProperty.phone});
    return [
      for (final c in all)
        if (c.phones.isNotEmpty) BookContact(c.displayName ?? '', [for (final p in c.phones) p.number]),
    ];
  }

  @override
  Stream<void> get changes => fc.FlutterContacts.onDatabaseChange;
}

/// Platforms without an address book.
class NoAddressBook implements AddressBook {
  @override
  Future<ContactsAccess> access() async => ContactsAccess.unavailable;
  @override
  Future<ContactsAccess> requestAccess() async => ContactsAccess.unavailable;
  @override
  Future<void> openSettings() async {}
  @override
  Future<List<BookContact>> read() async => const [];
  @override
  Stream<void> get changes => const Stream.empty();
}
