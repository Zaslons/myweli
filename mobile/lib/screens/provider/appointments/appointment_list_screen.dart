import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:myweli/widgets/common/brand_refresh.dart';
import 'package:myweli/widgets/common/loading_indicator.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/text_styles.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/status_colors.dart';
import '../../../models/appointment.dart';
import '../../../providers/pro_appointment_provider.dart';
import '../../../providers/pro_auth_provider.dart';
import 'appointment_calendar_view.dart';

class AppointmentListScreen extends StatefulWidget {
  const AppointmentListScreen({super.key});

  @override
  State<AppointmentListScreen> createState() => _AppointmentListScreenState();
}

class _AppointmentListScreenState extends State<AppointmentListScreen>
    with SingleTickerProviderStateMixin {
  late TabController _mainTabController; // Calendar vs List
  late TabController _listTabController; // Today/Upcoming/Pending/All

  @override
  void initState() {
    super.initState();
    _mainTabController = TabController(length: 2, vsync: this);
    _listTabController = TabController(length: 4, vsync: this);
    _mainTabController.addListener(_onMainTabChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final authProvider = Provider.of<ProAuthProvider>(context, listen: false);
      if (authProvider.isAuthenticated && authProvider.provider != null) {
        final appointmentProvider =
            Provider.of<ProAppointmentProvider>(context, listen: false);
        // Load all appointments for calendar view
        appointmentProvider.loadAppointments(authProvider.provider!.id);
      }
    });
  }

  void _onMainTabChanged() {
    if (!_mainTabController.indexIsChanging) {
      final authProvider = Provider.of<ProAuthProvider>(context, listen: false);
      if (!authProvider.isAuthenticated || authProvider.provider == null) {
        return;
      }

      final appointmentProvider =
          Provider.of<ProAppointmentProvider>(context, listen: false);

      if (_mainTabController.index == 0) {
        // Calendar view - load all appointments
        appointmentProvider.loadAppointments(authProvider.provider!.id);
      } else {
        // List view - load based on selected list tab
        _loadAppointmentsForListTab(_listTabController.index);
      }
    }
  }

  @override
  void dispose() {
    _mainTabController.dispose();
    _listTabController.dispose();
    super.dispose();
  }

  void _loadAppointmentsForListTab(int index) {
    final authProvider = Provider.of<ProAuthProvider>(context, listen: false);
    if (!authProvider.isAuthenticated || authProvider.provider == null) return;

    final appointmentProvider =
        Provider.of<ProAppointmentProvider>(context, listen: false);
    AppointmentStatus? status;

    switch (index) {
      case 0: // Today
        final today = DateTime.now();
        final todayStart = DateTime(today.year, today.month, today.day);
        final todayEnd = todayStart.add(const Duration(days: 1));
        appointmentProvider.loadAppointments(
          authProvider.provider!.id,
          startDate: todayStart,
          endDate: todayEnd,
        );
        return;
      case 1: // Upcoming
        appointmentProvider.loadAppointments(
          authProvider.provider!.id,
          startDate: DateTime.now(),
        );
        return;
      case 2: // Pending
        status = AppointmentStatus.pending;
        break;
      case 3: // All
        break;
    }

    appointmentProvider.loadAppointments(
      authProvider.provider!.id,
      status: status,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Rendez-vous'),
        bottom: TabBar(
          controller: _mainTabController,
          tabs: const [
            Tab(text: 'Calendrier'),
            Tab(text: 'Liste'),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/pro/appointment/new'),
        icon: const Icon(Icons.add),
        label: const Text('Ajouter'),
      ),
      body: Consumer2<ProAuthProvider, ProAppointmentProvider>(
        builder: (context, authProvider, appointmentProvider, _) {
          if (!authProvider.isAuthenticated) {
            return const Center(child: Text('Veuillez vous connecter'));
          }

          if (appointmentProvider.isLoading &&
              appointmentProvider.appointments.isEmpty) {
            return const Center(child: LoadingIndicator());
          }

          final appointments = appointmentProvider.appointments;

          return TabBarView(
            controller: _mainTabController,
            children: [
              // Calendar View
              BrandRefresh(
                onRefresh: () async {
                  if (authProvider.provider != null) {
                    await appointmentProvider
                        .loadAppointments(authProvider.provider!.id);
                  }
                },
                child: appointments.isEmpty
                    ? Center(
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
                          ],
                        ),
                      )
                    : AppointmentCalendarView(appointments: appointments),
              ),
              // List View
              Column(
                children: [
                  TabBar(
                    controller: _listTabController,
                    onTap: _loadAppointmentsForListTab,
                    tabs: const [
                      Tab(text: 'Aujourd\'hui'),
                      Tab(text: 'À venir'),
                      Tab(text: 'En attente'),
                      Tab(text: 'Tous'),
                    ],
                  ),
                  Expanded(
                    child: BrandRefresh(
                      onRefresh: () async {
                        _loadAppointmentsForListTab(_listTabController.index);
                      },
                      child: appointments.isEmpty
                          ? Center(
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
                                ],
                              ),
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.all(AppTheme.spacingM),
                              itemCount: appointments.length,
                              itemBuilder: (context, index) {
                                final appointment = appointments[index];
                                return _AppointmentCard(
                                  appointment: appointment,
                                  onTap: () => context.push(
                                      '/pro/appointment/${appointment.id}'),
                                );
                              },
                            ),
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
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
        title: Text(
          Formatters.formatDateTime(appointment.appointmentDate),
          style:
              AppTextStyles.titleMedium.copyWith(color: AppColors.textPrimary),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
