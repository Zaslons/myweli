import 'package:flutter/material.dart';

import '../../core/constants/booking_horizons.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/text_styles.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/salon_time.dart';
import '../../models/appointment.dart';
import '../../widgets/booking/slot_picker.dart';
import '../../widgets/common/app_button.dart';

/// Move an existing appointment to another free slot (A14c §19.2).
///
/// **A route, not a mode on the booking hub**, and the contract decides it
/// rather than taste. `POST /appointments/{id}/reschedule` accepts
/// `newDateTime` and an `artistId` marked **PROVIDER ONLY**, and carries the
/// deposit and balance over unchanged. So of the hub's three sections, services
/// and artist are both forbidden here — changing either changes the price and
/// therefore the deposit, which is a cancel-and-rebook — and the hub ends in a
/// deposit sheet and `createAppointment`, which is the wrong ending entirely.
/// A "reschedule mode" would suppress two thirds of that screen and replace its
/// last step. The reuse belongs at the component level, and it is [SlotPicker].
///
/// **Not in the router**, for the same reason `showMyweliDatePicker` is not: it
/// returns a value to exactly one caller and is never deep-linked. Pushed as a
/// `MaterialPageRoute`, the shape the picker family already uses.
///
/// **The appointment carries everything, and that is what fixes the live
/// defect this screen replaces.** The screen used to require the whole salon
/// object for one reason: `Appointment.durationMinutes` could be null on a
/// consumer payload, so the only correct source for « how long does this
/// booking need » was the salon's own catalogue — the old flow passed nothing
/// and let the target recompute from a freshly-defaulted length variant, so
/// rescheduling a 3-hour braid could be offered 30-minute slots.
///
/// That reason is gone: the server backfills `durationMinutes` from the
/// catalogue that priced the booking, and stamps the salon's name, timezone,
/// country and booking window onto the payload (Decision C). Requiring the
/// salon now would mean fetching it from the public route — the door that
/// stops opening for a salon which is `draft` or `suspended`.
Future<DateTime?> showRescheduleScreen({
  required BuildContext context,
  required Appointment appointment,
}) {
  return Navigator.of(context).push<DateTime>(
    MaterialPageRoute<DateTime>(
      fullscreenDialog: true,
      builder: (_) => RescheduleScreen(appointment: appointment),
    ),
  );
}

/// Public so tests can pump it without a navigator — the A14a/A14b idiom.
class RescheduleScreen extends StatefulWidget {
  const RescheduleScreen({super.key, required this.appointment});

  final Appointment appointment;

  @override
  State<RescheduleScreen> createState() => _RescheduleScreenState();
}

class _RescheduleScreenState extends State<RescheduleScreen> {
  late DateTime _date;
  DateTime? _slot;

  String? get _tz => widget.appointment.providerTimezone;

  @override
  void initState() {
    super.initState();
    // Open on the day the appointment is currently on, in SALON time — the
    // wall clock the user recognises, never the device's.
    final wall = toSalonTime(widget.appointment.appointmentDate, tz: _tz);
    _date = DateTime(wall.year, wall.month, wall.day);
  }

  @override
  Widget build(BuildContext context) {
    final wall = toSalonTime(widget.appointment.appointmentDate, tz: _tz);
    final services = widget.appointment.serviceNames;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: 'Fermer',
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Reporter le rendez-vous'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppTheme.spacingM),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // **What is being moved.** The screen this replaces showed
                    // none of it — a bare picker with no answer to "which
                    // booking is this?". The enrichment that makes the duration
                    // correct carries the name and the services too.
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(AppTheme.spacingM),
                      decoration: BoxDecoration(
                        color: AppColors.secondary,
                        borderRadius: BorderRadius.circular(AppTheme.radiusXL),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.appointment.providerName ?? 'le salon',
                            style: AppTextStyles.titleMedium,
                          ),
                          if (services.isNotEmpty) ...[
                            const SizedBox(height: AppTheme.spacingXS),
                            Text(
                              services.join(' · '),
                              style: AppTextStyles.bodySmall.copyWith(
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                          const SizedBox(height: AppTheme.spacingS),
                          Row(
                            children: [
                              const Icon(
                                Icons.event_busy,
                                size: AppTheme.iconS,
                                color: AppColors.textTertiary,
                              ),
                              const SizedBox(width: AppTheme.spacingS),
                              Expanded(
                                child: Text(
                                  'Actuellement : '
                                  '${Formatters.formatDate(wall)} à '
                                  '${Formatters.formatTime(wall)}',
                                  style: AppTextStyles.bodySmall.copyWith(
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppTheme.spacingL),
                    Text('Nouvelle date', style: AppTextStyles.titleMedium),
                    const SizedBox(height: AppTheme.spacingS),
                    SlotPicker(
                      providerId: widget.appointment.providerId,
                      selectedDate: _date,
                      selectedSlot: _slot,
                      serviceIds: widget.appointment.serviceIds,
                      artistId: widget.appointment.artistId,
                      // Server-backfilled from the catalogue that priced the
                      // booking, so it is never the freshly-defaulted length
                      // the old flow recomputed. §19.2.
                      durationMinutes: widget.appointment.durationMinutes,
                      tz: _tz,
                      countryCode: widget.appointment.providerCountryCode,
                      // A14d. A consumer reschedule is a CLIENT path, so the
                      // salon's window binds it — the pro's own reschedule is
                      // exempt server-side and lives on a different screen.
                      horizon: Duration(
                        days:
                            widget.appointment.providerBookingHorizonDays ??
                            kDefaultBookingHorizonDays,
                      ),
                      minimumNotice: Duration(
                        minutes:
                            widget.appointment.providerMinimumNoticeMinutes ??
                            kDefaultMinimumNoticeMinutes,
                      ),
                      onDateChanged: (d) => setState(() {
                        _date = d;
                        // A slot on the old day cannot survive a day change.
                        _slot = null;
                      }),
                      onSlotSelected: (s) => setState(() => _slot = s),
                    ),
                  ],
                ),
              ),
            ),
            // **Selecting is not submitting.** Moving a booking is
            // consequential, and the flow this replaces popped the instant a
            // time was chosen. The button states what will happen.
            Padding(
              padding: const EdgeInsets.all(AppTheme.spacingM),
              child: AppButton(
                text: _slot == null
                    ? 'Choisissez un créneau'
                    : 'Reporter à ${Formatters.formatTime(toSalonTime(_slot!, tz: _tz))}',
                icon: Icons.event_repeat,
                onPressed: _slot == null
                    ? null
                    : () => Navigator.of(context).pop(_slot),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
