import 'package:flutter/material.dart';

import '../common/avatar.dart';
import '../common/deps.dart';
import '../l10n/app_localizations.dart';
import '../services/chat_session.dart';
import 'phone_field.dart';

/// "Dados do grupo" (members, admins, add, leave) or "Dados do contato".
class GroupInfoScreen extends StatelessWidget {
  const GroupInfoScreen({super.key, required this.session});
  final ChatSession session;

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final me = Deps.of(context).chat.myUserId;
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) {
        final members = session.members;
        return Scaffold(
          appBar: AppBar(title: Text(session.isGroup ? l.groupInfo : l.contactInfo)),
          body: ListView(
            children: [
              const SizedBox(height: 24),
              Center(
                child: Avatar(name: session.name, mxc: session.avatar, radius: 56, group: session.isGroup),
              ),
              const SizedBox(height: 12),
              Center(child: Text(session.name, style: Theme.of(context).textTheme.headlineSmall)),
              if (session.isGroup) ...[
                Center(child: Text(l.members(members.length))),
                const Divider(height: 32),
                if (session.iAmAdmin)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: PhoneLookupField(
                      fieldKey: const ValueKey('add_member_phone'),
                      buttonLabel: l.addMember,
                      onUser: (userId, _) => session.addMembers([userId]),
                    ),
                  ),
                for (final m in members)
                  ListTile(
                    leading: Avatar(name: m.name, mxc: m.avatar),
                    title: Text(m.userId == me ? l.you : m.name),
                    trailing: m.isAdmin ? Chip(label: Text(l.admin)) : null,
                    onLongPress: !session.iAmAdmin || m.userId == me
                        ? null
                        : () => showModalBottomSheet<void>(
                            context: context,
                            builder: (context) => SafeArea(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (!m.isAdmin)
                                    ListTile(
                                      title: Text(l.makeAdmin),
                                      onTap: () {
                                        Navigator.pop(context);
                                        session.makeAdmin(m.userId);
                                      },
                                    ),
                                  ListTile(
                                    title: Text(l.removeMember),
                                    onTap: () {
                                      Navigator.pop(context);
                                      session.removeMember(m.userId);
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ),
                  ),
                const Divider(),
                ListTile(
                  key: const Key('leave_group'),
                  leading: Icon(Icons.logout, color: Theme.of(context).colorScheme.error),
                  title: Text(l.leaveGroup, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  onTap: () async {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: Text(l.leaveQuestion),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l.cancel)),
                          TextButton(onPressed: () => Navigator.pop(context, true), child: Text(l.leaveGroup)),
                        ],
                      ),
                    );
                    if (ok != true || !context.mounted) return;
                    await session.leave();
                    if (context.mounted) Navigator.of(context).popUntil((r) => r.isFirst);
                  },
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
