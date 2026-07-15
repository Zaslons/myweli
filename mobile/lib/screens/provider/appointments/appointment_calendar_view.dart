import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/text_styles.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/salon_time.dart';
import '../../../core/utils/status_colors.dart';
import '../../../models/appointment.dart';
import '../../../providers/pro_auth_provider.dart';

class AppointmentCalendarView extends StatefulWidget {
  final List<Appointment> appointments;

  const AppointmentCalendarView({
    super.key,
    required this.appointments,
  });

  @override
  State<AppointmentCalendarView> createState() =>
      _AppointmentCalendarViewState();
}

class _AppointmentCalendarViewState extends State<AppointmentCalendarView> {
  late ValueNotifier<List<Appointment>> _selectedAppointments;
  late DateTime _focusedDay = _salonTodayNaive();
  DateTime? _selectedDay;

  String? get _tz => context.read<ProAuthProvider>().salonTimezone;

  /// The ACTIVE salon's "today" as a NAIVE date — table_calendar compares
  /// its naive day cells field-to-field (never `.toUtc()` these).
  DateTime _salonTodayNaive() {
    final s = salonNow(tz: _tz);
    return DateTime(s.year, s.month, s.day);
  }

  @override
  void initState() {
    super.initState();
    _selectedDay = _salonTodayNaive();
    _selectedAppointments =
        ValueNotifier(_getAppointmentsForDay(_selectedDay!));
  }

  @override
  void didUpdateWidget(AppointmentCalendarView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.appointments != widget.appointments) {
      _selectedAppointments.value =
          _getAppointmentsForDay(_selectedDay ?? _salonTodayNaive());
    }
  }

  @override
  void dispose() {
    _selectedAppointments.dispose();
    super.dispose();
  }

  List<Appointment> _getAppointmentsForDay(DateTime day) {
    // `day` is a naive table_calendar cell; the booking date is a UTC
    // instant — compare both as the ACTIVE SALON's calendar days.
    return widget.appointments.where((appointment) {
      final d = toSalonTime(appointment.appointmentDate, tz: _tz);
      return d.year == day.year && d.month == day.month && d.day == day.day;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Calendar
        Container(
          margin: const EdgeInsets.all(AppTheme.spacingM),
          padding: const EdgeInsets.all(AppTheme.spacingM),
          decoration: BoxDecoration(
            color: AppColors.secondary,
            borderRadius: BorderRadius.circular(AppTheme.radiusXL),
            boxShadow: AppTheme.elevation1,
          ),
          child: TableCalendar<Appointment>(
            firstDay: _salonTodayNaive().subtract(const Duration(days: 365)),
            lastDay: _salonTodayNaive().add(const Duration(days: 365)),
            focusedDay: _focusedDay,
            // The « today » ring follows the SALON's today, not the device's.
            currentDay: _salonTodayNaive(),
            selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
            calendarFormat: CalendarFormat.month,
            startingDayOfWeek: StartingDayOfWeek.monday,
            calendarStyle: CalendarStyle(
              selectedDecoration: const BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
              ),
              todayDecoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.5),
                shape: BoxShape.circle,
              ),
              markerDecoration: const BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
              ),
              outsideDaysVisible: false,
            ),
            headerStyle: HeaderStyle(
              formatButtonVisible: false,
              titleCentered: true,
              titleTextStyle: AppTextStyles.titleMedium.copyWith(
                color: AppColors.textPrimary,
              ),
            ),
            eventLoader: _getAppointmentsForDay,
            onDaySelected: (selectedDay, focusedDay) {
              if (!isSameDay(_selectedDay, selectedDay)) {
                setState(() {
                  _selectedDay = selectedDay;
                  _focusedDay = focusedDay;
                  _selectedAppointments.value =
                      _getAppointmentsForDay(selectedDay);
                });
              }
            },
            onPageChanged: (focusedDay) {
              _focusedDay = focusedDay;
            },
            calendarBuilders: CalendarBuilders(
              markerBuilder: (context, date, events) {
                if (events.isNotEmpty) {
                  return Positioned(
                    bottom: 1,
                    child: Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: AppColors.primary,
                        shape: BoxShape.circle,
                      ),
                    ),
                  );
                }
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
        // Selected day appointments
        Expanded(
          child: ValueListenableBuilder<List<Appointment>>(
            valueListenable: _selectedAppointments,
            builder: (context, appointments, _) {
              if (appointments.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.event_busy,
                          size: AppTheme.iconXL,
                          color: AppColors.textSecondary),
                      const SizedBox(height: AppTheme.spacingM),
                      Text(
                        'Aucun rendez-vous',
                        style: AppTextStyles.titleLarge.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: AppTheme.spacingS),
                      Text(
                        _selectedDay != null
                            ? 'pour ${Formatters.formatDate(_selectedDay!)}'
                            : '',
                        style: AppTextStyles.bodyMedium.copyWith(
                          color: AppColors.textTertiary,
                        ),
                      ),
                    ],
                  ),
                );
              }

              return ListView.builder(
                padding:
                    const EdgeInsets.symmetric(horizontal: AppTheme.spacingM),
                itemCount: appointments.length,
                itemBuilder: (context, index) {
                  final appointment = appointments[index];
                  return _AppointmentCard(
                    appointment: appointment,
                    onTap: () =>
                        context.push('/pro/appointment/${appointment.id}'),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _AppointmentCard extends StatelessWidget {
  final Appointment appointment;
  final VoidCallback onTap;

  const _AppointmentCard({
    required this.appointment,
    required this.onTap,
  });

  Color _getStatusColor(AppointmentStatus status) =>
      appointmentStatusColor(status);

  String _getStatusText(AppointmentStatus status) {
    switch (status) {
      case AppointmentStatus.pending:
        return 'En attente';
      case AppointmentStatus.confirmed:
        return 'Confirmé';
      case AppointmentStatus.completed:
        return 'Terminé';
      case AppointmentStatus.cancelled:
        return 'Annulé';
      case AppointmentStatus.noShow:
        return 'Absent';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: AppTheme.spacingM),
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          backgroundColor:
              _getStatusColor(appointment.status).withValues(alpha: 0.2),
          child: Icon(
            Icons.calendar_today,
            color: _getStatusColor(appointment.status),
            size: AppTheme.iconS,
          ),
        ),
        title: Text(
          Formatters.formatTime(toSalonTime(appointment.appointmentDate,
              tz: context.read<ProAuthProvider>().salonTimezone)),
          style:
              AppTextStyles.titleMedium.copyWith(color: AppColors.textPrimary),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: AppTheme.spacingXS),
            Text('${appointment.serviceIds.length} service(s)'),
            Text(Formatters.formatCurrency(
              appointment.totalPrice,
              currency: context.read<ProAuthProvider>().salonCurrency,
            )),
          ],
        ),
        trailing: Chip(
          label: Text(
            _getStatusText(appointment.status),
            style: AppTextStyles.bodySmall.copyWith(color: Colors.white),
          ),
          backgroundColor: _getStatusColor(appointment.status),
        ),
      ),
    );
  }
}
