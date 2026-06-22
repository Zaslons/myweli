import 'package:flutter/material.dart';

import '../../core/theme/colors.dart';
import '../../core/theme/text_styles.dart';
import '../../models/availability.dart';

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

  Future<void> _editRange(
      BuildContext context, int day, TimeSlot current) async {
    final start = await showTimePicker(
      context: context,
      helpText: 'Heure de début',
      initialTime: TimeOfDay(
          hour: current.startTime.hour, minute: current.startTime.minute),
    );
    if (start == null || !context.mounted) return;
    final end = await showTimePicker(
      context: context,
      helpText: 'Heure de fin',
      initialTime:
          TimeOfDay(hour: current.endTime.hour, minute: current.endTime.minute),
    );
    if (end == null) return;
    if (end.hour * 60 + end.minute <= start.hour * 60 + start.minute) return;
    _setDay(day, _slot(start, end));
  }

  String _fmt(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

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
                  child:
                      Text('${_fmt(slot.startTime)} – ${_fmt(slot.endTime)}'),
                )
              else
                Text(
                  offLabel,
                  style: AppTextStyles.bodySmall
                      .copyWith(color: AppColors.textTertiary),
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
