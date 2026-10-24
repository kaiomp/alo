import 'package:flutter/material.dart';

import '../common/actions.dart';
import '../common/avatar.dart';
import '../common/deps.dart';
import '../common/theme.dart';
import '../common/widgets.dart';
import '../l10n/app_localizations.dart';
import '../services/chat_session.dart';
import '../services/models.dart';
import 'phone_field.dart';

/// "Dados do grupo" (members, admins, add, leave) or "Dados do contato".
class GroupInfoScreen extends StatelessWidget {
  const GroupInfoScreen({super.key, required this.session, this.onClose, this.onLeft});
  final ChatSession session;

  /// Wide layout: the info is a side pane with an X instead of a back arrow.
  final VoidCallback? onClose;

  /// After leaving the group. Default: back to the chat list.
  final VoidCallback? onLeft;

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final me = Deps.of(context).chat.myUserId;
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) {
        final members = session.members;
        final other = members.where((m) => m.userId != me).firstOrNull;
        return Scaffold(
          appBar: AppBar(
            automaticallyImplyLeading: onClose == null,
            leading: onClose == null
                ? null
                : IconButton(
                    key: const Key('info_close'),
                    tooltip: l.close,
                    icon: const Icon(Icons.close),
                    onPressed: onClose,
                  ),
            title: Text(session.isGroup ? l.groupInfo : l.contactInfo),
          ),
          body: FormWidth(
            child: ListView(
              children: [
                _Header(session: session, memberCount: members.length),
                _ActionRow(onMessage: onClose ?? () => Navigator.of(context).pop()),
                const SizedBox(height: 24),
                const SectionBand(),
                ListTile(
                  minTileHeight: 72,
                  leading: const Icon(Icons.lock_outline),
                  title: Text(l.encryption),
                  subtitle: Text(l.encryptionRow),
                  onTap: () => showE2eExplainer(context),
                ),
                const SectionBand(),
                ListTile(
                  enabled: false,
                  leading: const Icon(Icons.perm_media_outlined),
                  title: Text(l.mediaLinksDocs),
                  trailing: Text(l.none),
                ),
                const SectionBand(),
                if (session.isGroup)
                  ..._members(context, l, members, me)
                else if (other != null)
                  _BlockRow(member: other),
              ],
            ),
          ),
        );
      },
    );
  }

  List<Widget> _members(BuildContext context, L10n l, List<Member> members, String me) {
    final scheme = Theme.of(context).colorScheme;
    final colors = ChatColors.of(context);
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Text(
          l.members(members.length),
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: scheme.onSurfaceVariant),
        ),
      ),
      if (session.iAmAdmin)
        ListTile(
          key: const Key('add_participants'),
          minTileHeight: 64,
          leading: CircleAvatar(
            radius: 20,
            backgroundColor: colors.tint,
            child: Icon(Icons.person_add_alt_1, size: 22, color: colors.accent),
          ),
          title: Text(l.addParticipants, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
          onTap: () => Navigator.of(context).push(pageRoute<void>(context, _AddMembersScreen(session: session))),
        ),
      for (final m in members)
        Builder(
          builder: (tile) => ListTile(
            minTileHeight: 64,
            leading: Avatar(name: m.name, seed: m.userId, mxc: m.avatar, radius: 20),
            title: Text(m.userId == me ? l.you : m.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: m.isAdmin
                ? Text(
                    l.admin,
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: colors.accent),
                  )
                : null,
            onLongPress: !session.iAmAdmin || m.userId == me ? null : () => _memberActions(tile, l, m),
          ),
        ),
      const SectionBand(),
      ListTile(
        key: const Key('leave_group'),
        leading: Icon(Icons.logout, color: scheme.error),
        title: Text(l.leaveGroup, style: TextStyle(color: scheme.error)),
        onTap: () async {
          final ok = await confirm(
            context,
            title: l.leaveQuestion,
            body: l.leaveExplain,
            action: l.leaveGroup,
            destructive: true,
          );
          if (!ok || !context.mounted) return;
          if (!await runOrSnack(context, session.leave) || !context.mounted) return;
          if (onLeft != null) {
            onLeft!();
          } else {
            Navigator.of(context).popUntil((r) => r.isFirst);
          }
        },
      ),
      const SizedBox(height: 24),
    ];
  }

  Future<void> _memberActions(BuildContext tile, L10n l, Member m) async {
    final run = await showActions<Future<void> Function()>(
      tile,
      anchor: rectOf(tile),
      actions: [
        if (!m.isAdmin) MenuAction(() => session.makeAdmin(m.userId), Icons.admin_panel_settings_outlined, l.makeAdmin),
        MenuAction(
          () => session.removeMember(m.userId),
          Icons.person_remove_outlined,
          l.removeMember,
          destructive: true,
        ),
      ],
    );
    if (run != null && tile.mounted) await runOrSnack(tile, run);
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.session, required this.memberCount});
  final ChatSession session;
  final int memberCount;

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
      child: Column(
        children: [
          Avatar(name: session.name, seed: session.roomId, mxc: session.avatar, radius: 56, group: session.isGroup),
          const SizedBox(height: 16),
          Text(session.name, textAlign: TextAlign.center, style: theme.textTheme.headlineSmall),
          if (session.isGroup) ...[
            const SizedBox(height: 4),
            Text(
              '${l.groupLabel} · ${l.members(memberCount)}',
              style: TextStyle(fontSize: 16, color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }
}

/// Mensagem / Ligar / Pesquisar tiles under the header.
class _ActionRow extends StatelessWidget {
  const _ActionRow({required this.onMessage});
  final VoidCallback onMessage;

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _ActionTile(icon: Icons.chat_bubble_outline, label: l.messageHint, onTap: onMessage),
        const SizedBox(width: 12),
        _ActionTile(icon: Icons.call_outlined, label: l.call, note: l.soon),
        const SizedBox(width: 12),
        _ActionTile(icon: Icons.search, label: l.search, note: l.soon),
      ],
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({required this.icon, required this.label, this.note, this.onTap});
  final IconData icon;
  final String label;
  final String? note; // set when not available yet ("em breve")
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final colors = ChatColors.of(context);
    final enabled = onTap != null;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: BorderSide(color: scheme.outlineVariant),
    );
    return Material(
      shape: shape,
      color: Colors.transparent,
      child: InkWell(
        customBorder: shape,
        onTap: onTap,
        child: SizedBox(
          width: 96,
          height: 72,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 24, color: enabled ? colors.accent : scheme.onSurfaceVariant),
              const SizedBox(height: 4),
              Text(label, style: TextStyle(fontSize: 13, color: scheme.onSurface)),
              // Always a note line, empty or not, so the tiles line up.
              Text(note ?? '', style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
            ],
          ),
        ),
      ),
    );
  }
}

