import 'package:flutter/material.dart';

import '../auth/phone.dart';
import '../chat_list/chat_filter.dart';
import '../common/avatar.dart';
import '../common/deps.dart';
import '../common/theme.dart';
import '../common/widgets.dart';
import '../config.dart';
import '../contacts/address_book.dart';
import '../l10n/app_localizations.dart';
import 'new_group_screen.dart';
import 'phone_field.dart';

/// WhatsApp's contact picker: "Novo grupo", a chat by number, then
/// "Contatos no Chama" and "Convidar para o Chama". Pops with the room ID.
class NewChatScreen extends StatefulWidget {
  const NewChatScreen({super.key});

  @override
  State<NewChatScreen> createState() => _NewChatScreenState();
}

class _NewChatScreenState extends State<NewChatScreen> {
  final _phone = FocusNode();
  final _search = TextEditingController();
  bool _opening = false;

  @override
  void dispose() {
    _phone.dispose();
    _search.dispose();
    super.dispose();
  }

  /// Search by name (no case, no accents) or by digits of the number.
  bool _matches(String name, String phone) {
    final q = foldText(_search.text.trim());
    final digits = q.replaceAll(RegExp(r'\D'), '');
    return q.isEmpty || foldText(name).contains(q) || (digits.isNotEmpty && phone.contains(digits));
  }

  Future<void> _chatWith(String userId) async {
    final roomId = await Deps.of(context).chat.startDirectChat(userId);
    if (mounted) Navigator.pop(context, roomId);
  }

  /// A tapped contact: one chat at a time, a failure in a snackbar.
  Future<void> _open(String userId) async {
    setState(() => _opening = true);
    await runOrSnack(context, () => _chatWith(userId));
    if (mounted) setState(() => _opening = false);
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final deps = Deps.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.newChat)),
      body: FormWidth(
        child: ListenableBuilder(
          listenable: deps.contacts,
          builder: (context, _) {
            final contacts = deps.contacts;
            final onChama = [
              for (final c in contacts.onChama)
                if (_matches(c.name, c.phone)) c,
            ];
            final invite = [
              for (final c in contacts.invite)
                if (_matches(c.name, c.phone)) c,
            ];
            return ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                if (contacts.access == ContactsAccess.granted)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                    child: SearchBox(
                      fieldKey: const Key('contact_search'),
                      controller: _search,
                      hint: l.searchContacts,
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
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
                    onUser: (userId, _) => _chatWith(userId),
                  ),
                ),
                if (contacts.access == ContactsAccess.notGranted || contacts.access == ContactsAccess.blocked)
                  ContactsRationale(
                    blocked: contacts.access == ContactsAccess.blocked,
                    onAllow: () => runOrSnack(context, contacts.allow),
                  ),
                if (onChama.isNotEmpty) SectionHeader(l.contactsOnChama, key: const Key('contacts_on_chama')),
                for (final c in onChama)
                  ContactRow(
                    key: ValueKey('contact_${c.userId}'),
                    name: c.name,
                    phone: c.phone,
                    seed: c.userId,
                    onTap: _opening ? null : () => _open(c.userId),
                  ),
                if (invite.isNotEmpty) SectionHeader(l.inviteToChama, key: const Key('contacts_invite')),
                for (final c in invite)
                  ContactRow(
                    key: ValueKey('invite_${c.phone}'),
                    name: c.name,
                    phone: c.phone,
                    seed: c.phone,
                    trailing: TextButton(
                      onPressed: () => runOrSnack(context, () => deps.shareText(l.inviteText(chamaInviteUrl))),
                      child: Text(l.invite, semanticsLabel: '${l.invite} ${ContactRow.labelOf(c.name, c.phone)}'),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// A saved contact: avatar, the saved name and the number under it. A contact
/// saved without a name shows its number instead.
class ContactRow extends StatelessWidget {
  const ContactRow({super.key, required this.name, required this.phone, required this.seed, this.onTap, this.trailing});
  final String name;

  /// E.164 digits.
  final String phone;
  final String seed;
  final VoidCallback? onTap;
  final Widget? trailing;

  static String labelOf(String name, String phone) => name.trim().isEmpty ? formatPhone(phone) : name;

  @override
  Widget build(BuildContext context) {
    final named = name.trim().isNotEmpty;
    return ListTile(
      minTileHeight: 64,
      horizontalTitleGap: 14,
      // The name is in the title already; the avatar would say it twice.
      leading: ExcludeSemantics(
        child: Avatar(name: name, seed: seed),
      ),
      title: Text(
        labelOf(name, phone),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
      ),
      subtitle: named ? Text(formatPhone(phone), maxLines: 1, overflow: TextOverflow.ellipsis) : null,
      trailing: trailing,
      onTap: onTap,
    );
  }
}

/// Why Chama wants the address book, shown before the system dialog (Android
/// asks apps to explain first; the Play Store asks for a prominent
/// disclosure). Without it the number field still works.
class ContactsRationale extends StatelessWidget {
  const ContactsRationale({super.key, required this.blocked, required this.onAllow});

  /// The user chose "don't ask again": the button opens the system settings.
  final bool blocked;
  final VoidCallback onAllow;

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: scheme.surfaceContainer, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.contacts_outlined, color: ChatColors.of(context).accent),
              const SizedBox(width: 12),
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(l.contactsRationaleTitle, style: theme.textTheme.titleMedium),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            l.contactsRationale,
            style: theme.textTheme.bodyMedium?.copyWith(fontSize: 14, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          FilledButton(
            key: const Key('contacts_allow'),
            onPressed: onAllow,
            child: Text(blocked ? l.contactsOpenSettings : l.contactsAllow),
          ),
        ],
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
      backgroundColor: Theme.of(context).colorScheme.primary,
      child: Icon(icon, size: 22, color: Theme.of(context).colorScheme.onPrimary),
    ),
    title: Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
    onTap: onTap,
  );
}
