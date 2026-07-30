import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/text_styles.dart';
import 'app_snack_bar.dart';

/// Design: docs/design/mobile-a6-feedback.md · SYSTEM.md §15, §13.4.
///
/// Feedback raised while a bottom sheet or dialog is open **cannot be a
/// snackbar**: `ModalBarrier` renders `BlockSemantics(ExcludeSemantics(…))`,
/// so the bar is pruned from the semantics tree — a screen reader never hears
/// it — and it paints *under* the scrim (§10). A6 found six such sites; they
/// raise their message here instead, inside the modal that owns the failure.
///
/// It is a **live region** for the same reason a `SnackBar` is one: the message
/// appears away from focus, and this is the mechanism both platforms support
/// (`SemanticsService` is discouraged on Android — see `AppSnackBar`).
///
/// It borrows [SnackKind] deliberately: feedback speaks ONE vocabulary — the
/// same colour, the same glyph, the same meaning — whether it lands in a bar
/// or inside the modal that raised it.
class InlineFeedback extends StatelessWidget {
  const InlineFeedback(this.message, {super.key, this.kind = SnackKind.error});

  /// `null` renders nothing — so a caller can hold one nullable field and put
  /// this in its tree unconditionally.
  final String? message;

  final SnackKind kind;

  @override
  Widget build(BuildContext context) {
    final text = message;
    if (text == null) return const SizedBox.shrink();
    return Semantics(
      liveRegion: true,
      container: true,
      child: Padding(
        padding: const EdgeInsets.only(top: AppTheme.spacingS),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(kind.icon, size: AppTheme.iconS, color: kind.color),
            const SizedBox(width: AppTheme.spacingS),
            Expanded(
              child: Text(
                text,
                style: AppTextStyles.bodyMedium.copyWith(color: kind.color),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
