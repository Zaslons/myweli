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
            const _ColumnHeadings(),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _WheelColumn(
                      values: [
                        for (var h = 0; h < TimeOfDay.hoursPerDay; h++) h,
                      ],
                      selected: _hour,
                      isEnabled: _hourEnabled,
                      semanticLabel: (h) => '${h}h',
                      onPick: _pickHour,
                    ),
                  ),
                  Expanded(
                    child: _WheelColumn(
                      values: [
                        for (var m = 0;
                            m < TimeOfDay.minutesPerHour;
                            m += widget.minuteStep)
                          m,
                      ],
                      selected: _minute,
                      isEnabled: (m) => !_isBelowMin(_hour, m),
                      semanticLabel: (m) => '$m minutes',
                      onPick: _pickMinute,
                    ),
                  ),
                ],
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
