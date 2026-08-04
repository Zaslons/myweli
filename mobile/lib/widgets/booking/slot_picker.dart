import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/constants/booking_horizons.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/text_styles.dart';
import '../../core/utils/app_clock.dart';
import '../../core/utils/booking_error_cta.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/salon_time.dart';
import '../../providers/appointment_provider.dart';
import '../../providers/locality_provider.dart';
import '../common/empty_state.dart';
import '../common/loading_indicator.dart';
import '../common/myweli_date_picker.dart';
import '../common/salon_time_hint.dart';

/// Pick a day, then one of the salon's **actually free** starts on it (A14c §19).
///
/// **Why this is a component and not a screen.** Two surfaces need exactly this
/// and nothing else: the booking hub's « Date et heure » card, and consumer
/// reschedule. They were separate implementations, and the second one — inside
/// `date_time_selection_screen` — was missing the first one's in-flight guard,
/// compared slots by hour-and-minute only (so it could match the wrong day),
/// and offered a 90-day horizon where the hub offered 365.
///
/// **Why not reuse the hub screen for reschedule**, which is the obvious other
/// answer: the reschedule contract accepts `newDateTime` and nothing else a
/// consumer may set (`artistId` is marked PROVIDER ONLY, and deposit + balance
/// carry over unchanged). Of the hub's three sections, services and artist are
/// both forbidden — changing them changes the price and therefore the deposit,
/// which is a cancel-and-rebook — and the hub ends in a deposit sheet and
/// `createAppointment`. A "reschedule mode" would suppress two thirds of the
/// screen and replace its ending, so the reuse belongs at this level instead.
///
/// **It owns the request race.** `_reqId` is a monotonic token: a response that
/// is not the newest is dropped. The hub fires concurrent loads from seven
/// places (a service tap, a length change, two artist taps, the card header, a
/// new date, and its own prefill), and reschedule fires from two — without the
/// token, a slow answer for Tuesday can land after a fast one for Wednesday and
/// paint the wrong day's slots under the right day's heading.
class SlotPicker extends StatefulWidget {
  const SlotPicker({
    super.key,
    required this.providerId,
    required this.selectedDate,
    required this.onDateChanged,
    required this.onSlotSelected,
    this.serviceIds = const [],
    this.artistId,
    this.durationMinutes,
    this.selectedSlot,
    this.tz,
    this.countryCode,
    this.onInteraction,
    this.horizon = kBookingHorizon,
    this.minimumNotice = const Duration(minutes: kDefaultMinimumNoticeMinutes),
    this.refreshSignal,
  });

  final String providerId;

  /// The day whose slots are shown. **Controlled**: the host owns it, because
  /// the hub also sets it from outside (picking a service auto-jumps to the
  /// earliest free day).
  final DateTime selectedDate;
  final ValueChanged<DateTime> onDateChanged;

  /// The chosen start, as an **instant**. Compared with `isAtSameMomentAs`,
  /// never by hour and minute — `date_time_selection_screen` compared
  /// `hour == hour && minute == minute`, which matches 14:00 on any day.
  final DateTime? selectedSlot;
  final ValueChanged<DateTime> onSlotSelected;

  final List<String> serviceIds;
  final String? artistId;

  /// Minutes the booking needs. **Resolved by the caller, not derived here** —
  /// that is what keeps `models.Provider` out of this file and lets reschedule,
  /// which has an `Appointment` and no salon in hand, use the same widget.
  /// Null falls back to [kDefaultSlotDuration].
  final int? durationMinutes;

  /// The salon's zone, for the times shown and for [SalonTimeHint].
  final String? tz;

  /// The salon's ISO country code — **the code, not the label**.
  ///
  /// Resolving it to a name needs `LocalityProvider`, and where that lookup
  /// happens is a performance decision rather than a style one. Three screens
  /// currently write `context.watch<LocalityProvider>().countryName(...)` in
  /// their own `build`, which rebuilds the WHOLE screen when the locality tree
  /// loads — on the booking hub that is 1,226 lines redrawn to update one line
  /// of grey text.
  ///
  /// So the lookup lives in a `Selector` scoped to the hint below. [SalonTimeHint]
  /// itself stays a pure function of its props — it has no provider
  /// dependencies, which is what lets `salon_time_hint_test.dart` pump it in
  /// isolation with a `deviceOffsetOverride`, and pushing the lookup *into* it
  /// would take that away from every future test.
  ///
  /// The same duplication at `booking_confirmation_screen:361` and
  /// `appointment_detail_screen:504` is **left alone deliberately**: fixing it
  /// means touching two screens this slice has no other business in.
  final String? countryCode;

