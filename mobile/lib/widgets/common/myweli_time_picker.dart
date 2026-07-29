import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/text_styles.dart';
import '../../core/utils/formatters.dart';
import 'app_button.dart';

/// The house time picker (A14b, `docs/design/mobile-a14-pickers.md` §8–§12).
///
/// **Why we own this, and it is not row 73's story.** A14a's case was *"Material
/// clips a digit by 1.5dp"*. Material's **time** picker does not clip. It does
/// four other things, each verified against Flutter 3.38.6:
///
/// 1. **It refuses to scale its primary content, as a literal.**
///    `time_picker.dart:387` passes `textScaler: TextScaler.noScaling` to the
///    hour and the minute. In dial mode those are `displayLarge` — 57sp on a
///    64dp line — inside a hard-coded 80dp box. 64 in 80 fits at 1×, and fits
///    *identically* at 200%, because it never grows. **That is worse than a
///    clip: a clip is visible.** `design_system_pin_test.dart` now forbids
///    writing it here.
/// 2. **It caps its own container at 1.1×** (`:2544-2552`), with Flutter's own
///    comment admitting why, and applies the cap to height only — the portrait
///    width stays the literal `310`.
/// 3. **Its dial numbers do scale, to 2×, on rings that do not.**
///    `_kTimePickerInnerDialOffset` is a const `28`, and `dialTextStyle` is
///    `bodyLarge` — *our* `bodyLarge`, 16sp on a 24dp line
///    (`app_theme.dart:212`). At 2× that is a **48dp line box on 28dp of radial
///    gap**, so the 0–11 ring and the 12–23 ring overlap by **20dp** at every
///    clock position. The 20 is the line-box figure and is exact; the painted
///    ink overlaps by nearer 4dp, which is an estimate and is marked as one.
/// 4. **And no assertion in this repo can fail on any of it.** The dial is a
///    `CustomPaint` inside `ExcludeSemantics` with `excludeFromSemantics: true`.
///    Every helper in `test/a11y/_a11y.dart` walks `RenderParagraph`s; the dial
///    has zero. A gate pointed at `showTimePicker` is green unconditionally,
///    which is why A14b's gate had to be pointed at *this* widget instead.
///
/// The theme cannot rescue it either. `hourMinuteSize` and `dialSize` are
/// abstract getters on the private `_TimePickerDefaults` and appear **zero**
/// times in `time_picker_theme.dart`. You can shrink the font and you can never
/// grow the box — so unlike `dayStyle`, this is not even *"reachable by doing
/// the forbidden thing"*.
///
/// **The shape that answers all four: two columns of text rows.** A row's height
/// comes from the text it holds ([_rowHeight]), so the control grows with the
/// scale instead of clamping it, and there is no ring whose radius can collide
/// with a glyph. It is the same formula `_WeekStrip` and A14a's day cell use —
/// the house has one answer to *"a row that must grow"* and should not gain a
/// second.
///
/// Unlike the date picker there is **no pop-on-tap**: a time is two values, so
/// no single tap means *done*. « Confirmer » commits.
Future<TimeOfDay?> showMyweliTimePicker({
  required BuildContext context,
  required TimeOfDay initialTime,
  TimeOfDay? minTime,
  int minuteStep = 5,
  String? helpText,
}) {
  return Navigator.of(context).push<TimeOfDay>(
    MaterialPageRoute<TimeOfDay>(
      fullscreenDialog: true,
      builder: (_) => MyweliTimePickerScreen(
        initialTime: initialTime,
        minTime: minTime,
        minuteStep: minuteStep,
        helpText: helpText,
      ),
    ),
  );
}

/// The picker's screen. Public for the same reason [MyweliDatePickerScreen] is:
/// a test can pump it directly, without a `Navigator` and a route transition
/// standing between the gate and the layout it is measuring.
class MyweliTimePickerScreen extends StatefulWidget {
  const MyweliTimePickerScreen({
    super.key,
    required this.initialTime,
    this.minTime,
    this.minuteStep = 5,
    this.helpText,
  });

  final TimeOfDay initialTime;

  /// The earliest selectable time, inclusive. Null means the whole day.
  ///
  /// **This is the parameter Material could not express**, and three shipped
  /// error states existed in its place — see §10.1. `pro_manual_booking`'s
  /// « Choisissez une date et une heure à venir. » was reachable only because
  /// *today + an earlier hour* was pickable.
  final TimeOfDay? minTime;

