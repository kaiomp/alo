import 'package:alo/chat/message_bubble.dart';
import 'package:alo/l10n/app_localizations.dart';
import 'package:alo/services/models.dart';
import 'package:alo/services/security_code.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const me = '@me:alo.test';
const bob = '@bob:alo.test';

void main() {
  late Client client;
  late SharedPreferences prefs;
  late SecurityCodeWatch watch;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    final db = await MatrixSdkDatabase.init(
      'security_code_test',
      database: await databaseFactoryFfi.openDatabase(':memory:'),
      sqfliteFactory: databaseFactoryFfi,
    );
    client = Client('security_code_test', database: db)..setUserId(me);
    watch = SecurityCodeWatch(client, prefs);
  });

  tearDown(() => watch.dispose());

  Room room(String id, Map<String, String> members) {
    final r = Room(id: id, client: client, membership: Membership.join);
    members.forEach(
      (user, membership) => r.setState(
        Event(
          type: EventTypes.RoomMember,
          content: {'membership': membership},
          eventId: '\$$user$membership',
          senderId: user,
          stateKey: user,
          originServerTs: DateTime(2026),
          room: r,
        ),
      ),
    );
    client.rooms.add(r);
    return r;
  }

  void masterKey(String user, String key) {
    client.userDeviceKeys[user] = DeviceKeysList(
      user,
      client,
      outdated: false,
      crossSigningKeys: {
        key: CrossSigningKey.fromJson({
          'user_id': user,
          'usage': ['master'],
          'keys': {'ed25519:$key': key},
        }, client),
      },
    );
  }

  test('the first key seen is trusted; a new one adds a notice to every shared chat', () {
    room('!dm:alo.test', {bob: 'join'});
    room('!group:alo.test', {bob: 'join'});
    room('!old:alo.test', {bob: 'leave'});
    masterKey(bob, 'KEY1');
    watch.check();
    expect(watch.noticesIn('!dm:alo.test'), isEmpty);

    masterKey(bob, 'KEY2');
    watch.check();
    watch.check(); // seen once, noted once
    expect(watch.noticesIn('!dm:alo.test').map((n) => n.userId), [bob]);
    expect(watch.noticesIn('!group:alo.test').map((n) => n.userId), [bob]);
    expect(watch.noticesIn('!old:alo.test'), isEmpty);
    expect(watch.revision.value, 1);
  });

  test('pins and notices survive a restart and go on sign-out', () async {
    room('!dm:alo.test', {bob: 'join'});
    masterKey(bob, 'KEY1');
    watch.check();
    masterKey(bob, 'KEY2');
    watch.check();

    final restarted = SecurityCodeWatch(client, prefs);
    expect(restarted.noticesIn('!dm:alo.test'), hasLength(1));
    restarted.check(); // KEY2 is pinned: no second notice
    expect(restarted.noticesIn('!dm:alo.test'), hasLength(1));

    await restarted.clear();
    await restarted.dispose();
    expect(SecurityCodeWatch(client, prefs).noticesIn('!dm:alo.test'), isEmpty);
  });

  test('my own key and a list still loading add nothing', () {
    room('!dm:alo.test', {bob: 'join', me: 'join'});
    masterKey(me, 'MINE1');
    masterKey(bob, 'KEY1');
    watch.check();
    masterKey(me, 'MINE2');
    client.userDeviceKeys[bob] = DeviceKeysList(bob, client); // empty while /keys/query runs
    watch.check();
    expect(watch.noticesIn('!dm:alo.test'), isEmpty);
  });

  test('the notice reads like WhatsApp', () {
    final m = Message(
      id: 'security_${bob}_1',
      senderId: bob,
      senderName: 'Bia',
      isMine: false,
      time: DateTime(2026),
      kind: MessageKind.system,
      systemKind: SystemKind.securityCodeChanged,
    );
    expect(
      MessageBubble.systemText(m, lookupL10n(const Locale('pt')), myUserId: me),
      'O código de segurança de Bia mudou',
    );
    expect(MessageBubble.systemText(m, lookupL10n(const Locale('en')), myUserId: me), "Bia's security code changed");
  });

  test(
    'a saved number now answering for another account adds a line to every chat with the old one (final review 6)',
    () async {
      room('!dm:alo.test', {bob: 'join'});
      room('!group:alo.test', {bob: 'join'});
      room('!old:alo.test', {bob: 'leave'});
      watch.noteNumberMoved(bob, 'Mãe');
      expect(watch.noticesIn('!dm:alo.test').map((n) => (n.userId, n.name)), [(bob, 'Mãe')]);
      expect(watch.noticesIn('!group:alo.test'), hasLength(1));
      expect(watch.noticesIn('!old:alo.test'), isEmpty);
      expect(watch.revision.value, 1);

      final restarted = SecurityCodeWatch(client, prefs);
      expect(restarted.noticesIn('!dm:alo.test').single.name, 'Mãe');
      await restarted.dispose();

      final m = Message(
        id: 'security_${bob}_1',
        senderId: bob,
        senderName: 'Mãe',
        isMine: false,
        time: DateTime(2026),
        kind: MessageKind.system,
        systemKind: SystemKind.numberMoved,
      );
      expect(
        MessageBubble.systemText(m, lookupL10n(const Locale('pt')), myUserId: me),
        'O número de Mãe agora é de outra conta',
      );
      expect(
        MessageBubble.systemText(m, lookupL10n(const Locale('en')), myUserId: me),
        "Mãe's number now belongs to another account",
      );
    },
  );
}
