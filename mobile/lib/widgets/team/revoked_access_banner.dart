import 'package:flutter/material.dart';

import '../../core/constants/unnamed_salon.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/text_styles.dart';
import '../../core/utils/team_error_messages.dart';

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

  /// The salon the access was lost to. When `ProAuthProvider.salonName` has
  /// no name to give (its unnamed word, [kUnnamedOwnSalon]), the banner says
  /// the app's one sentence for a withdrawn access — the `not_a_member`
  /// refusal's — rather than « Votre accès à votre salon ».
  final String salonName;

  String get _message => salonName == kUnnamedOwnSalon
      ? teamErrorMessage('not_a_member')
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
