import 'package:flutter/foundation.dart';

/// Time in the app and the calm settings. Chama earns nothing from
/// attention, so it can be honest about time: no streaks, no badges.
/// Limit: only the demo implements it today; the real one counts
/// foreground minutes on the device and never sends them anywhere.
abstract interface class WellbeingService {
  ValueListenable<int> get todayMinutes;

  /// Minutes per day, oldest first; the last one is today.
  ValueListenable<List<int>> get lastWeek;

  /// Null means no limit.
  ValueNotifier<int?> get dailyLimit;

  /// Quiet hours: notifications wait for the morning, favourites excepted.
  ValueNotifier<bool> get restMode;
  ({Duration from, Duration to}) get restHours;

  /// Notifications batched at [digestTimes] (time of day).
  ValueNotifier<bool> get digest;
  List<Duration> get digestTimes;

  ValueNotifier<bool> get hideLikes;
  ValueNotifier<bool> get hideSeenBy;
  ValueNotifier<bool> get grey;

  /// Reels in the feed play by themselves, muted, while on screen.
  ValueNotifier<bool> get autoplay;

  /// The daily limit is reached and the pause card should show.
  ValueListenable<bool> get pauseDue;

  /// "Mais 5 minutos".
  void snooze();
}
