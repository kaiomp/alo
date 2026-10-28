import 'package:flutter/foundation.dart';

import '../auth/id_client.dart';
import '../common/notifications.dart';
import '../contacts/address_book.dart';
import '../contacts/contact_sync.dart';
import '../contacts/contacts_service.dart';
import '../services/push.dart';
import 'demo_data.dart';

/// The sign-in service: never reached, the demo starts signed in.
class DemoId implements IdClient {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// The address book: the demo people, all on Alô.
class DemoContacts extends ChangeNotifier implements ContactsService {
  @override
  ContactsAccess access = ContactsAccess.granted;

  @override
  List<AloContact> onAlo = [
    for (final (i, p) in [ana, carol, cida, fernanda, juliana, lucas, mae, marcos, pai, pedro, rafael, thiago].indexed)
      AloContact(name: p.name, phone: '55819876500${i.toString().padLeft(2, '0')}', userId: p.id),
  ];

  @override
  List<InviteContact> invite = const [InviteContact(name: 'Seu Zé da Padaria', phone: '5581987659999')];

  @override
  Future<void> start() async {}

  @override
  Future<void> allow() async {}

  @override
  Future<void> refresh() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// No notifications on the demo: nothing arrives from outside.
class DemoNotifications implements Notifications {
  @override
  final opened = ValueNotifier<String?>(null);

  @override
  Future<void> checkLaunch() async {}

  @override
  Future<void> requestPermission() async {}

  @override
  Future<bool> enabled() async => true;

  @override
  Future<void> openSettings() async {}

  @override
  Future<void> cancel(String roomId) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class DemoPush implements PushService {
  @override
  final active = ValueNotifier<bool>(true);

  @override
  Future<bool> register() async => true;

  @override
  Future<void> refresh() async {}

  @override
  void resumed() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
