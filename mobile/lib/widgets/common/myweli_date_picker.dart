import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/text_styles.dart';
import '../../core/utils/formatters.dart';
import 'app_button.dart';
import 'confirm_dialog.dart';
import 'myweli_month_grid.dart';

/// The house date picker (A14, SYSTEM.md §21 row 73).
///
/// **Why we own this.** At 200% text scale Material's `showDatePicker` renders
/// two-digit days as a single digit — measured at « 20 » having **35.4dp and
/// needing 36.9** on a 360dp phone. It is 1.5dp.
///
/// **Correction, from the adversarial review.** The first version of this
/// comment — and row 73 itself — said the defect was *"unreachable from the
/// outside"* because our theme *"never sets a `dayStyle`"*. That is wrong:
/// `calendar_date_picker.dart:1174` reads
/// `datePickerTheme.dayStyle ?? defaults.dayStyle`, so `dayStyle` **is**
/// reachable, and one line in `AppTheme` would have cleared the 1.5dp.
///
/// It would have cleared it **by shrinking the day number** — M3's default is
/// `bodyLarge` (16sp), so the only theme-level fix is a smaller font. That is
/// the one remedy §13.3 forbids in terms, and the one row 73's own sentence
/// (*"more width, never a smaller font"*) rules out. So the honest statement is
/// not "unreachable" but **"reachable only by doing the forbidden thing"** —
/// and inside a dialog Material insets on every side, more width is not
/// available.
///
/// That distinction is not pedantry: A14a's own first draft took the forbidden
/// route by accident, and the review caught it.
///
/// **Three decisions carry the fix, and each is arithmetic rather than taste.**
///
/// 1. **A full-screen route, not a dialog.** Worth stating plainly that this
///    alone buys almost nothing: a 360dp page yields ~46.9dp per column against
///    the dialog's ~46. Seven columns of a 360dp screen is seven columns of a
///    360dp screen. What it buys is a container that cannot shrink further and
///    a body with room to grow downwards.
/// 2. **The day cell is a rounded rectangle, never a circle.** This is the fix,
///    and it now lives in [MyweliMonthGrid] where the arithmetic is recorded.
/// 3. **The cell's height grows with the text and its width does not.** Seven
///    48dp targets need 336dp plus padding, which no 360dp phone has, so §13.2's
///    floor is unreachable horizontally for *any* month grid. Height is floored
///    at 48 and the whole cell is tappable; the width is grid-bound.
///
/// **The grid moved out in A14b.** A14a built the bar, the weekday row and the
/// cells private to this file, which made them unusable by the two surfaces
/// that want a month without a page around it — the combined date-and-time
/// control and (in A14c) the pro calendar. They are now
/// `myweli_month_grid.dart`, and this file is the *page*: a route, a title, and
/// the decision to pop on tap.
///
/// Tapping a day selects **and pops** — one tap, not two. The five call sites
/// all want a date and nothing else, and Material's OK/Cancel pair existed to
/// confirm a selection the user could not otherwise see.
Future<DateTime?> showMyweliDatePicker({
  required BuildContext context,
  required DateTime initialDate,
  required DateTime firstDate,
  required DateTime lastDate,
  DateTime? today,
  String? helpText,
}) {
  assert(
    !lastDate.isBefore(firstDate),
    'lastDate ($lastDate) is before firstDate ($firstDate) — the picker would '
    'show a range with no selectable day in it',
  );
  return Navigator.of(context).push<DateTime>(
    MaterialPageRoute<DateTime>(
      fullscreenDialog: true,
      builder: (_) => MyweliDatePickerScreen(
        initialDate: initialDate,
        firstDate: firstDate,
        lastDate: lastDate,
        today: today,
        helpText: helpText,
      ),
    ),
  );
}

/// **Clamps [initialDate] into `[firstDate, lastDate]`.**
///
/// An out-of-range `initialDate` is reachable today: rescheduling a PAST
/// appointment passes its own date while `firstDate` is today, so the picker
/// would open on a month where every day is disabled and the back chevron is
/// off — a silent dead end whose only exit is one forward tap per elapsed
/// month. Material asserted and crashed in debug; this lands the user on the
/// nearest legal month.
///
/// Shared with [MyweliDateTimePickerScreen], which inherits the same hazard
/// through the same reschedule flow.
DateTime clampToRange(DateTime initial, DateTime first, DateTime last) =>
    initial.isBefore(first)
    ? first
    : initial.isAfter(last)
    ? last
    : initial;

