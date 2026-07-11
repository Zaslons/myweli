import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/di/dependency_injection.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/text_styles.dart';
import '../../core/utils/calendar_event.dart';
import '../../core/utils/cancellation_policy.dart';
import '../../core/utils/formatters.dart';
import '../../models/appointment.dart';
import '../../providers/appointment_provider.dart';
import '../../providers/provider_provider.dart';
import '../../widgets/booking/deposit_payment_sheet.dart';
import '../../widgets/common/app_button.dart';
import '../../widgets/common/loading_indicator.dart';
import '../../widgets/common/timed_cached_image.dart';
import '../../widgets/review/submit_review_sheet.dart';

class AppointmentDetailScreen extends StatefulWidget {
  final String appointmentId;

  const AppointmentDetailScreen({
    super.key,
    required this.appointmentId,
  });

  @override
  State<AppointmentDetailScreen> createState() =>
      _AppointmentDetailScreenState();
}

class _AppointmentDetailScreenState extends State<AppointmentDetailScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = Provider.of<AppointmentProvider>(context, listen: false);
      provider.loadAppointmentById(widget.appointmentId);
    });
  }

  // Parity 1.8: the chosen spécialiste, resolved once from the salon's
  // public team (the payload carries only artistId).
  String? _artistName;
  String? _artistLookupFor;

  void _maybeResolveArtist(Appointment appointment) {
    final artistId = appointment.artistId;
    if (artistId == null || artistId.isEmpty) return;
    if (_artistLookupFor == artistId) return;
    _artistLookupFor = artistId;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final res = await serviceLocator.providerService.getProviderById(
        appointment.providerId,
      );
      if (!mounted) return;
      final name = res.data?.artists
          .where((a) => a.id == artistId)
          .map((a) => a.name)
          .firstOrNull;
      if (name != null) setState(() => _artistName = name);
    });
  }

  /// « Appeler »/« WhatsApp » (parity 1.6): resolve the salon's public
  /// coordinates, then launch the dialer / wa.me (provider-detail idiom).
  Future<void> _contactSalon(
    Appointment appointment, {
    required bool whatsapp,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    final res = await serviceLocator.providerService.getProviderById(
      appointment.providerId,
    );
    final p = res.data;
    final raw = whatsapp ? p?.whatsapp : p?.phoneNumber;
    if (!res.success || p == null || raw == null || raw.isEmpty) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            whatsapp ? 'WhatsApp indisponible.' : 'Numéro indisponible.',
          ),
        ),
      );
      return;
    }
    final uri = whatsapp
        ? Uri.parse('https://wa.me/${raw.replaceAll(RegExp(r'[^0-9]'), '')}')
        : Uri.parse('tel:${raw.replaceAll(RegExp(r'\s'), '')}');
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Impossible d’ouvrir l’application.')),
      );
    }
  }

  Future<void> _handleCancel(Appointment appointment) async {
    final provider = Provider.of<AppointmentProvider>(context, listen: false);
    final outcome = cancellationOutcome(
      appointmentDate: appointment.appointmentDate,
      now: DateTime.now(),
      windowHours: appointment.cancellationWindowHours,
      depositAmount: appointment.depositAmount,
    );

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Annuler le rendez-vous ?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Êtes-vous sûr de vouloir annuler ce rendez-vous ?'),
            if (appointment.depositAmount > 0) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(AppTheme.spacingM),
                decoration: BoxDecoration(
                  color: outcome.depositForfeited
                      ? AppColors.errorLight
                      : AppColors.successLight,
                  borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      outcome.depositForfeited
                          ? Icons.warning_amber_rounded
                          : Icons.info_outline,
                      size: 18,
                      color: outcome.depositForfeited
                          ? AppColors.error
                          : AppColors.success,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        outcome.depositForfeited
                            ? 'Annulation à moins de '
                                '${appointment.cancellationWindowHours} h : '
                                'votre acompte de '
                                '${Formatters.formatCurrency(appointment.depositAmount)} '
                                'ne sera pas remboursé.'
                            : 'Votre acompte de '
                                '${Formatters.formatCurrency(appointment.depositAmount)} '
                                'sera remboursé.',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: outcome.depositForfeited
                              ? AppColors.error
                              : AppColors.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Non'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'Oui, annuler',
              style: TextStyle(color: AppColors.error),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final success = await provider.cancelAppointment(widget.appointmentId);

    if (!mounted) return;

    if (success) {
      context.pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Rendez-vous annulé'),
          backgroundColor: AppColors.success,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(provider.error ?? 'Erreur lors de l\'annulation'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _handleReschedule(Appointment appointment) async {
    final serviceIds = appointment.serviceIds.join(',');
    final artistParam =
        appointment.artistId != null ? '&artistId=${appointment.artistId}' : '';
    final uri = '/booking/date-time?providerId=${appointment.providerId}'
        '&serviceIds=$serviceIds&returnToHub=1'
        '&dateTime=${appointment.appointmentDate.toIso8601String()}$artistParam';

    final newDateTime = await context.push<DateTime>(uri);
    if (newDateTime == null || !mounted) return;

    final provider = Provider.of<AppointmentProvider>(context, listen: false);
    final success = await provider.rescheduleAppointment(
      id: appointment.id,
      newDateTime: newDateTime,
    );

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          success ? 'Rendez-vous reporté' : (provider.error ?? 'Erreur'),
        ),
        backgroundColor: success ? AppColors.success : AppColors.error,
      ),
    );
  }

  /// Pay-later: open the deposit sheet in submit mode (the booking exists). The
  /// salon's Mobile Money handle comes from the provider's deposit policy.
  Future<void> _handleSendDeposit(Appointment appointment) async {
    final providerProvider =
        Provider.of<ProviderProvider>(context, listen: false);
    await providerProvider.loadProviderById(appointment.providerId);
    if (!mounted) return;
    final p = providerProvider.selectedProvider;
    final sent = await showDepositSubmitSheet(
      context,
      appointmentId: appointment.id,
      depositAmount: appointment.depositAmount,
      balanceDue: appointment.balanceDue,
      providerName: p?.name ?? 'le salon',
      depositOperator: p?.depositMobileMoneyOperator,
      depositNumber: p?.depositMobileMoneyNumber,
    );
    if (sent != true || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Acompte envoyé. En attente de confirmation du salon.'),
        backgroundColor: AppColors.success,
      ),
    );
  }

  /// View the screenshot the consumer already submitted (signed URL).
  Future<void> _viewMyProof(Appointment appointment) async {
    final messenger = ScaffoldMessenger.of(context);
    final res = await serviceLocator.appointmentService.depositScreenshotUrl(
      appointmentId: appointment.id,
    );
    if (!mounted) return;
    if (res.success && res.data != null) {
      await showDialog<void>(
        context: context,
        builder: (_) => Dialog(
          backgroundColor: Colors.transparent,
          child: InteractiveViewer(
            child: TimedCachedImage(imageUrl: res.data!, fit: BoxFit.contain),
          ),
        ),
      );
    } else {
      messenger.showSnackBar(
        SnackBar(content: Text(res.error ?? 'Capture indisponible')),
      );
    }
  }

  /// State-aware deposit row: à envoyer (with the pay-later CTA) → en attente de
  /// confirmation (view proof) → confirmé. Myweli never holds the money.
  Widget _depositSection(Appointment a) {
    final hasProof = a.depositScreenshotUrl != null;
    final amount = Formatters.formatCurrency(a.depositAmount);

    IconData icon;
    String label;
    String? hint;
    Widget? action;

    Widget viewProofButton() => AppButton(
          text: 'Voir ma capture',
          type: AppButtonType.secondary,
          onPressed: () => _viewMyProof(a),
        );

    switch (a.status) {
      case AppointmentStatus.confirmed:
        icon = Icons.verified_outlined;
        label = 'Acompte confirmé';
        hint = 'Le salon a confirmé la réception de votre acompte.';
        if (hasProof) action = viewProofButton();
      case AppointmentStatus.pending:
        if (hasProof) {
          icon = Icons.hourglass_empty;
          label = 'Acompte — en attente de confirmation';
          hint = 'Le salon confirmera après vérification.';
          action = viewProofButton();
        } else {
          icon = Icons.savings_outlined;
          label = 'Acompte à envoyer';
          hint = 'Payez le salon directement, puis joignez une capture.';
          action = AppButton(
            text: "Envoyer l'acompte",
            icon: Icons.send_outlined,
            onPressed: () => _handleSendDeposit(a),
          );
        }
      case AppointmentStatus.completed:
      case AppointmentStatus.cancelled:
      case AppointmentStatus.noShow:
        icon = Icons.savings_outlined;
        label = 'Acompte';
        if (hasProof) action = viewProofButton();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _InfoRow(icon: icon, label: label, value: amount),
        if (hint != null) ...[
          const SizedBox(height: 4),
          Text(
            hint,
            style:
                AppTextStyles.bodySmall.copyWith(color: AppColors.textTertiary),
          ),
        ],
        if (action != null) ...[
          const SizedBox(height: 8),
          action,
        ],
      ],
    );
  }

  /// Add this upcoming appointment to the phone's native calendar. Loads the
  /// provider (reusing the cached fetch) for the title/location/services, then
  /// opens the OS "new event" sheet — the user saves it in their own calendar
  /// app (Myweli never writes the entry). Design: docs/design/appointment-calendar.md.
  Future<void> _addToCalendar(Appointment appointment) async {
    final messenger = ScaffoldMessenger.of(context);
    final providerProvider =
        Provider.of<ProviderProvider>(context, listen: false);
    await providerProvider.loadProviderById(appointment.providerId);
    if (!mounted) return;
    final p = providerProvider.selectedProvider;

    final serviceNames = <String>[];
    var totalDuration = 0;
    if (p != null) {
      for (final s in p.services) {
        if (appointment.serviceIds.contains(s.id)) {
          serviceNames.add(s.name);
          totalDuration += s.durationMinutes;
        }
      }
    }

    final ok = await addAppointmentToCalendar(
      buildAppointmentCalendarEvent(
        providerName: p?.name ?? 'le salon',
        providerAddress: p?.address,
        serviceNames: serviceNames,
        start: appointment.appointmentDate,
        totalDurationMinutes: totalDuration,
        depositAmount: appointment.depositAmount,
        balanceDue: appointment.balanceDue,
      ),
    );
    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? 'Rendez-vous ajouté à votre calendrier'
              : 'Impossible d\'ouvrir le calendrier',
        ),
        backgroundColor: ok ? AppColors.success : AppColors.error,
      ),
    );
  }

  Future<void> _leaveReview(Appointment appointment) async {
    final providerProvider =
        Provider.of<ProviderProvider>(context, listen: false);
    await providerProvider.loadProviderById(appointment.providerId);
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: SubmitReviewSheet(
          providerId: appointment.providerId,
          appointmentId: appointment.id,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: const Text('Détails'),
      ),
      body: Consumer<AppointmentProvider>(
        builder: (context, provider, _) {
          if (provider.isLoading && provider.selectedAppointment == null) {
            return const LoadingIndicator();
          }

          final appointment = provider.selectedAppointment;
          if (appointment != null) _maybeResolveArtist(appointment);
          if (appointment == null) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline,
                      size: 64, color: AppColors.error),
                  const SizedBox(height: 16),
                  Text(
                    provider.error ?? 'Rendez-vous non trouvé',
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            );
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(AppTheme.spacingM),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Appointment Info Card
                Container(
                  padding: const EdgeInsets.all(AppTheme.spacingL),
                  decoration: BoxDecoration(
                    color: AppColors.secondary,
                    borderRadius: BorderRadius.circular(AppTheme.radiusXL),
                    boxShadow: AppTheme.elevation1,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Informations du rendez-vous',
                        style: AppTextStyles.titleLarge,
                      ),
                      const Divider(height: 24),
                      _InfoRow(
                        icon: Icons.calendar_today,
                        label: 'Date',
                        value:
                            Formatters.formatDate(appointment.appointmentDate),
                      ),
                      const SizedBox(height: 16),
                      _InfoRow(
                        icon: Icons.access_time,
                        label: 'Heure',
                        value:
                            Formatters.formatTime(appointment.appointmentDate),
                      ),
                      if (_artistName != null) ...[
                        const SizedBox(height: 16),
                        _InfoRow(
                          icon: Icons.person_outline,
                          label: 'Spécialiste',
                          value: _artistName!,
                        ),
                      ],
                      const SizedBox(height: 16),
                      _InfoRow(
                        icon: Icons.attach_money,
                        label: 'Prix total',
                        value:
                            Formatters.formatCurrency(appointment.totalPrice),
                      ),
                      if (appointment.depositAmount > 0) ...[
                        const SizedBox(height: 16),
                        _depositSection(appointment),
                        const SizedBox(height: 16),
                        _InfoRow(
                          icon: Icons.account_balance_wallet_outlined,
                          label: 'Solde à régler au salon',
                          value:
                              Formatters.formatCurrency(appointment.balanceDue),
                        ),
                      ],
                      if (appointment.notes != null &&
                          appointment.notes!.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        _InfoRow(
                          icon: Icons.note,
                          label: 'Notes',
                          value: appointment.notes!,
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                // Action Buttons
                if (appointment.status != AppointmentStatus.cancelled &&
                    appointment.status != AppointmentStatus.completed) ...[
                  if (appointment.appointmentDate.isAfter(DateTime.now())) ...[
                    AppButton(
                      text: 'Reporter',
                      icon: Icons.event_repeat,
                      isLoading: provider.isLoading,
                      onPressed: () => _handleReschedule(appointment),
                    ),
                    const SizedBox(height: 8),
                    AppButton(
                      text: 'Ajouter au calendrier',
                      type: AppButtonType.secondary,
                      icon: Icons.event_available,
                      onPressed: () => _addToCalendar(appointment),
                    ),
                    const SizedBox(height: 8),
                  ],
                  AppButton(
                    text: 'Annuler le rendez-vous',
                    type: AppButtonType.secondary,
                    isLoading: provider.isLoading,
                    onPressed: () => _handleCancel(appointment),
                  ),
                  const SizedBox(height: 8),
                ],
                if (appointment.status == AppointmentStatus.completed) ...[
                  AppButton(
                    text: 'Donner mon avis',
                    icon: Icons.rate_review_outlined,
                    onPressed: () => _leaveReview(appointment),
                  ),
                  const SizedBox(height: 8),
                ],
                AppButton(
                  text: 'Appeler',
                  icon: Icons.phone,
                  onPressed: () => _contactSalon(appointment, whatsapp: false),
                ),
                const SizedBox(height: 8),
                AppButton(
                  text: 'WhatsApp',
                  icon: Icons.chat_outlined,
                  type: AppButtonType.secondary,
                  onPressed: () => _contactSalon(appointment, whatsapp: true),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: AppColors.textSecondary),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: AppTextStyles.bodySmall.copyWith(
                  color: AppColors.textTertiary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: AppTextStyles.bodyMedium,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
