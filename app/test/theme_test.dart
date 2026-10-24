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

  test('light mode keeps the brand orange as primary', () {
    expect(chamaTheme(Brightness.light).colorScheme.primary, Tokens.flame);
  });
}
