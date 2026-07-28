import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:myweli/widgets/common/brand_refresh.dart';
import 'package:myweli/widgets/common/loading_indicator.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/text_styles.dart';
import '../../../core/utils/app_clock.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/salon_time.dart';
import '../../../core/utils/status_colors.dart';
import '../../../core/utils/status_labels.dart';
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
    // Two TabControllers (Calendrier/Liste + the list's status tabs).
    with
        TickerProviderStateMixin {
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
        appointmentProvider.loadAppointments(authProvider.activeSalonId ?? '');
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
        appointmentProvider.loadAppointments(authProvider.activeSalonId ?? '');
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
      case 0: // Today — the ACTIVE SALON's day bounds (salon_time.dart).
        final bounds = salonDayBoundsUtc(tz: authProvider.salonTimezone);
        appointmentProvider.loadAppointments(
          authProvider.activeSalonId ?? '',
          startDate: bounds.startUtc,
          endDate: bounds.endUtc,
        );
        return;
      case 1: // Upcoming
        appointmentProvider.loadAppointments(
          authProvider.activeSalonId ?? '',
          startDate: AppClock.now(),
        );
        return;
      case 2: // Pending
        status = AppointmentStatus.pending;
        break;
      case 3: // All
        break;
    }

    appointmentProvider.loadAppointments(
      authProvider.activeSalonId ?? '',
      status: status,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Rendez-vous'),
        // **Deliberately NOT scrollable, unlike the four-tab bar below.**
        // Measured, not assumed: « Calendrier » + « Liste » is 257.8dp of strip
        // at 200% text, inside a 360dp bar — it fits at every width and scale
        // §10 supports, so there is nothing to fix and dividing the width in two
        // is the better control for a binary view switcher (Material's own
        // guidance: fixed tabs for two short labels).
        //
        // What protects it long-term is the GATE, not this comment: the width
        // gate walks every RenderParagraph on this screen at all six
        // width×scale configurations, so a renamed or added tab that starts
        // clipping goes red on its own.
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
                        .loadAppointments(authProvider.activeSalonId ?? '');
                  }
                },
                child: appointments.isEmpty
                    ? Center(
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
                    // §13.3's width twin — the same bar as `earnings_screen`,
                    // and the same silent fade: « Aujourd’hui » needs 72.2dp and
                    // gets 58.0 at 360. See that file for the full argument for
                    // `center` over the M3 default.
                    //
                    // **This one lives inside a `TabBarView` page**, so making it
                    // scrollable is a gesture-arena change as well as a layout
                    // one: a horizontal drag on the strip now scrolls the strip
                    // instead of paging back to « Calendrier ». That is what
                    // scrollable tabs are, and it is the standard trade.
                    isScrollable: true,
                    tabAlignment: TabAlignment.center,
                    tabs: const [
                      Tab(text: 'Aujourd’hui'),
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
                                      size: AppTheme.iconXL,
                                      color: AppColors.textSecondary),
                                  const SizedBox(height: AppTheme.spacingM),
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

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: AppTheme.spacingM),
      child: ListTile(
        onTap: onTap,
        title: Text(
          Formatters.formatDateTime(toSalonTime(
            appointment.appointmentDate,
            tz: context.read<ProAuthProvider>().salonTimezone,
          )),
          style:
              AppTextStyles.titleMedium.copyWith(color: AppColors.textPrimary),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Module clients C1c: who booked + the no-show badge.
            Row(
              children: [
                Flexible(
                  child: Text(
                    appointment.clientName ?? 'Client',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if ((appointment.clientNoShowCount ?? 0) >= 1) ...[
                  const SizedBox(width: AppTheme.spacingXS),
                  Text(
                    appointment.clientNoShowCount == 1
                        ? '· 1 absence'
                        : '· ${appointment.clientNoShowCount} absences',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: (appointment.clientNoShowCount ?? 0) >= 2
                          ? AppColors.error
                          : AppColors.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
            Text('${appointment.serviceIds.length} service(s)'),
            Text(Formatters.formatCurrency(
              appointment.totalPrice,
              currency: context.read<ProAuthProvider>().salonCurrency,
            )),
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
