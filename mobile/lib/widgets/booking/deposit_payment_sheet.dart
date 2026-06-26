import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/config/app_config.dart';
import '../../core/di/dependency_injection.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/text_styles.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/mobile_money.dart';
import '../../models/payment.dart';
import '../../providers/appointment_provider.dart';
import '../common/app_button.dart';
import '../provider/image_picker_sheet.dart';
import '../provider/mock_image_picker_sheet.dart';

/// Opens the deposit hand-off sheet in **book mode**: the deposit is paid
/// **directly to the salon** (Wave deep link or copy-number) — Myweli holds
/// nothing — and the (pending) booking is created on confirm. The screenshot is
/// optional here (it can be sent later from the appointment). Returns true once
/// the booking is created.
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

/// Opens the deposit sheet in **submit mode** (pay-later): the booking already
/// exists, so confirming attaches the screenshot to [appointmentId] instead of
/// creating a booking. Returns true once the proof is attached.
Future<bool?> showDepositSubmitSheet(
  BuildContext context, {
  required String appointmentId,
  required double depositAmount,
  required double balanceDue,
  required String providerName,
  MobileMoneyOperator? depositOperator,
  String? depositNumber,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _DepositPaymentSheet(
      appointmentId: appointmentId,
      depositAmount: depositAmount,
      balanceDue: balanceDue,
      providerName: providerName,
      depositOperator: depositOperator,
      depositNumber: depositNumber,
    ),
  );
}

class _DepositPaymentSheet extends StatefulWidget {
  final double depositAmount;
  final double balanceDue;
  final String providerName;
  final MobileMoneyOperator? depositOperator;
  final String? depositNumber;

  /// Submit mode (pay-later) when non-null; book mode otherwise.
  final String? appointmentId;

  // Book-mode only.
  final String? providerId;
  final List<String>? serviceIds;
  final DateTime? appointmentDateTime;
  final String? artistId;
  final String? notes;

  const _DepositPaymentSheet({
    required this.depositAmount,
    required this.balanceDue,
    required this.providerName,
    this.depositOperator,
    this.depositNumber,
    this.appointmentId,
    this.providerId,
    this.serviceIds,
    this.appointmentDateTime,
    this.artistId,
    this.notes,
  });

  bool get isSubmitMode => appointmentId != null;

  @override
  State<_DepositPaymentSheet> createState() => _DepositPaymentSheetState();
}

class _DepositPaymentSheetState extends State<_DepositPaymentSheet> {
  /// The private object key returned by the upload (sent to the backend).
  String? _screenshotKey;

  /// The just-picked local file, used only to preview the attachment.
  String? _localPreviewPath;
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
    final String? source;
    if (AppConfig.useApiBackend) {
      source = await showImagePicker(context);
    } else {
      source = await showMockImagePicker(context);
    }
    if (source == null || !mounted) return;
    setState(() {
      _uploading = true;
      _error = null;
    });
    // Upload to PRIVATE storage; we keep only the returned key (proof is never
    // public). Preview uses the local file we just picked.
    final res = await serviceLocator.appointmentService
        .uploadDepositScreenshot(source: source);
    if (!mounted) return;
    setState(() {
      _uploading = false;
      if (res.success && res.data != null) {
        _screenshotKey = res.data;
        _localPreviewPath = source;
      } else {
        _error = res.error ?? 'Échec de l’envoi de la capture';
      }
    });
  }

  Future<void> _markPaid() async {
    setState(() {
      _booking = true;
      _error = null;
    });
    final provider = context.read<AppointmentProvider>();
    final bool ok;
    if (widget.isSubmitMode) {
      ok = await provider.submitDeposit(
        appointmentId: widget.appointmentId!,
        screenshotKey: _screenshotKey!,
      );
    } else {
      ok = await provider.bookAppointment(
        providerId: widget.providerId!,
        serviceIds: widget.serviceIds!,
        appointmentDateTime: widget.appointmentDateTime!,
        artistId: widget.artistId,
        notes: widget.notes,
        depositAmount: widget.depositAmount,
        depositScreenshotUrl: _screenshotKey,
      );
    }
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _booking = false;
        _error = provider.error ??
            (widget.isSubmitMode
                ? 'Erreur lors de l’envoi de l’acompte'
                : 'Erreur lors de la réservation');
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
              Text(
                widget.isSubmitMode ? "Envoyer l'acompte" : "Payer l'acompte",
                style: AppTextStyles.titleMedium,
              ),
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
                text: widget.isSubmitMode
                    ? "Envoyer l'acompte"
                    : "J'ai payé l'acompte",
                isLoading: _booking,
                // Submit mode needs a screenshot (it's the proof being sent);
                // book mode lets you confirm now and attach proof later.
                onPressed: (_booking ||
                        _uploading ||
                        (widget.isSubmitMode && _screenshotKey == null))
                    ? null
                    : _markPaid,
              ),
              const SizedBox(height: 8),
              Text(
                widget.isSubmitMode
                    ? 'Le salon confirmera après réception de l’acompte.'
                    : 'Le salon confirmera après réception. Statut : en attente.',
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
    if (_screenshotKey != null && _localPreviewPath != null) {
      return Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
            child: SizedBox(
              width: 48,
              height: 48,
              child: _localPreviewPath!.startsWith('asset:')
                  ? Image.asset(
                      _localPreviewPath!.substring('asset:'.length),
                      fit: BoxFit.cover,
                    )
                  : Image.file(File(_localPreviewPath!), fit: BoxFit.cover),
            ),
          ),
          const SizedBox(width: AppTheme.spacingM),
          const Expanded(child: Text('Capture jointe')),
          TextButton(
            onPressed: () => setState(() {
              _screenshotKey = null;
              _localPreviewPath = null;
            }),
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
                widget.isSubmitMode
                    ? 'Joindre une capture du paiement'
                    : 'Joindre une capture du paiement (optionnel)',
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
