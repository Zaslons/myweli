import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/di/dependency_injection.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/text_styles.dart';
import '../../core/utils/app_clock.dart';
import '../../core/utils/calendar_event.dart';
import '../../core/utils/cancellation_policy.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/salon_time.dart';
import '../../models/appointment.dart';
import '../../models/provider.dart' as models;
import '../../providers/appointment_provider.dart';
import '../../providers/locality_provider.dart';
import '../../providers/provider_provider.dart';
import '../../widgets/booking/deposit_payment_sheet.dart';
import '../../widgets/common/app_button.dart';
import '../../widgets/common/app_snack_bar.dart';
import '../../widgets/common/confirm_dialog.dart';
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
  String? _artistName;
  String? _providerCountryCode;
  String? _providerLookupFor;

  /// **Retained now, not discarded** (A14c §19.2). This lookup already fetched
  /// the salon and kept two strings out of it. Reschedule needs the services to
  /// compute the booking's real duration — `Appointment.durationMinutes` is a
  /// provider-enriched field and can be null on a consumer payload — so keeping
  /// the object costs one reference and saves a second round trip.
  models.Provider? _salon;

  void _maybeResolveProviderFacts(Appointment appointment) {
    if (_providerLookupFor == appointment.providerId) return;
    _providerLookupFor = appointment.providerId;
    final artistId = appointment.artistId;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final res = await serviceLocator.providerService.getProviderById(
        appointment.providerId,
      );
      if (!mounted) return;
      final name = (artistId == null || artistId.isEmpty)
          ? null
          : res.data?.artists
                .where((a) => a.id == artistId)
                .map((a) => a.name)
                .firstOrNull;
      setState(() {
        _salon = res.data;
        _providerCountryCode = res.data?.countryCode;
        if (name != null) _artistName = name;
      });
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
    // **The salon is required, and that is the fix.** The old flow pushed
    // `/booking/date-time` with no `durationMinutes`, so the target recomputed
    // it from the CURRENT catalogue and a freshly-defaulted length variant — a
    // 3-hour braid could be offered 30-minute slots. `_maybeResolveProviderFacts`
    // already loads the salon on every appointment; it just used to throw it
    // away.
    var salon = _salon;
    if (salon == null) {
      final res = await serviceLocator.providerService.getProviderById(
        appointment.providerId,
      );
      if (!mounted) return;
      salon = res.data;
    }
    if (salon == null) {
      AppSnackBar.show(
        context,
        'Impossible de charger le salon',
        kind: SnackKind.error,
      );
      return;
    }

    final newDateTime = await showRescheduleScreen(
      context: context,
      appointment: appointment,
      salon: salon,
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

  /// Pay-later: open the deposit sheet in submit mode (the booking exists). The
  /// salon's Mobile Money handle comes from the provider's deposit policy.
  Future<void> _handleSendDeposit(Appointment appointment) async {
    final providerProvider = Provider.of<ProviderProvider>(
      context,
      listen: false,
    );
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
      depositCountryCode: p?.countryCode,
      depositNumber: p?.depositMobileMoneyNumber,
      currency: appointment.currency ?? p?.currency,
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

  /// Add this upcoming appointment to the phone's native calendar. Loads the
  /// provider (reusing the cached fetch) for the title/location/services, then
  /// opens the OS "new event" sheet — the user saves it in their own calendar
  /// app (Myweli never writes the entry). Design: docs/design/appointment-calendar.md.
  Future<void> _addToCalendar(Appointment appointment) async {
    final messenger = ScaffoldMessenger.of(context);
    final providerProvider = Provider.of<ProviderProvider>(
      context,
      listen: false,
    );
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

  Future<void> _leaveReview(Appointment appointment) async {
    final providerProvider = Provider.of<ProviderProvider>(
      context,
      listen: false,
    );
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
      appBar: AppBar(title: const Text('Détails')),
      body: Consumer<AppointmentProvider>(
        builder: (context, provider, _) {
          if (provider.isLoading && provider.selectedAppointment == null) {
            return const LoadingIndicator();
          }

          final appointment = provider.selectedAppointment;
          if (appointment != null) _maybeResolveProviderFacts(appointment);
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
                            .countryName(_providerCountryCode),
                        padding: const EdgeInsets.only(top: AppTheme.spacingXS),
                      ),
                      if (_artistName != null) ...[
                        const SizedBox(height: AppTheme.spacingM),
                        _InfoRow(
                          icon: Icons.person_outline,
                          label: 'Spécialiste',
                          value: _artistName!,
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
                // Action Buttons
                if (appointment.status != AppointmentStatus.cancelled &&
                    appointment.status != AppointmentStatus.completed) ...[
                  if (appointment.appointmentDate.isAfter(AppClock.now())) ...[
                    AppButton(
                      text: 'Reporter',
                      icon: Icons.event_repeat,
                      isLoading: provider.isLoading,
                      onPressed: () => _handleReschedule(appointment),
                    ),
                    const SizedBox(height: AppTheme.spacingS),
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