/// The picker's screen. Public so tests can pump it without a route.
class MyweliDatePickerScreen extends StatelessWidget {
  const MyweliDatePickerScreen({
    super.key,
    required this.initialDate,
    required this.firstDate,
    required this.lastDate,
    this.today,
    this.helpText,
  });

  final DateTime initialDate;
  final DateTime firstDate;
  final DateTime lastDate;

  /// The salon's today, for the « aujourd'hui » marker. Passed in rather than
  /// read — see [MyweliMonthGrid.today].
  final DateTime? today;

  /// The screen's title. `weekly_hours_editor.dart` is the only picker caller
  /// in the app that passes one today, and the house API keeps that affordance.
  final String? helpText;

  @override
  Widget build(BuildContext context) {
    final initial = clampToRange(initialDate, firstDate, lastDate);
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close, size: AppTheme.iconM),
          tooltip: 'Fermer',
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(helpText ?? 'Choisir une date'),
      ),
      body: SafeArea(
        child: MyweliMonthNavigator(
          initialMonth: initial,
          firstDate: firstDate,
          lastDate: lastDate,
          selectedDays: {CalendarDay.of(initial)},
          today: today,
          onDayTap: (d) => Navigator.of(context).pop(d),
        ),
      ),
    );
  }
}

/// What a multi-select CHANGED — never what it holds (A14e).
///
/// **A delta, not a set, and the reason is a silent data loss.** The
/// multi-picker's `firstDate` is the salon's today, so `MyweliMonthGrid._enabled`
/// refuses every earlier day: a past blocked date cannot be selected, and
/// seeding one would paint it selected and inert. A caller handed a full set
/// would have to remember to re-merge the days the picker never showed — and
/// forgetting means deleting them, permanently, with no error and nothing on
/// screen to notice. A delta cannot express the days it did not show.
typedef DaySelectionDelta = ({
  Set<CalendarDay> added,
  Set<CalendarDay> removed,
});

/// Pick several days at once, and report only what changed.
///
/// Mirrors [showMyweliDatePicker]'s shape — a full-screen route, a close
/// leading, a `MyweliMonthNavigator` — with the one difference that makes it a
/// different control: **it cannot pop on tap.** A tap toggles; the commit is an
/// explicit button, because selecting is not submitting.
///
/// Returns null on dismiss. An empty delta is impossible: the button that
/// produces one is disabled.
Future<DaySelectionDelta?> showMyweliMultiDatePicker({
  required BuildContext context,
  required Set<CalendarDay> initialSelection,
  required DateTime firstDate,
  required DateTime lastDate,
  DateTime? today,
  String? helpText,
}) {
  assert(
    !lastDate.isBefore(firstDate),
    'lastDate ($lastDate) is before firstDate ($firstDate) — the picker would '
    'show a range with no selectable day in it',
  );
  return Navigator.of(context).push<DaySelectionDelta>(
    MaterialPageRoute<DaySelectionDelta>(
      fullscreenDialog: true,
      builder: (_) => MyweliMultiDatePickerScreen(
        initialSelection: initialSelection,
        firstDate: firstDate,
        lastDate: lastDate,
        today: today,
        helpText: helpText,
      ),
    ),
  );
}

/// The multi-picker's screen. Public so tests can pump it without a route.
class MyweliMultiDatePickerScreen extends StatefulWidget {
  const MyweliMultiDatePickerScreen({
    super.key,
    required this.initialSelection,
    required this.firstDate,
    required this.lastDate,
    this.today,
    this.helpText,
  });

  /// The days already chosen, **restricted to the picker's own range** by the
  /// caller. A day outside `[firstDate, lastDate]` would render selected and
  /// disabled — `primary` fill under `textTertiary` ink, with a dead tap — so
  /// the invariant is asserted rather than documented.
  final Set<CalendarDay> initialSelection;
  final DateTime firstDate;
  final DateTime lastDate;
  final DateTime? today;
  final String? helpText;

  @override
  State<MyweliMultiDatePickerScreen> createState() =>
      _MyweliMultiDatePickerScreenState();
}

