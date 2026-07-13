import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/text_styles.dart';
import '../../../core/utils/deposit.dart';
import '../../../core/utils/formatters.dart';
import '../../../models/provider_user.dart';
import '../../../providers/locality_provider.dart';
import '../../../providers/pro_auth_provider.dart';
import '../../../providers/pro_deposit_settings_provider.dart';
import '../../../widgets/common/app_button.dart';
import '../../../widgets/common/app_text_field.dart';
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

  final _numberController = TextEditingController();
  bool _numberPrefilled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ProDepositSettingsProvider>().load(widget.providerId);
      // Multi-pays MP2: the operator chips render the salon COUNTRY's catalog.
      context.read<LocalityProvider>().ensureLoaded();
    });
  }

  @override
  void dispose() {
    _numberController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final provider = context.read<ProDepositSettingsProvider>();
    provider.setMobileMoneyNumber(_numberController.text);
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
    if (!_numberPrefilled) {
      _numberController.text = provider.mobileMoneyNumber;
      _numberPrefilled = true;
    }
    final pct = (provider.depositPercentage * 100).round();
    final deposit = computeDeposit(
      total: _sampleTotal,
      depositRequired: provider.depositRequired,
      percentage: provider.depositPercentage,
    );
    final balance = _sampleTotal - deposit;

    // T52: deposits are a trust feature — only VERIFIED salons may enable
    // them (the server enforces it; this mirrors the rule with guidance).
    final verified =
        context.watch<ProAuthProvider>().provider?.verificationStatus ==
            VerificationStatus.verified;

    return ListView(
      padding: const EdgeInsets.all(AppTheme.spacingM),
      children: [
        if (!verified) ...[
          Container(
            padding: const EdgeInsets.all(AppTheme.spacingM),
            decoration: BoxDecoration(
              color: AppColors.warning.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Les acomptes sont disponibles après la vérification '
                  'de votre compte.',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.warning,
                  ),
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: () => context.push('/pro/verification'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textPrimary,
                    side: const BorderSide(color: AppColors.border),
                  ),
                  child: const Text('Vérifier mon compte'),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppTheme.spacingM),
        ],
        Container(
          decoration: BoxDecoration(
            color: AppColors.secondary,
            borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
            border: Border.all(color: AppColors.border),
          ),
          child: SwitchListTile(
            value: provider.depositRequired,
            onChanged: verified ? provider.setDepositRequired : null,
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
                  'Exemple sur une prestation de ${Formatters.formatCurrency(_sampleTotal, currency: context.read<ProAuthProvider>().salonCurrency)}',
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
                      Formatters.formatCurrency(
                        deposit,
                        currency: context.read<ProAuthProvider>().salonCurrency,
                      ),
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
                      Formatters.formatCurrency(
                        balance,
                        currency: context.read<ProAuthProvider>().salonCurrency,
                      ),
                      style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
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
                const Text('Recevoir l\'acompte',
                    style: AppTextStyles.bodyMedium),
                const SizedBox(height: 4),
                Text(
                  'Le client envoie l\'acompte directement sur ce compte '
                  'Mobile Money. Myweli ne le traite pas.',
                  style: AppTextStyles.bodySmall
                      .copyWith(color: AppColors.textTertiary),
                ),
                const SizedBox(height: AppTheme.spacingM),
                // Multi-pays MP2: the salon COUNTRY's operator catalog
                // (GET /localities) — never a hardcoded list.
                Consumer<LocalityProvider>(
                  builder: (context, locality, _) {
                    final operators = locality.operatorsFor(
                      context.read<ProAuthProvider>().salonCountryCode,
                    );
                    if (operators.isEmpty) {
                      if (locality.error != null) {
                        return Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Impossible de charger les opérateurs.',
                                style: AppTextStyles.bodySmall
                                    .copyWith(color: AppColors.textTertiary),
                              ),
                            ),
                            TextButton(
                              onPressed: locality.retry,
                              child: const Text('Réessayer'),
                            ),
                          ],
                        );
                      }
                      return const Center(
                        child: Padding(
                          padding: EdgeInsets.all(AppTheme.spacingS),
                          child: LoadingIndicator(),
                        ),
                      );
                    }
                    return Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: operators.map((op) {
                        return ChoiceChip(
                          label: Text(op.label),
                          selected: provider.mobileMoneyOperator == op.id,
                          showCheckmark: false,
                          selectedColor: AppColors.primary,
                          backgroundColor: AppColors.surface,
                          onSelected: (_) =>
                              provider.setMobileMoneyOperator(op.id),
                        );
                      }).toList(),
                    );
                  },
                ),
                const SizedBox(height: AppTheme.spacingM),
                AppTextField(
                  label: 'Numéro Mobile Money',
                  hint: 'Ex: 07 07 12 34 56',
                  controller: _numberController,
                  keyboardType: TextInputType.phone,
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