  /// Fired before any user-driven change, for hosts that track how a user
  /// entered a flow. The hub uses it; reschedule does not.
  final VoidCallback? onInteraction;

  /// How far ahead the day picker reaches — the salon's own
  /// `bookingHorizonDays` since A14d, falling back to [kBookingHorizon].
  ///
  /// Two `Duration`s rather than an `Availability`, deliberately: this file
  /// keeps `models.Provider` out (see the class doc), which is what lets the
  /// hub and the reschedule screen share it. The caller resolves; this widget
  /// only bounds and explains.
  final Duration horizon;

  /// How soon before a start a client may still book — the salon's own
  /// `minimumNoticeMinutes` (A14d).
  ///
  /// The widget never enforces it (the server does); it uses it to say WHY a
  /// day is empty and to offer the first day that is not.
  final Duration minimumNotice;

  /// Bump to force a re-fetch with the same inputs.
  ///
  /// **Without this the extraction would silently lose a refresh.** The hub
  /// re-loaded unconditionally when the « Date et heure » card was re-opened
  /// (`onHeaderTap`), which matters: slots go stale while a user is deciding,
  /// and someone else may have taken the 14:00 in the meantime. A
  /// `didUpdateWidget` that only watches the query inputs would see no change
  /// and skip it.
  ///
  /// Declarative rather than a `GlobalKey`-reachable `reload()`, so a test can
  /// drive it by pumping and the widget keeps one path into `_load`.
  final Object? refreshSignal;

  @override
  State<SlotPicker> createState() => _SlotPickerState();
}

/// The duration assumed when the caller has none — a single 30 that was three
/// separate inline literals before this file existed (the hub twice, and the
/// screen A14c deletes).
/// Why a day offered nothing — A14d. See `SlotPicker._emptyReason`.
enum _EmptyReason { past, beyondHorizon, tooSoon, full }

const int kDefaultSlotDuration = 30;

class _SlotPickerState extends State<SlotPicker> {
  List<DateTime> _slots = const [];
  bool _loading = false;

  /// Set when the salon could not be ASKED — distinct from « no free slot »,
  /// which is `_slots.isEmpty` with no error. See [AppointmentProvider
  /// .getAvailableTimeSlots]; the two rendered the same sentence until A14c.
  String? _error;

  /// Non-null when retrying cannot succeed — the way out goes elsewhere.
  BookingErrorCta? _errorCta;

  int _reqId = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void didUpdateWidget(SlotPicker old) {
    super.didUpdateWidget(old);
    // Everything the query depends on. The hub mutates `serviceIds`,
    // `artistId` and `durationMinutes` from outside while this is mounted, and
    // used to re-fire the load by hand at four separate call sites.
    // `listEquals`, not `join(',')`: this runs on EVERY parent rebuild, and the
    // hub `setState`s constantly — two string allocations per frame to answer a
    // question `listEquals` answers in O(n) with none.
    if (old.selectedDate != widget.selectedDate ||
        old.artistId != widget.artistId ||
        old.durationMinutes != widget.durationMinutes ||
        old.refreshSignal != widget.refreshSignal ||
        !listEquals(old.serviceIds, widget.serviceIds)) {
      _load();
    }
  }

  Future<void> _load() async {
    final reqId = ++_reqId;
    setState(() {
      _loading = true;
      _error = null;
      _errorCta = null;
    });

    final res = await context.read<AppointmentProvider>().getAvailableTimeSlots(
      providerId: widget.providerId,
      date: widget.selectedDate,
      serviceIds: widget.serviceIds.isNotEmpty ? widget.serviceIds : null,
      artistId: widget.artistId,
      durationMinutes: widget.durationMinutes ?? kDefaultSlotDuration,
    );

    if (!mounted || reqId != _reqId) return;
    setState(() {
      _slots = res.slots;
      _error = res.error;
      _errorCta = bookingErrorCta(res.code);
      _loading = false;
    });
  }

