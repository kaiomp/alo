import 'package:intl/intl.dart';

import '../l10n/app_localizations.dart';

// Calendar days compared in UTC so a daylight-saving change cannot shift them.
int _daysBetween(DateTime a, DateTime b) =>
    DateTime.utc(b.year, b.month, b.day).difference(DateTime.utc(a.year, a.month, a.day)).inDays;

bool sameDay(DateTime a, DateTime b) => _daysBetween(a, b) == 0;

/// Day divider text: "Hoje", "Ontem", the weekday for the last week, else the date.
String dayLabel(DateTime t, DateTime now, L10n l) {
  final diff = _daysBetween(t, now);
  if (diff == 0) return l.today;
  if (diff == 1) return l.yesterday;
  if (diff > 1 && diff < 7) {
    final w = DateFormat.EEEE(l.localeName).format(t);
    return w[0].toUpperCase() + w.substring(1);
  }
  return DateFormat.yMd(l.localeName).format(t);
}

/// "14:03"
String clock(DateTime t, L10n l) => DateFormat.Hm(l.localeName).format(t);

/// Chat list time: the clock for today, else like [dayLabel].
String listTime(DateTime t, DateTime now, L10n l) => sameDay(t, now) ? clock(t, l) : dayLabel(t, now, l);
