/// The month grid and its header bar, extracted from `MyweliDatePickerScreen`
/// (A14, `docs/design/mobile-a14-pickers.md`).
///
/// **Why these are their own file.** A14a built them private to the date
/// picker, which is a *picker*: it pops on tap and owns a `Scaffold`. Two other
/// surfaces want the same month without either — A14b's combined date-and-time
/// control renders it as **step 1 inside one route**, and A14c's pro calendar
/// embeds it in a card inside a scrolling column. A widget that can only exist
/// as a full-screen route cannot serve them, so the grid stops being a page and
/// becomes a component the pages compose.
///
/// Everything below is A14a's code and A14a's reasoning, moved rather than
/// rewritten. The arithmetic that decided the cell's shape is recorded at
/// [_cellHeight] and [_DayCell].
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/text_styles.dart';
import '../../core/utils/formatters.dart';

/// Same calendar day, ignoring time.
///
/// **Public because `table_calendar`'s `isSameDay` is about to stop existing**
/// (A14c). Its consumer today is `myweli_date_time_picker.dart`;
/// `appointment_calendar_view` still calls **table_calendar's** at `:94` and
/// `:121`, and A14c is what repoints it. An earlier draft of this comment said
/// that file "calls it twice" as though it already meant this one — it does
/// not, and a house calendar that leaves callers importing a retired package
/// for one predicate has not retired it.
bool isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// Midnight on [d]'s calendar day. Private: no caller outside this file yet.
DateTime _dayOf(DateTime d) => DateTime(d.year, d.month, d.day);

/// « mars 2026 » between two chevrons, with the label toggling a year list.
class MyweliMonthBar extends StatelessWidget {
  const MyweliMonthBar({
    super.key,
    required this.month,
    required this.canGoBack,
    required this.canGoForward,
    required this.pickingYear,
    required this.onBack,
    required this.onForward,
    required this.onToggleYear,
  });

  final DateTime month;
  final bool canGoBack;
  final bool canGoForward;
  final bool pickingYear;
  final VoidCallback onBack;
  final VoidCallback onForward;
  final VoidCallback onToggleYear;

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
            child: Semantics(
              button: true,
              expanded: pickingYear,
              label: pickingYear
                  ? 'Choisir un mois'
                  : 'Choisir une année — '
                        '${Formatters.formatMonthYear(month)}',
              child: InkWell(
                onTap: onToggleYear,
                // **A 48dp floor, because this was 40.** `spacingS` twice
                // around a 24dp `titleMedium` line is 40dp, under §13.2 — and
                // the Row's own 48 comes from the flanking `IconButton`s, so the
                // label's hit area really was short. A14a shipped it; A14b's
                // review found it when the extraction made it a SECOND screen's
                // control. A minimum, not a height: the box still grows with the
                // text (§13.3).
                child: Container(
                  constraints: const BoxConstraints(
                    minHeight: AppTheme.spacingXXL,
                  ),
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(
                    vertical: AppTheme.spacingS,
                  ),
                  child: Text(
                    Formatters.formatMonthYear(month),
                    textAlign: TextAlign.center,
                    style: AppTextStyles.titleMedium,
                  ),
                ),
              ),
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

/// The years in [firstYear]..[lastYear], as a list. Reached from the month bar.
class MyweliYearList extends StatelessWidget {
  const MyweliYearList({
    super.key,
    required this.selectedYear,
    required this.firstYear,
    required this.lastYear,
    required this.onPick,
  });

  final int selectedYear;
  final int firstYear;
  final int lastYear;
  final ValueChanged<int> onPick;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: AppTheme.spacingS),
      itemCount: lastYear - firstYear + 1,
      itemBuilder: (context, i) {
        final year = firstYear + i;
        final isSel = year == selectedYear;
        return ListTile(
          // A row of text, so the height comes from the text and the §13.2
          // floor is a minimum rather than a box — `ListTile` already grows.
          minVerticalPadding: AppTheme.spacingSM,
          selected: isSel,
          selectedTileColor: AppColors.primary,
          title: Text(
            '$year',
            textAlign: TextAlign.center,
            style: AppTextStyles.titleMedium.copyWith(
              color: isSel ? AppColors.secondary : AppColors.textPrimary,
            ),
          ),
          onTap: () => onPick(year),
        );
      },
    );
  }
}