  /// The minute granularity. 5 by default: salon slots are 15 or 30 in practice,
  /// but a reschedule may have to match an arbitrary server slot, so the leaf
  /// takes the parameter rather than the family assuming a granularity. A site
  /// that needs exact minutes passes 1.
  final int minuteStep;

  /// The screen's title, defaulting to « Choisir une heure ».
  ///
  /// `weekly_hours_editor.dart` is the only caller in the app that has ever
  /// passed one, and there it is load-bearing rather than decorative: without
  /// it the two dialogs of a start–end chain were **visually identical**, with
  /// nothing on screen saying which one you were in.
  final String? helpText;

  @override
  State<MyweliTimePickerScreen> createState() => _MyweliTimePickerScreenState();
}

class _MyweliTimePickerScreenState extends State<MyweliTimePickerScreen> {
  late int _hour;
  late int _minute;

  @override
  void initState() {
    super.initState();
    _hour = widget.initialTime.hour;
    // Snapped to the grid the columns actually offer. An `initialTime` of 09:07
    // with a step of 5 would otherwise highlight no row at all, and « Confirmer »
    // would return a value the user never saw.
    _minute =
        (widget.initialTime.minute ~/ widget.minuteStep) * widget.minuteStep;
    if (_selectionBelowMin) {
      final min = widget.minTime!;
      _hour = min.hour;
      _minute = _ceilToStep(min.minute);
      if (_minute >= TimeOfDay.minutesPerHour) {
        _hour += 1;
        _minute = 0;
      }
    }
  }

  int _ceilToStep(int minute) =>
      ((minute + widget.minuteStep - 1) ~/ widget.minuteStep) *
      widget.minuteStep;

  bool get _selectionBelowMin => _isBelowMin(_hour, _minute);

  bool _isBelowMin(int hour, int minute) {
    final min = widget.minTime;
    if (min == null) return false;
    return hour * TimeOfDay.minutesPerHour + minute <
        min.hour * TimeOfDay.minutesPerHour + min.minute;
  }

  /// An hour is offered when *any* minute on the grid within it is selectable.
  bool _hourEnabled(int hour) {
    final min = widget.minTime;
    if (min == null) return true;
    return hour > min.hour || (hour == min.hour && !_allMinutesBelowMin(hour));
  }

  bool _allMinutesBelowMin(int hour) {
    for (var m = 0; m < TimeOfDay.minutesPerHour; m += widget.minuteStep) {
      if (!_isBelowMin(hour, m)) return false;
    }
    return true;
  }

  void _pickHour(int hour) => setState(() {
        _hour = hour;
        if (_isBelowMin(_hour, _minute)) {
          // Moving to the boundary hour can strand the minute below the floor.
          // Dragging it up is the behaviour the two-dialog chain faked with
          // `pickedStart.hour + 1` arithmetic, and getting it wrong is what the
          // deleted error states used to catch.
          _minute = _ceilToStep(widget.minTime!.minute);
        }
      });

