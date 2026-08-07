import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/di/dependency_injection.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/text_styles.dart';
import '../../core/utils/app_clock.dart';
import '../../core/utils/booking_error_cta.dart';
import '../../core/utils/calendar_event.dart';
import '../../core/utils/cancellation_policy.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/salon_time.dart';
import '../../models/appointment.dart';
import '../../providers/appointment_provider.dart';
import '../../providers/locality_provider.dart';
import '../../widgets/booking/deposit_payment_sheet.dart';
import '../../widgets/common/app_button.dart';
import '../../widgets/common/app_snack_bar.dart';
import '../../widgets/common/confirm_dialog.dart';
import '../../widgets/common/inline_feedback.dart';
import '../../widgets/common/loading_indicator.dart';
import '../../widgets/common/salon_time_hint.dart';
import '../../widgets/common/timed_cached_image.dart';
import '../../widgets/review/submit_review_sheet.dart';
import 'reschedule_screen.dart';

class AppointmentDetailScreen extends StatefulWidget {
  final String appointmentId;

  const AppointmentDetailScreen({super.key, required this.appointmentId});

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
      // The country label of the « heure du salon » hint reads the tree.
      context.read<LocalityProvider>().ensureLoaded();
    });
  }

  // ONE lazy provider fetch per appointment: the chosen spécialiste
  // (parity 1.8 — the payload carries only artistId) AND the salon's
  // country for the hint label (multi-pays MP2).
  /// « Appeler »/« WhatsApp » (parity 1.6): launch the dialer / wa.me from the
  /// coordinates the booking already carries.
  ///
  /// These are kept for a salon that has STOPPED taking appointments, on
  /// purpose — that is when a client with a booking needs to reach it most.
  /// They used to be fetched from the public route, which meant a stopped
  /// salon answered « Numéro indisponible. » — a sentence blaming the phone
  /// number for something that was never about the number.
  Future<void> _contactSalon(
    Appointment appointment, {
    required bool whatsapp,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    final raw = whatsapp
        ? appointment.providerWhatsapp
        : appointment.providerPhone;
    if (raw == null || raw.isEmpty) {
      AppSnackBar.showOn(
        messenger,
        whatsapp ? 'WhatsApp indisponible.' : 'Numéro indisponible.',
        kind: SnackKind.error,
      );
      return;
    }
    final uri = whatsapp
        ? Uri.parse('https://wa.me/${raw.replaceAll(RegExp(r'[^0-9]'), '')}')
        : Uri.parse('tel:${raw.replaceAll(RegExp(r'\s'), '')}');
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      AppSnackBar.showOn(
        messenger,
        'Impossible d’ouvrir l’application.',
        kind: SnackKind.error,
      );
    }
  }

  Future<void> _handleCancel(Appointment appointment) async {
    final provider = Provider.of<AppointmentProvider>(context, listen: false);
    final outcome = cancellationOutcome(
      appointmentDate: appointment.appointmentDate,
      now: AppClock.now(),
      windowHours: appointment.cancellationWindowHours,
      depositAmount: appointment.depositAmount,
    );

    final confirmed = await showConfirmDialog(
      context,
      title: 'Annuler le rendez-vous ?',
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Êtes-vous sûr de vouloir annuler ce rendez-vous ?'),
          if (appointment.depositAmount > 0) ...[
            const SizedBox(height: AppTheme.spacingSM),
            Container(
              padding: const EdgeInsets.all(AppTheme.spacingM),
              decoration: BoxDecoration(
                // §13.1: `errorLight`/`successLight` are foregrounds (4.66:1 ON
                // white). Used as a fill they put `error` ink at 2.00:1 and
                // `success` ink at 1.85:1 — both illegible. A neutral tint
                // carries the ink (9.19:1 / 15.98:1) and the semantic hue moves
                // to the border, beside the glyph that already distinguishes it.
                color: AppColors.surfaceVariant,
                border: Border.all(
                  color: outcome.depositForfeited
                      ? AppColors.error
                      : AppColors.success,
                ),
                borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    outcome.depositForfeited
                        ? Icons.warning_amber_rounded
                        : Icons.info_outline,
                    size: AppTheme.iconS,
                    color: outcome.depositForfeited
                        ? AppColors.error
                        : AppColors.success,
                  ),
                  const SizedBox(width: AppTheme.spacingS),
                  Expanded(
                    child: Text(
                      outcome.depositForfeited
                          ? 'Annulation à moins de '
                                '${appointment.cancellationWindowHours} h : '
                                'votre acompte de '
                                '${Formatters.formatCurrency(appointment.depositAmount, currency: appointment.currency ?? appointment.providerCurrency ?? 'XOF')} '
                                'ne sera pas remboursé.'
                          : 'Votre acompte de '
                                '${Formatters.formatCurrency(appointment.depositAmount, currency: appointment.currency ?? appointment.providerCurrency ?? 'XOF')} '
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
      // §15: label the button with the VERB, never « Oui ». The consequence —
      // whether the deposit is forfeited — is the computed body above.
      confirmLabel: 'Annuler le rendez-vous',
      cancelLabel: 'Garder',
    );
    if (!confirmed || !mounted) return;

    final success = await provider.cancelAppointment(widget.appointmentId);

    if (!mounted) return;

    if (success) {
      context.pop();
      AppSnackBar.show(context, 'Rendez-vous annulé', kind: SnackKind.success);
    } else {
      AppSnackBar.show(
        context,
        provider.error ?? 'Erreur lors de l’annulation',
        kind: SnackKind.error,
      );
    }
  }

  Future<void> _handleReschedule(Appointment appointment) async {
    // **No salon fetch.** The reschedule screen needed the whole salon object
    // for the booking's real duration and window — `durationMinutes` could be
    // null on a consumer payload, so a 3-hour braid was offered 30-minute
    // slots. The server backfills the duration from the catalogue that priced
    // the booking and stamps the window on the payload, so the facts arrive
    // with the appointment and « Impossible de charger le salon » — a message
    // about a fetch that no longer happens — goes with them.
    final newDateTime = await showRescheduleScreen(
      context: context,
      appointment: appointment,
    );
    if (newDateTime == null || !mounted) return;

    final provider = Provider.of<AppointmentProvider>(context, listen: false);
    final success = await provider.rescheduleAppointment(
      id: appointment.id,
      newDateTime: newDateTime,
    );

    if (!mounted) return;

    AppSnackBar.outcome(
      context,
      ok: success,
      success: 'Rendez-vous reporté',
      error: provider.error ?? 'Erreur',
    );
  }

  /// Pay-later: open the deposit sheet in submit mode (the booking exists).
  ///
  /// The Mobile Money handle rides the appointment. It used to be fetched from
  /// the public route, which made this the worst of the six: a client who owed
  /// a deposit at a salon that had stopped being listed opened the sheet with
  /// **nowhere to send the money**, on the one screen whose entire job is
  /// collecting it.
  Future<void> _handleSendDeposit(Appointment appointment) async {
    final sent = await showDepositSubmitSheet(
      context,
      appointmentId: appointment.id,
      depositAmount: appointment.depositAmount,
      balanceDue: appointment.balanceDue,
      providerName: appointment.providerName ?? 'le salon',
      depositOperator: appointment.depositMobileMoneyOperator,
      depositCountryCode: appointment.providerCountryCode,
      depositNumber: appointment.depositMobileMoneyNumber,
      currency: appointment.currency ?? appointment.providerCurrency,
    );
    if (sent != true || !mounted) return;
    AppSnackBar.show(
      context,
      'Acompte envoyé. En attente de confirmation du salon.',
      kind: SnackKind.success,
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
      AppSnackBar.showOn(
        messenger,
        res.error ?? 'Capture indisponible',
        kind: SnackKind.error,
      );
    }
  }

  /// State-aware deposit row: à envoyer (with the pay-later CTA) → en attente de
  /// confirmation (view proof) → confirmé. Myweli never holds the money.
  Widget _depositSection(Appointment a) {
    final hasProof = a.depositScreenshotUrl != null;
    final amount = Formatters.formatCurrency(
      a.depositAmount,
      currency: a.currency ?? a.providerCurrency ?? 'XOF',
    );

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
            text: 'Envoyer l’acompte',
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
          const SizedBox(height: AppTheme.spacingXS),
          Text(
            hint,
            style: AppTextStyles.bodySmall.copyWith(
              color: AppColors.textTertiary,
            ),
          ),
        ],
        if (action != null) ...[
          const SizedBox(height: AppTheme.spacingS),
          action,
        ],
      ],
    );
  }

  /// Add this upcoming appointment to the phone's native calendar, then open
  /// the OS "new event" sheet — the user saves it in their own calendar app
  /// (Myweli never writes the entry). Design: docs/design/appointment-calendar.md.
  ///
  /// Everything comes off the appointment. When the salon fetch failed this
  /// wrote « Rendez-vous — le salon » with **zero duration** and then reported
  /// success — the most dishonest of the six degradations, because the user
  /// was told it worked.
  Future<void> _addToCalendar(Appointment appointment) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await addAppointmentToCalendar(
      buildAppointmentCalendarEvent(
        providerName: appointment.providerName ?? 'le salon',
        providerAddress: appointment.providerAddress,
        serviceNames: appointment.serviceNames,
        start: appointment.appointmentDate,
        totalDurationMinutes: appointment.durationMinutes ?? 0,
        depositAmount: appointment.depositAmount,
        balanceDue: appointment.balanceDue,
        currency: appointment.currency ?? appointment.providerCurrency,
      ),
    );
    if (!mounted) return;
    AppSnackBar.outcomeOn(
      messenger,
      ok: ok,
      success: 'Rendez-vous ajouté à votre calendrier',
      error: 'Impossible d’ouvrir le calendrier',
    );
  }

  /// « Donner mon avis » — kept for a stopped salon: the visit happened, and
  /// the write is authenticated and appointment-scoped.
  ///
  /// No salon load. The sheet used one only to fill an artist picker whose
  /// value the server discards — `ReviewsService.submitForAppointment` derives
  /// `artistId`/`artistName` from the APPOINTMENT — so the picker was a
  /// control that controlled nothing. It now shows who actually served the
  /// booking, read off the payload.
  Future<void> _leaveReview(Appointment appointment) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: SubmitReviewSheet(
          providerId: appointment.providerId,
          appointmentId: appointment.id,
          artistName: appointment.artistName,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(title: const Text('Détails')),
      body: Consumer<AppointmentProvider>(
        builder: (context, provider, _) {
          if (provider.isLoading && provider.selectedAppointment == null) {
            return const LoadingIndicator();
          }

          final appointment = provider.selectedAppointment;
          if (appointment == null) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.error_outline,
                    size: AppTheme.iconXL,
                    color: AppColors.error,
                  ),
                  const SizedBox(height: AppTheme.spacingM),
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
                        value: Formatters.formatDate(
                          toSalonTime(
                            appointment.appointmentDate,
                            tz: appointment.providerTimezone,
                          ),
                        ),
                      ),
                      const SizedBox(height: AppTheme.spacingM),
                      _InfoRow(
                        icon: Icons.access_time,
                        label: 'Heure',
                        value: Formatters.formatTime(
                          toSalonTime(
                            appointment.appointmentDate,
                            tz: appointment.providerTimezone,
                          ),
                        ),
                      ),
                      SalonTimeHint(
                        tz: appointment.providerTimezone,
                        countryLabel: context
                            .watch<LocalityProvider>()
                            .countryName(appointment.providerCountryCode),
                        padding: const EdgeInsets.only(top: AppTheme.spacingXS),
                      ),
                      if (appointment.artistName case final artist?) ...[
                        const SizedBox(height: AppTheme.spacingM),
                        _InfoRow(
                          icon: Icons.person_outline,
                          label: 'Spécialiste',
                          value: artist,
                        ),
                      ],
                      const SizedBox(height: AppTheme.spacingM),
                      _InfoRow(
                        icon: Icons.attach_money,
                        label: 'Prix total',
                        value: Formatters.formatCurrency(
                          appointment.totalPrice,
                          currency:
                              appointment.currency ??
                              appointment.providerCurrency ??
                              'XOF',
                        ),
                      ),
                      if (appointment.depositAmount > 0) ...[
                        const SizedBox(height: AppTheme.spacingM),
                        _depositSection(appointment),
                        const SizedBox(height: AppTheme.spacingM),
                        _InfoRow(
                          icon: Icons.account_balance_wallet_outlined,
                          label: 'Solde à régler au salon',
                          value: Formatters.formatCurrency(
                            appointment.balanceDue,
                            currency:
                                appointment.currency ??
                                appointment.providerCurrency ??
                                'XOF',
                          ),
                        ),
                      ],
                      if (appointment.notes != null &&
                          appointment.notes!.isNotEmpty) ...[
                        const SizedBox(height: AppTheme.spacingM),
                        _InfoRow(
                          icon: Icons.note,
                          label: 'Notes',
                          value: appointment.notes!,
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: AppTheme.spacingL),
                // The salon stopped taking appointments (§12, §6 cell 6).
                //
                // Stated once, above the actions it explains — the client is
                // not left to infer it from a button that has quietly gone
                // missing. What stays is deliberate: « Annuler » (a stopped
                // salon must not trap anyone in a booking), « Appeler » /
                // « WhatsApp » (this is when they need the salon MOST), the
                // deposit block, and the calendar export.
                if (salonStoppedMessage(appointment.providerStatus)
                    case final stopped?) ...[
                  InlineFeedback(stopped, kind: SnackKind.info),
                  const SizedBox(height: AppTheme.spacingM),
                ],
                // Action Buttons
                if (appointment.status != AppointmentStatus.cancelled &&
                    appointment.status != AppointmentStatus.completed) ...[
                  if (appointment.appointmentDate.isAfter(AppClock.now())) ...[
                    // « Reporter » is withheld for a salon that is not live:
                    // the server refuses the move (`provider_suspended` /
                    // `provider_not_published`), so offering it would be a
                    // dead end with a button on it. Hiding is a courtesy OVER
                    // the server gate, never instead of one.
                    if (appointment.salonIsLive) ...[
                      AppButton(
                        text: 'Reporter',
                        icon: Icons.event_repeat,
                        isLoading: provider.isLoading,
                        onPressed: () => _handleReschedule(appointment),
                      ),
                      const SizedBox(height: AppTheme.spacingS),
                    ],
                    AppButton(
                      text: 'Ajouter au calendrier',
                      type: AppButtonType.secondary,
                      icon: Icons.event_available,
                      onPressed: () => _addToCalendar(appointment),
                    ),
                    const SizedBox(height: AppTheme.spacingS),
                  ],
                  AppButton(
                    text: 'Annuler le rendez-vous',
                    type: AppButtonType.secondary,
                    isLoading: provider.isLoading,
                    onPressed: () => _handleCancel(appointment),
                  ),
                  const SizedBox(height: AppTheme.spacingS),
                ],
                if (appointment.status == AppointmentStatus.completed) ...[
                  AppButton(
                    text: 'Donner mon avis',
                    icon: Icons.rate_review_outlined,
                    onPressed: () => _leaveReview(appointment),
                  ),
                  const SizedBox(height: AppTheme.spacingS),
                ],
                AppButton(
                  text: 'Appeler',
                  icon: Icons.phone,
                  onPressed: () => _contactSalon(appointment, whatsapp: false),
                ),
                const SizedBox(height: AppTheme.spacingS),
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
        Icon(icon, size: AppTheme.iconS, color: AppColors.textSecondary),
        const SizedBox(width: AppTheme.spacingSM),
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
              const SizedBox(height: AppTheme.spacingXS),
              Text(value, style: AppTextStyles.bodyMedium),
            ],
          ),
        ),
      ],
    );
  }
}
