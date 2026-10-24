import 'package:flutter/material.dart';

import '../common/deps.dart';
import '../l10n/app_localizations.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final chat = Deps.of(context).chat;
    return Scaffold(
      appBar: AppBar(title: Text(l.settings)),
      body: ListView(
        children: [
          FutureBuilder<String>(
            future: chat.myName(),
            builder: (context, snap) => ListTile(
              leading: const Icon(Icons.person),
              title: Text(snap.data ?? ''),
              subtitle: Text(chat.myUserId),
            ),
          ),
          SwitchListTile(
            key: const Key('read_receipts_switch'),
            title: Text(l.readReceipts),
            subtitle: Text(l.readReceiptsExplain),
            value: chat.readReceipts,
            onChanged: (v) async {
              await chat.setReadReceipts(v);
              setState(() {});
            },
          ),
          ListTile(
            leading: const Icon(Icons.logout),
            title: Text(l.signOut),
            onTap: () async {
              Navigator.of(context).popUntil((r) => r.isFirst);
              await chat.signOut();
            },
          ),
        ],
      ),
    );
  }
}
