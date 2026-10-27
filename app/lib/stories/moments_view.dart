import 'package:flutter/material.dart';

import '../common/avatar.dart';
import '../common/deps.dart';
import '../common/net_image.dart';
import '../common/theme.dart';
import '../common/time_format.dart';
import '../common/widgets.dart';
import '../l10n/app_localizations.dart';
import '../services/social_service.dart';
import 'moment_ring.dart';
import 'moment_viewer.dart';

/// Momentos: rings of everyone with something new on top, then big cards
/// of the recent and the already seen ones.
class MomentsView extends StatelessWidget {
  const MomentsView({super.key});

  static void open(BuildContext context, List<MomentGroup> groups, int index) => Navigator.of(context).push(
    PageRouteBuilder<void>(
      transitionDuration: const Duration(milliseconds: 320),
      reverseTransitionDuration: const Duration(milliseconds: 240),
      pageBuilder: (_, _, _) => MomentViewer(groups: groups, initial: index),
      transitionsBuilder: (_, a, _, child) {
        final curve = CurvedAnimation(parent: a, curve: Curves.easeOutCubic);
        return FadeTransition(
          opacity: curve,
          child: ScaleTransition(scale: Tween(begin: 0.92, end: 1.0).animate(curve), child: child),
        );
      },
    ),
  );

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final social = Deps.of(context).social!;
    final scheme = Theme.of(context).colorScheme;
    return ValueListenableBuilder<List<MomentGroup>>(
      valueListenable: social.moments,
      builder: (context, groups, _) {
        final unseen = groups.where((g) => !g.seen).toList();
        final seen = groups.where((g) => g.seen).toList();
        void openAt(MomentGroup g) => open(context, groups, groups.indexOf(g));
        return ListView(
          key: const Key('moments'),
          padding: const EdgeInsets.only(bottom: 96),
          children: [
            SizedBox(
              height: 112,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(10, 10, 10, 0),
                children: [
                  _RingTile(
                    person: social.me.person,
                    label: l.you,
                    seen: true,
                    badge: true,
                    onTap: () => ScaffoldMessenger.of(context)
                      ..hideCurrentSnackBar()
                      ..showSnackBar(SnackBar(content: Text(l.comingSoon))),
                  ),
                  for (final g in groups)
                    _RingTile(
                      key: Key('ring_${g.person.id}'),
                      person: g.person,
                      label: g.person.name.split(' ').first,
                      seen: g.seen,
                      onTap: () => openAt(g),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
              child: Row(
                children: [
                  Icon(Icons.lock_outline_rounded, size: 14, color: scheme.onSurfaceVariant),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(l.momentsPrivate, style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant)),
                  ),
                ],
              ),
            ),
            if (unseen.isNotEmpty) ...[SectionHeader(l.recentMoments), _Grid(groups: unseen, onOpen: openAt)],
            if (seen.isNotEmpty) ...[SectionHeader(l.seenMoments), _Grid(groups: seen, onOpen: openAt)],
          ],
        );
      },
    );
  }
}

class _RingTile extends StatelessWidget {
  const _RingTile({
    super.key,
    required this.person,
    required this.label,
    required this.seen,
    required this.onTap,
    this.badge = false,
  });
  final Person person;
  final String label;
  final bool seen;
  final bool badge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: SizedBox(
        // Wider with large text, so first names are never cut.
        width: MediaQuery.textScalerOf(context).scale(80).clamp(80, 150),
        child: Column(
          children: [
            MomentRing(person: person, seen: seen, badge: badge),
            const SizedBox(height: 6),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: seen ? FontWeight.w400 : FontWeight.w600,
                color: seen ? scheme.onSurfaceVariant : scheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Grid extends StatelessWidget {
  const _Grid({required this.groups, required this.onOpen});
  final List<MomentGroup> groups;
  final ValueChanged<MomentGroup> onOpen;

  @override
  Widget build(BuildContext context) => GridView.builder(
    shrinkWrap: true,
    physics: const NeverScrollableScrollPhysics(),
    padding: const EdgeInsets.symmetric(horizontal: 12),
    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: 2,
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 0.66,
    ),
    itemCount: groups.length,
    itemBuilder: (context, i) => _MomentCard(group: groups[i], onTap: () => onOpen(groups[i])),
  );
}

/// The newest moment as a tall card, its author at the bottom.
class _MomentCard extends StatelessWidget {
  const _MomentCard({required this.group, required this.onTap});
  final MomentGroup group;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final last = group.moments.last;
    final p = group.person;
    return GestureDetector(
      key: Key('card_${p.id}'),
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Opacity(opacity: group.seen ? 0.75 : 1, child: NetImage(last.image)),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: [0.5, 1],
                  colors: [Tokens.shadeClear, Tokens.shadeDeeper],
                ),
              ),
            ),
            Positioned(
              left: 10,
              top: 10,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: group.seen ? Tokens.onPhotoFaint : Tokens.ipe, width: 2),
                ),
                child: Avatar(name: p.name, seed: p.id, mxc: p.avatar, radius: 15),
              ),
            ),
            Positioned(
              left: 12,
              right: 12,
              bottom: 12,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    p.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  Text(
                    ago(last.time, DateTime.now(), l),
                    style: const TextStyle(color: Tokens.onPhotoMuted, fontSize: 12.5),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
