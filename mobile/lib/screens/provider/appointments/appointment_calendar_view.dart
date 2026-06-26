import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/text_styles.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/status_colors.dart';
import '../../../models/appointment.dart';

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
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;

  @override
  void initState() {
    super.initState();
    _selectedDay = DateTime.now();
    _selectedAppointments =
        ValueNotifier(_getAppointmentsForDay(_selectedDay!));
  }

  @override
  void didUpdateWidget(AppointmentCalendarView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.appointments != widget.appointments) {
      _selectedAppointments.value =
          _getAppointmentsForDay(_selectedDay ?? DateTime.now());
    }
  }

  @override
  void dispose() {
    _selectedAppointments.dispose();
    super.dispose();
  }

  List<Appointment> _getAppointmentsForDay(DateTime day) {
    return widget.appointments.where((appointment) {
      final appointmentDate = appointment.appointmentDate;
      return appointmentDate.year == day.year &&
          appointmentDate.month == day.month &&
          appointmentDate.day == day.day;
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
            firstDay: DateTime.now().subtract(const Duration(days: 365)),
            lastDay: DateTime.now().add(const Duration(days: 365)),
            focusedDay: _focusedDay,
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
                          size: 64, color: AppColors.textSecondary),
                      const SizedBox(height: 16),
                      Text(
                        'Aucun rendez-vous',
                        style: AppTextStyles.titleLarge.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 8),
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
            size: 20,
          ),
        ),
        title: Text(
          Formatters.formatTime(appointment.appointmentDate),
          style:
              AppTextStyles.titleMedium.copyWith(color: AppColors.textPrimary),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text('${appointment.serviceIds.length} service(s)'),
            Text(Formatters.formatCurrency(appointment.totalPrice)),
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
