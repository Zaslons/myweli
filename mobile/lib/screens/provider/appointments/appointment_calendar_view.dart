import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/booking_horizons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/text_styles.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/salon_time.dart';
import '../../../core/utils/status_colors.dart';
import '../../../core/utils/status_labels.dart';
import '../../../models/appointment.dart';
import '../../../providers/pro_auth_provider.dart';
import '../../../widgets/common/myweli_month_grid.dart';

class AppointmentCalendarView extends StatefulWidget {
  final List<Appointment> appointments;

  const AppointmentCalendarView({super.key, required this.appointments});

  @override
  State<AppointmentCalendarView> createState() =>
      _AppointmentCalendarViewState();
}

class _AppointmentCalendarViewState extends State<AppointmentCalendarView> {
  late ValueNotifier<List<Appointment>> _selectedAppointments;

  /// The salon's today, then whatever the pro taps.
  ///
  /// **Non-nullable, and that is a fix rather than a tidy-up.** It was
  /// `DateTime?` only because `table_calendar`'s `isSameDay` took two nullables
  /// and the type never had to be honest — `initState` seeds it and no path
  /// clears it. Making it truthful deletes two `!`s, a `??` fallback and a
  /// nullable `isSameDay` call in one move; the house `isSameDay`
  /// (`myweli_month_grid.dart`) takes two non-null days.
  late DateTime _selectedDay = _salonTodayNaive();

  /// Every appointment, bucketed by the salon's calendar day — built **once per
  /// data change**, not per build.
  ///
  /// **What this replaces.** `eventLoader` was called once per visible cell (42
  /// of them), and each call ran `.where()` over every appointment with a
  /// `context.read<ProAuthProvider>()` **and** a `toSalonTime` inside the loop —
  /// `_tz` was a getter, re-read per element. With 100 appointments that is
  /// ~4,200 provider lookups and ~4,200 timezone conversions **per frame**, plus
  /// 42 throwaway lists. The marker builder then threw all of it away and asked
  /// only `events.isNotEmpty`.
  Map<CalendarDay, List<Appointment>> _byDay = const {};

  /// Day → what its dot announces. Derived from [_byDay], same pass.
  Map<CalendarDay, String> _markers = const {};

  String? get _tz => context.read<ProAuthProvider>().salonTimezone;

  /// The ACTIVE salon's "today" as a NAIVE date — the grid compares its day
  /// cells field-to-field (never `.toUtc()` these).
  DateTime _salonTodayNaive() {
    final s = salonNow(tz: _tz);
    return DateTime(s.year, s.month, s.day);
  }

  @override
  void initState() {
    super.initState();
    _index();
    _selectedAppointments = ValueNotifier(_forDay(_selectedDay));
  }

