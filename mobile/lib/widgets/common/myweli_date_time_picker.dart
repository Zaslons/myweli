import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/text_styles.dart';
import '../../core/utils/formatters.dart';
import 'app_button.dart';
import 'myweli_date_picker.dart';
import 'myweli_month_grid.dart';
import 'myweli_time_picker.dart';

/// A date and a time, in **one route** (A14b, §11.3).
///
/// **The chain this replaces, and the answer it destroys.**
/// `pro_journal_screen.dart:425` opened the date picker, and `:433` opened the
/// time picker the instant the first one popped. Cancelling the second one hit
///
/// ```dart
/// if (time == null || !mounted) return;
/// ```
///
/// — so the date the user had already chosen was **thrown away with no message
/// and no way back to it**. Two modals in a row, and the second one's Cancel
/// silently undid the first one's answer.
///
/// Here the two steps are one route. Going back from the time step returns to
/// the date step **with the date still selected**, because it is one widget's
/// state rather than one route's return value. Nothing is committed until
/// « Confirmer ».
///
/// ## It returns the parts, not a `DateTime`, and that is deliberate
///
/// Composing `DateTime(y, m, d, h, min)` here would be device-local — the exact
/// shape §18 forbids, and the one `availability_screen.dart:651-657` records
/// having got wrong once already, with the note *"The pin cannot see this:
/// there is no clock token here."*
///
/// Only the call site knows the salon's timezone, so only the call site can run
/// `salonDateTime(...)`. Returning a `DateTime` would make the unsafe call the
/// convenient one; returning `({date, time})` makes recombining through the
/// seam the only thing a caller can do.
///
/// ## The past-time constraint
///
/// [minTimeOnToday] is what finally makes `pro_journal_screen.dart:449`'s
/// « Créneau indisponible. » a server-side backstop rather than the user's
/// first feedback. Material's picker could not express *"not before now"*, so
/// today-plus-an-earlier-hour was submittable and the round-trip was the
/// validation. Passed in rather than read for the same reason as [today].
Future<({DateTime date, TimeOfDay time})?> showMyweliDateTimePicker({
  required BuildContext context,
  required DateTime initialDate,
  required TimeOfDay initialTime,
  required DateTime firstDate,
  required DateTime lastDate,
  DateTime? today,
  TimeOfDay? minTimeOnToday,
  int minuteStep = 5,
  String? helpText,
}) {
  assert(
    !lastDate.isBefore(firstDate),
    'lastDate ($lastDate) is before firstDate ($firstDate) — the picker would '
    'show a range with no selectable day in it',
  );
  return Navigator.of(context).push<({DateTime date, TimeOfDay time})>(
    MaterialPageRoute<({DateTime date, TimeOfDay time})>(
      fullscreenDialog: true,
      builder: (_) => MyweliDateTimePickerScreen(
        initialDate: initialDate,
        initialTime: initialTime,
        firstDate: firstDate,
        lastDate: lastDate,
        today: today,
        minTimeOnToday: minTimeOnToday,
        minuteStep: minuteStep,
        helpText: helpText,
      ),
    ),
  );
}

/// The combined picker's screen. Public so tests can pump it without a route.
class MyweliDateTimePickerScreen extends StatefulWidget {
  const MyweliDateTimePickerScreen({
    super.key,
    required this.initialDate,
    required this.initialTime,
    required this.firstDate,
    required this.lastDate,
    this.today,
    this.minTimeOnToday,
    this.minuteStep = 5,
    this.helpText,
  });

  final DateTime initialDate;
  final TimeOfDay initialTime;
  final DateTime firstDate;
  final DateTime lastDate;

  /// The salon's today, for the « aujourd'hui » marker and for deciding whether
  /// [minTimeOnToday] applies.
  final DateTime? today;

  /// The earliest time selectable **when the chosen day is [today]**.
  final TimeOfDay? minTimeOnToday;

  final int minuteStep;
  final String? helpText;

  @override
  State<MyweliDateTimePickerScreen> createState() =>
      _MyweliDateTimePickerScreenState();
}

