import 'package:flutter/material.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/text_styles.dart';
import '../../../core/theme/app_theme.dart';

class OnlineBookingScreen extends StatelessWidget {
  const OnlineBookingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Réservation en ligne'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppTheme.spacingM),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Info Banner
            Container(
              padding: const EdgeInsets.all(AppTheme.spacingM),
              decoration: BoxDecoration(
                color: Colors.amber.withOpacity(0.1),
                borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
                border: Border.all(color: Colors.amber.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.amber.shade700),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Apporte 12% de réservations en plus',
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: Colors.amber.shade900,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Réservation en ligne dans votre design',
              style: AppTextStyles.headlineMedium.copyWith(
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Créez un formulaire de réservation en ligne dans votre style. Placez-le sur 10+ plateformes populaires : cartes, réseaux sociaux. Les clients pourront réserver même la nuit.',
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 24),
            // Color Customization
            Text(
              'Personnalisation des couleurs',
              style: AppTextStyles.titleLarge.copyWith(
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(AppTheme.spacingL),
              decoration: BoxDecoration(
                color: AppColors.secondary,
                borderRadius: BorderRadius.circular(AppTheme.radiusXL),
                boxShadow: AppTheme.elevation1,
              ),
              child: Column(
                children: [
                  // Color Preview
                  Container(
                    height: 120,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [AppColors.primary, AppColors.primary.withOpacity(0.7)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Color Picker Mockup
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          height: 50,
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                            border: Border.all(color: AppColors.border),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: TextField(
                          decoration: InputDecoration(
                            labelText: 'Code couleur',
                            hintText: '#675890',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton(
                        onPressed: () {},
                        child: const Text('Appliquer'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            // Preview Section
            Text(
              'Aperçu du widget',
              style: AppTextStyles.titleLarge.copyWith(
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(AppTheme.spacingM),
              decoration: BoxDecoration(
                color: AppColors.secondary,
                borderRadius: BorderRadius.circular(AppTheme.radiusXL),
                boxShadow: AppTheme.elevation2,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Mock Phone Preview
                  Container(
                    padding: const EdgeInsets.all(AppTheme.spacingM),
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Salon Excellence',
                              style: AppTextStyles.titleMedium.copyWith(
                                color: AppColors.primary,
                              ),
                            ),
                            Icon(Icons.check_circle, color: Colors.green, size: 20),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Cocody, Angré 7ème Tranche',
                          style: AppTextStyles.bodySmall.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 16),
                        // Service Categories
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              _CategoryChip('Coupe', isSelected: true),
                              const SizedBox(width: 8),
                              _CategoryChip('Coloration'),
                              const SizedBox(width: 8),
                              _CategoryChip('Manucure'),
                              const SizedBox(width: 8),
                              _CategoryChip('Massage'),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(AppTheme.spacingM),
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.card_giftcard, color: AppColors.secondary),
                              const SizedBox(width: 8),
                              Text(
                                'Acheter un certificat ou abonnement',
                                style: AppTextStyles.bodyMedium.copyWith(
                                  color: AppColors.secondary,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Icon(Icons.arrow_forward, color: AppColors.secondary, size: 16),
                            ],
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
              'Plus de 100 études ont permis de rendre l\'interface du formulaire aussi conviviale et intuitive que possible.',
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.textTertiary,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  final String label;
  final bool isSelected;

  const _CategoryChip(this.label, {this.isSelected = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: isSelected ? AppColors.primary : AppColors.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        border: Border.all(
          color: isSelected ? AppColors.primary : AppColors.border,
        ),
      ),
      child: Text(
        label,
        style: AppTextStyles.bodyMedium.copyWith(
          color: isSelected ? AppColors.secondary : AppColors.textPrimary,
        ),
      ),
    );
  }
}
