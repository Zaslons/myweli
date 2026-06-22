import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/text_styles.dart';
import '../../../core/utils/formatters.dart';
import '../../../models/payment.dart';
import '../../../models/payout.dart';
import '../../../providers/pro_auth_provider.dart';
import '../../../providers/pro_payout_provider.dart';
import '../../../widgets/common/app_button.dart';
import '../../../widgets/common/empty_state.dart';
import '../../../widgets/common/loading_indicator.dart';

class ProPayoutsScreen extends StatefulWidget {
  const ProPayoutsScreen({super.key});

  @override
  State<ProPayoutsScreen> createState() => _ProPayoutsScreenState();
}

class _ProPayoutsScreenState extends State<ProPayoutsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final id = context.read<ProAuthProvider>().provider?.providerId;
      if (id != null && id.isNotEmpty) {
        context.read<ProPayoutProvider>().load(id);
      }
    });
  }

  Future<void> _requestPayout(
      String providerId, ProPayoutProvider payouts) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.secondary,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(AppTheme.radiusXL)),
      ),
      builder: (_) => _RequestPayoutSheet(
        providerId: providerId,
        available: payouts.availableBalance,
        payouts: payouts,
      ),
    );
    if (result == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Virement demandé'),
          backgroundColor: AppColors.success,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Virements')),
      body: Consumer2<ProAuthProvider, ProPayoutProvider>(
        builder: (context, auth, payouts, _) {
          final providerId = auth.provider?.providerId;
          if (providerId == null || providerId.isEmpty) {
            return const EmptyState(
              icon: Icons.storefront_outlined,
              title: 'Profil incomplet',
              description: 'Configurez votre profil pour gérer vos virements.',
            );
          }
          if (payouts.isLoading) {
            return const LoadingIndicator();
          }
          if (payouts.loadFailed) {
            return EmptyState(
              icon: Icons.wifi_off,
              title: 'Chargement impossible',
              description: 'Vérifiez votre connexion et réessayez.',
              actionText: 'Réessayer',
              onAction: () => payouts.load(providerId),
            );
          }

          return ListView(
            padding: const EdgeInsets.all(AppTheme.spacingM),
            children: [
              _BalanceCard(
                available: payouts.availableBalance,
                pending: payouts.pendingBalance,
                canRequest: payouts.canRequest,
                onRequest: () => _requestPayout(providerId, payouts),
              ),
              const SizedBox(height: AppTheme.spacingM),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.info_outline,
                      size: 16, color: AppColors.textTertiary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Les virements sont traités sous 48 h vers votre compte '
                      'Mobile Money. Myweli ne prélève aucune commission '
                      '(abonnement uniquement).',
                      style: AppTextStyles.bodySmall
                          .copyWith(color: AppColors.textTertiary),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppTheme.spacingL),
              Text(
                'HISTORIQUE',
                style: AppTextStyles.labelSmall.copyWith(
                    color: AppColors.textTertiary, letterSpacing: 0.5),
              ),
              const SizedBox(height: 8),
              if (payouts.payouts.isEmpty)
                Text(
                  'Aucun virement pour le moment.',
                  style: AppTextStyles.bodySmall
                      .copyWith(color: AppColors.textTertiary),
                )
              else
                ...payouts.payouts.map((p) => _PayoutTile(payout: p)),
            ],
          );
        },
      ),
    );
  }
}

class _BalanceCard extends StatelessWidget {
  final double available;
  final double pending;
  final bool canRequest;
  final VoidCallback onRequest;

