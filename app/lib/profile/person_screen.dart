import 'package:flutter/material.dart';

import '../common/avatar.dart';
import '../common/deps.dart';
import '../common/net_image.dart';
import '../common/theme.dart';
import '../common/time_format.dart';
import '../l10n/app_localizations.dart';
import '../services/social_service.dart';

/// Someone else's profile: a person, a creator or a local business.
class PersonScreen extends StatelessWidget {
  const PersonScreen({super.key, required this.person});
  final Person person;

  static void open(BuildContext context, Person person) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => PersonScreen(person: person)));

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final social = Deps.of(context).social!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final colors = ChatColors.of(context);
    final profile = social.profileOf(person);
    final posts = social.postsBy(person.id).where((p) => p.image != null).toList();
    final business = person.business;
    Widget stat(int n, String label) => Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: count(n, l),
            style: TextStyle(fontWeight: FontWeight.w700, color: scheme.onSurface),
          ),
          TextSpan(text: ' $label'),
        ],
      ),
      style: TextStyle(fontSize: 14, color: scheme.onSurfaceVariant, fontFeatures: tabularFigures),
    );
    return Scaffold(
      appBar: AppBar(title: Text(person.at)),
      body: CustomScrollView(
        key: const Key('person_page'),
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(person.name, style: theme.textTheme.headlineSmall),
                            if (business != null) ...[
                              const SizedBox(height: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(color: colors.tint, borderRadius: BorderRadius.circular(8)),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.storefront_outlined, size: 14, color: colors.onTint),
                                    const SizedBox(width: 5),
                                    Text(
                                      l.businessProfile,
                                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: colors.onTint),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(business, style: TextStyle(fontSize: 13.5, color: scheme.onSurfaceVariant)),
                            ],
                          ],
                        ),
                      ),
                      Avatar(name: person.name, seed: person.id, mxc: person.avatar, radius: 36),
                    ],
                  ),
                  if (profile.bio.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      profile.bio,
                      style: TextStyle(fontSize: 15, height: 21 / 15, color: scheme.onSurface),
                    ),
                  ],
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 14,
                    children: [stat(profile.followers, l.followers), stat(profile.following, l.following)],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton(onPressed: () {}, child: Text(l.follow)),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton(onPressed: () {}, child: Text(l.message)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(2, 0, 2, 48),
            sliver: SliverGrid.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 2,
                crossAxisSpacing: 2,
              ),
              itemCount: posts.length,
              itemBuilder: (context, i) => Stack(
                fit: StackFit.expand,
                children: [
                  NetImage(posts[i].image!),
                  if (posts[i].isReel)
                    const Positioned(
                      top: 6,
                      right: 6,
                      child: Icon(Icons.slow_motion_video_rounded, color: Colors.white, size: 18),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
