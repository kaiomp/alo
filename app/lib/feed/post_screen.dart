import 'package:flutter/material.dart';

import '../common/avatar.dart';
import '../common/deps.dart';
import '../l10n/app_localizations.dart';
import '../services/social_service.dart';
import 'feed_view.dart';
import 'post_card.dart';

/// One post with its replies, oldest first, and a reply box.
class PostScreen extends StatefulWidget {
  const PostScreen({super.key, required this.postId});
  final String postId;

  @override
  State<PostScreen> createState() => _PostScreenState();
}

class _PostScreenState extends State<PostScreen> {
  final _reply = TextEditingController();

  @override
  void dispose() {
    _reply.dispose();
    super.dispose();
  }

  Future<void> _send(SocialService social) async {
    final text = _reply.text.trim();
    if (text.isEmpty) return;
    _reply.clear();
    FocusScope.of(context).unfocus();
    await social.reply(widget.postId, text);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final social = Deps.of(context).social!;
    final scheme = Theme.of(context).colorScheme;
    return ValueListenableBuilder<List<Post>>(
      valueListenable: social.feed,
      builder: (context, posts, _) {
        bool mine(Post p) => p.id == widget.postId;
        final post =
            posts.where(mine).firstOrNull ??
            social.forYou.value.where(mine).firstOrNull ??
            social.postsBy(social.me.person.id).where(mine).firstOrNull;
        if (post == null) return const Scaffold();
        final replies = social.repliesTo(post.id);
        return Scaffold(
          appBar: AppBar(title: Text(post.author.name)),
          body: Column(
            children: [
              Expanded(
                child: ListView(
                  key: const Key('post_page'),
                  children: [
                    PostCard(
                      post: post,
                      large: true,
                      onLike: () => social.toggleLike(post.id),
                      onRepost: () => repost(context, social, post),
                      onShare: () => sharePost(context, post),
                    ),
                    const Divider(),
                    if (replies.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                        child: Text(
                          l.replies,
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: scheme.onSurfaceVariant),
                        ),
                      ),
                    for (final r in replies)
                      PostCard(
                        key: Key('post_${r.id}'),
                        post: r,
                        onLike: () {},
                        onRepost: () {},
                        onShare: () => sharePost(context, r),
                      ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
              _ReplyBar(
                controller: _reply,
                hint: l.replyTo(post.author.name.split(' ').first),
                onSend: () => _send(social),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ReplyBar extends StatelessWidget {
  const _ReplyBar({required this.controller, required this.hint, required this.onSend});
  final TextEditingController controller;
  final String hint;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final me = Deps.of(context).social!.me.person;
    return Material(
      color: scheme.surface,
      child: SafeArea(
        top: false,
        child: Container(
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: scheme.outlineVariant, width: 0.5)),
          ),
          padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
          child: Row(
            children: [
              Avatar(name: me.name, seed: me.id, mxc: me.avatar, radius: 16),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  key: const Key('reply_field'),
                  controller: controller,
                  minLines: 1,
                  maxLines: 4,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    hintText: hint,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
                  ),
                  onSubmitted: (_) => onSend(),
                ),
              ),
              ValueListenableBuilder(
                valueListenable: controller,
                builder: (context, v, _) => IconButton(
                  key: const Key('reply_send'),
                  tooltip: L10n.of(context).send,
                  onPressed: v.text.trim().isEmpty ? null : onSend,
                  color: scheme.primary,
                  icon: const Icon(Icons.send_rounded),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
