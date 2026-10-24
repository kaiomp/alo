import 'package:chama/common/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

double contrast(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  return (la > lb ? la + 0.05 : lb + 0.05) / (la > lb ? lb + 0.05 : la + 0.05);
}

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('filled button text meets WCAG AA in $brightness mode', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: chamaTheme(brightness),
          home: Scaffold(
            body: FilledButton(onPressed: () {}, child: const Text('Avançar')),
          ),
        ),
      );
      final fill = tester
          .widget<Material>(find.descendant(of: find.byType(FilledButton), matching: find.byType(Material)))
          .color!;
      final text = DefaultTextStyle.of(tester.element(find.text('Avançar'))).style.color!;
      expect(contrast(fill, text), greaterThanOrEqualTo(4.5));
    });
  }

  for (final (name, c, surface) in [
    ('light', ChatColors.light, chamaTheme(Brightness.light).colorScheme.surface),
    ('dark', ChatColors.dark, chamaTheme(Brightness.dark).colorScheme.surface),
  ]) {
    test('chat colours meet WCAG AA in $name mode', () {
      for (final bubble in [c.mine, c.other]) {
        expect(contrast(c.bubbleText, bubble), greaterThanOrEqualTo(4.5));
        expect(contrast(c.meta, bubble), greaterThanOrEqualTo(4.5)); // 11 px time
        expect(contrast(c.readTick, bubble), greaterThanOrEqualTo(3)); // icon
      }
      expect(contrast(c.accent, surface), greaterThanOrEqualTo(4.5)); // unread time, headers
      expect(contrast(c.onTint, c.tint), greaterThanOrEqualTo(4.5)); // selected chip
      expect(contrast(c.onNotice, c.notice), greaterThanOrEqualTo(4.5));
    });
  }

  test('white on orange fills: AA for text, 3:1 for icons', () {
    expect(contrast(Colors.white, Tokens.flameDeep), greaterThanOrEqualTo(4.5));
    expect(contrast(Colors.white, Tokens.flameText), greaterThanOrEqualTo(4.5)); // unread badge
    expect(contrast(Colors.white, Tokens.flame), greaterThanOrEqualTo(3));
  });

  test('light mode keeps the brand orange as primary', () {
    expect(chamaTheme(Brightness.light).colorScheme.primary, Tokens.flame);
  });
}
