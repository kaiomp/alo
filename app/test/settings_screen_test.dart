import 'package:chama/common/deps.dart';
import 'package:chama/common/notifications.dart';
import 'package:chama/common/theme.dart';
import 'package:chama/contacts/address_book.dart';
import 'package:chama/contacts/contacts_service.dart';
import 'package:chama/l10n/app_localizations.dart';
import 'package:chama/profile/settings_screen.dart';
import 'package:chama/services/push.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes.dart';

class _Notifications extends Notifications {
  bool allowed = false;
  var settingsOpened = 0;

  @override
  Future<bool> enabled() async => allowed;

  @override
  Future<void> openSettings() async => settingsOpened++;
}

class _Push extends PushService {
  _Push(super.chat, super.prefs);
  var registered = 0;

  @override
  Future<bool> register() async {
    registered++;
    return false;
  }
}

void main() {
  testWidgets('the notification row says when Android blocks them, and each state leads to its fix', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final chat = (await tester.runAsync(() => testService(prefs)))!;
    chat.client.setUserId('@me:chama.test');
    final notifications = _Notifications();
    final push = _Push(chat, prefs);
    await tester.pumpWidget(
      Deps(
        chat: chat,
        id: chat.id,
        contacts: ContactsService(chat, NoAddressBook(), prefs),
        notifications: notifications,
        push: push,
        newRecorder: () => throw UnimplementedError(),
        pickFile: ({required bool image}) async => null,
        shareText: (_) async {},
        child: MaterialApp(
          theme: chamaTheme(Brightness.light),
          locale: const Locale('pt'),
          supportedLocales: L10n.supportedLocales,
          localizationsDelegates: L10n.localizationsDelegates,
          home: const SettingsScreen(),
        ),
      ),
    );
    await tester.pump();
    final l = lookupL10n(const Locale('pt'));
    final row = find.byKey(const Key('notifications_status'));
    await tester.scrollUntilVisible(row, 100);

    // Permission denied: off, and the tap opens the system settings.
    expect(find.descendant(of: row, matching: find.text(l.notificationsBlocked(l.appName))), findsOneWidget);
    await tester.tap(row);
    expect(notifications.settingsOpened, 1);

    // Turned on there; back in the app, no distributor yet: the tap tries again.
    notifications.allowed = true;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(find.descendant(of: row, matching: find.text(l.notificationsNeedApp(l.appName))), findsOneWidget);
    await tester.tap(row);
    expect(push.registered, 1);

    push.active.value = true;
    await tester.pump();
    expect(find.descendant(of: row, matching: find.text(l.notificationsOn)), findsOneWidget);
    await tester.tap(row);
    expect((notifications.settingsOpened, push.registered), (1, 1), reason: 'on: nothing to fix');
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));
}