  const _BalanceCard({
    required this.available,
    required this.pending,
    required this.canRequest,
    required this.onRequest,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppTheme.spacingL),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Solde disponible (acomptes collectés)',
            style: AppTextStyles.bodySmall
                .copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 4),
          Text(
            Formatters.formatCurrency(available),
            style: AppTextStyles.headlineMedium
                .copyWith(color: AppColors.textPrimary),
          ),
          if (pending > 0) ...[
            const SizedBox(height: 2),
            Text(
              'En attente : ${Formatters.formatCurrency(pending)}',
              style: AppTextStyles.bodySmall
                  .copyWith(color: AppColors.textTertiary),
            ),
          ],
          const SizedBox(height: AppTheme.spacingM),
          AppButton(
            text: 'Demander un virement',
            onPressed: canRequest ? onRequest : null,
          ),
        ],
      ),
    );
  }
}

class _PayoutTile extends StatelessWidget {
  final Payout payout;

  const _PayoutTile({required this.payout});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (payout.status) {
      PayoutStatus.paid => ('Versé', AppColors.success),
      PayoutStatus.pending => ('En attente', AppColors.warning),
      PayoutStatus.failed => ('Échoué', AppColors.error),
    };
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.divider)),
      ),
      child: Row(
        children: [
          const Icon(Icons.payments_outlined,
              size: 20, color: AppColors.textSecondary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(Formatters.formatCurrency(payout.amount),
                    style: AppTextStyles.bodyMedium),
                const SizedBox(height: 2),
                Text(
                  '${payout.operator.displayName} · '
                  '${Formatters.formatDateShort(payout.requestedAt)}',
                  style: AppTextStyles.bodySmall
                      .copyWith(color: AppColors.textTertiary),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(label,
                style: AppTextStyles.labelSmall.copyWith(color: color)),
          ),
        ],
      ),
    );
  }
}

class _RequestPayoutSheet extends StatefulWidget {
  final String providerId;
  final double available;
  final ProPayoutProvider payouts;

  const _RequestPayoutSheet({
    required this.providerId,
    required this.available,
    required this.payouts,
  });

  @override
  State<_RequestPayoutSheet> createState() => _RequestPayoutSheetState();
}

class _RequestPayoutSheetState extends State<_RequestPayoutSheet> {
  late final TextEditingController _amount =
      TextEditingController(text: widget.available.toStringAsFixed(0));
  MobileMoneyOperator _operator = MobileMoneyOperator.wave;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    final amount = double.tryParse(_amount.text.trim()) ?? 0;
    if (amount <= 0 || amount > widget.available) {
      setState(() => _error = 'Montant invalide (max '
          '${Formatters.formatCurrency(widget.available)})');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final ok = await widget.payouts.requestPayout(
      providerId: widget.providerId,
      amount: amount,
      operator: _operator,
    );
    if (!mounted) return;
    if (ok) {
      Navigator.pop(context, true);
    } else {
      setState(() {
        _busy = false;
        _error = widget.payouts.error ?? 'Erreur';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppTheme.spacingL,
        AppTheme.spacingL,
        AppTheme.spacingL,
        AppTheme.spacingL + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Demander un virement', style: AppTextStyles.titleLarge),
          const SizedBox(height: AppTheme.spacingM),
          TextField(
            controller: _amount,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              labelText: 'Montant (FCFA)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: AppTheme.spacingM),
          Text('Vers', style: AppTextStyles.bodySmall),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            children: MobileMoneyOperator.values.map((op) {
              final selected = _operator == op;
              return ChoiceChip(
                label: Text(
                  op.displayName,
                  style: TextStyle(
                    color:
                        selected ? AppColors.secondary : AppColors.textPrimary,
                  ),
                ),
                selected: selected,
                showCheckmark: false,
                selectedColor: AppColors.primary,
                backgroundColor: AppColors.surface,
                onSelected: (_) => setState(() => _operator = op),
              );
            }).toList(),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!,
                style:
                    AppTextStyles.bodySmall.copyWith(color: AppColors.error)),
          ],
          const SizedBox(height: AppTheme.spacingL),
          AppButton(
            text: 'Confirmer la demande',
            isLoading: _busy,
            onPressed: _busy ? null : _confirm,
          ),
        ],
      ),
    );
  }
}
