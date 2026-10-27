import 'dart:async';

import 'package:flutter/foundation.dart';

import '../services/models.dart';
import '../services/social_service.dart';
import 'demo_chat.dart';
import 'demo_data.dart' as d;

/// Momentos, Praça and Perfil on fixed data. Likes, posts and replies stay
/// in memory until the page reloads.
class DemoSocialService implements SocialService {
  DemoSocialService(DateTime now, this._chat)
    : _feed = ValueNotifier(d.demoFeed(now)),
      _moments = ValueNotifier(d.demoMoments(now)),
      _mine = d.demoMyPosts(now),
      _replies = d.demoReplies(now);

  final DemoChatService _chat;
  final ValueNotifier<List<Post>> _feed;
  final ValueNotifier<List<MomentGroup>> _moments;
  final List<Post> _mine;
  final Map<String, List<Post>> _replies;
  var _n = 0;

  @override
  ValueListenable<List<Post>> get feed => _feed;
  @override
  ValueListenable<List<MomentGroup>> get moments => _moments;
  @override
  List<Moment> get myMoments => const [];

  @override
  SocialProfile get me => SocialProfile(
    person: d.me,
    bio: 'Designer em Recife 🌴 Identidade visual, tipografia e muito café. Açaí sem granola, por favor.',
    followers: 1204,
    following: 386,
    posts: 248,
  );

  @override
  List<Post> postsBy(String personId) =>
      personId == d.me.id ? _mine : _feed.value.where((p) => p.author.id == personId).toList();

  @override
  List<Post> repliesTo(String postId) => _replies[postId] ?? const [];

  /// Nothing new arrives in the demo; the spinner shows for a moment.
  @override
  Future<void> refresh() => Future.delayed(const Duration(milliseconds: 900));

  void _change(String postId, Post Function(Post) f) {
    _feed.value = [for (final p in _feed.value) p.id == postId ? f(p) : p];
    final i = _mine.indexWhere((p) => p.id == postId);
    if (i >= 0) _mine[i] = f(_mine[i]);
  }

  @override
  void toggleLike(String postId) =>
      _change(postId, (p) => p.copyWith(liked: !p.liked, likes: p.likes + (p.liked ? -1 : 1)));

  @override
  void toggleRepost(String postId) =>
      _change(postId, (p) => p.copyWith(reposted: !p.reposted, reposts: p.reposts + (p.reposted ? -1 : 1)));

  @override
  Future<void> publish(String text, {Uri? image}) async {
    final post = Post(id: 'new${_n++}', author: d.me, time: DateTime.now(), text: text, image: image);
    _feed.value = [post, ..._feed.value];
    _mine.insert(0, post);
  }

  @override
  Future<void> reply(String postId, String text) async {
    final list = _replies[postId] = [...repliesTo(postId)];
    list.add(Post(id: 'reply${_n++}', author: d.me, time: DateTime.now(), text: text));
    _change(postId, (p) => p.copyWith(replies: p.replies + 1));
  }

  @override
  void markSeen(String personId) {
    final all = _moments.value;
    if (all.every((g) => g.person.id != personId || g.seen)) return;
    final updated = [for (final g in all) g.person.id == personId ? g.seenNow() : g];
    _moments.value = [...updated.where((g) => !g.seen), ...updated.where((g) => g.seen)];
  }

  @override
  Future<void> replyToMoment(Person to, Moment moment, String text) async {
    final chat = _chat.world.chats.where((c) => !c.isGroup && c.other.id == to.id).firstOrNull;
    if (chat != null) _chat.sendMine(chat.id, MessageKind.text, body: text);
  }

  @override
  Future<DataExport> exportAll({required ValueChanged<double> progress}) async {
    for (var i = 1; i <= 30; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      progress(i / 30);
    }
    final day = DateTime.now().toIso8601String().substring(0, 10);
    return DataExport(fileName: 'chama-bia-santana-$day.zip', bytes: 1288490189);
  }

  @override
  Future<void> moveTo(String address, {required ValueChanged<int> progress}) async {
    const steps = 40;
    for (var i = 1; i <= steps; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      progress(me.followers * i ~/ steps);
    }
  }
}
