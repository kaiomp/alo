import 'package:alo/common/time_format.dart';
import 'package:alo/l10n/app_localizations.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  test('day labels in pt-BR', () async {
    await initializeDateFormatting('pt');
    final l = await L10n.delegate.load(const Locale('pt'));
    final now = DateTime(2026, 10, 24, 12);
    expect(dayLabel(DateTime(2026, 10, 24, 1), now, l), 'Hoje');
    expect(dayLabel(DateTime(2026, 10, 23, 23), now, l), 'Ontem');
    expect(dayLabel(DateTime(2026, 10, 20), now, l), 'Terça-feira');
    expect(dayLabel(DateTime(2026, 9, 1), now, l), '01/09/2026');
    expect(listTime(DateTime(2026, 10, 24, 9, 5), now, l), '09:05');
  });

  test('sameDay ignores the clock', () {
    expect(sameDay(DateTime(2026, 10, 24, 0, 1), DateTime(2026, 10, 24, 23, 59)), isTrue);
    expect(sameDay(DateTime(2026, 10, 24, 23, 59), DateTime(2026, 10, 25)), isFalse);
  });

  test('UTC timestamps use the local day and clock', () async {
    await initializeDateFormatting('pt');
    final l = await L10n.delegate.load(const Locale('pt'));
    final local = DateTime(2026, 10, 23, 23, 30);
    final utc = local.toUtc();
    final now = DateTime(2026, 10, 23, 23, 45).toUtc();
    expect(sameDay(utc, local), isTrue);
    expect(dayLabel(utc, now, l), 'Hoje');
    expect(listTime(utc, now, l), '23:30');
    expect(clock(utc, l), '23:30');
    expect(dayLabel(utc, DateTime(2026, 10, 24, 8), l), 'Ontem');
  });
}