/// « L M M J V S D » — Monday first, from `Formatters`, never a literal list.
class MyweliWeekdayHeader extends StatelessWidget {
  const MyweliWeekdayHeader({super.key});

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

/// One month, as a `Column` of `Row`s of `Expanded` cells.
///
/// **Not a `GridView`.** `childAspectRatio` is prohibited by a source pin —
/// *"a tile height derived from its WIDTH cannot grow with the text inside
/// it"* — and it is the only way a fixed-count grid delegate makes square
/// cells. `Expanded` is also the shape `_WeekStrip` arrived at for exactly this
/// 7-across problem, so the app has one answer to it rather than two.
///
/// **Days outside [month] are not rendered**, only reserved as blank space.
/// Web's `MonthCalendar` draws them dimmed and clickable, and that turned out
/// to be a defect rather than a style: clicking one selects a day the header
/// does not name. A14c changes web to match this, not the other way round —
/// and mobile has a second reason, which is that `textTertiary` is already
/// spent on *disabled*, and the consumer funnel is the one surface where both
/// states occur in the same month.
class MyweliMonthGrid extends StatelessWidget {
  const MyweliMonthGrid({
    super.key,
    required this.month,
    required this.onDayTap,
    this.selectedDay,
    this.today,
    this.firstDate,
    this.lastDate,
  });

  /// Any day in the month to render; only its year and month are read.
  final DateTime month;

  final ValueChanged<DateTime> onDayTap;

  /// The chosen day, or null — the pro calendar opens with nothing chosen.
  final DateTime? selectedDay;

  /// The salon's today, for the « aujourd'hui » marker.
  ///
  /// Passed in rather than read, because the grid must not touch a clock:
  /// `salon_time_pin_test.dart` keeps the wall clock out of `lib/`, and the
  /// right answer is the **active salon's** day (§18), which only the call site
  /// knows the timezone for. Null means no marker.
  final DateTime? today;

  /// The selectable range. Null on either end means unbounded — the pro
  /// calendar browses freely and disables nothing.
  final DateTime? firstDate;
  final DateTime? lastDate;

  bool _enabled(DateTime day) {
    if (firstDate != null && day.isBefore(_dayOf(firstDate!))) return false;
    if (lastDate != null && day.isAfter(_dayOf(lastDate!))) return false;
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    // `weekday` is 1 = Monday … 7 = Sunday, which is already the French week.
    final leading = DateTime(month.year, month.month).weekday - 1;

    final cells = <DateTime?>[
      ...List<DateTime?>.filled(leading, null),
      for (var d = 1; d <= daysInMonth; d++)
        DateTime(month.year, month.month, d),
    ];
    while (cells.length % 7 != 0) {
      cells.add(null);
    }

    return Column(
      children: [
        for (var w = 0; w < cells.length ~/ 7; w++)
          // No `crossAxisAlignment: stretch` here: inside a scroll view the
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
                          selected:
                              selectedDay != null &&
                              isSameDay(day, selectedDay!),
                          isToday: today != null && isSameDay(day, today!),
                          enabled: _enabled(day),
                          onPick: onDayTap,
                        ),
                ),
            ],
          ),
      ],
    );
  }
}

/// A month bar, a weekday row and a grid, with the month navigation wired up.
///
/// This is the whole calendar minus the page around it — which is exactly the
/// seam A14b needed: `MyweliDatePickerScreen` wraps it in a `Scaffold` that pops
/// on tap, and `MyweliDateTimePickerScreen` renders it as step 1 of a route that
/// does not pop until a time has been chosen too. Neither owns the navigation
/// logic, so neither can get it subtly different.
class MyweliMonthNavigator extends StatefulWidget {
  const MyweliMonthNavigator({
    super.key,
    required this.initialMonth,
    required this.firstDate,
    required this.lastDate,
    required this.onDayTap,
    this.selectedDay,
    this.today,
  });

  final DateTime initialMonth;
  final DateTime firstDate;
  final DateTime lastDate;
  final ValueChanged<DateTime> onDayTap;
  final DateTime? selectedDay;
  final DateTime? today;

  @override
  State<MyweliMonthNavigator> createState() => _MyweliMonthNavigatorState();
}

class _MyweliMonthNavigatorState extends State<MyweliMonthNavigator> {
  late DateTime _month;

