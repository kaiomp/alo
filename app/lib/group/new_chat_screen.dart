import 'package:flutter/material.dart';

import '../common/deps.dart';
import '../common/theme.dart';
import '../common/widgets.dart';
import '../l10n/app_localizations.dart';
import 'new_group_screen.dart';
import 'phone_field.dart';

/// Start a 1:1 chat by phone number, or go to "Novo grupo".
/// Pops with the room ID to open.
class NewChatScreen extends StatefulWidget {
  const NewChatScreen({super.key});

  @override
  State<NewChatScreen> createState() => _NewChatScreenState();
}

class _NewChatScreenState extends State<NewChatScreen> {
  final _phone = FocusNode();

  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.newChat)),
      body: FormWidth(
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            CircleIconRow(
              tileKey: const Key('new_group'),
              icon: Icons.group_add,
              label: l.newGroup,
              onTap: () async {
                final roomId = await Navigator.of(context).push<String>(pageRoute(context, const NewGroupScreen()));
                if (roomId != null && context.mounted) Navigator.pop(context, roomId);
              },
            ),
            CircleIconRow(icon: Icons.person_add_alt_1, label: l.newContact, onTap: _phone.requestFocus),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
              child: PhoneLookupField(
                fieldKey: const ValueKey('new_chat_phone'),
                focusNode: _phone,
                buttonLabel: l.startChat,
                onUser: (userId, _) async {
                  final roomId = await Deps.of(context).chat.startDirectChat(userId);
                  if (context.mounted) Navigator.pop(context, roomId);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// List row with a 40 px orange circle icon ("Novo grupo", "Novo contato").
class CircleIconRow extends StatelessWidget {
  const CircleIconRow({super.key, this.tileKey, required this.icon, required this.label, required this.onTap});
  final Key? tileKey;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    key: tileKey,
    minTileHeight: 64,
    leading: CircleAvatar(
      radius: 20,
      backgroundColor: Tokens.flame,
      child: Icon(icon, size: 22, color: Colors.white),
    ),
    title: Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
    onTap: onTap,
  );
}