class _MyweliDateTimePickerScreenState
    extends State<MyweliDateTimePickerScreen> {
  late DateTime _date;
  late int _hour;
  late int _minute;
  bool _onTimeStep = false;

  @override
  void initState() {
    super.initState();
    // Clamped for the same reason `MyweliDatePickerScreen` clamps: rescheduling
    // a PAST appointment passes its own date while `firstDate` is today, so an
    // unclamped picker opens on a month where every day is disabled and the
    // back chevron is off.
    _date = clampToRange(widget.initialDate, widget.firstDate, widget.lastDate);
    _hour = widget.initialTime.hour;
    _minute =
        (widget.initialTime.minute ~/ widget.minuteStep) * widget.minuteStep;
    _liftAboveFloor();
  }

  /// True when the chosen day is the salon's today, so the past-time floor bites.
  bool get _floorApplies =>
      widget.minTimeOnToday != null &&
      widget.today != null &&
      isSameDay(_date, widget.today!);

  int get _floorMinutes =>
      widget.minTimeOnToday!.hour * TimeOfDay.minutesPerHour +
      widget.minTimeOnToday!.minute;

  int get _selectedMinutes => _hour * TimeOfDay.minutesPerHour + _minute;

  bool get _belowFloor => _floorApplies && _selectedMinutes < _floorMinutes;

  /// Moves the selection up to the first grid time at or after the floor.
  ///
  /// Called when the day changes as well as at init, because **the floor is a
  /// property of the day**: picking today after picking tomorrow can strand a
  /// time in the past, and leaving it stranded would resurrect exactly the
  /// error state this control deletes.
  void _liftAboveFloor() {
    if (!_belowFloor) return;
    final ceil =
        ((_floorMinutes + widget.minuteStep - 1) ~/ widget.minuteStep) *
            widget.minuteStep;
    _hour = ceil ~/ TimeOfDay.minutesPerHour;
    _minute = ceil % TimeOfDay.minutesPerHour;
  }

  bool _hourEnabled(int hour) {
    if (!_floorApplies) return true;
    return (hour + 1) * TimeOfDay.minutesPerHour > _floorMinutes;
  }

  bool _minuteEnabled(int minute) {
    if (!_floorApplies) return true;
    return _hour * TimeOfDay.minutesPerHour + minute >= _floorMinutes;
  }

  void _pickDay(DateTime day) => setState(() {
        _date = day;
        _liftAboveFloor();
        _onTimeStep = true;
      });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(
            _onTimeStep ? Icons.arrow_back : Icons.close,
            size: AppTheme.iconM,
          ),
          // Back on the time step, close on the date step — so the affordance
          // says which one it is. Back keeps `_date`; that is the whole fix.
          tooltip: _onTimeStep ? 'Retour à la date' : 'Fermer',
          onPressed: _onTimeStep
              ? () => setState(() => _onTimeStep = false)
              : () => Navigator.of(context).pop(),
        ),
        title: Text(widget.helpText ?? 'Choisir la date et l’heure'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            _StepSummary(
              date: _date,
              hour: _hour,
              minute: _minute,
              onTimeStep: _onTimeStep,
              onEditDate: () => setState(() => _onTimeStep = false),
              onEditTime: () => setState(() => _onTimeStep = true),
            ),
            if (!_onTimeStep)
              Expanded(
                child: MyweliMonthNavigator(
                  initialMonth: _date,
                  firstDate: widget.firstDate,
                  lastDate: widget.lastDate,
                  selectedDay: _date,
                  today: widget.today,
                  onDayTap: _pickDay,
                ),
              )
            else ...[
              Expanded(
                child: MyweliTimeWheels(
                  hour: _hour,
                  minute: _minute,
                  minuteStep: widget.minuteStep,
                  isHourEnabled: _hourEnabled,
                  isMinuteEnabled: _minuteEnabled,
                  onHour: (h) => setState(() {
                    _hour = h;
                    _liftAboveFloor();
                  }),
                  onMinute: (m) => setState(() => _minute = m),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(AppTheme.spacingM),
                child: AppButton(
                  text: 'Confirmer',
                  isFullWidth: true,
                  onPressed: _belowFloor
                      ? null
                      : () => Navigator.of(context).pop((
                            date: _date,
                            time: TimeOfDay(hour: _hour, minute: _minute),
                          )),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The two answers so far, either of which is one tap from being changed.
class _StepSummary extends StatelessWidget {
  const _StepSummary({
    required this.date,
    required this.hour,
    required this.minute,
    required this.onTimeStep,
    required this.onEditDate,
    required this.onEditTime,
  });

  final DateTime date;
  final int hour;
  final int minute;
  final bool onTimeStep;
  final VoidCallback onEditDate;
  final VoidCallback onEditTime;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppTheme.spacingM),
      child: Row(
        children: [
          Expanded(
            child: _StepChip(
              label: 'Date',
              value: Formatters.formatDateShort(date),
              active: !onTimeStep,
              onTap: onEditDate,
            ),
          ),
          const SizedBox(width: AppTheme.spacingS),
          Expanded(
            child: _StepChip(
              label: 'Heure',
              value: Formatters.formatHourMinute(hour, minute),
              active: onTimeStep,
              onTap: onEditTime,
            ),
          ),
        ],
      ),
    );
  }
}

class _StepChip extends StatelessWidget {
  const _StepChip({
    required this.label,
    required this.value,
    required this.active,
    required this.onTap,
  });

  final String label;
  final String value;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: active,
      label: '$label, $value',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          // Padding, never a height: the two lines inside grow with the scale
          // and the chip has to grow with them (§13.3).
          padding: const EdgeInsets.all(AppTheme.spacingSM),
          decoration: BoxDecoration(
            color: active ? AppColors.primary : AppColors.secondary,
            border: Border.all(
              color: active ? AppColors.primary : AppColors.borderStrong,
            ),
            borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
          ),
          child: ExcludeSemantics(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: AppTextStyles.labelSmall.copyWith(
                    color:
                        active ? AppColors.secondary : AppColors.textTertiary,
                  ),
                ),
                Text(
                  value,
                  style: AppTextStyles.titleMedium.copyWith(
                    color: active ? AppColors.secondary : AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
