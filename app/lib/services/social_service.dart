import 'package:flutter/foundation.dart';

/// Someone who posts or shares moments. [avatar] is an image address the
/// [Avatar] widget loads through ChatService.thumbnail.
class Person {
  const Person({required this.id, required this.name, required this.handle, this.avatar});
  final String id;
  final String name;

  /// Fediverse-style address without the leading "@", e.g. `bia@chama.app`.
  final String handle;
  final Uri? avatar;
}

/// One post in Praça: short text, maybe a photo.
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

  Post copyWith({int? likes, bool? liked, int? replies, int? reposts, bool? reposted}) => Post(
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

/// A finished export of everything the user owns.
class DataExport {
  const DataExport({required this.fileName, required this.bytes});
  final String fileName;
  final int bytes;
}

/// The social tabs (Momentos, Praça, Perfil). The home screen shows them
/// only when [Deps.social] holds one. Limit: only the demo implements it
/// today; the real one (Matrix rooms for moments, ActivityPub for posts and
/// followers) replaces it without touching the screens.
abstract interface class SocialService {
  /// Posts of the people I follow and mine, newest first. Never ranked.
  ValueListenable<List<Post>> get feed;

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
