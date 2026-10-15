import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/text_styles.dart';

/// « Votre accès à {salon} a été retiré. » — the revoked-access notice (module
/// `access` R4b §5.3), shared by the sign-in screen and the rejoin gate
/// (docs/design/pro-rejoin-gate.md §3).
///
/// A live region: on the sign-in screen it appears AFTER the first frame —
/// read from the auth provider's one-shot notice, or in place after a sign-in
/// that the revocation ended (S11) — away from where focus is, so a screen
/// reader is told why it is still on this screen (SYSTEM.md §15).
class RevokedAccessBanner extends StatelessWidget {
  const RevokedAccessBanner({super.key, required this.salonName});

  /// The salon the access was lost to. `ProAuthProvider.salonName`'s
  /// fallback « votre salon » (no salon known) reads « ce salon ».
  final String salonName;

  String get _message => salonName == 'votre salon'
      ? 'Votre accès à ce salon a été retiré.'
      : 'Votre accès à $salonName a été retiré.';

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(AppTheme.spacingM),
        decoration: BoxDecoration(
          color: AppColors.error.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
          border: Border.all(color: AppColors.error.withValues(alpha: 0.4)),
        ),
        child: Row(
          children: [
            const Icon(Icons.person_off_outlined, color: AppColors.error),
            const SizedBox(width: AppTheme.spacingS),
            Expanded(
              child: Text(
                _message,
                style: AppTextStyles.bodyMedium.copyWith(
                  color: AppColors.error,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
