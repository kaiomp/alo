import 'package:alo/chat/chat_screen.dart';
import 'package:alo/chat_list/home_screen.dart';
import 'package:alo/common/deps.dart';
import 'package:alo/common/notifications.dart';
import 'package:alo/common/theme.dart';
import 'package:alo/contacts/address_book.dart';
import 'package:alo/contacts/contacts_service.dart';
import 'package:alo/l10n/app_localizations.dart';
import 'package:alo/services/chat_service.dart';
import 'package:alo/services/push.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes.dart';

const roomId = '!r:alo.test';

// Not Android: no notification, push or address-book plugins in a widget test.
final desktop = TargetPlatformVariant.only(TargetPlatform.linux);

void main() {
  Future<(ChatService, Notifications)> pumpHome(WidgetTester tester, {String? pending, bool joined = true}) async {
    tester.view
      ..physicalSize = const Size(390, 844)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final chat = (await tester.runAsync(() => testService(prefs)))!;
    chat.client
      ..setUserId('@me:alo.test')
      ..rooms.add(Room(id: roomId, client: chat.client, membership: joined ? Membership.join : Membership.invite));
    // A tap that arrived before the home screen existed.
    final notifications = Notifications()..opened.value = pending;
    await tester.pumpWidget(
      Deps(
        chat: chat,
        id: chat.id,
        contacts: ContactsService(chat, NoAddressBook(), prefs),
        notifications: notifications,
        push: PushService(chat, prefs),
        newRecorder: () => throw UnimplementedError(),
        pickFile: ({required bool image}) async => null,
        shareText: (_) async {},
        child: MaterialApp(
          theme: aloTheme(Brightness.light),
          locale: const Locale('pt'),
          supportedLocales: L10n.supportedLocales,
          localizationsDelegates: L10n.localizationsDelegates,
          home: const HomeScreen(),
        ),
      ),
    );
    await settle(tester);
    return (chat, notifications);
  }

  testWidgets('a notification tapped before the home screen existed opens its chat', (tester) async {
    final (_, notifications) = await pumpHome(tester, pending: roomId);
    expect(find.byType(ChatScreen), findsOneWidget);
    expect(notifications.opened.value, isNull);
  }, variant: desktop);

  testWidgets('a notification tapped with the home screen up opens its chat', (tester) async {
    final (_, notifications) = await pumpHome(tester);
    expect(find.byType(ChatScreen), findsNothing);
    notifications.opened.value = roomId;
    await settle(tester);
    expect(find.byType(ChatScreen), findsOneWidget);
  }, variant: desktop);

  testWidgets('a pending tap for a chat this device has not joined stays on the list', (tester) async {
    final (_, notifications) = await pumpHome(tester, pending: roomId, joined: false);
    expect(find.byType(ChatScreen), findsNothing);
    expect(notifications.opened.value, isNull);
  }, variant: desktop);
}

/// Lets the post-frame work (database reads included) finish.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(milliseconds: 400));
  }
}
