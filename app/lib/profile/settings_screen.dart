import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../auth/phone.dart';
import '../common/avatar.dart';
import '../common/deps.dart';
import '../common/widgets.dart';
import '../config.dart';
import '../l10n/app_localizations.dart';
import '../wellbeing/wellbeing_screen.dart';
import 'profile_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> with WidgetsBindingObserver {
  late Future<({String name, Uri? avatar})> _profile = Deps.of(context).chat.myProfile();

  /// Android lets the app post notifications (see [Notifications.enabled]).
  bool _allowed = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (!onAndroid) return;
    // The status shows what the server has, not only what this phone stored.
    unawaited(Deps.of(context).push.refresh());
    unawaited(_checkAllowed());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Back from the system settings: the user may have turned them on or off.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (onAndroid && state == AppLifecycleState.resumed) unawaited(_checkAllowed());
  }

  Future<void> _checkAllowed() async {
    final allowed = await Deps.of(context).notifications.enabled();
    if (mounted && allowed != _allowed) setState(() => _allowed = allowed);
  }

  Future<void> _editProfile() async {
    final profile = await _profile;
    if (!mounted) return;
    await Navigator.of(context).push(
      pageRoute<void>(
        context,
        ProfileScreen(editing: true, initialName: profile.name, onDone: () => Navigator.of(context).pop()),
      ),
    );
    if (mounted) setState(() => _profile = Deps.of(context).chat.myProfile());
  }

  Future<void> _about() async {
    final l = L10n.of(context);
    final id = Deps.of(context).chat.myUserId;
    await showSheetOrDialog<void>(
      context,
      title: l.about(l.appName),
      action: l.close,
      builder: (context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l.aboutBody),
          const SizedBox(height: 16),
          Text(l.technicalId, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          Row(
            children: [
              Expanded(child: SelectableText(id, key: const Key('technical_id'))),
              IconButton(
                tooltip: l.copy,
                icon: const Icon(Icons.copy, size: 20),
                onPressed: () => Clipboard.setData(ClipboardData(text: id)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _signOut() async {
    final l = L10n.of(context);
    final ok = await confirm(
      context,
      title: l.signOutQuestion(l.appName),
      body: l.signOutExplain,
      action: l.signOut,
      destructive: true,
    );
    if (!ok || !mounted) return;
    final chat = Deps.of(context).chat;
    Navigator.of(context).popUntil((r) => r.isFirst);
    await chat.signOut();
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final chat = Deps.of(context).chat;
    final scheme = Theme.of(context).colorScheme;
    final phone = chat.phone;
    return Scaffold(
      appBar: AppBar(title: Text(l.settings)),
      body: ListView(
        children: [
          FutureBuilder(
            future: _profile,
            builder: (context, snap) => ListTile(
              key: const Key('settings_profile'),
              minTileHeight: 88,
              leading: Avatar(name: snap.data?.name ?? '', seed: chat.myUserId, mxc: snap.data?.avatar, radius: 28),
              title: Text(snap.data?.name ?? '', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
              subtitle: phone == null ? null : Text(formatPhone(phone)),
              trailing: const Icon(Icons.chevron_right),
              onTap: _editProfile,
            ),
          ),
          const Divider(),
          if (Deps.of(context).simpleMode case final simple?)
            ListenableBuilder(
              listenable: simple,
              builder: (context, _) => SwitchListTile(
                key: const Key('simple_switch'),
                secondary: const Icon(Icons.text_increase_rounded),
                title: Text(l.simpleMode),
                subtitle: Text(l.simpleModeBody),
                value: simple.on,
                onChanged: (v) => simple.on = v,
              ),
            ),
          SectionHeader(l.sectionAccount),
          ListTile(
            leading: const Icon(Icons.person_outline),
            title: Text(l.profileTitle),
            subtitle: Text(l.profileRowSub),
            onTap: _editProfile,
          ),
          SectionHeader(l.sectionPrivacy),
          SwitchListTile(
            key: const Key('read_receipts_switch'),
            secondary: const Icon(Icons.done_all),
            title: Text(l.readReceipts),
            subtitle: Text(l.readReceiptsExplain),
            value: chat.readReceipts,
            onChanged: (v) async {
              await chat.setReadReceipts(v);
              setState(() {});
            },
          ),
          if (Deps.of(context).wellbeing != null)
            ListTile(
              key: const Key('settings_wellbeing'),
              leading: const Icon(Icons.spa_outlined),
              title: Text(l.wellbeing),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const WellbeingScreen())),
            ),
          SectionHeader(l.tabChats),
          ListTile(
            enabled: false,
            leading: const Icon(Icons.palette_outlined),
            title: Text(l.theme),
            subtitle: Text(l.themeSystem),
          ),
          if (onAndroid) ...[
            SectionHeader(l.sectionNotifications),
            ValueListenableBuilder<bool>(
              valueListenable: Deps.of(context).push.active,
              builder: (context, registered, _) {
                final deps = Deps.of(context);
                final on = _allowed && registered;
                return ListTile(
                  key: const Key('notifications_status'),
                  leading: Icon(on ? Icons.notifications_active_outlined : Icons.notifications_off_outlined),
                  title: Text(l.sectionNotifications),
                  subtitle: Text(
                    !_allowed
                        ? l.notificationsBlocked(l.appName)
                        : registered
                        ? l.notificationsOn
                        : l.notificationsNeedApp(l.appName),
                  ),
                  // Blocked: the system screen that unblocks them. No
                  // distributor: try again (one may have been installed).
                  onTap: on
                      ? null
                      : !_allowed
                      ? () => unawaited(deps.notifications.openSettings())
                      : () => unawaited(deps.push.register()),
                );
              },
            ),
          ],
          SectionHeader(l.sectionHelp),
          ListTile(leading: const Icon(Icons.info_outline), title: Text(l.about(l.appName)), onTap: _about),
          const SizedBox(height: 16),
          const Divider(),
          ListTile(
            key: const Key('sign_out'),
            leading: Icon(Icons.logout, color: scheme.error),
            title: Text(l.signOut, style: TextStyle(color: scheme.error)),
            onTap: _signOut,
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
