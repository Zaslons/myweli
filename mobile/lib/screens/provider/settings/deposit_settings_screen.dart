import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/forms/field_errors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/text_styles.dart';
import '../../../core/utils/deposit.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/phone_numbering.dart';
import '../../../core/utils/validators.dart';
import '../../../models/provider_user.dart';
import '../../../providers/locality_provider.dart';
import '../../../providers/pro_auth_provider.dart';
import '../../../providers/pro_deposit_settings_provider.dart';
import '../../../widgets/common/app_button.dart';
import '../../../widgets/common/app_snack_bar.dart';
import '../../../widgets/common/empty_state.dart';
import '../../../widgets/common/label_value_row.dart';
import '../../../widgets/common/loading_indicator.dart';
import '../../../widgets/common/phone_number_field.dart';

class DepositSettingsScreen extends StatefulWidget {
  final String providerId;

  const DepositSettingsScreen({super.key, required this.providerId});

  @override
  State<DepositSettingsScreen> createState() => _DepositSettingsScreenState();
}

class _DepositSettingsScreenState extends State<DepositSettingsScreen> {
  /// A representative service price used only to preview the split.
  static const double _sampleTotal = 20000;

  final _numberFocus = FocusNode();

  // A7/§14 — the field that decides where a salon's deposits land.
  //
  // **E.164.** `PUT /deposit-policy` validates `mobileMoneyNumber` as E.164
  // (openapi.yaml:1758), and the field is prefilled from the stored value. The
  // review caught the first version as a LOCKOUT with an *empty intersection*:
  // a 10-digit local rule and an E.164 server contract can never both pass, so
  // no salon could have saved a deposit policy at all.
  //
  // **Judged whenever it is not empty** (phone-national-length.md §2.3): the
  // number is sent whatever the switch says — the PUT replaces the whole
  // policy — and the server checks any non-null one. Required only while a
  // deposit is collected.
  late final _errors = FieldErrors({'number': _numberRule});

  String? _numberRule(String value) =>
      context.read<ProDepositSettingsProvider>().depositRequired
      ? Validators.phoneNumber(value)
      : Validators.optionalPhoneNumber(value);

  /// The number as the field last emitted it (normalized — `''` once
  /// cleared), or null while the salon has not touched it: the stored value
  /// stands. Read from the provider rather than copied into a controller on
  /// the first build, which ran BEFORE `load()` and so never saw the stored
  /// value on a cold start (the A7-fix test file reported it).
  String? _editedNumber;

  String _number(ProDepositSettingsProvider provider) =>
      _editedNumber ?? PhoneNumbering.normalize(provider.mobileMoneyNumber);

  /// Deposits off hide the « Recevoir l'acompte » card — and with it the one
  /// place a refused number can be shown and fixed. Set by a refused save;
  /// it stays, so the field does not vanish under the salon's thumb the moment
  /// the number turns valid.
  bool _showNumberWhileOff = false;

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
    _numberFocus.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final provider = context.read<ProDepositSettingsProvider>();
    // A7/§14 — the number clients are told to send money to had NO validation
    // whatsoever: `"abc"` saved fine, rendered verbatim in the client's deposit
    // sheet, and went into the Wave deep link. The only transformation on the
    // whole path was `.trim()`.
    //
    // Required only when a deposit is actually being collected — a salon that
    // turns deposits off does not need a number; but one it keeps is still
    // judged (`_numberRule`).
    final number = _number(provider);
    if (!_errors.validate({'number': number})) {
      setState(() {
        if (!provider.depositRequired) _showNumberWhileOff = true;
      });
      _numberFocus.requestFocus();
      return;
    }
    setState(() {});
    provider.setMobileMoneyNumber(number);
    final ok = await provider.save(widget.providerId);
    if (!mounted) return;
    AppSnackBar.outcome(
      context,
      ok: ok,
      success: 'Paramètres enregistrés',
      error: provider.error ?? 'Erreur',
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
                const SizedBox(height: AppTheme.spacingS),
                OutlinedButton(
                  onPressed: () => context.push('/pro/verification'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textPrimary,
                    side: const BorderSide(color: AppColors.borderStrong),
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
          // Flutter 3.44 asserts on this (`list_tile.dart`,
          // `_findIntermediateWidget`): the tile paints its ink on the nearest
          // `Material` ANCESTOR, and the walk up stops at the first coloured box —
          // this one. The switch row's ripple painted BEHIND its own card. The
          // assertion is new; the defect is not. `transparency` paints nothing, so
          // the bordered card and its golden are unchanged.
          child: Material(
            type: MaterialType.transparency,
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
                LabelValueRow(
                  label: 'Pourcentage de l’acompte',
                  value: '$pct %',
                  valueStyle: AppTextStyles.titleMedium,
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
                const SizedBox(height: AppTheme.spacingS),
                LabelValueRow(
                  label: 'Acompte payé en ligne',
                  value: Formatters.formatCurrency(
                    deposit,
                    currency: context.read<ProAuthProvider>().salonCurrency,
                  ),
                  valueStyle: AppTextStyles.bodyMedium.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: AppTheme.spacingXS),
                LabelValueRow(
                  label: 'Solde au salon',
                  value: Formatters.formatCurrency(
                    balance,
                    currency: context.read<ProAuthProvider>().salonCurrency,
                  ),
                  labelStyle: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
        if (provider.depositRequired || _showNumberWhileOff) ...[
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
                  'Recevoir l’acompte',
                  style: AppTextStyles.bodyMedium,
                ),
                const SizedBox(height: AppTheme.spacingXS),
                Text(
                  'Le client envoie l’acompte directement sur ce compte '
                  'Mobile Money. MyWeli ne le traite pas.',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.textTertiary,
                  ),
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
                                style: AppTextStyles.bodySmall.copyWith(
                                  color: AppColors.textTertiary,
                                ),
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
                      spacing: AppTheme.spacingS,
                      runSpacing: AppTheme.spacingS,
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
                // A free-text field until phone-national-length.md: its hint
                // (« Ex: 07 07 12 34 56 ») showed a form the rule refused, and
                // it checked the separator-free value while sending the raw
                // one. The shared field takes the country from its picker and
                // emits what is checked.
                PhoneNumberField(
                  label: 'Numéro Mobile Money',
                  // The current value: the lazy list may cull this card, and
                  // the field must come back as it was left.
                  initialValue: _number(provider),
                  focusNode: _numberFocus,
                  errorText: _errors['number'],
                  onChanged: (v) => setState(() {
                    _editedNumber = v;
                    _errors.revalidate('number', v);
                  }),
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
                'Politique d’annulation',
                style: AppTextStyles.bodyMedium,
              ),
              const SizedBox(height: AppTheme.spacingXS),
              Text(
                'Au-delà de ce délai avant le rendez-vous, le client peut '
                'annuler et garder son acompte ; en deçà, l’acompte n’est pas '
                'remboursé.',
                style: AppTextStyles.bodySmall.copyWith(
                  color: AppColors.textTertiary,
                ),
              ),
              const SizedBox(height: AppTheme.spacingM),
              Wrap(
                spacing: AppTheme.spacingS,
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
