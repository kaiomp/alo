import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../auth/phone.dart';
import '../common/avatar.dart';
import '../common/deps.dart';
import '../common/widgets.dart';
import '../config.dart';
import '../l10n/app_localizations.dart';
import 'profile_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late Future<({String name, Uri? avatar})> _profile = Deps.of(context).chat.myProfile();

  @override
  void initState() {
    super.initState();
    // The status shows what the server has, not only what this phone stored.
    if (onAndroid) unawaited(Deps.of(context).push.refresh());
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
      title: l.about,
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
      title: l.signOutQuestion,
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
              builder: (context, on, _) => ListTile(
                key: const Key('notifications_status'),
                leading: Icon(on ? Icons.notifications_active_outlined : Icons.notifications_off_outlined),
                title: Text(l.sectionNotifications),
                subtitle: Text(on ? l.notificationsOn : l.notificationsNeedApp),
              ),
            ),
          ],
          SectionHeader(l.sectionHelp),
          ListTile(leading: const Icon(Icons.info_outline), title: Text(l.about), onTap: _about),
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
