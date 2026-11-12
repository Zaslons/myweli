import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/colors.dart';
import '../../../core/utils/validation_labels.dart';
import '../../../widgets/common/empty_state.dart';

/// « Salons à valider » on a server from before B0.18 (B0.18 —
/// docs/design/salon-go-live-approval.md §9.2: the console goes live before
/// the backend, so its routes answer 404 for a while).
///
/// Calm and explicit — the page exists, the server will catch up — never
/// « Chargement impossible », which would send the admin looking for a fault,
/// and no « Réessayer », which could not succeed until the deploy (SYSTEM.md
/// §12). The top bar's « Rafraîchir » is the way to look again.
class AdminValidationUnavailable extends StatelessWidget {
  const AdminValidationUnavailable({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.secondary,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.symmetric(vertical: AppTheme.spacingXL),
      child: const EmptyState(
        icon: Icons.schedule,
        title: ValidationLabels.unavailableTitle,
        description: ValidationLabels.unavailableBody,
      ),
    );
  }
}
