import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/config/app_config.dart';
import '../../../core/config/subscription_plans.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/text_styles.dart';
import '../../../core/utils/formatters.dart';
import '../../../models/subscription.dart';
import '../../../providers/pro_subscription_provider.dart';
import '../../../widgets/common/app_button.dart';
import '../../../widgets/common/loading_indicator.dart';

/// Provider "Mon abonnement" (FR-PRO-SUB-001): plan + trial status, Pro value &
/// indicative (anchor) pricing, and a contact CTA. Read-only — in-app billing is
/// deferred (PRD §6.3). Design: docs/design/pro-subscription.md.
class ProSubscriptionScreen extends StatefulWidget {
  const ProSubscriptionScreen({super.key});

  @override
  State<ProSubscriptionScreen> createState() => _ProSubscriptionScreenState();
}

class _ProSubscriptionScreenState extends State<ProSubscriptionScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ProSubscriptionProvider>().load();
    });
  }

  Future<void> _contact() async {
    final messenger = ScaffoldMessenger.of(context);
    final number = AppConfig.supportWhatsApp;
    if (number.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Contact bientôt disponible.')),
      );
      return;
    }
    final uri = Uri.parse(
      'https://wa.me/$number?text='
      '${Uri.encodeComponent('Bonjour Myweli, je souhaite passer à l\'offre Pro.')}',
    );
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Impossible d\'ouvrir WhatsApp.'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(title: const Text('Mon abonnement')),
      body: Consumer<ProSubscriptionProvider>(
        builder: (context, provider, _) {
          if (provider.isLoading) return const LoadingIndicator();

          if (provider.loadFailed || provider.subscription == null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(AppTheme.spacingL),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error_outline,
                        size: 64, color: AppColors.error),
                    const SizedBox(height: 16),
                    Text(
                      provider.error ?? 'Erreur lors du chargement',
                      textAlign: TextAlign.center,
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 16),
                    AppButton(
                      text: 'Réessayer',
                      type: AppButtonType.secondary,
                      onPressed: () => provider.load(),
                    ),
                  ],
                ),
              ),
            );
          }

          final sub = provider.subscription!;
          return ListView(
            padding: const EdgeInsets.all(AppTheme.spacingM),
            children: [
              _TrialBanner(sub: sub),
              const SizedBox(height: AppTheme.spacingM),
              _ProCard(onContact: _contact),
              const SizedBox(height: AppTheme.spacingM),
              const _FreeCard(),
              const SizedBox(height: AppTheme.spacingL),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.info_outline,
                      size: 18, color: AppColors.textTertiary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Les offres payantes arriveront au lancement. '
                      'Profitez de toutes les fonctionnalités Pro pendant '
                      'votre essai.',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _TrialBanner extends StatelessWidget {
  const _TrialBanner({required this.sub});
  final Subscription sub;

  @override
  Widget build(BuildContext context) {
    final trialing = sub.isTrialing;
    final title = trialing
        ? 'Essai gratuit — ${sub.trialDaysLeft} jour'
            '${sub.trialDaysLeft > 1 ? 's' : ''} restant'
            '${sub.trialDaysLeft > 1 ? 's' : ''}'
        : 'Essai terminé — offre Gratuite';
    final subtitle = trialing && sub.trialEndsAt != null
        ? 'Se termine le ${Formatters.formatDate(sub.trialEndsAt!)}'
        : 'Vous profitez de l\'offre Découverte (gratuite).';

    return Container(
      padding: const EdgeInsets.all(AppTheme.spacingL),
      decoration: BoxDecoration(
        color: trialing ? AppColors.successLight : AppColors.secondary,
        borderRadius: BorderRadius.circular(AppTheme.radiusXL),
        boxShadow: AppTheme.elevation1,
      ),
      child: Row(
        children: [
          Icon(
            trialing ? Icons.workspace_premium : Icons.info_outline,
            color: trialing ? AppColors.surface : AppColors.textSecondary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTextStyles.titleMedium.copyWith(
                    color: trialing ? AppColors.surface : AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: AppTextStyles.bodySmall.copyWith(
                    color:
                        trialing ? AppColors.surface : AppColors.textTertiary,
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

class _ProCard extends StatelessWidget {
  const _ProCard({required this.onContact});
  final VoidCallback onContact;

  @override
  Widget build(BuildContext context) {
    final anchor = Formatters.formatCurrency(
      SubscriptionPlans.proAnchorMonthlyFcfa.toDouble(),
    );
    return Container(
      padding: const EdgeInsets.all(AppTheme.spacingL),
      decoration: BoxDecoration(
        color: AppColors.secondary,
        borderRadius: BorderRadius.circular(AppTheme.radiusXL),
        border: Border.all(color: AppColors.primary),
        boxShadow: AppTheme.elevation1,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Pro', style: AppTextStyles.titleLarge),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '$anchor/mois',
                style: AppTextStyles.bodyMedium.copyWith(
                  color: AppColors.textTertiary,
                  decoration: TextDecoration.lineThrough,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Gratuit pendant ${SubscriptionPlans.trialMonths} mois',
                style: AppTextStyles.titleMedium.copyWith(
                  color: AppColors.successLight,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (final e in SubscriptionPlans.proEntitlements) _Check(text: e),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(AppTheme.spacingM),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
            ),
            child: Row(
              children: [
                const Icon(Icons.savings_outlined,
                    size: 18, color: AppColors.textSecondary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    SubscriptionPlans.roiLine,
                    style: AppTextStyles.bodySmall,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          AppButton(
            text: 'Nous contacter',
            icon: Icons.chat_outlined,
            onPressed: onContact,
          ),
        ],
      ),
    );
  }
}

class _FreeCard extends StatelessWidget {
  const _FreeCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppTheme.spacingL),
      decoration: BoxDecoration(
        color: AppColors.secondary,
        borderRadius: BorderRadius.circular(AppTheme.radiusXL),
        boxShadow: AppTheme.elevation1,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Découverte (Gratuit)', style: AppTextStyles.titleLarge),
          const SizedBox(height: 4),
          Text(
            'Pour démarrer — sans frais.',
            style: AppTextStyles.bodySmall.copyWith(
              color: AppColors.textTertiary,
            ),
          ),
          const SizedBox(height: 12),
          for (final e in SubscriptionPlans.freeEntitlements) _Check(text: e),
        ],
      ),
    );
  }
}

class _Check extends StatelessWidget {
  const _Check({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.check_circle_outline,
              size: 18, color: AppColors.successLight),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: AppTextStyles.bodyMedium)),
        ],
      ),
    );
  }
}
