import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants/failure_messages.dart';
import '../../core/constants/unnamed_salon.dart';
import '../../core/di/dependency_injection.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/text_styles.dart';
import '../../core/utils/app_clock.dart';
import '../../core/utils/booking_error_cta.dart';
import '../../core/utils/calendar_event.dart';
import '../../core/utils/cancellation_policy.dart';
import '../../core/utils/client_booking_rule.dart';
import '../../core/utils/deposit_state.dart';
import '../../core/utils/external_link.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/helpers.dart';
import '../../core/utils/rebook.dart';
import '../../core/utils/salon_place.dart';
import '../../core/utils/salon_time.dart';
import '../../models/appointment.dart';
import '../../providers/appointment_provider.dart';
import '../../providers/locality_provider.dart';
import '../../widgets/booking/cancellation_notice_box.dart';
import '../../widgets/booking/deposit_payment_sheet.dart';
import '../../widgets/common/app_async_view.dart';
import '../../widgets/common/app_button.dart';
import '../../widgets/common/app_card.dart';
import '../../widgets/common/app_chip.dart';
import '../../widgets/common/app_skeleton.dart';
import '../../widgets/common/app_snack_bar.dart';
import '../../widgets/common/confirm_dialog.dart';
import '../../widgets/common/inline_feedback.dart';
import '../../widgets/common/label_value_row.dart';
import '../../widgets/common/salon_photo_placeholder.dart';
import '../../widgets/common/salon_time_hint.dart';
import '../../widgets/common/screen_title.dart';
import '../../widgets/common/section_heading.dart';
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
    if (!whatsapp) return callPhone(context, raw);
    final uri = Uri.parse(
      'https://wa.me/${raw.replaceAll(RegExp(r'[^0-9]'), '')}',
    );
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
    // The salon's rule, the web's words (consumer-app-truth.md §2.2).
    final notice = cancellationNotice(appointment, AppClock.now());
    final confirmed = await showConfirmDialog(
      context,
      title: 'Annuler le rendez-vous ?',
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Êtes-vous sûr de vouloir annuler ce rendez-vous ?'),
          if (notice != null) ...[
            const SizedBox(height: AppTheme.spacingSM),
            CancellationNoticeBox(notice: notice),
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
      error: provider.error ?? kGenericErrorMessage,
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
      // « Wave · Salon »: a label, so the title form.
      providerName: salonNameOr(appointment.providerName, kUnnamedSalon),
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
        providerName: appointment.providerName,
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
      // Cards are `secondary` on `background` (SYSTEM §3.1): the step that
      // lifts them, now they have no shadow (B9.8 F2).
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const ScreenTitle('Rendez-vous')),
      body: Consumer<AppointmentProvider>(
        builder: (context, provider, _) {
          // The provider's selection is app-wide and survives the screen: on
          // the way to B it still holds A. Shown as it was, A's details — and
          // A's actions — stood on B's screen until B answered.
          final selected = provider.selectedAppointment;
          return AppAsyncView<Appointment>(
            isLoading: provider.isLoading,
            error: provider.error,
            data: selected?.id == widget.appointmentId ? selected : null,
            isEmpty: (_) => false,
            loading: const SkeletonDetail(sections: 3),
            empty: const SizedBox.shrink(),
            onRetry: () => provider.loadAppointmentById(widget.appointmentId),
            builder: (context, appointment) =>
                _detail(context, provider, appointment),
          );
        },
      ),
    );
  }

  Widget _detail(
    BuildContext context,
    AppointmentProvider provider,
    Appointment appointment,
  ) {
    // One instant per build: the chip, the sentence, the deposit row and every
    // action ask the client rule with the same clock.
    final now = AppClock.now();
    final deposit = depositState(appointment, now);
    final currency =
        appointment.currency ?? appointment.providerCurrency ?? 'XOF';
    final upcoming =
        (appointment.status == AppointmentStatus.pending ||
            appointment.status == AppointmentStatus.confirmed) &&
        appointment.appointmentDate.isAfter(now);
    final open =
        appointment.status == AppointmentStatus.pending ||
        appointment.status == AppointmentStatus.confirmed;
    final rebook = canRebook(appointment, now);
    // One primary per state (SYSTEM §1): money first, then the move, then
    // the next booking.
    final sendIsPrimary = deposit?.action == DepositAction.send;

    final sections = <Widget>[
      _header(context, appointment, now),
      _whenSection(context, appointment, upcoming),
      if (appointment.serviceNames.isNotEmpty) _servicesSection(appointment),
      ?_salonSection(context, appointment),
      _paymentSection(appointment, deposit, currency),
      if ((appointment.notes ?? '').trim().isNotEmpty)
        _section(
          title: 'Notes',
          children: [
            Text(appointment.notes!.trim(), style: AppTextStyles.bodyMedium),
          ],
        ),
    ];

    final actions = <Widget>[
      // « Reporter » is withheld for a salon that is not live: the server
      // refuses the move (`provider_suspended` / `provider_not_published`), so
      // offering it would be a dead end with a button on it.
      if (upcoming && appointment.salonIsLive)
        AppButton(
          text: 'Reporter',
          icon: Icons.event_repeat,
          type: sendIsPrimary ? AppButtonType.secondary : AppButtonType.primary,
          isLoading: provider.isLoading,
          onPressed: () => _handleReschedule(appointment),
        ),
      // Only an open booking can be changed. A no-show is closed like a
      // cancellation or a completed visit: the server refuses to cancel it
      // (`invalid_state`) (consumer-app-truth.md §2.7).
      if (open)
        AppButton(
          text: 'Annuler le rendez-vous',
          type: AppButtonType.secondary,
          isLoading: provider.isLoading,
          onPressed: () => _handleCancel(appointment),
        ),
      // Decision 201: the web's rule (decision 183) — any booking that is not
      // upcoming, at a salon still taking appointments.
      if (rebook)
        AppButton(
          text: 'Réserver à nouveau',
          icon: Icons.refresh,
          onPressed: () => context.push(rebookLocation(appointment)),
        ),
      if (appointment.status == AppointmentStatus.completed)
        AppButton(
          text: 'Donner mon avis',
          icon: Icons.rate_review_outlined,
          type: AppButtonType.secondary,
          onPressed: () => _leaveReview(appointment),
        ),
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppTheme.spacingM),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, section) in sections.indexed) ...[
            if (i > 0) const SizedBox(height: AppTheme.spacingM),
            section,
          ],
          if (actions.isNotEmpty) ...[
            const SizedBox(height: AppTheme.spacingL),
            for (final (i, action) in actions.indexed) ...[
              if (i > 0) const SizedBox(height: AppTheme.spacingS),
              action,
            ],
          ],
        ],
      ),
    );
  }

  /// A titled card: `SectionHeading` in `titleMedium`, announced as a level-2
  /// heading (SYSTEM §13.4), then its content.
  Widget _section({required String title, required List<Widget> children}) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeading(
            title: title,
            style: AppTextStyles.titleMedium,
            headingLevel: 2,
          ),
          const SizedBox(height: AppTheme.spacingS),
          ...children,
        ],
      ),
    );
  }

  /// The photo, the salon's name, the status chip and its sentence, and the
  /// stopped-salon sentence (appointment-detail-complete.md §2.3).
  Widget _header(BuildContext context, Appointment a, DateTime now) {
    final photo = a.providerPhotoUrl;
    final sentence = clientStatusSentence(a, now);
    final stopped = salonStoppedMessage(a.providerStatus);
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Decoration: the name below says the same, so it is excluded from
          // semantics. 3:2, the salon cover's own shape (web `aspect-cover`,
          // web-swiss-salon.md §1), clipped by the card's radius.
          ClipRRect(
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(AppTheme.radiusXL),
            ),
            child: AspectRatio(
              aspectRatio: kSalonCoverAspect,
              child: ExcludeSemantics(
                child: photo != null && photo.isNotEmpty
                    ? TimedCachedImage(
                        imageUrl: photo,
                        width: double.infinity,
                        height: double.infinity,
                        alignment: kSalonCoverCut,
                      )
                    : const SalonPhotoPlaceholder(
                        width: double.infinity,
                        height: double.infinity,
                      ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(AppTheme.spacingM),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // The salon's name is this screen's subject: level 1.
                Semantics(
                  headingLevel: 1,
                  child: Text(
                    salonNameOr(a.providerName, kUnnamedSalon),
                    style: AppTextStyles.titleLarge.copyWith(
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(height: AppTheme.spacingS),
                AppChip.status(
                  label: clientStatusLabel(a, now),
                  tone: clientStatusTone(a, now),
                ),
                if (sentence != null) ...[
                  const SizedBox(height: AppTheme.spacingS),
                  Text(
                    sentence,
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
                // The salon stopped taking appointments (§12, §6 cell 6):
                // stated once, above the actions it explains.
                if (stopped != null) ...[
                  const SizedBox(height: AppTheme.spacingM),
                  InlineFeedback(stopped, kind: SnackKind.info),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// « Le rendez-vous »: the date with its weekday, the start and end, the
  /// specialist and, while it is ahead, the calendar (§2.4).
  Widget _whenSection(BuildContext context, Appointment a, bool upcoming) {
    final tz = a.providerTimezone;
    final start = toSalonTime(a.appointmentDate, tz: tz);
    final minutes = a.durationMinutes;
    // No duration in words: the two surfaces' formatters disagree, and the end
    // time already says it.
    final time = minutes != null && minutes > 0
        ? '${Formatters.formatTime(start)} – '
              '${Formatters.formatTime(toSalonTime(a.appointmentDate.add(Duration(minutes: minutes)), tz: tz))}'
        : Formatters.formatTime(start);
    return _section(
      title: 'Le rendez-vous',
      children: [
        LabelValueRow(label: 'Date', value: Formatters.formatDate(start)),
        const SizedBox(height: AppTheme.spacingXS),
        LabelValueRow(label: 'Heure', value: time),
        SalonTimeHint(
          tz: tz,
          countryLabel: context.watch<LocalityProvider>().countryName(
            a.providerCountryCode,
          ),
          padding: const EdgeInsets.only(top: AppTheme.spacingXS),
        ),
        if (a.artistName case final artist?) ...[
          const SizedBox(height: AppTheme.spacingXS),
          LabelValueRow(label: 'Spécialiste', value: artist),
        ],
        if (upcoming) ...[
          const SizedBox(height: AppTheme.spacingM),
          AppButton(
            text: 'Ajouter au calendrier',
            type: AppButtonType.secondary,
            icon: Icons.event_available,
            onPressed: () => _addToCalendar(a),
          ),
        ],
      ],
    );
  }

  /// « Prestations »: one line per service, in the booking's order (§2.5).
  Widget _servicesSection(Appointment a) {
    return _section(
      title: 'Prestations',
      children: [
        for (final (i, name) in a.serviceNames.indexed) ...[
          if (i > 0) const SizedBox(height: AppTheme.spacingXS),
          Text(name, style: AppTextStyles.bodyMedium),
        ],
      ],
    );
  }

  /// « Le salon »: the address, and each way to reach it only when it works
  /// (§2.6). Null when there is nothing to show.
  Widget? _salonSection(BuildContext context, Appointment a) {
    final lines = salonAddressLines(a);
    final buttons = <Widget>[
      if (a.hasPosition)
        AppButton(
          text: 'Itinéraire',
          icon: Icons.directions,
          type: AppButtonType.secondary,
          isFullWidth: false,
          onPressed: () => Helpers.launchNavigation(
            latitude: a.providerLatitude!,
            longitude: a.providerLongitude!,
            label: a.providerName,
            context: context,
          ),
        ),
      if ((a.providerPhone ?? '').isNotEmpty)
        AppButton(
          text: 'Appeler',
          icon: Icons.phone,
          type: AppButtonType.secondary,
          isFullWidth: false,
          onPressed: () => _contactSalon(a, whatsapp: false),
        ),
      if ((a.providerWhatsapp ?? '').isNotEmpty)
        AppButton(
          text: 'WhatsApp',
          icon: Icons.chat_outlined,
          type: AppButtonType.secondary,
          isFullWidth: false,
          onPressed: () => _contactSalon(a, whatsapp: true),
        ),
      // Withheld for a stopped salon: its page is gone (Decision C).
      if (a.salonIsLive)
        AppButton(
          text: 'Voir le salon',
          icon: Icons.storefront_outlined,
          type: AppButtonType.secondary,
          isFullWidth: false,
          onPressed: () => context.push('/provider/${a.providerId}'),
        ),
    ];
    if (lines.isEmpty && buttons.isEmpty) return null;
    return _section(
      title: 'Le salon',
      children: [
        for (final line in lines)
          Text(
            line,
            style: AppTextStyles.bodyMedium.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        if (buttons.isNotEmpty) ...[
          if (lines.isNotEmpty) const SizedBox(height: AppTheme.spacingM),
          Wrap(
            spacing: AppTheme.spacingS,
            runSpacing: AppTheme.spacingS,
            children: buttons,
          ),
        ],
      ],
    );
  }

  /// « Paiement »: the total, the deposit's state and the balance while the
  /// booking is open (§2.7, decision 197).
  Widget _paymentSection(
    Appointment a,
    DepositState? deposit,
    String currency,
  ) {
    String money(double v) => Formatters.formatCurrency(v, currency: currency);
    return _section(
      title: 'Paiement',
      children: [
        LabelValueRow(label: 'Total', value: money(a.totalPrice)),
        if (deposit != null) ...[
          const SizedBox(height: AppTheme.spacingXS),
          LabelValueRow(label: deposit.label, value: money(a.depositAmount)),
          if (deposit.sentence case final line?) ...[
            const SizedBox(height: AppTheme.spacingXS),
            Text(
              line,
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.textTertiary,
              ),
            ),
          ],
          if (deposit.action == DepositAction.send) ...[
            const SizedBox(height: AppTheme.spacingS),
            AppButton(
              text: 'Envoyer l’acompte',
              icon: Icons.send_outlined,
              onPressed: () => _handleSendDeposit(a),
            ),
          ] else if (deposit.action == DepositAction.viewProof) ...[
            const SizedBox(height: AppTheme.spacingS),
            AppButton(
              text: 'Voir ma capture',
              type: AppButtonType.secondary,
              onPressed: () => _viewMyProof(a),
            ),
          ],
          if (deposit.showBalance) ...[
            const SizedBox(height: AppTheme.spacingS),
            LabelValueRow(
              label: 'Solde à régler au salon',
              value: money(a.balanceDue),
            ),
          ],
        ],
      ],
    );
  }
}

/// The salon cover's shape, 3:2 — the web's `aspect-cover` token, the shape
/// the owner chose for the salon page (web-swiss-salon.md §1). A named
/// constant, as SYSTEM.md §5 « What §5 does not govern » allows.
const double kSalonCoverAspect = 3 / 2;

/// Where the cover is cut: 50 % across, 20 % down — the web cards'
/// `object-subject`, so a head in an upright photo stays in the frame.
const Alignment kSalonCoverCut = Alignment(0, -0.6);
