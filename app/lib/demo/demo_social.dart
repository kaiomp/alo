import 'dart:async';

import 'package:flutter/foundation.dart';

import '../services/models.dart';
import '../feed/ads.dart';
import '../services/social_service.dart';
import 'demo_chat.dart';
import 'demo_data.dart' as d;

/// Momentos, the feed and Perfil on fixed data. Likes, posts and replies stay
/// in memory until the page reloads.
class DemoSocialService implements SocialService {
  DemoSocialService(DateTime now, this._chat)
    : _feed = ValueNotifier(d.demoFeed(now)),
      _moments = ValueNotifier(d.demoMoments(now)),
      _mine = d.demoMyPosts(now),
      _replies = d.demoReplies(now),
      _ads = d.demoAds(now) {
    _pool = d.demoForYou(now, _feed.value);
    _recompute();
  }

  final DemoChatService _chat;
  final ValueNotifier<List<Post>> _feed;
  final ValueNotifier<List<MomentGroup>> _moments;
  final List<Post> _mine;
  final Map<String, List<Post>> _replies;
  List<Post> _ads;
  late List<Post> _pool;
  final _forYou = ValueNotifier<List<Post>>(const []);
  final _algorithm = ValueNotifier('padrao');
  final _hiddenTopics = ValueNotifier<Set<String>>(const {});
  final _hiddenPosts = <String>{};

  /// "Mostrar mais/menos disso" per topic; higher comes first.
  final _weight = <String, int>{};
  var _n = 0;

  @override
  ValueListenable<List<Post>> get forYou => _forYou;
  @override
  List<FeedChoice> get algorithms => d.demoAlgorithms;
  @override
  ValueListenable<String> get algorithm => _algorithm;
  @override
  List<String> get topics => d.topicsAll;
  @override
  ValueListenable<Set<String>> get hiddenTopics => _hiddenTopics;

  @override
  void chooseAlgorithm(String id) {
    _algorithm.value = id;
    _recompute();
  }

  @override
  void setTopic(String topic, bool on) {
    _hiddenTopics.value = on ? ({..._hiddenTopics.value}..remove(topic)) : {..._hiddenTopics.value, topic};
    _recompute();
  }

  void _weigh(String postId, int by) {
    final topic = [..._pool, ..._feed.value].where((p) => p.id == postId).firstOrNull?.topic;
    if (topic != null) _weight[topic] = (_weight[topic] ?? 0) + by;
  }

  @override
  void moreLike(String postId) {
    _weigh(postId, 1);
    _recompute();
  }

  @override
  void lessLike(String postId) {
    _weigh(postId, -1);
    _hiddenPosts.add(postId);
    _recompute();
  }

  /// "Para você" from the chosen feed, the topic switches and the
  /// more/less answers, with the ad placed by [mixAds].
  void _recompute() {
    const community = {
      'arte-pe': {'arte', 'música e capoeira'},
      'varzea': {'futebol de várzea'},
    };
    final id = _algorithm.value;
    final keep = community[id];
    final name = d.demoAlgorithms.firstWhere((a) => a.id == id).name;
    final List<Post> organic = switch (id) {
      'seguindo' => _feed.value,
      'perto' => _pool.where((p) => d.nearIds.contains(p.id)).toList(),
      _ when keep != null => [
        for (final p in {
          for (final p in [..._pool, ..._feed.value]) p.id: p,
        }.values)
          if (keep.contains(p.topic)) p.copyWith(reason: Reason(ReasonKind.community, name)),
      ],
      _ => _pool,
    };
    final visible = [
      for (final p in organic)
        if (!_hiddenPosts.contains(p.id) && !_hiddenTopics.value.contains(p.topic)) p,
    ];
    // Stable: equal weights keep the feed's own order.
    final ranked = [for (final (i, p) in visible.indexed) (i, p)]
      ..sort((a, b) {
        final w = (_weight[b.$2.topic] ?? 0).compareTo(_weight[a.$2.topic] ?? 0);
        return w != 0 ? w : a.$1.compareTo(b.$1);
      });
    final posts = [for (final (_, p) in ranked) p];
    _forYou.value = id == 'seguindo'
        ? posts
        : mixAds(posts, [
            for (final a in _ads)
              if (!_hiddenTopics.value.contains(a.topic)) a,
          ]);
  }

  @override
  SocialProfile profileOf(Person person) {
    if (person.id == d.me.id) return me;
    return SocialProfile(
      person: person,
      bio: d.demoBios[person.id] ?? '',
      followers: 800 + person.name.length * 137,
      following: 120 + person.name.length * 11,
      posts: postsBy(person.id).length + 40,
    );
  }

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
  List<Post> postsBy(String personId) => personId == d.me.id
      ? _mine
      : {
          for (final p in [..._feed.value, ..._pool, ..._ads])
            if (p.author.id == personId || p.coAuthor?.id == personId) p.id: p,
        }.values.toList();

  @override
  List<Post> repliesTo(String postId) => _replies[postId] ?? const [];

  /// Nothing new arrives in the demo; the spinner shows for a moment.
  @override
  Future<void> refresh() => Future.delayed(const Duration(milliseconds: 900));

  /// Applies [f] to the post wherever it shows (both feeds, my profile).
  void _change(String postId, Post Function(Post) f) {
    List<Post> apply(List<Post> list) => [for (final p in list) p.id == postId ? f(p) : p];
    _pool = apply(_pool);
    _ads = apply(_ads);
    _feed.value = apply(_feed.value);
    final i = _mine.indexWhere((p) => p.id == postId);
    if (i >= 0) _mine[i] = f(_mine[i]);
    _recompute();
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
