import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/text_styles.dart';
import '../common/app_button.dart';

/// Pre-permission rationale shown at the first appropriate moment (consumer:
/// after the first booking; pro: first dashboard visit). Returns true if the
/// user chose to enable (→ trigger the OS prompt), false if they deferred or
/// dismissed. Copy defaults to the consumer wording; pass [title]/[body] to
/// override. Design: docs/design/push-notifications-app.md.
Future<bool> showPushPermissionSheet(
  BuildContext context, {
  String title = 'Activer les notifications',
  String body = 'Recevez vos rappels et confirmations de rendez-vous, et soyez '
      'prévenu·e dès que votre salon répond.',
}) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _PushPermissionSheet(title: title, body: body),
  );
  return result ?? false;
}

class _PushPermissionSheet extends StatelessWidget {
  const _PushPermissionSheet({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.secondary,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppTheme.radiusXXL),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppTheme.spacingL,
            AppTheme.spacingS,
            AppTheme.spacingL,
            AppTheme.spacingL,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.divider,
                    borderRadius: BorderRadius.circular(AppTheme.radiusPill),
                  ),
                ),
              ),
              const SizedBox(height: AppTheme.spacingL),
              const Icon(
                Icons.notifications_active_outlined,
                size: 40,
                color: AppColors.textPrimary,
              ),
              const SizedBox(height: AppTheme.spacingM),
              Text(
                title,
                style: AppTextStyles.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppTheme.spacingS),
              Text(
                body,
                style: AppTextStyles.bodyMedium.copyWith(
                  color: AppColors.textSecondary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppTheme.spacingL),
              AppButton(
                text: 'Activer',
                onPressed: () => Navigator.of(context).pop(true),
              ),
              const SizedBox(height: AppTheme.spacingS),
              AppButton(
                text: 'Plus tard',
                type: AppButtonType.text,
                onPressed: () => Navigator.of(context).pop(false),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
