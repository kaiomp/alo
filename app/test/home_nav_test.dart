import 'package:alo/chat_list/home_screen.dart';
import 'package:alo/common/theme.dart';
import 'package:alo/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('tab labels stay on one line on a 360 px phone with large text', (tester) async {
    await tester.runAsync(() async {
      final inter = FontLoader('Inter');
      for (final w in [400, 500, 600]) {
        inter.addFont(rootBundle.load('assets/fonts/Inter-$w.ttf'));
      }
      await inter.load();
    });
    tester.view
      ..physicalSize = const Size(360, 800)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    late List<(IconData, String)> tabs;
    // Each tab selected in turn: the selected label is bold and wider.
    for (var selected = 0; selected < 4; selected++) {
      await tester.pumpWidget(
        MaterialApp(
          theme: aloTheme(Brightness.light),
          locale: const Locale('pt'),
          supportedLocales: L10n.supportedLocales,
          localizationsDelegates: L10n.localizationsDelegates,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(1.3)),
            child: child!,
          ),
          home: Builder(
            builder: (context) {
              final l = L10n.of(context);
              tabs = [
                (Icons.chat_outlined, l.tabChats),
                (Icons.update, l.tabUpdates),
                (Icons.groups_outlined, l.tabCommunities),
                (Icons.call_outlined, l.tabCalls),
              ];
              return Scaffold(
                bottomNavigationBar: HomeNavBar(tabs: tabs, selected: selected, onSelected: (_) {}),
              );
            },
          ),
        ),
      );
      for (final (_, label) in tabs) {
        final text = tester.renderObject<RenderParagraph>(find.text(label));
        final lines = text
            .getBoxesForSelection(TextSelection(baseOffset: 0, extentOffset: label.length))
            .map((b) => b.top)
            .toSet();
        expect(lines, hasLength(1), reason: label);
      }
    }
  });
}
