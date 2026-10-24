import 'package:chama/chat/chat_screen.dart';
import 'package:chama/chat_list/home_screen.dart';
import 'package:chama/common/deps.dart';
import 'package:chama/common/notifications.dart';
import 'package:chama/common/theme.dart';
import 'package:chama/contacts/address_book.dart';
import 'package:chama/contacts/contacts_service.dart';
import 'package:chama/l10n/app_localizations.dart';
import 'package:chama/services/chat_service.dart';
import 'package:chama/services/push.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes.dart';

const roomId = '!r:chama.test';

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
      ..setUserId('@me:chama.test')
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
          theme: chamaTheme(Brightness.light),
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
