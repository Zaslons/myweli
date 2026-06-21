import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/text_styles.dart';
import '../../../core/utils/deposit.dart';
import '../../../core/utils/formatters.dart';
import '../../../providers/pro_deposit_settings_provider.dart';
import '../../../widgets/common/app_button.dart';
import '../../../widgets/common/empty_state.dart';
import '../../../widgets/common/loading_indicator.dart';

class DepositSettingsScreen extends StatefulWidget {
  final String providerId;

  const DepositSettingsScreen({super.key, required this.providerId});

  @override
  State<DepositSettingsScreen> createState() => _DepositSettingsScreenState();
}

class _DepositSettingsScreenState extends State<DepositSettingsScreen> {
  /// A representative service price used only to preview the split.
  static const double _sampleTotal = 20000;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ProDepositSettingsProvider>().load(widget.providerId);
    });
  }

  Future<void> _save() async {
    final provider = context.read<ProDepositSettingsProvider>();
    final ok = await provider.save(widget.providerId);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok ? 'Paramètres enregistrés' : (provider.error ?? 'Erreur'),
        ),
        backgroundColor: ok ? AppColors.success : AppColors.error,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Acompte')),
      body: Consumer<ProDepositSettingsProvider>(
        builder: (context, provider, _) {
          if (provider.isLoading) {
            return const LoadingIndicator();
          }
          if (provider.loadFailed) {
            return EmptyState(
              icon: Icons.wifi_off,
              title: 'Chargement impossible',
              description: 'Vérifiez votre connexion et réessayez.',
              actionText: 'Réessayer',
              onAction: () => provider.load(widget.providerId),
            );
          }
          return _buildForm(provider);
        },
      ),
    );
  }

  Widget _buildForm(ProDepositSettingsProvider provider) {
    final pct = (provider.depositPercentage * 100).round();
    final deposit = computeDeposit(
      total: _sampleTotal,
      depositRequired: provider.depositRequired,
      percentage: provider.depositPercentage,
    );
    final balance = _sampleTotal - deposit;

    return ListView(
      padding: const EdgeInsets.all(AppTheme.spacingM),
      children: [
        Container(
          decoration: BoxDecoration(
            color: AppColors.secondary,
            borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
            border: Border.all(color: AppColors.border),
          ),
          child: SwitchListTile(
            value: provider.depositRequired,
            onChanged: provider.setDepositRequired,
            title: const Text('Exiger un acompte'),
            subtitle: Text(
              'Limite les rendez-vous manqués',
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.textTertiary,
              ),
            ),
          ),
        ),
        if (provider.depositRequired) ...[
          const SizedBox(height: AppTheme.spacingM),
          Container(
            padding: const EdgeInsets.all(AppTheme.spacingM),
            decoration: BoxDecoration(
              color: AppColors.secondary,
              borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      "Pourcentage de l'acompte",
                      style: AppTextStyles.bodyMedium,
                    ),
                    Text('$pct %', style: AppTextStyles.titleMedium),
                  ],
                ),
                Slider(
                  value: provider.depositPercentage.clamp(0.05, 0.80),
                  min: 0.05,
                  max: 0.80,
                  divisions: 15,
                  label: '$pct %',
                  onChanged: provider.setDepositPercentage,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppTheme.spacingM),
          Container(
            padding: const EdgeInsets.all(AppTheme.spacingM),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Exemple sur une prestation de ${Formatters.formatCurrency(_sampleTotal)}',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Acompte payé en ligne',
                        style: AppTextStyles.bodyMedium),
                    Text(
                      Formatters.formatCurrency(deposit),
                      style: AppTextStyles.bodyMedium
                          .copyWith(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Solde au salon',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                    Text(
                      Formatters.formatCurrency(balance),
                      style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: AppTheme.spacingM),
        Container(
          padding: const EdgeInsets.all(AppTheme.spacingM),
          decoration: BoxDecoration(
            color: AppColors.secondary,
            borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Politique d'annulation",
                style: AppTextStyles.bodyMedium,
              ),
              const SizedBox(height: 4),
              Text(
                'Au-delà de ce délai avant le rendez-vous, le client peut '
                "annuler et garder son acompte ; en deçà, l'acompte n'est pas "
                'remboursé.',
                style: AppTextStyles.bodySmall.copyWith(
                  color: AppColors.textTertiary,
                ),
              ),
              const SizedBox(height: AppTheme.spacingM),
              Wrap(
                spacing: 8,
                children: [12, 24, 48].map((h) {
                  final selected = provider.cancellationWindowHours == h;
                  return ChoiceChip(
                    label: Text(
                      '$h h',
                      style: TextStyle(
                        color: selected
                            ? AppColors.secondary
                            : AppColors.textPrimary,
                      ),
                    ),
                    selected: selected,
                    showCheckmark: false,
                    selectedColor: AppColors.primary,
                    backgroundColor: AppColors.surface,
                    onSelected: (_) => provider.setCancellationWindowHours(h),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppTheme.spacingL),
        AppButton(
          text: 'Enregistrer',
          onPressed: provider.isSaving ? null : _save,
          isLoading: provider.isSaving,
        ),
      ],
    );
  }
}