  void _pickMinute(int minute) => setState(() => _minute = minute);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close, size: AppTheme.iconM),
          tooltip: 'Fermer',
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(widget.helpText ?? 'Choisir une heure'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            _TimeHeadline(hour: _hour, minute: _minute),
            Expanded(
              child: MyweliTimeWheels(
                hour: _hour,
                minute: _minute,
                minuteStep: widget.minuteStep,
                isHourEnabled: _hourEnabled,
                isMinuteEnabled: (m) => !_isBelowMin(_hour, m),
                onHour: _pickHour,
                onMinute: _pickMinute,
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(AppTheme.spacingM),
              child: AppButton(
                text: 'Confirmer',
                isFullWidth: true,
                onPressed: _selectionBelowMin
                    ? null
                    : () => Navigator.of(context)
                        .pop(TimeOfDay(hour: _hour, minute: _minute)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A start and an end, on **one** surface (A14b, §11.2).
///
/// **This replaces two identical modals in a row.** Chain B
/// (`availability_screen.dart:633` + `:640`) opened two `showTimePicker`s with
/// no `helpText` on either — *visually identical, with nothing on screen saying
/// which one you were in*. Chain C (`weekly_hours_editor.dart:61` + `:68`)
/// labelled them, and those labels are the only localised strings any picker
/// call in this app has ever passed.
///
/// **And it deletes two error states by construction, not by restyling them.**
/// The end column cannot offer a time at or before the start, so:
///
/// - `availability_screen.dart:670-678`'s « L'heure de fin doit être après
///   l'heure de début » — a snackbar that also threw away both answers — has
///   nothing left to catch;
/// - `weekly_hours_editor.dart:75`'s `if (end <= start) return;` — a **bare
///   silent return**, after two modals, indistinguishable from a cancel — has
///   nothing left to swallow.
///
/// Returns null on cancel and calls back **once**, on confirm. That is not a
/// detail: `availability_screen.dart:113` wires `WeeklyHoursEditor.onChanged`
/// straight to `provider.updateAvailability`, so a control that emitted per edit
/// would write to the server on every tap.
Future<({TimeOfDay start, TimeOfDay end})?> showMyweliTimeRangePicker({
  required BuildContext context,
  required TimeOfDay initialStart,
  required TimeOfDay initialEnd,
  int minuteStep = 5,
  String startLabel = 'Début',
  String endLabel = 'Fin',
  String? helpText,
}) {
  return Navigator.of(context).push<({TimeOfDay start, TimeOfDay end})>(
    MaterialPageRoute<({TimeOfDay start, TimeOfDay end})>(
      fullscreenDialog: true,
      builder: (_) => MyweliTimeRangePickerScreen(
        initialStart: initialStart,
        initialEnd: initialEnd,
        minuteStep: minuteStep,
        startLabel: startLabel,
        endLabel: endLabel,
        helpText: helpText,
      ),
    ),
  );
}

/// The range picker's screen. Public so tests can pump it without a route.
class MyweliTimeRangePickerScreen extends StatefulWidget {
  const MyweliTimeRangePickerScreen({
    super.key,
    required this.initialStart,
    required this.initialEnd,
    this.minuteStep = 5,
    this.startLabel = 'Début',
    this.endLabel = 'Fin',
    this.helpText,
  });

  final TimeOfDay initialStart;
  final TimeOfDay initialEnd;
  final int minuteStep;
  final String startLabel;
  final String endLabel;
  final String? helpText;

  @override
  State<MyweliTimeRangePickerScreen> createState() =>
      _MyweliTimeRangePickerScreenState();
}

class _MyweliTimeRangePickerScreenState
    extends State<MyweliTimeRangePickerScreen> {
  late int _startMinutes;
  late int _endMinutes;

  /// Which half the two columns below are editing. Both values stay visible in
  /// the chips, which is the whole reason this is one screen and not two.
  bool _editingEnd = false;

  static const int _minutesPerDay =
      TimeOfDay.hoursPerDay * TimeOfDay.minutesPerHour;

  /// The last time the grid can represent — 23:55 at a step of 5.
  int get _lastGridMinute => _minutesPerDay - widget.minuteStep;

  int _snap(TimeOfDay t) {
    final raw = t.hour * TimeOfDay.minutesPerHour + t.minute;
    return (raw ~/ widget.minuteStep) * widget.minuteStep;
  }

  @override
  void initState() {
    super.initState();
    _startMinutes = _snap(widget.initialStart).clamp(0, _lastGridMinute - 1);
    _endMinutes = _snap(widget.initialEnd);
    if (_endMinutes <= _startMinutes) _endMinutes = _afterStart(_startMinutes);
  }

  /// Where the end goes when the start has invalidated it: one hour later,
  /// capped at the end of the grid.
  ///
  /// This is the behaviour `availability_screen.dart:642` faked with
  /// `TimeOfDay(hour: pickedStart.hour + 1, …)` — arithmetic standing in for
  /// two dialogs being unable to see each other. Here the two halves are on one
  /// screen, so it is just a default the user can immediately change.
  int _afterStart(int start) =>
      math.min(start + TimeOfDay.minutesPerHour, _lastGridMinute);

  void _setEditing(bool end) => setState(() => _editingEnd = end);

  void _pickHour(int hour) => setState(() {
        if (_editingEnd) {
          _endMinutes = _clampEnd(hour * TimeOfDay.minutesPerHour +
              _endMinutes % TimeOfDay.minutesPerHour);
        } else {
          _setStart(hour * TimeOfDay.minutesPerHour +
              _startMinutes % TimeOfDay.minutesPerHour);
        }
      });

  void _pickMinute(int minute) => setState(() {
        if (_editingEnd) {
          _endMinutes = _clampEnd((_endMinutes ~/ TimeOfDay.minutesPerHour) *
                  TimeOfDay.minutesPerHour +
              minute);
        } else {
          _setStart((_startMinutes ~/ TimeOfDay.minutesPerHour) *
                  TimeOfDay.minutesPerHour +
              minute);
        }
      });

  void _setStart(int value) {
    _startMinutes = value.clamp(0, _lastGridMinute - 1);
    // Moving the start past the end drags the end with it rather than refusing
    // the tap — refusing would make the start column's disabled rows depend on
    // the end, which is the kind of mutual constraint a user cannot see.
    if (_endMinutes <= _startMinutes) _endMinutes = _afterStart(_startMinutes);
  }

  int _clampEnd(int value) =>
      value <= _startMinutes ? _startMinutes + widget.minuteStep : value;

  int get _active => _editingEnd ? _endMinutes : _startMinutes;

  bool _hourEnabled(int hour) {
    if (!_editingEnd) {
      // A start with no room after it cannot begin a range.
      return hour * TimeOfDay.minutesPerHour < _lastGridMinute;
    }
    return (hour + 1) * TimeOfDay.minutesPerHour > _startMinutes;
  }

  bool _minuteEnabled(int minute) {
    final hour = _active ~/ TimeOfDay.minutesPerHour;
    final candidate = hour * TimeOfDay.minutesPerHour + minute;
    return _editingEnd
        ? candidate > _startMinutes
        : candidate < _lastGridMinute;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close, size: AppTheme.iconM),
          tooltip: 'Fermer',
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(widget.helpText ?? 'Choisir un horaire'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            _PickerChipPair(
              leftLabel: widget.startLabel,
              leftValue: Formatters.formatHourMinute(
                _startMinutes ~/ TimeOfDay.minutesPerHour,
                _startMinutes % TimeOfDay.minutesPerHour,
              ),
              rightLabel: widget.endLabel,
              rightValue: Formatters.formatHourMinute(
                _endMinutes ~/ TimeOfDay.minutesPerHour,
                _endMinutes % TimeOfDay.minutesPerHour,
              ),
              rightActive: _editingEnd,
              onPick: _setEditing,
            ),
            Expanded(
              child: MyweliTimeWheels(
                // Keyed on which half is being edited, so switching chips
                // rebuilds the columns and each one re-opens scrolled to the
                // value it is now showing. Without the key the wheels keep the
                // scroll position of the half the user just left.
                key: ValueKey(_editingEnd),
                hour: _active ~/ TimeOfDay.minutesPerHour,
                minute: _active % TimeOfDay.minutesPerHour,
                minuteStep: widget.minuteStep,
                isHourEnabled: _hourEnabled,
                isMinuteEnabled: _minuteEnabled,
                onHour: _pickHour,
                onMinute: _pickMinute,
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(AppTheme.spacingM),
              child: AppButton(
                text: 'Confirmer',
                isFullWidth: true,
                onPressed: () => Navigator.of(context).pop((
                  start: _toTimeOfDay(_startMinutes),
                  end: _toTimeOfDay(_endMinutes),
                )),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

TimeOfDay _toTimeOfDay(int minutes) => TimeOfDay(
      hour: minutes ~/ TimeOfDay.minutesPerHour,
      minute: minutes % TimeOfDay.minutesPerHour,
    );

/// Two labelled values side by side, one of them active — « Début 09:00 » next
/// to « Fin 17:00 », or « Date 11/03/2026 » next to « Heure 14:30 ».
///
/// **Shared, because the range picker and the combined picker had written it
/// twice**, in two files, identically. Two copies of a control is how A13's
/// plural rule ended up with four spellings that disagreed at one value.
///
/// **It is a `Wrap`, not a `Row` of `Expanded`s, and the goldens are why.**
/// Half a 360dp screen is ~156dp. « 11/03/2026 » at `titleMedium` × 2× needs
/// **172.3dp** and has no space to break at, so the chip split the number
/// itself: « 11/03/2 » on one line and « 026 » on the next. §13.3 forbids a
/// mid-word break outright, and a date is one token.
///
/// A `Wrap` sizes each chip to its content and drops the second onto a new row
/// when both no longer fit — *wrap, not scroll*, the same answer B9 and B11
/// took. It also removes a second defect the pictures showed: with `Expanded`,
/// a label that wrapped made one chip taller than its neighbour.
class _PickerChipPair extends StatelessWidget {
  const _PickerChipPair({
    required this.leftLabel,
    required this.leftValue,
    required this.rightLabel,
    required this.rightValue,
    required this.rightActive,
    required this.onPick,
  });

  final String leftLabel;
  final String leftValue;
  final String rightLabel;
  final String rightValue;
  final bool rightActive;
  final ValueChanged<bool> onPick;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppTheme.spacingM),
      // `Align` so the pair fills the row and starts at the left edge. Without
      // it the `Wrap` shrink-wraps and the enclosing `Column` centres it, which
      // the 2× golden showed as two stacked chips floating in the middle of the
      // screen while every other element was left-aligned.
      child: Align(
        alignment: Alignment.centerLeft,
        child: Wrap(
          spacing: AppTheme.spacingS,
          runSpacing: AppTheme.spacingS,
          children: [
            _PickerChip(
              label: leftLabel,
              value: leftValue,
              active: !rightActive,
              onTap: () => onPick(false),
            ),
            _PickerChip(
              label: rightLabel,
              value: rightValue,
              active: rightActive,
              onTap: () => onPick(true),
            ),
          ],
        ),
      ),
    );
  }
}

class _PickerChip extends StatelessWidget {
  const _PickerChip({
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
          // No fixed height and no fixed width: both dimensions come from the
          // text, which is what lets the `Wrap` above make the reflow decision.
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

/// The chip pair, for the combined picker in the sibling file.
///
/// A thin public alias rather than making `_PickerChipPair` public directly:
/// the two callers pass different things (times vs a date and a time), and the
/// shared widget takes strings so neither has to know about the other's types.
class MyweliPickerChipPair extends StatelessWidget {
  const MyweliPickerChipPair({
    super.key,
    required this.leftLabel,
    required this.leftValue,
    required this.rightLabel,
    required this.rightValue,
    required this.rightActive,
    required this.onPick,
  });

  final String leftLabel;
  final String leftValue;
  final String rightLabel;
  final String rightValue;
  final bool rightActive;
  final ValueChanged<bool> onPick;

  @override
  Widget build(BuildContext context) => _PickerChipPair(
        leftLabel: leftLabel,
        leftValue: leftValue,
        rightLabel: rightLabel,
        rightValue: rightValue,
        rightActive: rightActive,
        onPick: onPick,
      );
}

/// « 14:30 », so the value is legible without decoding two highlighted rows.
class _TimeHeadline extends StatelessWidget {
  const _TimeHeadline({required this.hour, required this.minute});

  final int hour;
  final int minute;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppTheme.spacingM),
      child: Text(
        // Through `Formatters`, never a local `padLeft` pair — that is the
        // spelling `weekly_hours_editor` grew privately and A13's plural sweep
        // is the precedent for not letting a second one exist.
        Formatters.formatHourMinute(hour, minute),
        textAlign: TextAlign.center,
        style: AppTextStyles.headlineMedium,
      ),
    );
  }
}

/// « Heures » · « Minutes » over two columns of numbers.
///
/// Public and `Scaffold`-free so all three controls in this family — and
/// `MyweliDateTimePickerScreen`, which lives in another file — render the same
/// wheels rather than three copies that drift. The state stays with the caller:
/// each control has a different idea of what is selectable (a floor, a start,
/// or nothing), and folding that in here would mean one widget with three modes.
class MyweliTimeWheels extends StatelessWidget {
  const MyweliTimeWheels({
    super.key,
    required this.hour,
    required this.minute,
    required this.minuteStep,
    required this.onHour,
    required this.onMinute,
    this.isHourEnabled,
    this.isMinuteEnabled,
  });

  final int hour;
  final int minute;
  final int minuteStep;
  final ValueChanged<int> onHour;
  final ValueChanged<int> onMinute;
  final bool Function(int)? isHourEnabled;
  final bool Function(int)? isMinuteEnabled;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const _ColumnHeadings(),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _WheelColumn(
                  values: [for (var h = 0; h < TimeOfDay.hoursPerDay; h++) h],
                  selected: hour,
                  isEnabled: isHourEnabled ?? (_) => true,
                  semanticLabel: (h) => '${h}h',
                  onPick: onHour,
                ),
              ),
              Expanded(
                child: _WheelColumn(
                  values: [
                    for (var m = 0;
                        m < TimeOfDay.minutesPerHour;
                        m += minuteStep)
                      m,
                  ],
                  selected: minute,
                  isEnabled: isMinuteEnabled ?? (_) => true,
                  semanticLabel: (m) => '$m minutes',
                  onPick: onMinute,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// « Heures » · « Minutes ».
class _ColumnHeadings extends StatelessWidget {
  const _ColumnHeadings();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppTheme.spacingS),
      child: Row(
        children: [
          for (final label in const ['Heures', 'Minutes'])
            Expanded(
              child: ExcludeSemantics(
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: AppTextStyles.labelSmall
                      .copyWith(color: AppColors.textTertiary),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A row's height: the scaled line plus breathing room, floored at §13.2's 48.
///
/// The same formula as A14a's day cell (`myweli_date_picker.dart:457-464`) and
/// `_WeekStrip`'s pill, for the same reason — a box whose height is a constant
/// is a box that clips at 200%, and that is the entire complaint against
/// Material's `hourMinuteSize` of `Size(96, 80)`.
double _rowHeight(BuildContext context) {
  const style = AppTextStyles.titleMedium;
  final line = (style.fontSize ?? 14) * (style.height ?? 1.4);
  return math.max(
    AppTheme.spacingXXL,
    MediaQuery.textScalerOf(context).scale(line) + AppTheme.spacingS,
  );
}

/// A row plus the gap around it — what one list item actually occupies, and the
/// unit the opening scroll offset is counted in.
double _itemExtent(BuildContext context) =>
    _rowHeight(context) + 2 * AppTheme.spacingXS;

/// One scrollable column of selectable numbers.
class _WheelColumn extends StatefulWidget {
  const _WheelColumn({
    required this.values,
    required this.selected,
    required this.isEnabled,
    required this.semanticLabel,
    required this.onPick,
  });

  final List<int> values;
  final int selected;
  final bool Function(int) isEnabled;
  final String Function(int) semanticLabel;
  final ValueChanged<int> onPick;

  @override
  State<_WheelColumn> createState() => _WheelColumnState();
}

class _WheelColumnState extends State<_WheelColumn> {
  ScrollController? _controller;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // **Opened at 14:30, the user must see 14 and 30.** A column that always
    // starts at 00 makes the header's « 14:30 » disagree with everything on
    // screen, and reaching the selected hour costs a scroll before the first
    // useful tap.
    //
    // Built here rather than in `initState` because the offset depends on
    // `_rowHeight`, which reads the text scale — and once, not on every
    // dependency change: rebuilding it would yank the list back under a user
    // who had already scrolled.
    if (_controller != null) return;
    final index = widget.values.indexOf(widget.selected);
    _controller = ScrollController(
      initialScrollOffset: index <= 0 ? 0 : index * _itemExtent(context),
    );
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      controller: _controller,
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.spacingS,
        vertical: AppTheme.spacingXS,
      ),
      itemCount: widget.values.length,
      itemBuilder: (context, i) {
        final value = widget.values[i];
        final isSel = value == widget.selected;
        final enabled = widget.isEnabled(value);
        return Semantics(
          button: true,
          selected: isSel,
          enabled: enabled,
          label: widget.semanticLabel(value),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: enabled ? () => widget.onPick(value) : null,
            child: Container(
              height: _rowHeight(context),
              alignment: Alignment.center,
              margin: const EdgeInsets.symmetric(vertical: AppTheme.spacingXS),
              decoration: BoxDecoration(
                color: isSel ? AppColors.primary : null,
                borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
              ),
              child: ExcludeSemantics(
                child: Text(
                  value.toString().padLeft(2, '0'),
                  style: AppTextStyles.titleMedium.copyWith(
                    color: !enabled
                        ? AppColors.textTertiary
                        : isSel
                            ? AppColors.secondary
                            : AppColors.textPrimary,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
