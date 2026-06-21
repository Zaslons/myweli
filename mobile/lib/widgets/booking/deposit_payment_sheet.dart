import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/text_styles.dart';
import '../../core/utils/formatters.dart';
import '../../models/payment.dart';
import '../../providers/appointment_provider.dart';
import '../common/app_button.dart';

/// Opens the Mobile Money deposit sheet. Returns true once the acompte is paid
/// and the booking is confirmed, or null if dismissed.
Future<bool?> showDepositPaymentSheet(
  BuildContext context, {
  required double depositAmount,
  required double balanceDue,
  required String providerId,
  required List<String> serviceIds,
  required DateTime appointmentDateTime,
  String? artistId,
  String? notes,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _DepositPaymentSheet(
      depositAmount: depositAmount,
      balanceDue: balanceDue,
      providerId: providerId,
      serviceIds: serviceIds,
      appointmentDateTime: appointmentDateTime,
      artistId: artistId,
      notes: notes,
    ),
  );
}

enum _Status { idle, processing, success, failure }

class _DepositPaymentSheet extends StatefulWidget {
  final double depositAmount;
  final double balanceDue;
  final String providerId;
  final List<String> serviceIds;
  final DateTime appointmentDateTime;
  final String? artistId;
  final String? notes;

  const _DepositPaymentSheet({
    required this.depositAmount,
    required this.balanceDue,
    required this.providerId,
    required this.serviceIds,
    required this.appointmentDateTime,
    this.artistId,
    this.notes,
  });

  @override
  State<_DepositPaymentSheet> createState() => _DepositPaymentSheetState();
}

class _DepositPaymentSheetState extends State<_DepositPaymentSheet> {
  static const _operatorKey = 'myweli_last_operator_v1';

  MobileMoneyOperator _operator = MobileMoneyOperator.wave;
  _Status _status = _Status.idle;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadOperator();
  }

  Future<void> _loadOperator() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_operatorKey);
    if (saved == null || !mounted) return;
    setState(() {
      _operator = MobileMoneyOperator.values.firstWhere(
        (o) => o.name == saved,
        orElse: () => _operator,
      );
    });
  }

  Future<void> _pay() async {
    setState(() {
      _status = _Status.processing;
      _error = null;
    });

    // Capture the provider before the async gap; remember the operator.
    final provider = context.read<AppointmentProvider>();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_operatorKey, _operator.name);

    final ok = await provider.payDepositAndBook(
      providerId: widget.providerId,
      serviceIds: widget.serviceIds,
      appointmentDateTime: widget.appointmentDateTime,
      artistId: widget.artistId,
      notes: widget.notes,
      depositAmount: widget.depositAmount,
      operator: _operator,
    );

    if (!mounted) return;
    if (ok) {
      setState(() => _status = _Status.success);
      await Future.delayed(const Duration(milliseconds: 700));
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _status = _Status.failure;
        _error = provider.error;
      });
    }
  }

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
          padding: const EdgeInsets.all(AppTheme.spacingL),
          child: _buildBody(),
        ),
      ),
    );
  }

  Widget _buildBody() {
    switch (_status) {
      case _Status.processing:
        return _centered(
          const CircularProgressIndicator(),
          'Paiement en cours…',
        );
      case _Status.success:
        return _centered(
          const Icon(Icons.check_circle, size: 56, color: AppColors.success),
          'Acompte payé',
        );
      case _Status.idle:
      case _Status.failure:
        return _buildForm();
    }
  }

  Widget _centered(Widget icon, String label) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: AppTheme.spacingM),
        icon,
        const SizedBox(height: AppTheme.spacingM),
        Text(label, style: AppTextStyles.titleMedium),
        const SizedBox(height: AppTheme.spacingM),
      ],
    );
  }

  Widget _buildForm() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(
          child: Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.divider,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
        ),
        const SizedBox(height: AppTheme.spacingM),
        const Text("Payer l'acompte", style: AppTextStyles.titleMedium),
        const SizedBox(height: 4),
        Text(
          Formatters.formatCurrency(widget.depositAmount),
          style: AppTextStyles.headlineLarge,
        ),
        const SizedBox(height: 2),
        Text(
          'Solde de ${Formatters.formatCurrency(widget.balanceDue)} à régler au salon',
          style: AppTextStyles.bodySmall.copyWith(
            color: AppColors.textTertiary,
          ),
        ),
        const SizedBox(height: AppTheme.spacingL),
        Text(
          'Choisir un opérateur',
          style: AppTextStyles.bodyMedium.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: AppTheme.spacingS),
        ...MobileMoneyOperator.values.map(_operatorTile),
        if (_status == _Status.failure) ...[
          const SizedBox(height: AppTheme.spacingS),
          Text(
            _error ?? 'Le paiement a échoué',
            style: AppTextStyles.bodySmall.copyWith(color: AppColors.error),
          ),
        ],
        const SizedBox(height: AppTheme.spacingL),
        AppButton(
          text: _status == _Status.failure
              ? 'Réessayer'
              : 'Payer ${Formatters.formatCurrency(widget.depositAmount)} via ${_operator.displayName}',
          onPressed: _pay,
        ),
      ],
    );
  }

  Widget _operatorTile(MobileMoneyOperator op) {
    final selected = op == _operator;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppTheme.spacingS),
      child: InkWell(
        onTap: () => setState(() => _operator = op),
        borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
        child: Container(
          padding: const EdgeInsets.all(AppTheme.spacingM),
          decoration: BoxDecoration(
            border: Border.all(
              color: selected ? AppColors.primary : AppColors.border,
              width: selected ? 2 : 1,
            ),
            borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.account_balance_wallet_outlined,
                size: 20,
                color: AppColors.textSecondary,
              ),
              const SizedBox(width: AppTheme.spacingM),
              Expanded(
                child: Text(op.displayName, style: AppTextStyles.bodyMedium),
              ),
              if (selected)
                const Icon(Icons.check_circle,
                    size: 20, color: AppColors.primary),
            ],
          ),
        ),
      ),
    );
  }
}
