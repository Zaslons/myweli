import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/colors.dart';

/// Caps the app's content column at [AppTheme.contentMaxWidth] (SYSTEM.md §10).
///
/// Wired into each app root's `MaterialApp.router(builder:)`, so it sits above
/// the `Router` and below `ScaffoldMessenger` — three lines, and no screen has
/// to know it exists.
///
/// ## What it does, and where
///
/// Below 720 it is the identity: a `ConstrainedBox(maxWidth: 720)` under a tight
/// 390 constraint passes it through, and a `Center` whose child already fills
/// the width changes nothing. So on every phone this app ships to, it costs a
/// widget and does nothing — which is the point. It earns its keep on a tablet,
/// a foldable, and a desktop window, where §10's rule applies: *"a 1000px-wide
/// line of French body copy is unreadable, and an `ElevatedButton` whose theme
/// says `minimumSize: Size(double.infinity, 48)` becomes a 1000px-wide button."*
///
/// The [ColoredBox] is not decoration. Above the `Navigator` there is nothing
/// painting the area outside the column, so without it the gutters are whatever
/// the window was cleared to.
///
/// ## Two consequences worth knowing before you move it
///
/// **Dialogs are capped**, because a dialog is a route under the `Navigator`,
/// which is under the builder. Desirable, and a no-op on a phone.
///
/// **So are SnackBars** — and the spec said otherwise, so this is worth spelling
/// out. `ScaffoldMessenger` does sit *above* the builder (`material/app.dart`),
/// but it is only the controller: the bar is rendered by `ScaffoldState` into
/// its own `_ScaffoldSlot.snackBar` and laid out against the **Scaffold's**
/// width (`scaffold.dart`). The Scaffold is under the builder, so the bar tracks
/// the content column. That was reviewed and kept — a floating bar aligned with
/// the column reads as belonging to it, and a 1400dp-wide bar on a stretched
/// window is the same defect §10 names for body copy. `content_width_test.dart`
/// measures it rather than trusting either account.
///
/// ## The admin app deliberately does NOT install this
///
/// `AdminScaffold` is a top-level `Row` with a 240dp sidebar, and seven
/// `AdminDataTable` call sites divide their width with `Expanded` columns and no
/// horizontal scroll anywhere. At 720 that leaves ~431dp for a five-column
/// table — truncation and overflow, not a scrollbar. §10 says it itself:
/// *"fine for the consumer app (its users hold phones) and wrong for admin."*
/// The exclusion is held by a negative source pin in
/// `test/a11y/content_width_test.dart`, not by this paragraph.
class ContentWidthCap extends StatelessWidget {
  const ContentWidthCap({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.background,
      child: Center(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final capped = math.min(
              constraints.maxWidth,
              AppTheme.contentMaxWidth,
            );
            final mq = MediaQuery.of(context);
            return ConstrainedBox(
              constraints: BoxConstraints(maxWidth: capped),
              // **`MediaQuery.size` has to follow the cap, or it lies.**
              //
              // `MaterialApp` publishes the WINDOW size, and this widget then
              // makes the tree narrower without telling anyone — so a screen
              // that sizes itself from `MediaQuery` reads 1200 while its box is
              // 720. Measured, not assumed: `content_width_test.dart` pumps a
              // 1200dp window and the mismatch was exactly that.
              //
              // Two screens were already wrong because of it, and both are the
              // kind a gate never sees:
              //
              //   · `story_viewer.dart` splits prev/next at `size.width * 0.35`
              //     against a LOCAL tap x. Uncorrected, the back zone becomes
              //     58% of the visible story and a tap just left of centre goes
              //     BACKWARDS.
              //   · `_FullScreenGallery` sizes its image from `size`, so the
              //     photo overflowed its own 720dp dialog and `InteractiveViewer`
              //     panned a mis-sized child.
              //
              // Only `size` is overridden. `padding`, `viewInsets` and
              // `viewPadding` stay the window's: the keyboard and the status bar
              // are still where the OS put them, and the column is full height.
              child: MediaQuery(
                data: mq.copyWith(size: Size(capped, mq.size.height)),
                child: child,
              ),
            );
          },
        ),
      ),
    );
  }
}