  // ---- A14d — why is this day empty? ------------------------------------
  //
  // Three conditions render as « nothing here », and they are not the same
  // sentence. Claimed only when CERTAIN: `_full` is the catch-all and absorbs
  // closed weekdays, blocked dates and genuine capacity, so a day is never
  // mislabelled a window breach. The reverse — calling a window breach « full »
  // — is the defect this exists to end.

  /// The last day a client may book, inclusive — matching the server, which
  /// refuses only days strictly after `today + horizon`.
  DateTime get _lastBookableDay {
    final t = salonToday(tz: widget.tz);
    // Field arithmetic so the day survives a DST boundary; `salonToday`
    // returns a UTC-flagged salon day, so this is exact.
    return DateTime(t.year, t.month, t.day + widget.horizon.inDays);
  }

  /// The first day that can contain a bookable start.
  DateTime get _firstBookableDay {
    final earliest = AppClock.now().toUtc().add(widget.minimumNotice);
    final wall = toSalonTime(earliest, tz: widget.tz);
    return DateTime(wall.year, wall.month, wall.day);
  }

  _EmptyReason get _emptyReason {
    final day = DateTime(
      widget.selectedDate.year,
      widget.selectedDate.month,
      widget.selectedDate.day,
    );
    // A day already gone is not « too soon » — that sentence is about a delay
    // before a start, and it reads as nonsense on a date four months past.
    // Reachable: `RescheduleScreen` seeds from the appointment's OWN day and
    // is deliberately not clamped, so a past booking opens here.
    final today = salonToday(tz: widget.tz);
    if (day.isBefore(DateTime(today.year, today.month, today.day))) {
      return _EmptyReason.past;
    }
    // Horizon first, mirroring the server's ordering. The both-at-once case is
    // unreachable: the API refuses a notice past the horizon as invalid_input.
    if (day.isAfter(_lastBookableDay)) return _EmptyReason.beyondHorizon;
    if (day.isBefore(_firstBookableDay)) return _EmptyReason.tooSoon;
    return _EmptyReason.full;
  }

