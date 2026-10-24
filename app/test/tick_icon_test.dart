import 'package:chama/chat/tick_icon.dart';
import 'package:chama/common/theme.dart';
import 'package:chama/l10n/app_localizations.dart';
import 'package:chama/services/ticks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('each tick has its icon; only read is blue', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: chamaTheme(Brightness.light),
        localizationsDelegates: L10n.localizationsDelegates,
        home: Row(children: [for (final t in Tick.values) TickIcon(t)]),
      ),
    );
    Icon icon(Tick t) => tester.widget<Icon>(find.byKey(Key('tick_${t.name}')));
    expect(icon(Tick.pending).icon, Icons.schedule);
    expect(icon(Tick.failed).icon, Icons.error_outline);
    expect(icon(Tick.sent).icon, Icons.done);
    expect(icon(Tick.delivered).icon, Icons.done_all);
    expect(icon(Tick.read).icon, Icons.done_all);
    expect(icon(Tick.read).color, ChatColors.light.readTick);
    expect(icon(Tick.delivered).color, isNot(ChatColors.light.readTick));
  });

  testWidgets('screen readers hear the tick in the app language', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: chamaTheme(Brightness.light),
        locale: const Locale('pt'),
        supportedLocales: L10n.supportedLocales,
        localizationsDelegates: L10n.localizationsDelegates,
        home: Row(children: [for (final t in Tick.values) TickIcon(t)]),
      ),
    );
    String? label(Tick t) => tester.widget<Icon>(find.byKey(Key('tick_${t.name}'))).semanticLabel;
    expect(label(Tick.pending), 'Enviando');
    expect(label(Tick.sent), 'Enviada');
    expect(label(Tick.delivered), 'Entregue');
    expect(label(Tick.read), 'Lida');
    expect(label(Tick.failed), 'Não enviada');
  });
}
