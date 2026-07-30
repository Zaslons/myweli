import 'package:flutter/material.dart';

import '../../core/theme/colors.dart';
import '../../core/theme/text_styles.dart';
import '../../core/utils/formatters.dart';
import '../../models/availability.dart';
import '../common/myweli_time_picker.dart';

const _dayNames = [
  'Lundi',
  'Mardi',
  'Mercredi',
  'Jeudi',
  'Vendredi',
  'Samedi',
  'Dimanche',
];

/// Edits a weekly working schedule as one range per day (a day is either a day
/// off or a single start–end range). Stateless — the parent owns the map.
class WeeklyHoursEditor extends StatelessWidget {
  final Map<int, List<TimeSlot>> hours;
  final ValueChanged<Map<int, List<TimeSlot>>> onChanged;

  /// Label for a day with no range (e.g. 'Repos' for hours, 'Aucune' for
  /// breaks), and the range a freshly-toggled-on day starts with.
  final String offLabel;
  final TimeOfDay defaultStart;
  final TimeOfDay defaultEnd;

  const WeeklyHoursEditor({
    super.key,
    required this.hours,
    required this.onChanged,
    this.offLabel = 'Repos',
    this.defaultStart = const TimeOfDay(hour: 9, minute: 0),
    this.defaultEnd = const TimeOfDay(hour: 17, minute: 0),
  });

  TimeSlot? _slotFor(int day) {
    final slots = hours[day];
    return (slots == null || slots.isEmpty) ? null : slots.first;
  }

  void _setDay(int day, TimeSlot? slot) {
    final next = {for (final e in hours.entries) e.key: e.value};
    if (slot == null) {
      next.remove(day);
    } else {
      next[day] = [slot];
    }
    onChanged(next);
  }

  TimeSlot _slot(TimeOfDay start, TimeOfDay end) => TimeSlot(
    startTime: DateTime(2000, 1, 1, start.hour, start.minute),
    endTime: DateTime(2000, 1, 1, end.hour, end.minute),
    isAvailable: true,
  );

  /// One screen for the whole range (A14b).
  ///
  /// **This was two modals and a bare silent `return`.** The old shape asked
  /// « Heure de début », then « Heure de fin », then:
  ///
  /// ```dart
  /// if (end.hour * 60 + end.minute <= start.hour * 60 + start.minute) return;
  /// ```
  ///
  /// — no snackbar, no message, nothing. Pick 17:00 then 09:00 and both dialogs
  /// closed and the row simply did not change, which is **indistinguishable from
  /// having cancelled**. It was the worst of the three chains: the other two at
  /// least said why.
  ///
  /// `MyweliTimeRangePicker` puts both halves on one screen and will not offer
  /// an end at or before the start, so the invalid state is unreachable rather
  /// than caught. The two `helpText`s become the two field labels — these were
  /// the only localised strings any picker call in the app passed, and without
  /// them the two dialogs of chain B were visually identical.
  ///
  /// `onChanged` still fires **exactly once, on confirm**. That is load-bearing:
  /// `availability_screen.dart` wires it straight to `updateAvailability`, so a
  /// control that emitted per edit would write to the server on every tap.
  Future<void> _editRange(
    BuildContext context,
    int day,
    TimeSlot current,
  ) async {
    final range = await showMyweliTimeRangePicker(
      context: context,
      initialStart: TimeOfDay(
        hour: current.startTime.hour,
        minute: current.startTime.minute,
      ),
      initialEnd: TimeOfDay(
        hour: current.endTime.hour,
        minute: current.endTime.minute,
      ),
      startLabel: 'Heure de début',
      endLabel: 'Heure de fin',
      helpText: '${_dayNames[day]} — horaires',
    );
    if (range == null) return;
    _setDay(day, _slot(range.start, range.end));
  }

  // `_fmt` used to live here as a private pair of `padLeft`s — the third
  // spelling of « 14:30 » in the repo. It is `Formatters.formatHourMinute` now,
  // for the reason A13 gave about the plural rule: four spellings of one job
  // disagreed at exactly one value, and nobody had noticed.
  String _fmt(DateTime t) => Formatters.formatHourMinute(t.hour, t.minute);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(7, (day) {
        final slot = _slotFor(day);
        final works = slot != null;
        return Container(
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: AppColors.divider)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(_dayNames[day], style: AppTextStyles.bodyMedium),
              ),
              if (works)
                TextButton(
                  onPressed: () => _editRange(context, day, slot),
                  child: Text(
                    '${_fmt(slot.startTime)} – ${_fmt(slot.endTime)}',
                  ),
                )
              else
                Text(
                  offLabel,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.textTertiary,
                  ),
                ),
              Switch(
                value: works,
                onChanged: (on) =>
                    _setDay(day, on ? _slot(defaultStart, defaultEnd) : null),
              ),
            ],
          ),
        );
      }),
    );
  }
}