class _BlockRow extends StatefulWidget {
  const _BlockRow({required this.member});
  final Member member;

  @override
  State<_BlockRow> createState() => _BlockRowState();
}

class _BlockRowState extends State<_BlockRow> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final error = Theme.of(context).colorScheme.error;
    final chat = Deps.of(context).chat;
    final m = widget.member;
    final blocked = chat.isBlocked(m.userId);
    return ListTile(
      key: const Key('block_contact'),
      enabled: !_busy,
      leading: Icon(Icons.block, color: error),
      title: Text(blocked ? l.unblock(m.name) : l.block(m.name), style: TextStyle(color: error)),
      onTap: () async {
        if (!blocked &&
            !await confirm(
              context,
              title: l.blockQuestion(m.name),
              body: l.blockExplain(m.name),
              action: l.blockAction,
              destructive: true,
            )) {
          return;
        }
        setState(() => _busy = true);
        try {
          await chat.setBlocked(m.userId, !blocked);
        } catch (_) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l.errUnknown)));
          }
        } finally {
          if (mounted) setState(() => _busy = false);
        }
      },
    );
  }
}

/// "Adicionar participantes": the phone lookup used by "Novo grupo".
class _AddMembersScreen extends StatelessWidget {
  const _AddMembersScreen({required this.session});
  final ChatSession session;

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.addParticipants)),
      body: FormWidth(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            PhoneLookupField(
              fieldKey: const ValueKey('add_member_phone'),
              buttonLabel: l.addMember,
              onUser: (userId, _) async {
                await session.addMembers([userId]);
                if (context.mounted) Navigator.of(context).pop();
              },
            ),
          ],
        ),
      ),
    );
  }
}
