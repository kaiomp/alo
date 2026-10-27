import '../services/social_service.dart';

/// Puts [ads] among [organic] posts: the first after [firstAt] organic
/// ones, then at least [gap] organic posts between two ads, so any ten
/// items in a row hold at most one ad. Ads left over are dropped.
List<Post> mixAds(List<Post> organic, List<Post> ads, {int firstAt = 4, int gap = 9}) {
  final out = <Post>[];
  var sinceAd = gap - firstAt; // the first ad may come after [firstAt] posts
  var next = 0;
  for (final p in organic) {
    if (sinceAd >= gap && next < ads.length) {
      out.add(ads[next++]);
      sinceAd = 0;
    }
    out.add(p);
    sinceAd++;
  }
  return out;
}
