import 'package:chama/common/widgets.dart';
import 'package:chama/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<bool?> tapWith(WidgetTester tester, Future<void> Function() action) async {
    bool? result;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('pt'),
        supportedLocales: L10n.supportedLocales,
        localizationsDelegates: L10n.localizationsDelegates,
        home: Scaffold(
          body: Builder(
            builder: (context) =>
                TextButton(onPressed: () async => result = await runOrSnack(context, action), child: const Text('go')),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pump();
    await tester.pump();
    return result;
  }

  testWidgets('a failed action shows the error instead of vanishing', (tester) async {
    expect(await tapWith(tester, () async => throw Exception('M_FORBIDDEN')), isFalse);
    expect(find.text('Algo deu errado. Tente de novo.'), findsOneWidget);
  });

  testWidgets('a successful action shows nothing', (tester) async {
    expect(await tapWith(tester, () async {}), isTrue);
    expect(find.byType(SnackBar), findsNothing);
  });
}