class _MyweliMultiDatePickerScreenState
    extends State<MyweliMultiDatePickerScreen> {
  late final Set<CalendarDay> _initial;
  late Set<CalendarDay> _selected;

  @override
  void initState() {
    super.initState();
    _initial = {...widget.initialSelection};
    _selected = {...widget.initialSelection};
    assert(
      _initial.every((d) => !d.isBefore(CalendarDay.of(widget.firstDate))),
      'a seeded day sits before firstDate, so the grid will paint it selected '
      'and refuse to toggle it — restrict the seed to the visible range',
    );
  }

  /// The whole point of the screen, computed once at pop.
  DaySelectionDelta get _delta => (
    added: _selected.difference(_initial),
    removed: _initial.difference(_selected),
  );

  bool get _changed => _delta.added.isNotEmpty || _delta.removed.isNotEmpty;

  void _toggle(DateTime day) {
    // `onDayTap` hands a LOCAL DateTime — `CalendarDay.toDateTime()`'s own
    // docstring calls that "never what a caller persists". Convert immediately
    // so no `DateTime` ever enters the selection.
    final d = CalendarDay.of(day);
    setState(
      () => _selected.contains(d) ? _selected.remove(d) : _selected.add(d),
    );
  }

  Future<void> _exit() async {
    if (!_changed) {
      Navigator.of(context).pop();
      return;
    }
    // The single picker had nothing to lose on dismiss; this one can lose ten
    // taps. `isDestructive: false` — abandoning an edit is not destroying data.
    final leave = await showConfirmDialog(
      context,
      title: 'Abandonner les modifications ?',
      message:
          'Les dates que vous venez de choisir ne seront pas enregistrées.',
      confirmLabel: 'Abandonner',
      cancelLabel: 'Continuer',
      icon: Icons.close,
      isDestructive: false,
    );
    if (leave && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_changed,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _exit();
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.close, size: AppTheme.iconM),
            tooltip: 'Fermer',
            onPressed: _exit,
          ),
          title: Text(widget.helpText ?? 'Choisir des dates'),
          actions: [
            // Undoes THIS session's taps — never a bulk unblock of stored data.
            if (_changed)
              TextButton(
                onPressed: () => setState(() => _selected = {..._initial}),
                child: const Text('Réinitialiser'),
              ),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: MyweliMonthNavigator(
                  initialMonth: clampToRange(
                    widget.today ?? widget.firstDate,
                    widget.firstDate,
                    widget.lastDate,
                  ),
                  firstDate: widget.firstDate,
                  lastDate: widget.lastDate,
                  // NO `markers:` — a non-null map reserves a marker row on
                  // every cell and changes its height. « Already blocked » and
                  // « just chosen » are the SAME fact here (this day will be
                  // blocked when I save), so one paint says both, and a marker
                  // derived from data being edited would go stale on the first
                  // tap.
                  selectedDays: _selected,
                  today: widget.today,
                  onDayTap: _toggle,
                ),
              ),
              _SelectionSummaryBar(
                selected: _selected.length,
                delta: _delta,
                // Gated on the DELTA, never on `_selected.isEmpty` — the naive
                // gate makes « tout débloquer » unreachable, because the pro
                // deselects their last day and the button dies.
                onSave: _changed
                    ? () => Navigator.of(context).pop(_delta)
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// State on one line, the change on the next, the act in a button below.
///
/// A `Column`, never a `Row` with the button beside it: `slot_picker.dart`
/// records the same §13.3 lesson — a sentence plus an action on one line is
/// the shape that clips at 200%.
class _SelectionSummaryBar extends StatelessWidget {
  const _SelectionSummaryBar({
    required this.selected,
    required this.delta,
    required this.onSave,
  });

  final int selected;
  final DaySelectionDelta delta;
  final VoidCallback? onSave;

  @override
  Widget build(BuildContext context) {
    final parts = [
      if (delta.added.isNotEmpty)
        Formatters.count(delta.added.length, 'ajoutée', 'ajoutées'),
      if (delta.removed.isNotEmpty)
        Formatters.count(delta.removed.length, 'retirée', 'retirées'),
    ];
    final state = selected == 0 && delta.removed.isNotEmpty
        ? 'Toutes vos dates bloquées seront retirées.'
        : selected == 0
        ? 'Touchez les jours à bloquer.'
        : Formatters.count(selected, 'date bloquée', 'dates bloquées');

    return Padding(
      padding: const EdgeInsets.all(AppTheme.spacingM),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The cell announces itself on tap; the COUNT does not, and the count
          // is what the button acts on.
          Semantics(
            liveRegion: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  state,
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: AppColors.textPrimary,
                  ),
                ),
                if (parts.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: AppTheme.spacingXS),
                    child: Text(
                      parts.join(' · '),
                      style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppTheme.spacingS),
          AppButton(text: 'Enregistrer', onPressed: onSave, isFullWidth: true),
        ],
      ),
    );
  }
}
