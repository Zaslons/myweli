import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/text_styles.dart';
import '../../core/utils/formatters.dart';

/// The house date picker (A14, SYSTEM.md §21 row 73).
///
/// **Why we own this.** At 200% text scale Material's `showDatePicker` renders
/// two-digit days as a single digit — measured at « 20 » having **35.4dp and
/// needing 36.9** on a 360dp phone. It is 1.5dp, and it is unreachable from the
/// outside: `AppTheme.datePickerTheme` sets colours, shape and elevation and
/// never a size, and §13.3's remedy everywhere else — *more width* — is not
/// available inside a dialog Material insets on every side.
///
/// **Three decisions carry the fix, and each is arithmetic rather than taste.**
///
/// 1. **A full-screen route, not a dialog.** Worth stating plainly that this
///    alone buys almost nothing: a 360dp page yields ~46.9dp per column against
///    the dialog's ~46. Seven columns of a 360dp screen is seven columns of a
///    360dp screen. What it buys is a header and actions with room to wrap, and
///    a container that cannot shrink further.
/// 2. **The day cell is a rounded rectangle, never a circle.** This is the fix.
///    `_WeekStrip`'s pill (`pro_journal_screen.dart:571`) must stay square
///    because it is round, so its diameter is `max(32, scaledLine + spacingS)`
///    — **48dp at 2×**, against 46.9dp of column. A circle cannot fit. A
///    rectangle takes the column's full width and grows only downwards, and two
///    digits at 2× need ≈32dp of glyph, which fits comfortably.
/// 3. **The cell's height grows with the text and its width does not.** Seven
///    48dp targets need 336dp plus padding, which no 360dp phone has, so §13.2's
///    floor is unreachable horizontally for *any* month grid. Height is floored
///    at 48 and the whole cell is tappable; the width is grid-bound. That is the
///    same trade `_WeekStrip` took (*"a fixed `minWidth: 48` × 7 overflowed
///    narrow phones"*) and the same one WEB-SYSTEM row 7h records for
///    `MonthCalendar` (*"height floored at 48, width grid-bound — recorded, not
///    hidden"*). Recorded here too.
///
/// Tapping a day selects **and pops** — one tap, not two. The five call sites
/// all want a date and nothing else, and Material's OK/Cancel pair existed to
/// confirm a selection the user could not otherwise see.
Future<DateTime?> showMyweliDatePicker({
  required BuildContext context,
  required DateTime initialDate,
  required DateTime firstDate,
  required DateTime lastDate,
  String? helpText,
}) {
  return Navigator.of(context).push<DateTime>(
    MaterialPageRoute<DateTime>(
      fullscreenDialog: true,
      builder: (_) => MyweliDatePickerScreen(
        initialDate: initialDate,
        firstDate: firstDate,
        lastDate: lastDate,
        helpText: helpText,
      ),
    ),
  );
}

/// The picker's screen. Public so tests can pump it without a route.
class MyweliDatePickerScreen extends StatefulWidget {
  const MyweliDatePickerScreen({
    super.key,
    required this.initialDate,
    required this.firstDate,
    required this.lastDate,
    this.helpText,
  });

  final DateTime initialDate;
  final DateTime firstDate;
  final DateTime lastDate;

  /// The screen's title. `weekly_hours_editor.dart` is the only picker caller
  /// in the app that passes one today, and the house API keeps that affordance.
  final String? helpText;

  @override
  State<MyweliDatePickerScreen> createState() => _MyweliDatePickerScreenState();
}

class _MyweliDatePickerScreenState extends State<MyweliDatePickerScreen> {
  late DateTime _month;

  @override
  void initState() {
    super.initState();
    _month = DateTime(widget.initialDate.year, widget.initialDate.month);
  }

  DateTime get _firstMonth =>
      DateTime(widget.firstDate.year, widget.firstDate.month);
  DateTime get _lastMonth =>
      DateTime(widget.lastDate.year, widget.lastDate.month);

  bool get _canGoBack => _month.isAfter(_firstMonth);
  bool get _canGoForward => _month.isBefore(_lastMonth);

  void _shift(int months) => setState(() {
        _month = DateTime(_month.year, _month.month + months);
      });

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
        title: Text(widget.helpText ?? 'Choisir une date'),
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _MonthBar(
              month: _month,
              canGoBack: _canGoBack,
              canGoForward: _canGoForward,
              onBack: () => _shift(-1),
              onForward: () => _shift(1),
            ),
            const _WeekdayHeader(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppTheme.spacingM,
                  vertical: AppTheme.spacingS,
                ),
                child: _MonthGrid(
                  month: _month,
                  selected: widget.initialDate,
                  firstDate: widget.firstDate,
                  lastDate: widget.lastDate,
                  onPick: (d) => Navigator.of(context).pop(d),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// « mars 2026 » between two chevrons.
class _MonthBar extends StatelessWidget {
  const _MonthBar({
    required this.month,
    required this.canGoBack,
    required this.canGoForward,
    required this.onBack,
    required this.onForward,
  });

  final DateTime month;
  final bool canGoBack;
  final bool canGoForward;
  final VoidCallback onBack;
  final VoidCallback onForward;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.spacingS,
        vertical: AppTheme.spacingS,
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left, size: AppTheme.iconM),
            tooltip: 'Mois précédent',
            onPressed: canGoBack ? onBack : null,
          ),
          // The label takes the rest of the row rather than a fixed box: a
          // month name is text, and §13.3 forbids dimensioning a box around it.
          Expanded(
            child: Text(
              Formatters.formatMonthYear(month),
              textAlign: TextAlign.center,
              style: AppTextStyles.titleMedium,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right, size: AppTheme.iconM),
            tooltip: 'Mois suivant',
            onPressed: canGoForward ? onForward : null,
          ),
        ],
      ),
    );
  }
}

