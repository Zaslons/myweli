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

/// A calendar day as an **identity** — year, month, day. No time, no zone.
///
/// **It exists because `Set<DateTime>` is a trap in this file** (A14c §16.3).
/// `DateTime.==` compares microseconds *and `isUtc`*, and the salon-time seam
/// hands out UTC-flagged date-only values — `salonToday` ends
/// `return DateTime.utc(s.year, s.month, s.day)` (`salon_time.dart:74`) — while
/// this grid builds its cells local. A `Set<DateTime>` seeded from `salonToday`
/// therefore **contains nothing**, silently: no error, no clue, every day
/// unselected. Measured red before this type existed.
///
/// A14e makes it worse rather than better: it seeds the set from
/// `availability.blockedDates` through `toSalonTime`, which returns a
/// `TZDateTime` — a **third** flavour of the same day.
///
/// [isSameDay] already solved the single-day case by comparing fields. This is
/// the same answer in a shape a `Set` and a `Map` can use. It stays in this file
/// beside [isSameDay] for the same reason that helper does; it moves to
/// `core/utils/` the day a second family wants it, not before.
@immutable
class CalendarDay implements Comparable<CalendarDay> {
  const CalendarDay(this.year, this.month, this.day);

  CalendarDay.of(DateTime d) : year = d.year, month = d.month, day = d.day;

  final int year;
  final int month;
  final int day;

  /// Local midnight on this day — what [MyweliMonthGrid] hands to `onDayTap`,
  /// and what a caller feeds to `Formatters`.
  ///
  /// **Never what a caller persists.** A stored instant goes through
  /// `salonDateTime(year, month, day, tz:)`, because only the call site knows
  /// the salon's zone (§18). Composing a `DateTime` here would be device-local,
  /// which is the exact shape `availability_screen` got wrong once already.
  DateTime toDateTime() => DateTime(year, month, day);

  bool isBefore(CalendarDay other) => compareTo(other) < 0;

  @override
  int compareTo(CalendarDay o) => year != o.year
      ? year.compareTo(o.year)
      : month != o.month
      ? month.compareTo(o.month)
      : day.compareTo(o.day);

  @override
  bool operator ==(Object other) =>
      other is CalendarDay &&
      other.year == year &&
      other.month == month &&
      other.day == day;

  @override
  int get hashCode => Object.hash(year, month, day);

