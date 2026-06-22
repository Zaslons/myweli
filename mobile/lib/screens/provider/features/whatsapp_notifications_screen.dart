import 'package:flutter/material.dart';

import '../../../core/config/feature_flags.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/text_styles.dart';
import '../../../widgets/common/coming_soon_scaffold.dart';

class WhatsAppNotificationsScreen extends StatelessWidget {
  const WhatsAppNotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    if (!FeatureFlags.futureProviderFeatures) {
      return const ComingSoonScaffold();
    }
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Notifications WhatsApp'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {},
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppTheme.spacingM),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Statistics Banner
            Container(
              padding: const EdgeInsets.all(AppTheme.spacingM),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
                border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.trending_down,
                      color: Colors.green, size: 32),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '60% de retards en moins',
                          style: AppTextStyles.titleMedium.copyWith(
                            color: Colors.green.shade700,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'Grâce aux rappels automatiques',
                          style: AppTextStyles.bodySmall.copyWith(
                            color: Colors.green.shade700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Notifications gratuites via WhatsApp',
              style: AppTextStyles.headlineMedium.copyWith(
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Automatisez les notifications et rappelez aux clients leur visite à l\'avance. Les notifications push gratuites via WhatsApp vous aideront à économiser.',
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Économisez sur les SMS et chatbots à partir de 3,500 FCFA par mois*. Envoyez gratuitement des rappels de rendez-vous, invitations de retour et messages d\'anniversaire.',
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.textTertiary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '* Lors de l\'envoi de 140 SMS par semaine',
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.textTertiary,
                fontStyle: FontStyle.italic,
              ),
            ),
            const SizedBox(height: 24),
            // Notification Settings
            Text(
              'Paramètres de notification',
              style: AppTextStyles.titleLarge.copyWith(
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            const _NotificationSettingItem(
              title: 'Rappel de rendez-vous',
              description: 'Envoyer 24h avant le rendez-vous',
              isEnabled: true,
            ),
            const SizedBox(height: 8),
            const _NotificationSettingItem(
              title: 'Confirmation de réservation',
              description: 'Envoyer immédiatement après réservation',
              isEnabled: true,
            ),
            const SizedBox(height: 8),
            const _NotificationSettingItem(
              title: 'Invitation de retour',
              description: 'Envoyer 7 jours après la dernière visite',
              isEnabled: true,
            ),
            const SizedBox(height: 8),
            const _NotificationSettingItem(
              title: 'Message d\'anniversaire',
              description: 'Envoyer le jour de l\'anniversaire',
              isEnabled: false,
            ),
            const SizedBox(height: 24),
            // Message Templates
            Text(
              'Modèles de messages',
              style: AppTextStyles.titleLarge.copyWith(
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            const _MessageTemplateCard(
              title: 'Rappel de rendez-vous',
              message:
                  'Bonjour ! Vous avez un rendez-vous demain à 16:00. Nous vous attendons ✨. Détails: Coupe + Coloration',
              time: '6 septembre 2024',
            ),
            const SizedBox(height: 12),
            const _MessageTemplateCard(
              title: 'Offre promotionnelle',
              message:
                  'Complexe classique pour seulement 3,000 FCFA. Manicure 💅, pédicure 🦶, vernis...',
              time: '11:00',
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () {},
              icon: const Icon(Icons.add),
              label: const Text('Créer un nouveau modèle'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppTheme.spacingL,
                  vertical: AppTheme.spacingM,
                ),
                minimumSize: const Size(double.infinity, 48),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NotificationSettingItem extends StatelessWidget {
  final String title;
  final String description;
  final bool isEnabled;

  const _NotificationSettingItem({
    required this.title,
    required this.description,
    required this.isEnabled,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppTheme.spacingM),
      decoration: BoxDecoration(
        color: AppColors.secondary,
        borderRadius: BorderRadius.circular(AppTheme.radiusXL),
        boxShadow: AppTheme.elevation1,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTextStyles.titleMedium.copyWith(
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: isEnabled,
            onChanged: (_) {},
            activeThumbColor: AppColors.primary,
          ),
        ],
      ),
    );
  }
}

class _MessageTemplateCard extends StatelessWidget {
  final String title;
  final String message;
  final String time;

  const _MessageTemplateCard({
    required this.title,
    required this.message,
    required this.time,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppTheme.spacingM),
      decoration: BoxDecoration(
        color: AppColors.secondary,
        borderRadius: BorderRadius.circular(AppTheme.radiusXL),
        boxShadow: AppTheme.elevation1,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: AppTextStyles.titleMedium.copyWith(
                  color: AppColors.textPrimary,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.edit),
                onPressed: () {},
              ),
            ],
          ),
          const SizedBox(height: 12),
          // WhatsApp Message Mockup
          Container(
            padding: const EdgeInsets.all(AppTheme.spacingM),
            decoration: BoxDecoration(
              color: Colors.green.shade50,
              borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
              border: Border.all(color: Colors.green.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: Colors.green,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(
                        Icons.business,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Salon Excellence',
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: Colors.green.shade900,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  message,
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: Colors.green.shade900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  time,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: Colors.green.shade700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