/// « L M M J V S D » — Monday first, from `Formatters`, never a literal list.
class _WeekdayHeader extends StatelessWidget {
  const _WeekdayHeader();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.spacingM,
        vertical: AppTheme.spacingXS,
      ),
      child: Row(
        children: [
          for (final label in Formatters.weekdayInitials())
            Expanded(
              child: ExcludeSemantics(
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: AppTextStyles.labelSmall.copyWith(
                    color: AppColors.textTertiary,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The month, as a `Column` of `Row`s of `Expanded` cells.
///
/// **Not a `GridView`.** `childAspectRatio` is prohibited by a source pin —
/// *"a tile height derived from its WIDTH cannot grow with the text inside
/// it"* — and it is the only way a fixed-count grid delegate makes square
/// cells. `Expanded` is also the shape `_WeekStrip` arrived at for exactly this
/// 7-across problem, so the app has one answer to it rather than two.
class _MonthGrid extends StatelessWidget {
  const _MonthGrid({
    required this.month,
    required this.selected,
    required this.firstDate,
    required this.lastDate,
    required this.onPick,
  });

  final DateTime month;
  final DateTime selected;
  final DateTime firstDate;
  final DateTime lastDate;
  final ValueChanged<DateTime> onPick;

  @override
  Widget build(BuildContext context) {
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    // `weekday` is 1 = Monday … 7 = Sunday, which is already the French week.
    final leading = DateTime(month.year, month.month).weekday - 1;

    final cells = <DateTime?>[
      ...List<DateTime?>.filled(leading, null),
      for (var d = 1; d <= daysInMonth; d++) DateTime(month.year, month.month, d),
    ];
    while (cells.length % 7 != 0) {
      cells.add(null);
    }

    return Column(
      children: [
        for (var w = 0; w < cells.length ~/ 7; w++)
          // No `crossAxisAlignment: stretch` here: inside the scroll view the
          // column's height is unbounded, and stretch would hand each cell
          // `BoxConstraints(w=46.9, h=Infinity)`. Every cell sizes itself from
          // the text scale instead, which is the point.
          Row(
            children: [
              for (final day in cells.sublist(w * 7, w * 7 + 7))
                Expanded(
                  child: day == null
                      ? SizedBox(height: _cellHeight(context))
                      : _DayCell(
                          day: day,
                          selected: _sameDay(day, selected),
                          enabled: !day.isBefore(_dayOf(firstDate)) &&
                              !day.isAfter(_dayOf(lastDate)),
                          onPick: onPick,
                        ),
                ),
            ],
          ),
      ],
    );
  }
}

DateTime _dayOf(DateTime d) => DateTime(d.year, d.month, d.day);

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// The cell's height: the scaled line plus breathing room, floored at §13.2's
/// 48. `_WeekStrip`'s formula, with the floor raised from 32 to 48 because here
/// the cell **is** the target rather than a pill inside a taller slot.
double _cellHeight(BuildContext context) {
  const style = AppTextStyles.bodyMedium;
  final line = (style.fontSize ?? 14) * (style.height ?? 1.4);
  return math.max(
    AppTheme.spacingXXL,
    MediaQuery.textScalerOf(context).scale(line) + AppTheme.spacingS,
  );
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.selected,
    required this.enabled,
    required this.onPick,
  });

  final DateTime day;
  final bool selected;
  final bool enabled;
  final ValueChanged<DateTime> onPick;

  @override
  Widget build(BuildContext context) {
    final Color fg = !enabled
        ? AppColors.textTertiary
        : selected
            ? AppColors.secondary
            : AppColors.textPrimary;

    return Semantics(
      button: true,
      selected: selected,
      enabled: enabled,
      label: Formatters.formatDate(day),
      child: GestureDetector(
        // The whole cell is the target — §13.2's floor is met on the axis a
        // 7-column grid can meet it on, and `opaque` makes the padding count.
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? () => onPick(day) : null,
        child: Container(
          height: _cellHeight(context),
          alignment: Alignment.center,
          // `spacingXS`, and the arithmetic is tight enough to state: it takes
          // 8dp off a 46.9dp column, leaving ~38.9 for a two-digit day that
          // needs ~31.7 at 2×. The first version wrote `spacingXS / 2` and the
          // §5 pin caught it — a literal `2` in an `EdgeInsets` is a numeric
          // one however it is spelled, which is the rule working.
          margin: const EdgeInsets.all(AppTheme.spacingXS),
          decoration: BoxDecoration(
            color: selected ? AppColors.primary : null,
            borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
          ),
          child: ExcludeSemantics(
            child: Text(
              '${day.day}',
              style: AppTextStyles.bodyMedium.copyWith(color: fg),
            ),
          ),
        ),
      ),
    );
  }
}