  @override
  String toString() => 'CalendarDay($year-$month-$day)';
}

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
    this.shrinkWrap = false,
  });

  final int selectedYear;
  final int firstYear;
  final int lastYear;
  final ValueChanged<int> onPick;

  /// Sizes to its content instead of filling a bounded box. Set by
  /// [MyweliMonthNavigator.shrinkWrap]; the physics go with it, because a
  /// shrink-wrapped list inside another scrollable must not scroll itself.
  final bool shrinkWrap;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: AppTheme.spacingS),
      shrinkWrap: shrinkWrap,
      physics: shrinkWrap ? const NeverScrollableScrollPhysics() : null,
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
    this.selectedDays = const <CalendarDay>{},
    this.today,
    this.firstDate,
    this.lastDate,
    this.markers,
  });

  /// Any day in the month to render; only its year and month are read.
  final DateTime month;

  final ValueChanged<DateTime> onDayTap;

  /// The chosen days. Empty means nothing chosen.
  ///
  /// **One selection concept, not two** (§17.1). A `selectedDay` alongside a
  /// `selectedDays` would need an `assert` to keep them apart and would cost
  /// every future reader the question "which one wins". The migration was three
  /// lines, because the grid has exactly one caller and the navigator two.
  ///
  /// The **toggle-vs-replace policy lives in the page**, which is the seam this
  /// file's header argues for: the picker pops on tap, A14e's multi-picker
  /// toggles a set, and the grid paints what it is told.
  final Set<CalendarDay> selectedDays;

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

  /// Day → the French phrase appended to that cell's accessibility label.
  ///
  /// A day present in the map gets **one dot** under its number; a day absent
  /// gets the reserved space and nothing in it.
  ///
  /// **Null is not the same as empty, and the difference is the cell's height.**
  /// Null turns the marker channel off, so the cell keeps A14a's geometry
  /// byte-for-byte — which is what leaves the two picker goldens alone. A
  /// non-null map, *even an empty one*, reserves the marker row on every cell in
  /// every month, so the card does not change height when a pro pages from a
  /// busy month to a quiet one.
  ///
  /// **Why a map and not a `Set` or a predicate.** The value carries what the
  /// day announces, so "is it marked" and "what does it say" are one lookup
  /// rather than a predicate plus a second parameter. A `Set<CalendarDay>` would
  /// need `markerSemanticsLabel` beside it; a `String Function(DateTime)` would
  /// run 28–31 times per build and allocate a string per cell per frame.
  ///
  /// The caller builds it **once per data change**, not per build — see
  /// `appointment_calendar_view`, where doing it per build cost ~4,200 timezone
  /// conversions a frame.
  final Map<CalendarDay, String>? markers;

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
                      ? SizedBox(
                          height: _cellHeight(
                            context,
                            withMarker: markers != null,
                          ),
                        )
                      : _DayCell(
                          day: day,
                          selected: selectedDays.contains(CalendarDay.of(day)),
                          withMarker: markers != null,
                          markerLabel: markers?[CalendarDay.of(day)],
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
    this.selectedDays = const <CalendarDay>{},
    this.today,
    this.markers,
    this.shrinkWrap = false,
  });

  final DateTime initialMonth;
  final DateTime firstDate;
  final DateTime lastDate;
  final ValueChanged<DateTime> onDayTap;
  final Set<CalendarDay> selectedDays;
  final DateTime? today;

  /// Passed straight through to [MyweliMonthGrid.markers].
  final Map<CalendarDay, String>? markers;

  /// Whether the navigator is exactly as tall as its content.
  ///
  /// `false` (the default, and A14a/A14b's shape byte-for-byte): the grid
  /// scrolls inside the leftover box and the year list fills it. **Requires a
  /// bounded parent** — which is what a `Scaffold` body gives it.
  ///
  /// `true`: legal inside a scroll view or an unbounded `Column`. **Not a
  /// preference — a requirement.** A `Column` hands its non-flex children
  /// unbounded main-axis constraints, so the `Expanded`s below do not merely
  /// look wrong there, they throw *"RenderFlex children have non-zero flex but
  /// incoming height constraints are unbounded"*. The pro calendar sits exactly
  /// there, under `BrandRefresh`.
  ///
  /// **Its one visible cost, accepted rather than hidden:** in shrink-wrap mode
  /// the year list replaces the grid, and three `ListTile`s are shorter than six
  /// week rows — so the card jumps when the year toggle is pressed. One tap,
  /// reversible; the alternative is arithmetic on a widget that has no business
  /// knowing the grid's height. Photographed in a golden so it cannot drift.
  final bool shrinkWrap;

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
    // **The page inset belongs to the page, not to the grid.**
    //
    // Full-screen (`shrinkWrap: false`) this is the picker's own page padding:
    // 360 − 2×`spacingM` = 328 over seven columns = **46.86dp**, which is the
    // width A14a's arithmetic is built on (a two-digit day needs 36.9dp at 2×
    // inside the cell's 8dp margin, so the column must be ≥ 44.9).
    //
    // Embedded (`shrinkWrap: true`) the host already contributes an inset, and
    // re-applying the page's would triple-count it. Measured on the pro
    // calendar: card margin 16 + card padding 16 + this 16 = 48 a side, leaving
    // **37.7dp** a column — so « 15 » wrapped to two lines at 2× and the cell
    // overflowed by exactly 40dp. `spacingS` here, `spacingS` on the card, and
    // the embedded column is 46.86 again — the same number the picker gets.
    final gridPadding = EdgeInsets.symmetric(
      horizontal: widget.shrinkWrap ? AppTheme.spacingS : AppTheme.spacingM,
      vertical: AppTheme.spacingS,
    );

    /// `Expanded` when the parent bounds us, the bare child when it does not.
    /// One tree, two height models — see [MyweliMonthNavigator.shrinkWrap].
    Widget fit(Widget child) =>
        widget.shrinkWrap ? child : Expanded(child: child);

    final grid = MyweliMonthGrid(
      month: _month,
      selectedDays: widget.selectedDays,
      today: widget.today,
      firstDate: widget.firstDate,
      lastDate: widget.lastDate,
      markers: widget.markers,
      onDayTap: widget.onDayTap,
    );

    return Column(
      mainAxisSize: widget.shrinkWrap ? MainAxisSize.min : MainAxisSize.max,
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
          fit(
            MyweliYearList(
              selectedYear: _month.year,
              firstYear: widget.firstDate.year,
              lastYear: widget.lastDate.year,
              shrinkWrap: widget.shrinkWrap,
              onPick: (y) => setState(() {
                _month = DateTime(y, _month.month);
                _pickingYear = false;
              }),
            ),
          )
        else ...[
          const MyweliWeekdayHeader(),
          fit(
            widget.shrinkWrap
                // No scroll view: a shrink-wrapped navigator is already inside
                // one (`BrandRefresh` on the pro calendar), and nesting two
                // vertical scrollables makes the inner one eat the outer's
                // pull-to-refresh gesture.
                ? Padding(padding: gridPadding, child: grid)
                : SingleChildScrollView(padding: gridPadding, child: grid),
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
///
/// **The line comes from `AppTheme.scaledLine` now, and that is a fix rather
/// than a tidy-up.** A14a inlined `scale(fontSize × height)`, which is only the
/// right answer under a linear scaler — and every gate here uses one. A14c
/// §16.1 measured the cell at **65.6dp holding a 72dp line** under a non-linear
/// curve: the day number painting over the weeks above and below, with the 4dp
/// of breathing room this docstring promises silently gone.
double _cellHeight(
  BuildContext context, {
  required bool withMarker,
}) => math.max(
  AppTheme.spacingXXL,
  AppTheme.scaledLine(context, _dayStyle) +
      AppTheme.spacingS +
      // The marker's own row: the dot plus the gap above it. Reserved whenever
      // the channel is on, marked or not, so a card does not change height
      // between a busy month and a quiet one.
      (withMarker ? AppTheme.spacingS : 0),
);

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.selected,
    required this.isToday,
    required this.enabled,
    required this.onPick,
    required this.withMarker,
    required this.markerLabel,
  });

  final DateTime day;
  final bool selected;
  final bool isToday;
  final bool enabled;
  final ValueChanged<DateTime> onPick;

  /// Whether this grid reserves the marker row at all. See [MyweliMonthGrid.markers].
  final bool withMarker;

  /// What this day's marker announces, or null for « nothing here ».
  final String? markerLabel;

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
      // **The count lives here and nowhere else.** `_WeekStrip` already tried
      // encoding it in pixels — `width: 3 + count.clamp(0, 5), height: 4,
      // shape: BoxShape.circle` — and `BoxShape.circle` paints
      // `drawCircle(center, rect.shortestSide / 2)`, so the shortest side is 4
      // for every count and one appointment paints the same dot as five. Only
      // an invisible box widened. In speech it costs no pixels and reads
      // exactly: « 3 rendez-vous, jeudi 19 mars 2026 ».
      label: [
        if (isToday) 'aujourd’hui',
        Formatters.formatDate(day),
        ?markerLabel,
      ].join(', '),
      child: GestureDetector(
        // The whole cell is the target — §13.2's floor is met on the axis a
        // 7-column grid can meet it on, and `opaque` makes the padding count.
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? () => onPick(day) : null,
        child: Container(
          height: _cellHeight(context, withMarker: withMarker),
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
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('${day.day}', style: _dayStyle.copyWith(color: fg)),
                if (withMarker) ...[
                  const SizedBox(height: AppTheme.spacingXS),
                  Container(
                    width: AppTheme.spacingXS,
                    height: AppTheme.spacingXS,
                    decoration: BoxDecoration(
                      // Null rather than a transparent colour: the row is real
                      // layout either way, and `null` says "no ink" where a
                      // transparent token would claim a colour it does not use.
                      color: markerLabel == null
                          ? null
                          : selected
                          ? AppColors.secondary
                          : AppColors.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
