import 'package:alo/common/theme.dart';
import 'package:alo/group/new_group_screen.dart';
import 'package:alo/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('the remove mark on a new member is a named 48 px button', (tester) async {
    final handle = tester.ensureSemantics();
    var removed = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: aloTheme(Brightness.light),
        locale: const Locale('pt'),
        supportedLocales: L10n.supportedLocales,
        localizationsDelegates: L10n.localizationsDelegates,
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: MemberChip(seed: '@u:alo.test', digits: '5511987654321', onRemove: () => removed++),
          ),
        ),
      ),
    );
    final mark = find.byKey(const Key('remove_member'));
    expect(tester.getSize(mark), const Size(48, 48));
    expect(
      tester.getSemantics(mark),
      isSemantics(label: 'Remover +55 11 98765-4321', isButton: true, hasTapAction: true),
    );
    // A tap near the mark's corner, well off the 18 px circle, still counts.
    await tester.tapAt(tester.getTopLeft(mark) + const Offset(4, 4));
    await tester.tapAt(tester.getBottomRight(mark) - const Offset(4, 4));
    expect(removed, 2);
    handle.dispose();
  });
}
