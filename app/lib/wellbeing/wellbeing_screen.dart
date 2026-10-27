import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../common/deps.dart';
import '../common/theme.dart';
import '../common/widgets.dart';
import '../l10n/app_localizations.dart';
import '../services/wellbeing_service.dart';

String _hm(Duration d) => '${d.inHours.toString().padLeft(2, '0')}:${(d.inMinutes % 60).toString().padLeft(2, '0')}';

/// Bem-estar: today's time, the week, a daily limit, quiet hours and the
/// calm options. No streaks, no badges, no guilt.
class WellbeingScreen extends StatelessWidget {
  const WellbeingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final w = Deps.of(context).wellbeing!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    Widget toggle(String key, ValueNotifier<bool> value, String title, [String? body]) => ValueListenableBuilder(
      valueListenable: value,
      builder: (context, on, _) => SwitchListTile(
        key: Key(key),
        value: on,
        onChanged: (v) => value.value = v,
        title: Text(title),
        subtitle: body == null ? null : Text(body),
      ),
    );
    final rest = w.restHours;
    return Scaffold(
      appBar: AppBar(title: Text(l.wellbeing)),
      body: ListView(
        key: const Key('wellbeing_page'),
        padding: const EdgeInsets.only(bottom: 40),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: ValueListenableBuilder(
              valueListenable: w.todayMinutes,
              builder: (context, m, _) =>
                  Text(l.wellbeingToday(m), key: const Key('today_minutes'), style: theme.textTheme.headlineMedium),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
            child: Text(l.wellbeingIntro, style: TextStyle(fontSize: 14.5, color: scheme.onSurfaceVariant)),
          ),
          _Week(service: w),
          SectionHeader(l.dailyLimit),
          _Limit(service: w),
          SectionHeader(l.restMode),
          toggle('rest_mode', w.restMode, l.restMode, l.restModeBody(_hm(rest.from), _hm(rest.to))),
          toggle('digest', w.digest, l.digest, l.digestBody(w.digestTimes.map(_hm).join(' · '))),
          SectionHeader(l.calmOptions),
          toggle('hide_likes', w.hideLikes, l.hideLikes),
          toggle('hide_seen_by', w.hideSeenBy, l.hideSeenBy),
          toggle('grey_mode', w.grey, l.greyMode, l.greyModeBody),
        ],
      ),
    );
  }
}

/// Seven bars, today in full açaí, with the limit as a thin line.
class _Week extends StatelessWidget {
  const _Week({required this.service});
  final WellbeingService service;

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final scheme = Theme.of(context).colorScheme;
    final today = DateTime.now();
    return ListenableBuilder(
      listenable: Listenable.merge([service.lastWeek, service.dailyLimit]),
      builder: (context, _) {
        final days = service.lastWeek.value;
        final limit = service.dailyLimit.value;
        final top = math.max(days.fold(1, math.max), limit ?? 0) * 1.15;
        const height = 120.0;
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l.last7Days,
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: ChatColors.of(context).accent),
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: height + 34,
                child: Stack(
                  children: [
                    if (limit != null)
                      AnimatedPositioned(
                        duration: const Duration(milliseconds: 300),
                        left: 0,
                        right: 0,
                        top: 16 + height * (1 - limit / top),
                        child: Container(height: 1.5, color: scheme.onSurfaceVariant.withValues(alpha: 0.5)),
                      ),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        for (final (i, m) in days.indexed)
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                Text(
                                  '$m',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: scheme.onSurfaceVariant,
                                    fontFeatures: tabularFigures,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                AnimatedContainer(
                                  duration: const Duration(milliseconds: 400),
                                  height: height * m / top,
                                  margin: const EdgeInsets.symmetric(horizontal: 7),
                                  decoration: BoxDecoration(
                                    color: i == days.length - 1
                                        ? scheme.primary
                                        : scheme.primary.withValues(alpha: 0.3),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  DateFormat.E(l.localeName)
                                      .format(today.subtract(Duration(days: days.length - 1 - i)))
                                      .substring(0, 3),
                                  style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// − 45 min por dia +, and a switch to have no limit at all.
class _Limit extends StatelessWidget {
  const _Limit({required this.service});
  final WellbeingService service;

  // Limit: 5-minute steps between 5 min and 4 h; nobody needs a finer knob.
  static const _step = 5, _min = 5, _max = 240;

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final scheme = Theme.of(context).colorScheme;
    final limit = service.dailyLimit;
    return ValueListenableBuilder<int?>(
      valueListenable: limit,
      builder: (context, v, _) => Column(
        children: [
          SwitchListTile(
            key: const Key('limit_switch'),
            value: v != null,
            onChanged: (on) => limit.value = on ? 45 : null,
            title: Text(v == null ? l.noLimit : l.minutesPerDay(v)),
          ),
          if (v != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  IconButton.filledTonal(
                    key: const Key('limit_less'),
                    tooltip: l.lessTime,
                    onPressed: v <= _min ? null : () => limit.value = v - _step,
                    icon: const Icon(Icons.remove_rounded),
                  ),
                  Expanded(
                    child: Text(
                      '$v min',
                      key: const Key('limit_value'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                        color: scheme.onSurface,
                        fontFeatures: tabularFigures,
                      ),
                    ),
                  ),
                  IconButton.filledTonal(
                    key: const Key('limit_more'),
                    tooltip: l.moreTime,
                    onPressed: v >= _max ? null : () => limit.value = v + _step,
                    icon: const Icon(Icons.add_rounded),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
