import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/colors.dart';
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
          selectedDay: initial,
          today: today,
          onDayTap: (d) => Navigator.of(context).pop(d),
        ),
      ),
    );
  }
}
