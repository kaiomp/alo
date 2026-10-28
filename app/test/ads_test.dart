import 'package:alo/feed/ads.dart';
import 'package:alo/services/social_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const who = Person(id: 'a', name: 'A', handle: 'a@x');
  Post post(String id, {bool ad = false}) => Post(id: id, author: who, time: DateTime(2026), sponsored: ad);

  test('the first ad comes after four posts, and never two in any ten items', () {
    final organic = [for (var i = 0; i < 40; i++) post('p$i')];
    final ads = [for (var i = 0; i < 10; i++) post('ad$i', ad: true)];
    final mixed = mixAds(organic, ads);
    expect(mixed.indexWhere((p) => p.sponsored), 4);
    for (var i = 0; i + 10 <= mixed.length; i++) {
      expect(mixed.sublist(i, i + 10).where((p) => p.sponsored).length, lessThanOrEqualTo(1), reason: 'at $i');
    }
    expect(mixed.where((p) => !p.sponsored).length, organic.length);
  });

  test('a short feed gets no ad before its fifth item', () {
    final mixed = mixAds([post('p0'), post('p1'), post('p2')], [post('ad', ad: true)]);
    expect(mixed.any((p) => p.sponsored), isFalse);
  });
}
