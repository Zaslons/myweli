import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/text_styles.dart';
import '../../../models/provider_user.dart';
import '../../../providers/pro_auth_provider.dart';
import '../../../widgets/common/app_button.dart';

class ProProfileScreen extends StatelessWidget {
  const ProProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Profil'),
      ),
      body: Consumer<ProAuthProvider>(
        builder: (context, authProvider, _) {
          if (!authProvider.isAuthenticated || authProvider.provider == null) {
            return const Center(child: Text('Veuillez vous connecter'));
          }

          final provider = authProvider.provider!;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(AppTheme.spacingL),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(AppTheme.spacingM),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Nom de l\'entreprise',
                          style: AppTextStyles.titleMedium
                              .copyWith(color: AppColors.textPrimary),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          provider.businessName,
                          style: AppTextStyles.bodyLarge
                              .copyWith(color: AppColors.textSecondary),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Type d\'entreprise',
                          style: AppTextStyles.titleMedium
                              .copyWith(color: AppColors.textPrimary),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _getBusinessTypeLabel(provider.businessType),
                          style: AppTextStyles.bodyLarge
                              .copyWith(color: AppColors.textSecondary),
                        ),
                        if (provider.address != null) ...[
                          const SizedBox(height: 16),
                          Text(
                            'Adresse',
                            style: AppTextStyles.titleMedium
                                .copyWith(color: AppColors.textPrimary),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            provider.address!,
                            style: AppTextStyles.bodyLarge
                                .copyWith(color: AppColors.textSecondary),
                          ),
                        ],
                        const SizedBox(height: 16),
                        Text(
                          'Téléphone',
                          style: AppTextStyles.titleMedium
                              .copyWith(color: AppColors.textPrimary),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          provider.phoneNumber,
                          style: AppTextStyles.bodyLarge
                              .copyWith(color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                AppButton(
                  text: 'Déconnexion',
                  type: AppButtonType.secondary,
                  onPressed: () async {
                    await authProvider.logout();
                    if (context.mounted) {
                      context.go('/pro/login');
                    }
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  String _getBusinessTypeLabel(BusinessType type) {
    switch (type) {
      case BusinessType.salon:
        return 'Salon de beauté';
      case BusinessType.barber:
        return 'Barbier';
      case BusinessType.spa:
        return 'Spa';
      case BusinessType.nailSalon:
        return 'Institut de manucure';
      case BusinessType.massage:
        return 'Massage';
      case BusinessType.other:
        return 'Autre';
    }
  }
}