  Future<void> _pickDay() async {
    widget.onInteraction?.call();
    final today = salonToday(tz: widget.tz);
    final picked = await showMyweliDatePicker(
      context: context,
      initialDate: DateTime(
        widget.selectedDate.year,
        widget.selectedDate.month,
        widget.selectedDate.day,
      ),
      firstDate: today,
      lastDate: today.add(widget.horizon),
      today: today,
    );
    if (picked == null || !mounted) return;
    widget.onDateChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SlotPickerDateRow(date: widget.selectedDate, onTap: _pickDay),
        // `Selector`, not `watch`: only this line rebuilds when the locality
        // tree lands.
        Selector<LocalityProvider, String?>(
          selector: (_, l) => l.countryName(widget.countryCode),
          builder: (context, label, _) => SalonTimeHint(
            tz: widget.tz,
            countryLabel: label,
            padding: const EdgeInsets.only(top: AppTheme.spacingXS),
          ),
        ),
        const SizedBox(height: AppTheme.spacingS),
        // Four states, and the fourth is new: the hub had loading / empty /
        // success and rendered « Aucun créneau disponible » for a failed
        // request too — telling a user the salon was full when the truth was
        // that we never reached it.
        if (_loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: AppTheme.spacingSM),
            child: Center(child: LoadingIndicator()),
          )
        else if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppTheme.spacingS),
            // A `Column`, not a `Row` with an `Expanded` text and a button
            // beside it: at 200% « Impossible de charger les créneaux… » plus
            // « Réessayer » on one line is the §13.3 shape that clips. The
            // action sits under the sentence and both grow.
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.wifi_off,
                      size: AppTheme.iconS,
                      color: AppColors.error,
                    ),
                    const SizedBox(width: AppTheme.spacingS),
                    Expanded(
                      child: Text(
                        _error!,
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.error,
                        ),
                      ),
                    ),
                  ],
                ),
                // §12 as amended by row 82: a retry only where retrying can
                // succeed. A salon the browse route will not serve is not
                // coming back this session, so its way out is another salon.
                Align(
                  alignment: Alignment.centerLeft,
                  child: _errorCta == null
                      ? TextButton(
                          onPressed: _load,
                          child: const Text('Réessayer'),
                        )
                      : TextButton(
                          onPressed: () => context.go(_errorCta!.href),
                          child: Text(_errorCta!.label),
                        ),
                ),
              ],
            ),
          )
        else if (_slots.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppTheme.spacingS),
            child: switch (_emptyReason) {
              // §12: an empty state says WHY, and offers the action that fixes
              // it. None of these carries « Réessayer » — the request
              // succeeded, and retrying a day outside the window can never
              // return anything.
              _EmptyReason.past => EmptyState(
                icon: Icons.history,
                title: 'Cette date est passée',
                description:
                    'Choisissez une date à venir pour voir les créneaux '
                    'disponibles.',
                actionText: 'Choisir une autre date',
                onAction: _pickDay,
              ),
              _EmptyReason.beyondHorizon => EmptyState(
                icon: Icons.calendar_month,
                title: 'Trop loin dans le temps',
                description:
                    'Ce salon accepte les réservations jusqu’au '
                    '${Formatters.formatDate(_lastBookableDay)}.',
                actionText: 'Aller au dernier jour disponible',
                onAction: () {
                  widget.onInteraction?.call();
                  widget.onDateChanged(_lastBookableDay);
                },
              ),
              _EmptyReason.tooSoon => EmptyState(
                icon: Icons.schedule,
                title: 'Réservation trop proche',
                description:
                    'Ce salon demande un délai de '
                    '${Formatters.formatDuration(widget.minimumNotice.inMinutes)} '
                    'avant chaque rendez-vous.',
                actionText: 'Aller au premier jour disponible',
                onAction: () {
                  widget.onInteraction?.call();
                  widget.onDateChanged(_firstBookableDay);
                },
              ),
              _EmptyReason.full => EmptyState(
                icon: Icons.event_busy,
                title: 'Aucun créneau ce jour-là',
                description:
                    'Ce salon n’a plus de disponibilité le '
                    '${Formatters.formatDate(widget.selectedDate)}.',
                actionText: 'Choisir une autre date',
                onAction: _pickDay,
              ),
            },
          )
        else
          Wrap(
            spacing: AppTheme.spacingS,
            runSpacing: AppTheme.spacingS,
            children: _slots.map((slot) {
              // Instant equality, not wall-clock fields.
              final selected =
                  widget.selectedSlot != null &&
                  widget.selectedSlot!.isAtSameMomentAs(slot);
              return ChoiceChip(
                label: Text(
                  Formatters.formatTime(toSalonTime(slot, tz: widget.tz)),
                ),
                selected: selected,
                onSelected: (_) {
                  widget.onInteraction?.call();
                  widget.onSlotSelected(slot);
                },
                selectedColor: AppColors.primary.withValues(alpha: 0.15),
                labelStyle: AppTextStyles.bodySmall.copyWith(
                  color: selected ? AppColors.primary : AppColors.textPrimary,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppTheme.radiusPill),
                  side: BorderSide(
                    color: selected
                        ? AppColors.primary
                        : AppColors.borderStrong,
                  ),
                ),
                backgroundColor: AppColors.secondary,
              );
            }).toList(),
          ),
      ],
    );
  }
}

/// The « mercredi 11 mars 2026 › » summary row that opens the day picker.
///
/// Public because both hosts render it, and because a golden of the reschedule
/// screen needs to find it. Was `_DatePickerRow`, private to the hub.
class SlotPickerDateRow extends StatelessWidget {
  const SlotPickerDateRow({super.key, required this.date, required this.onTap});

  final DateTime date;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48), // §13.2 touch target
      child: Semantics(
        button: true,
        label: Formatters.formatDate(date),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
          child: Container(
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(
              horizontal: AppTheme.spacingSM,
              vertical: AppTheme.spacingSM,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
              border: Border.all(color: AppColors.borderStrong),
              color: AppColors.secondary,
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.event,
                  color: AppColors.textSecondary,
                  size: AppTheme.iconS,
                ),
                const SizedBox(width: AppTheme.spacingSM),
                Expanded(
                  child: Text(
                    Formatters.formatDate(date),
                    style: AppTextStyles.bodyMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const Icon(Icons.chevron_right, color: AppColors.textTertiary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
