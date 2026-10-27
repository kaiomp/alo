import 'dart:async';

import 'package:flutter/foundation.dart';

import '../services/wellbeing_service.dart';

/// Starts at 24 minutes today and counts one minute per real minute.
class DemoWellbeing implements WellbeingService {
  /// [ticking] off for scenes, so only the script moves time.
  DemoWellbeing({bool ticking = true}) {
    dailyLimit.addListener(_check);
    if (ticking) Timer.periodic(const Duration(minutes: 1), (_) => elapse(1));
  }

  final _today = ValueNotifier(24);
  final _week = ValueNotifier(const [38, 52, 31, 44, 27, 61, 24]);
  final _due = ValueNotifier(false);
  int? _snoozedUntil;

  @override
  ValueListenable<int> get todayMinutes => _today;
  @override
  ValueListenable<List<int>> get lastWeek => _week;
  @override
  ValueListenable<bool> get pauseDue => _due;

  @override
  final dailyLimit = ValueNotifier<int?>(45);
  @override
  final restMode = ValueNotifier(false);
  @override
  final digest = ValueNotifier(false);
  @override
  final hideLikes = ValueNotifier(false);
  @override
  final hideSeenBy = ValueNotifier(false);
  @override
  final grey = ValueNotifier(false);
  @override
  final autoplay = ValueNotifier(true);

  @override
  ({Duration from, Duration to}) get restHours => (from: const Duration(hours: 22), to: const Duration(hours: 7));

  @override
  List<Duration> get digestTimes => const [Duration(hours: 12), Duration(hours: 19)];

  /// Scenes move the clock on.
  void elapse(int minutes) {
    _today.value += minutes;
    _week.value = [..._week.value.take(6), _today.value];
    _check();
  }

  void _check() {
    final limit = dailyLimit.value;
    _due.value = limit != null && _today.value >= limit && _today.value >= (_snoozedUntil ?? 0);
  }

  @override
  void snooze() {
    _snoozedUntil = _today.value + 5;
    _check();
  }
}
