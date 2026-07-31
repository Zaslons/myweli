import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/text_styles.dart';
import '../../core/utils/booking_duration.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/salon_time.dart';
import '../../models/appointment.dart';
import '../../models/provider.dart' as models;
import '../../models/service.dart';
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
/// **The salon is required, not optional**, and that is what fixes the live
/// defect this screen replaces. `Appointment.durationMinutes` is a
/// provider-enriched field that can be null on a consumer payload, so the only
/// correct source for "how long does this booking need" is the salon's own
/// services. The old flow passed nothing and let the target recompute from a
/// freshly-defaulted length variant — so rescheduling a 3-hour braid could be
/// offered 30-minute slots.
Future<DateTime?> showRescheduleScreen({
  required BuildContext context,
  required Appointment appointment,
  required models.Provider salon,
}) {
  return Navigator.of(context).push<DateTime>(
    MaterialPageRoute<DateTime>(
      fullscreenDialog: true,
      builder: (_) => RescheduleScreen(appointment: appointment, salon: salon),
    ),
  );
}

/// Public so tests can pump it without a navigator — the A14a/A14b idiom.
class RescheduleScreen extends StatefulWidget {
  const RescheduleScreen({
    super.key,
    required this.appointment,
    required this.salon,
  });

  final Appointment appointment;
  final models.Provider salon;

  @override
  State<RescheduleScreen> createState() => _RescheduleScreenState();
}

class _RescheduleScreenState extends State<RescheduleScreen> {
  late DateTime _date;
  DateTime? _slot;

  String? get _tz =>
      widget.appointment.providerTimezone ?? widget.salon.timezone;

  /// The services this booking actually contains, resolved against the salon's
  /// current catalogue. The appointment carries ids and nothing else.
  List<Service> get _services => widget.salon.services
      .where((s) => widget.appointment.serviceIds.contains(s.id))
      .toList();

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
    final services = _services;

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
                    // booking is this?". The salon load that makes the duration
                    // correct pays for this at no extra cost.
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
                            widget.salon.name,
                            style: AppTextStyles.titleMedium,
                          ),
                          if (services.isNotEmpty) ...[
                            const SizedBox(height: AppTheme.spacingXS),
                            Text(
                              services.map((s) => s.name).join(' · '),
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
                      // The salon's catalogue, never the appointment's
                      // nullable enriched field. §19.2.
                      durationMinutes: services.isEmpty
                          ? widget.appointment.durationMinutes
                          : totalBookingDuration(services, null),
                      tz: _tz,
                      countryCode: widget.salon.countryCode,
                      // A14d. A consumer reschedule is a CLIENT path, so the
                      // salon's window binds it — the pro's own reschedule is
                      // exempt server-side and lives on a different screen.
                      horizon: Duration(
                        days: widget.salon.availability.bookingHorizonDays,
                      ),
                      minimumNotice: Duration(
                        minutes: widget.salon.availability.minimumNoticeMinutes,
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