  /// Whether the year list is showing instead of the month grid.
  ///
  /// **Added after A14a's review, which measured the cost of not having it:**
  /// with only ±1-month chevrons, crossing `kBookingHorizon` took up to **12
  /// taps**, and the journal's ±365 range took 12 each way. Material had a year
  /// selector; removing it without replacement made the picker worse at the one
  /// thing a year-long horizon needs.
  bool _pickingYear = false;

  @override
  void initState() {
    super.initState();
    _month = DateTime(widget.initialMonth.year, widget.initialMonth.month);
  }

  @override
  void didUpdateWidget(MyweliMonthNavigator old) {
    super.didUpdateWidget(old);
    // **Deliberately does NOT resync `_month` from the widget.** That is the
    // defect `date_time_selection_screen` shipped: `table_calendar` resets its
    // focused day whenever the parent's differs, so every `setState` on that
    // screen yanked a swiped-to month back. The month the user navigated to is
    // this widget's own state, and a rebuild is not a reason to discard it.
  }

  DateTime get _firstMonth =>
      DateTime(widget.firstDate.year, widget.firstDate.month);
  DateTime get _lastMonth =>
      DateTime(widget.lastDate.year, widget.lastDate.month);

  void _shift(int months) => setState(() {
    _month = DateTime(_month.year, _month.month + months);
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MyweliMonthBar(
          month: _month,
          canGoBack: _month.isAfter(_firstMonth) && !_pickingYear,
          canGoForward: _month.isBefore(_lastMonth) && !_pickingYear,
          pickingYear: _pickingYear,
          onBack: () => _shift(-1),
          onForward: () => _shift(1),
          onToggleYear: () => setState(() => _pickingYear = !_pickingYear),
        ),
        if (_pickingYear)
          Expanded(
            child: MyweliYearList(
              selectedYear: _month.year,
              firstYear: widget.firstDate.year,
              lastYear: widget.lastDate.year,
              onPick: (y) => setState(() {
                _month = DateTime(y, _month.month);
                _pickingYear = false;
              }),
            ),
          )
        else ...[
          const MyweliWeekdayHeader(),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                horizontal: AppTheme.spacingM,
                vertical: AppTheme.spacingS,
              ),
              child: MyweliMonthGrid(
                month: _month,
                selectedDay: widget.selectedDay,
                today: widget.today,
                firstDate: widget.firstDate,
                lastDate: widget.lastDate,
                onDayTap: widget.onDayTap,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// **The day number's size, and the mistake A14a's review caught.**
///
/// Material renders a day at `bodyLarge` — M3's `dayStyle` defaults to
/// `_textTheme.bodyLarge` (`date_picker_theme.dart:1315`), which is why row 73's
/// « 20 » needed 36.9dp at 2×. A14a's first draft used `bodyMedium`, and that
/// silently made the dominant term of the "fix" a **12.5% reduction of the day
/// number at every text scale** — the one remedy §13.3 forbids in terms, shipped
/// inside an accessibility slice while the commit credited geometry.
///
/// It is `bodyLarge` now, the same size Material used, and the cell still holds
/// it: 36.9dp needed against 38.86 available (46.86 of column, less an 8dp
/// margin). The fix is the width, which is what it always claimed to be.
const TextStyle _dayStyle = AppTextStyles.bodyLarge;

/// The cell's height: the scaled line plus breathing room, floored at §13.2's
/// 48. `_WeekStrip`'s formula, with the floor raised from 32 to 48 because here
/// the cell **is** the target rather than a pill inside a taller slot.
double _cellHeight(BuildContext context) {
  const style = _dayStyle;
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
    required this.isToday,
    required this.enabled,
    required this.onPick,
  });

  final DateTime day;
  final bool selected;
  final bool isToday;
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
      label: isToday
          ? 'aujourd’hui, ${Formatters.formatDate(day)}'
          : Formatters.formatDate(day),
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
            // Today is a ring, not a fill: §13 forbids meaning carried by
            // colour alone, and the ring survives beside the selected fill so
            // « today » and « chosen » can be the same day or different ones.
            border: isToday && !selected
                ? Border.all(color: AppColors.primary)
                : null,
            borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
          ),
          child: ExcludeSemantics(
            child: Text('${day.day}', style: _dayStyle.copyWith(color: fg)),
          ),
        ),
      ),
    );
  }
}
