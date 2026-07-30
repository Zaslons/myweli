import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/colors.dart';

/// Design: docs/design/mobile-a6-feedback.md · SYSTEM.md §15.
///
/// The KIND is the API — a call site never picks a colour or a duration. §15's
/// table, verbatim: success `success`/3s · info `textPrimary`/3s · error
/// `error`/**6s** (an error needs time to read).
///
/// The **icon is not decoration** (§13.6, and an A6 amendment to §15):
/// `success` (#2D5016, relative luminance 0.072) and `error` (#8B0000, 0.062)
/// are the same shade in greyscale, so hue alone cannot carry the outcome —
/// exactly the failure A4b fixed on the story ring. Colour + glyph = two cues.
enum SnackKind {
  success(AppColors.success, Icons.check_circle_outline, Duration(seconds: 3)),
  info(AppColors.textPrimary, Icons.info_outline, Duration(seconds: 3)),
  error(AppColors.error, Icons.error_outline, Duration(seconds: 6));

  const SnackKind(this.color, this.icon, this.duration);

  final Color color;
  final IconData icon;
  final Duration duration;
}

/// §15, as amended by A6: **10s when the snackbar is the ONLY route back**
/// (an undone delete). When the UI itself is the undo — the favourite heart is
/// one tap — the kind's own duration is right, and a 10s bar occluding the
/// screen on every heart tap is a cost with no benefit.
const Duration kSnackActionDuration = Duration(seconds: 10);

/// An action on a snackbar: an **undo** (§15's reversible rung) or a
/// navigation. [label] is a verb (§17).
@immutable
class SnackAction {
  const SnackAction({
    required this.label,
    required this.onPressed,
    this.isOnlyRouteBack = true,
  });

  final String label;
  final VoidCallback onPressed;

  /// `true` (the default) → the bar lives [kSnackActionDuration]; `false` →
  /// the kind's own duration, because the screen itself offers the way back.
  final bool isOnlyRouteBack;
}

/// The single entry point for feedback (SYSTEM.md §15, §11.3) — it replaced 117
/// hand-built snackbar calls, of which 73 were raw inline `SnackBar(...)`.
///
/// **Accessibility: there is nothing to add here.** Flutter already wraps every
/// `SnackBar` in `Semantics(container: true, liveRegion: true)`
/// (material/snack_bar.dart:831) — the supported announcement mechanism on both
/// platforms, and the ONLY one on Android, where
/// `AccessibilityFeatures.supportsAnnounce` is false and a direct announcement
/// clears TalkBack's speech queue. Do **not** add `SemanticsService` here: A6
/// deleted the six sites that did, because on iOS they double-spoke the live
/// region's own text. Proven by `test/a11y/feedback_test.dart`.
///
/// **A snackbar shown under an open dialog or sheet is invisible AND
/// unreachable** — `ModalBarrier` renders `BlockSemantics(ExcludeSemantics(…))`,
/// so the bar is pruned from the semantics tree and painted under the scrim
/// (§10). Feedback raised while a modal is open belongs INSIDE it, as an inline
/// error. A6 converted six such sites; the gate keeps them converted.
abstract final class AppSnackBar {
  /// The ergonomic form. **Before an `await`, capture the messenger and use
  /// [showOn]** — a `BuildContext` does not survive the gap.
  static void show(
    BuildContext context,
    String message, {
    SnackKind kind = SnackKind.info,
    SnackAction? action,
  }) =>
      showOn(
        ScaffoldMessenger.of(context),
        message,
        kind: kind,
        action: action,
      );

  /// The primitive. [messenger] is a `ScaffoldMessengerState` captured BEFORE
  /// an await — the idiom 38 call sites already had right.
  static void showOn(
    ScaffoldMessengerState messenger,
    String message, {
    SnackKind kind = SnackKind.info,
    SnackAction? action,
  }) {
    // The newest message wins instead of queueing behind a 6s error — the
    // mirror of the web's `useToast`, where a re-show resets the timer.
    messenger.removeCurrentSnackBar(reason: SnackBarClosedReason.remove);
    messenger.showSnackBar(
      SnackBar(
        // Everything else — float, radius, elevation, text style, action
        // colour — comes from `snackBarTheme` (app_theme.dart). This adds the
        // two things a ThemeData cannot express: the per-kind colour and the
        // per-kind duration.
        backgroundColor: kind.color,
        duration: action != null && action.isOnlyRouteBack
            ? kSnackActionDuration
            : kind.duration,
        content: Row(
          children: [
            Icon(
              kind.icon,
              size: AppTheme.iconS,
              color: AppColors.secondary,
              // No `semanticLabel` — an unlabelled Icon contributes no semantics
              // node at all, so the glyph is the second greyscale-surviving cue
              // without becoming a second thing to read out.
            ),
            const SizedBox(width: AppTheme.spacingS),
            Expanded(child: Text(message)),
          ],
        ),
        action: action == null
            ? null
            : SnackBarAction(label: action.label, onPressed: action.onPressed),
      ),
    );
  }

  /// The 18 DUAL-OUTCOME sites — one call, two messages. Before A6 the tone was
  /// hand-picked per branch, which is how 30 of 61 errors ended up not red and
  /// only 7 of 31 successes green.
  static void outcome(
    BuildContext context, {
    required bool ok,
    required String success,
    required String error,
    SnackAction? action,
  }) =>
      outcomeOn(
        ScaffoldMessenger.of(context),
        ok: ok,
        success: success,
        error: error,
        action: action,
      );

  static void outcomeOn(
    ScaffoldMessengerState messenger, {
    required bool ok,
    required String success,
    required String error,
    SnackAction? action,
  }) =>
      showOn(
        messenger,
        ok ? success : error,
        kind: ok ? SnackKind.success : SnackKind.error,
        action: action,
      );
}