  @override
  void didUpdateWidget(AppointmentCalendarView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.appointments != widget.appointments) {
      _index();
      _selectedAppointments.value = _forDay(_selectedDay);
    }
  }

  @override
  void dispose() {
    _selectedAppointments.dispose();
    super.dispose();
  }

  /// One pass: N timezone conversions and **one** provider read.
  void _index() {
    final tz = _tz;
    final byDay = <CalendarDay, List<Appointment>>{};
    for (final a in widget.appointments) {
      final key = CalendarDay.of(toSalonTime(a.appointmentDate, tz: tz));
      (byDay[key] ??= <Appointment>[]).add(a);
    }
    _byDay = byDay;
    _markers = {
      for (final e in byDay.entries)
        // Through `Formatters.count`, not interpolation: « rendez-vous » is
        // invariant in the plural and A13 row 41's pin exists because four
        // spellings of that rule once coexisted.
        e.key: Formatters.count(e.value.length, 'rendez-vous', 'rendez-vous'),
    };
  }

  List<Appointment> _forDay(DateTime day) =>
      _byDay[CalendarDay.of(day)] ?? const [];

  @override
  Widget build(BuildContext context) {
    // **A `CustomScrollView`, and the reason is the defect this slice fixed.**
    //
    // This was a `Column` of [calendar card, `Expanded`(day list)], and it held
    // only because `table_calendar` pinned `rowHeight: 52.0` — a calendar that
    // refuses to grow with the text scale cannot overflow its page either. The
    // moment the house grid started sizing from the text, the `Column`
    // overflowed by **40 pixels** at 2×, on all three widths. The page never had
    // room for an honest calendar; nothing could say so while the calendar lied.
    //
    // It also repairs something adjacent that nobody had reported: the parent
    // wraps this in `BrandRefresh`, whose pull-to-refresh needs a scrollable —
    // and the only one here was the inner `ListView`, which the empty branch
    // replaced with a `Center`. **Pull-to-refresh was dead on exactly the days
    // a pro has nothing booked.** One scroll view for the whole page fixes the
    // overflow and the gesture together.
    return ValueListenableBuilder<List<Appointment>>(
      valueListenable: _selectedAppointments,
      builder: (context, appointments, _) => CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: _calendarCard()),
          if (appointments.isEmpty)
            SliverFillRemaining(hasScrollBody: false, child: _emptyDay())
          else
            SliverPadding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppTheme.spacingM,
              ),
              sliver: SliverList.builder(
                itemCount: appointments.length,
                itemBuilder: (context, index) {
                  final appointment = appointments[index];
                  return _AppointmentCard(
                    appointment: appointment,
                    onTap: () =>
                        context.push('/pro/appointment/${appointment.id}'),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _emptyDay() => Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(
          Icons.event_busy,
          size: AppTheme.iconXL,
          color: AppColors.textSecondary,
        ),
        const SizedBox(height: AppTheme.spacingM),
        Text(
          'Aucun rendez-vous',
          style: AppTextStyles.titleLarge.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: AppTheme.spacingS),
        Text(
          'pour ${Formatters.formatDate(_selectedDay)}',
          style: AppTextStyles.bodyMedium.copyWith(
            color: AppColors.textTertiary,
          ),
        ),
      ],
    ),
  );

  Widget _calendarCard() {
    return Container(
      // `spacingS`, not `spacingM`, and it is arithmetic rather than taste: the
      // day cell needs a 46.86dp column at 2× (A14a §2.1), which is
      // 360 − 2×`spacingS` here − 2×`spacingS` inside the navigator, ÷ 7.
      // At `spacingM` the column was 37.7 and the day number wrapped.
      margin: const EdgeInsets.all(AppTheme.spacingS),
      padding: const EdgeInsets.symmetric(vertical: AppTheme.spacingS),
      decoration: BoxDecoration(
        color: AppColors.secondary,
        borderRadius: BorderRadius.circular(AppTheme.radiusXL),
        boxShadow: AppTheme.elevation1,
      ),
      // **`shrinkWrap: true` is required, not preferred.** This card is a
      // non-flex child of a `Column`, so it receives unbounded main-axis
      // constraints — a navigator using `Expanded` throws there rather than
      // merely looking wrong.
      child: MyweliMonthNavigator(
        shrinkWrap: true,
        // **Read once, at mount.** `MyweliMonthNavigator` owns the viewed
        // month and refuses to resync it from the parent — which is the fix
        // for the defect `date_time_selection_screen` shipped, where every
        // `setState` yanked a swiped-to month back. So there is no
        // `_focusedDay` field here any more: the old one was mutated
        // WITHOUT `setState` in `onPageChanged`, i.e. it was never state at
        // all, and nothing read it back.
        initialMonth: _salonTodayNaive(),
        // Named constants, not the two inline `Duration(days: 365)`
        // literals this file carried: A14a introduced them and did not
        // sweep here.
        firstDate: _salonTodayNaive().subtract(kJournalPastHorizon),
        lastDate: _salonTodayNaive().add(kBookingHorizon),
        today: _salonTodayNaive(),
        selectedDays: {CalendarDay.of(_selectedDay)},
        markers: _markers,
        onDayTap: (day) {
          if (isSameDay(day, _selectedDay)) return;
          setState(() {
            _selectedDay = day;
            _selectedAppointments.value = _forDay(day);
          });
        },
      ),
    );
  }
}

class _AppointmentCard extends StatelessWidget {
  final Appointment appointment;
  final VoidCallback onTap;

  const _AppointmentCard({required this.appointment, required this.onTap});

  Color _getStatusColor(AppointmentStatus status) =>
      appointmentStatusColor(status);

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: AppTheme.spacingM),
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          backgroundColor: _getStatusColor(
            appointment.status,
          ).withValues(alpha: 0.2),
          child: Icon(
            Icons.calendar_today,
            color: _getStatusColor(appointment.status),
            size: AppTheme.iconS,
          ),
        ),
        title: Text(
          Formatters.formatTime(
            toSalonTime(
              appointment.appointmentDate,
              tz: context.read<ProAuthProvider>().salonTimezone,
            ),
          ),
          style: AppTextStyles.titleMedium.copyWith(
            color: AppColors.textPrimary,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: AppTheme.spacingXS),
            Text(
              Formatters.count(
                appointment.serviceIds.length,
                'service',
                'services',
              ),
            ),
            Text(
              Formatters.formatCurrency(
                appointment.totalPrice,
                currency: context.read<ProAuthProvider>().salonCurrency,
              ),
            ),
          ],
        ),
        trailing: Chip(
          label: Text(
            StatusLabels.of(appointment.status),
            style: AppTextStyles.bodySmall.copyWith(color: Colors.white),
          ),
          backgroundColor: _getStatusColor(appointment.status),
        ),
      ),
    );
  }
}
