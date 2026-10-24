import 'package:flutter/material.dart';

import '../common/deps.dart';
import '../l10n/app_localizations.dart';
import 'new_group_screen.dart';
import 'phone_field.dart';

/// Start a 1:1 chat by phone number, or go to "Novo grupo".
/// Pops with the room ID to open.
class NewChatScreen extends StatelessWidget {
  const NewChatScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.newChat)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ListTile(
            key: const Key('new_group'),
            leading: const CircleAvatar(child: Icon(Icons.group_add)),
            title: Text(l.newGroup),
            onTap: () async {
              final roomId = await Navigator.of(context)
                  .push<String>(MaterialPageRoute(builder: (_) => const NewGroupScreen()));
              if (roomId != null && context.mounted) Navigator.pop(context, roomId);
            },
          ),
          const SizedBox(height: 16),
          PhoneLookupField(
            fieldKey: const ValueKey('new_chat_phone'),
            buttonLabel: l.startChat,
            onUser: (userId, _) async {
              final roomId = await Deps.of(context).chat.startDirectChat(userId);
              if (context.mounted) Navigator.pop(context, roomId);
            },
          ),
        ],
      ),
    );
  }
}
