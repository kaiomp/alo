import 'package:flutter/material.dart';

import '../common/avatar.dart';
import '../common/deps.dart';
import '../common/net_image.dart';
import '../common/theme.dart';
import '../common/time_format.dart';
import '../feed/post_screen.dart';
import '../l10n/app_localizations.dart';
import '../services/social_service.dart';
import 'your_data.dart';

/// Perfil: my name, address, bio and counts, the "Seus dados são seus"
/// card, and my posts as a photo grid.
class MeView extends StatelessWidget {
  const MeView({super.key});

  @override
  Widget build(BuildContext context) {
    final social = Deps.of(context).social!;
    return ValueListenableBuilder(
      valueListenable: social.feed,
      builder: (context, _, _) {
        final profile = social.me;
        final posts = social.postsBy(profile.person.id);
        return CustomScrollView(
          key: const Key('profile'),
          slivers: [
            SliverToBoxAdapter(child: _Header(profile: profile)),
            const SliverToBoxAdapter(child: YourDataCard()),
            SliverToBoxAdapter(child: _GridTitle(count: profile.posts)),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(2, 0, 2, 96),
              sliver: SliverGrid.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisSpacing: 2,
                  crossAxisSpacing: 2,
                ),
                itemCount: posts.length,
                itemBuilder: (context, i) => _Tile(post: posts[i]),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.profile});
  final SocialProfile profile;

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final scheme = Theme.of(context).colorScheme;
    final colors = ChatColors.of(context);
    final p = profile.person;
    final [user, server] = p.handle.split('@');
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p.name, style: Theme.of(context).textTheme.headlineSmall),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Text('@$user', style: TextStyle(fontSize: 15, color: scheme.onSurface)),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(color: colors.tint, borderRadius: BorderRadius.circular(10)),
                          child: Text(server, style: TextStyle(fontSize: 12.5, color: colors.onTint)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Avatar(name: p.name, seed: p.id, mxc: p.avatar, radius: 38),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            profile.bio,
            style: TextStyle(fontSize: 15, height: 21 / 15, color: scheme.onSurface),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 14,
            children: [
              stat(profile.followers, l.followers),
              stat(profile.following, l.following),
              stat(profile.posts, l.postsCount),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(child: _Outlined(label: l.editProfile)),
              const SizedBox(width: 8),
              Expanded(child: _Outlined(label: l.shareProfile)),
            ],
          ),
        ],
      ),
    );
  }
}

class _Outlined extends StatelessWidget {
  const _Outlined({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return OutlinedButton(
      style: OutlinedButton.styleFrom(
        foregroundColor: scheme.onSurface,
        side: BorderSide(color: scheme.outlineVariant),
        minimumSize: const Size(0, 40),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
      onPressed: () => ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(L10n.of(context).comingSoon))),
      child: Text(label),
    );
  }
}

class _GridTitle extends StatelessWidget {
  const _GridTitle({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: scheme.onSurface, width: 1.5)),
      ),
      padding: const EdgeInsets.symmetric(vertical: 12),
      alignment: Alignment.center,
      child: Icon(Icons.grid_on_rounded, size: 22, color: scheme.onSurface),
    );
  }
}

/// A photo post as a square, or the first words of a text post.
class _Tile extends StatelessWidget {
  const _Tile({required this.post});
  final Post post;

  @override
  Widget build(BuildContext context) {
    final image = post.image;
    final colors = ChatColors.of(context);
    return GestureDetector(
      onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => PostScreen(postId: post.id))),
      child: image != null
          ? NetImage(image)
          : Container(
              color: colors.tint,
              padding: const EdgeInsets.all(10),
              child: Text(
                post.text,
                maxLines: 5,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12.5, color: colors.onTint),
              ),
            ),
    );
  }
}
