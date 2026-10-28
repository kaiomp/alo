import 'package:flutter/foundation.dart';

/// Someone who posts or shares moments. [avatar] is an image address the
/// [Avatar] widget loads through ChatService.thumbnail.
class Person {
  const Person({required this.id, required this.name, required this.handle, this.avatar, this.business});
  final String id;
  final String name;

  /// Fediverse-style address without the leading "@", e.g. `bia@alo.app`.
  final String handle;
  final Uri? avatar;

  /// A business profile's line ("Café · Boa Vista, Recife"); null for people.
  final String? business;

  /// "@ju.ferreira".
  String get at => '@${handle.split('@').first}';
}

/// Why a post is in "Para você". Every recommendation says why: Alô
/// ranks, but never in secret.
enum ReasonKind { follows, popular, near, topic, community }

class Reason {
  const Reason(this.kind, this.value);
  final ReasonKind kind;

  /// The handle, place, topic or community feed name.
  final String value;
}

/// One post in the feed: text, a photo, or a short vertical video (reel).
class Post {
  const Post({
    required this.id,
    required this.author,
    required this.time,
    this.text = '',
    this.image,
    this.imageRatio = 4 / 3,
    this.likes = 0,
    this.liked = false,
    this.replies = 0,
    this.reposts = 0,
    this.reposted = false,
    this.repostedBy,
    this.video,
    this.reason,
    this.topic,
    this.coAuthor,
    this.paidPartner,
    this.sponsored = false,
  });

  final String id;
  final Person author;
  final DateTime time;
  final String text;
  final Uri? image;

  /// Width / height of [image].
  final double imageRatio;
  final int likes;
  final bool liked;
  final int replies;
  final int reposts;
  final bool reposted;

  /// Someone I follow shared it; it shows at the time they did.
  final Person? repostedBy;

  /// A reel: short, vertical, muted until opened; [image] is its poster.
  final Uri? video;

  /// Why it is recommended; null in "Seguindo".
  final Reason? reason;

  /// "comida de rua": what "Mostrar mais/menos disso" and topic switches act on.
  final String? topic;

  /// A collab post with two authors.
  final Person? coAuthor;

  /// "Parceria paga com @marca": the creator was paid by this brand.
  final Person? paidPartner;

  /// An ad, always labelled "Patrocinado".
  final bool sponsored;

  bool get isReel => video != null;

  Post copyWith({int? likes, bool? liked, int? replies, int? reposts, bool? reposted, Reason? reason, String? topic}) =>
      Post(
        id: id,
        author: author,
        time: time,
        text: text,
        image: image,
        imageRatio: imageRatio,
        likes: likes ?? this.likes,
        liked: liked ?? this.liked,
        replies: replies ?? this.replies,
        reposts: reposts ?? this.reposts,
        reposted: reposted ?? this.reposted,
        repostedBy: repostedBy,
        video: video,
        reason: reason ?? this.reason,
        topic: topic ?? this.topic,
        coAuthor: coAuthor,
        paidPartner: paidPartner,
        sponsored: sponsored,
      );
}

/// One full-screen photo in someone's Momentos.
class Moment {
  const Moment({required this.id, required this.image, required this.time, this.caption = ''});
  final String id;
  final Uri image;
  final DateTime time;
  final String caption;
}

/// Everyone's moments of the last 24 hours, oldest first.
class MomentGroup {
  const MomentGroup({required this.person, required this.moments, this.seen = false});
  final Person person;
  final List<Moment> moments;
  final bool seen;

  MomentGroup seenNow() => MomentGroup(person: person, moments: moments, seen: true);
}

class SocialProfile {
  const SocialProfile({
    required this.person,
    required this.bio,
    required this.followers,
    required this.following,
    required this.posts,
  });
  final Person person;
  final String bio;
  final int followers;
  final int following;
  final int posts;
}

/// One way to build "Para você". Community feeds are made and shared by
/// people, with open rules.
class FeedChoice {
  const FeedChoice({required this.id, required this.name, required this.about, this.by, this.users});
  final String id;
  final String name;
  final String about;

  /// The community feed's author handle ("coletivo.mangue"); null for Alô's own.
  final String? by;
  final int? users;
}

/// A finished export of everything the user owns.
class DataExport {
  const DataExport({required this.fileName, required this.bytes});
  final String fileName;
  final int bytes;
}

/// The social tabs (Momentos, the feed, Perfil). The home screen shows them
/// only when [Deps.social] holds one. Limit: only the demo implements it
/// today; the real one (Matrix rooms for moments, ActivityPub for posts and
/// followers) replaces it without touching the screens.
abstract interface class SocialService {
  /// "Seguindo": posts of the people I follow and mine, newest first.
  ValueListenable<List<Post>> get feed;

  /// "Para você": recommended by the chosen [algorithm], each post with its
  /// [Post.reason]; at most one ad in any ten items.
  ValueListenable<List<Post>> get forYou;

  List<FeedChoice> get algorithms;
  ValueListenable<String> get algorithm;
  void chooseAlgorithm(String id);

  /// Topics I can switch off; [hiddenTopics] never show in "Para você".
  List<String> get topics;
  ValueListenable<Set<String>> get hiddenTopics;
  void setTopic(String topic, bool on);
  void moreLike(String postId);
  void lessLike(String postId);

  /// Takes back [lessLike] ("Desfazer").
  void undoLess(String postId);

  /// Bio and counts for anyone's profile page.
  SocialProfile profileOf(Person person);

  /// Contacts with moments; unseen first, then seen, each newest first.
  ValueListenable<List<MomentGroup>> get moments;

  /// My own moments (may be empty).
  List<Moment> get myMoments;
  SocialProfile get me;

  List<Post> postsBy(String personId);
  List<Post> repliesTo(String postId);

  Future<void> refresh();
  void toggleLike(String postId);
  void toggleRepost(String postId);
  Future<void> publish(String text, {Uri? image});
  Future<void> reply(String postId, String text);

  void markSeen(String personId);

  /// Goes into the 1:1 chat with the moment's author, end-to-end encrypted.
  Future<void> replyToMoment(Person to, Moment moment, String text);

  /// Builds the export; [progress] runs from 0 to 1.
  Future<DataExport> exportAll({required ValueChanged<double> progress});

  /// Moves my account to [address] (`name@server`) and tells my followers.
  /// [progress] counts the followers told so far.
  Future<void> moveTo(String address, {required ValueChanged<int> progress});
}
