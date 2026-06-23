import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/di/dependency_injection.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/text_styles.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/mobile_money.dart';
import '../../models/payment.dart';
import '../../providers/appointment_provider.dart';
import '../common/app_button.dart';
import '../common/timed_cached_image.dart';
import '../provider/mock_image_picker_sheet.dart';

/// Opens the deposit hand-off sheet. The deposit is paid **directly to the
/// salon** (Wave deep link or copy-number) — Myweli holds nothing. Returns true
/// once the (pending) booking is created.
Future<bool?> showDepositPaymentSheet(
  BuildContext context, {
  required double depositAmount,
  required double balanceDue,
  required String providerId,
  required String providerName,
  required List<String> serviceIds,
  required DateTime appointmentDateTime,
  MobileMoneyOperator? depositOperator,
  String? depositNumber,
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
      providerName: providerName,
      serviceIds: serviceIds,
      appointmentDateTime: appointmentDateTime,
      depositOperator: depositOperator,
      depositNumber: depositNumber,
      artistId: artistId,
      notes: notes,
    ),
  );
}

class _DepositPaymentSheet extends StatefulWidget {
  final double depositAmount;
  final double balanceDue;
  final String providerId;
  final String providerName;
  final List<String> serviceIds;
  final DateTime appointmentDateTime;
  final MobileMoneyOperator? depositOperator;
  final String? depositNumber;
  final String? artistId;
  final String? notes;

  const _DepositPaymentSheet({
    required this.depositAmount,
    required this.balanceDue,
    required this.providerId,
    required this.providerName,
    required this.serviceIds,
    required this.appointmentDateTime,
    this.depositOperator,
    this.depositNumber,
    this.artistId,
    this.notes,
  });

  @override
  State<_DepositPaymentSheet> createState() => _DepositPaymentSheetState();
}

class _DepositPaymentSheetState extends State<_DepositPaymentSheet> {
  String? _screenshotUrl;
  bool _uploading = false;
  bool _booking = false;
  String? _error;

  bool get _hasHandle => (widget.depositNumber ?? '').trim().isNotEmpty;

  Future<void> _payWithWave() async {
    final uri = waveDeepLink(
      number: widget.depositNumber!,
      amount: widget.depositAmount,
    );
    if (uri == null) return;
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Impossible d’ouvrir Wave')),
      );
    }
  }

  void _copyNumber() {
    Clipboard.setData(ClipboardData(text: widget.depositNumber!));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text('Numéro copié'), duration: Duration(seconds: 1)),
    );
  }

  Future<void> _attachScreenshot() async {
    final source = await showMockImagePicker(context);
    if (source == null || !mounted) return;
    setState(() => _uploading = true);
    final res =
        await serviceLocator.imageUploadService.uploadImage(source: source);
    if (!mounted) return;
    setState(() {
      _uploading = false;
      if (res.success) _screenshotUrl = res.data;
    });
  }

  Future<void> _markPaid() async {
    setState(() {
      _booking = true;
      _error = null;
    });
    final provider = context.read<AppointmentProvider>();
    final ok = await provider.bookAppointment(
      providerId: widget.providerId,
      serviceIds: widget.serviceIds,
      appointmentDateTime: widget.appointmentDateTime,
      artistId: widget.artistId,
      notes: widget.notes,
      depositAmount: widget.depositAmount,
      depositScreenshotUrl: _screenshotUrl,
    );
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _booking = false;
        _error = provider.error ?? 'Erreur lors de la réservation';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.secondary,
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(AppTheme.radiusXXL)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            AppTheme.spacingL,
            AppTheme.spacingL,
            AppTheme.spacingL,
            AppTheme.spacingL + MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text("Payer l'acompte", style: AppTextStyles.titleMedium),
              const SizedBox(height: 2),
              Text(
                'Versé directement au salon. Myweli ne prélève rien.',
                style: AppTextStyles.bodySmall
                    .copyWith(color: AppColors.textTertiary),
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
                    Text('Acompte',
                        style: AppTextStyles.bodySmall
                            .copyWith(color: AppColors.textSecondary)),
                    Text(Formatters.formatCurrency(widget.depositAmount),
                        style: AppTextStyles.headlineMedium),
                    Text(
                      'Solde ${Formatters.formatCurrency(widget.balanceDue)} à régler au salon',
                      style: AppTextStyles.bodySmall
                          .copyWith(color: AppColors.textTertiary),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppTheme.spacingM),
              if (_hasHandle) ...[
                if (widget.depositOperator == MobileMoneyOperator.wave) ...[
                  AppButton(text: 'Payer avec Wave', onPressed: _payWithWave),
                  const SizedBox(height: AppTheme.spacingS),
                ],
                InkWell(
                  onTap: _copyNumber,
                  borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
                  child: Container(
                    padding: const EdgeInsets.all(AppTheme.spacingM),
                    decoration: BoxDecoration(
                      border: Border.all(color: AppColors.border),
                      borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${widget.depositOperator?.displayName ?? 'Mobile Money'} · ${widget.providerName}',
                                style: AppTextStyles.bodySmall
                                    .copyWith(color: AppColors.textTertiary),
                              ),
                              Text(widget.depositNumber!,
                                  style: AppTextStyles.bodyMedium),
                            ],
                          ),
                        ),
                        Text('Copier',
                            style: AppTextStyles.bodySmall
                                .copyWith(color: AppColors.primary)),
                      ],
                    ),
                  ),
                ),
              ] else
                Text(
                  'Ce salon n’a pas encore configuré de compte pour l’acompte. '
                  'Contactez-le directement.',
                  style: AppTextStyles.bodySmall
                      .copyWith(color: AppColors.textTertiary),
                ),
              const SizedBox(height: AppTheme.spacingM),
              _screenshotRow(),
              if (_error != null) ...[
                const SizedBox(height: AppTheme.spacingS),
                Text(_error!,
                    style: AppTextStyles.bodySmall
                        .copyWith(color: AppColors.error)),
              ],
              const SizedBox(height: AppTheme.spacingL),
              AppButton(
                text: "J'ai payé l'acompte",
                isLoading: _booking,
                onPressed: (_booking || _uploading) ? null : _markPaid,
              ),
              const SizedBox(height: 8),
              Text(
                'Le salon confirmera après réception. Statut : en attente.',
                textAlign: TextAlign.center,
                style: AppTextStyles.bodySmall
                    .copyWith(color: AppColors.textTertiary),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _screenshotRow() {
    if (_screenshotUrl != null) {
      return Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
            child: SizedBox(
              width: 48,
              height: 48,
              child: TimedCachedImage(
                  imageUrl: _screenshotUrl!, fit: BoxFit.cover),
            ),
          ),
          const SizedBox(width: AppTheme.spacingM),
          const Expanded(child: Text('Capture jointe')),
          TextButton(
            onPressed: () => setState(() => _screenshotUrl = null),
            child: const Text('Retirer'),
          ),
        ],
      );
    }
    return InkWell(
      onTap: _uploading ? null : _attachScreenshot,
      borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
      child: Container(
        padding: const EdgeInsets.all(AppTheme.spacingM),
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        ),
        child: Row(
          children: [
            if (_uploading)
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              const Icon(Icons.attachment,
                  size: 18, color: AppColors.textSecondary),
            const SizedBox(width: AppTheme.spacingM),
            Expanded(
              child: Text(
                'Joindre une capture du paiement (optionnel)',
                style: AppTextStyles.bodySmall
                    .copyWith(color: AppColors.textSecondary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
