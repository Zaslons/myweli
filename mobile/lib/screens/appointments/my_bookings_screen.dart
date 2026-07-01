import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:myweli/widgets/common/loading_indicator.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/text_styles.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/visit_history.dart';
import '../../models/appointment.dart';
import '../../providers/appointment_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/provider_provider.dart';
import '../../widgets/booking/appointment_card.dart';
import '../../widgets/common/app_button.dart';
import '../../widgets/common/empty_state.dart';

class MyBookingsScreen extends StatefulWidget {
  const MyBookingsScreen({super.key});

  @override
  State<MyBookingsScreen> createState() => _MyBookingsScreenState();
}

class _MyBookingsScreenState extends State<MyBookingsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);

      // Check if user is authenticated, if not redirect to login
      if (!authProvider.isAuthenticated) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content:
                  Text('Veuillez vous connecter pour voir vos rendez-vous'),
              duration: Duration(seconds: 2),
            ),
          );
          context.go('/login?returnTo=${Uri.encodeComponent('/bookings')}');
        });
        return;
      }

      final appointmentProvider =
          Provider.of<AppointmentProvider>(context, listen: false);
      final providerProvider =
          Provider.of<ProviderProvider>(context, listen: false);

      // Load appointments and providers
      appointmentProvider.loadAppointments();
      if (providerProvider.providers.isEmpty) {
        providerProvider.loadProviders();
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Mes rendez-vous'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'À venir'),
            Tab(text: 'Passés'),
            Tab(text: 'Annulés'),
          ],
        ),
      ),
      body: Consumer<AppointmentProvider>(
        builder: (context, provider, _) {
          return TabBarView(
            controller: _tabController,
            children: [
              _buildAppointmentsList(
                provider.upcomingAppointments,
                provider.isLoading,
              ),
              _buildHistory(
                provider.visitHistory,
                provider.isLoading,
              ),
              _buildAppointmentsList(
                provider.cancelledAppointments,
                provider.isLoading,
              ),
            ],
          );
        },
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: 2,
        onTap: (index) {
          if (index == 0) context.go('/home');
          if (index == 1) context.push('/favorites');
          if (index == 3) context.push('/notifications');
        },
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home),
            label: 'Accueil',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.map),
            label: 'Carte',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.calendar_today),
            label: 'Rendez-vous',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.notifications_none),
            label: 'Actu',
          ),
        ],
      ),
    );
  }

  Widget _buildAppointmentsList(
      List<Appointment> appointments, bool isLoading) {
    if (isLoading && appointments.isEmpty) {
      return const Center(child: LoadingIndicator());
    }

    if (appointments.isEmpty) {
      return const EmptyState(
        icon: Icons.calendar_today,
        title: 'Aucun rendez-vous',
        description: 'Vous n\'avez pas de rendez-vous dans cette catégorie',
      );
    }

    return RefreshIndicator(
      onRefresh: () async {
        final provider =
            Provider.of<AppointmentProvider>(context, listen: false);
        await provider.loadAppointments();
      },
      child: ListView.builder(
        padding: const EdgeInsets.all(AppTheme.spacingM),
        itemCount: appointments.length,
        itemBuilder: (context, index) {
          final appointment = appointments[index];
          return Padding(
            padding: const EdgeInsets.only(bottom: AppTheme.spacingM),
            child: AppointmentCard(
              appointment: appointment,
              onTap: () => context.push('/appointment/${appointment.id}'),
            ),
          );
        },
      ),
    );
  }

  Widget _buildHistory(List<Appointment> visits, bool isLoading) {
    if (isLoading && visits.isEmpty) {
      return const Center(child: LoadingIndicator());
    }

    if (visits.isEmpty) {
      return const EmptyState(
        icon: Icons.history,
        title: 'Aucune visite',
        description: 'Vos rendez-vous passés apparaîtront ici.',
      );
    }

    final groups = groupVisitsByMonth(visits);
    final spent = totalSpent(visits);

    final children = <Widget>[
      Row(
        children: [
          Expanded(
            child: _summaryMetric(
              '${visits.length}',
              visits.length == 1 ? 'visite' : 'visites',
            ),
          ),
          const SizedBox(width: AppTheme.spacingM),
          Expanded(
            child: _summaryMetric(
              Formatters.formatCurrency(spent),
              'dépensés',
            ),
          ),
        ],
      ),
      const SizedBox(height: AppTheme.spacingM),
    ];

    for (final group in groups) {
      children.add(
        Padding(
          padding: const EdgeInsets.only(bottom: AppTheme.spacingS),
          child: Text(
            Formatters.formatMonthYear(group.month).toUpperCase(),
            style: AppTextStyles.labelSmall.copyWith(
              color: AppColors.textTertiary,
              letterSpacing: 0.5,
            ),
          ),
        ),
      );
      for (final visit in group.visits) {
        children.add(
          Padding(
            padding: const EdgeInsets.only(bottom: AppTheme.spacingM),
            child: Column(
              children: [
                AppointmentCard(
                  appointment:
                      visit.copyWith(status: AppointmentStatus.completed),
                  onTap: () => context.push('/appointment/${visit.id}'),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: AppButton(
                    text: 'Réserver à nouveau',
                    type: AppButtonType.secondary,
                    icon: Icons.refresh,
                    onPressed: () => _rebook(visit),
                  ),
                ),
              ],
            ),
          ),
        );
      }
    }

    return RefreshIndicator(
      onRefresh: () async {
        final provider =
            Provider.of<AppointmentProvider>(context, listen: false);
        await provider.loadAppointments();
      },
      child: ListView(
        padding: const EdgeInsets.all(AppTheme.spacingM),
        children: children,
      ),
    );
  }

  void _rebook(Appointment appointment) {
    final uri = Uri(path: '/booking', queryParameters: {
      'providerId': appointment.providerId,
      if (appointment.serviceIds.isNotEmpty)
        'serviceIds': appointment.serviceIds.join(','),
      if (appointment.artistId != null) 'artistId': appointment.artistId!,
    });
    context.push(uri.toString());
  }

  Widget _summaryMetric(String value, String label) {
    return Container(
      padding: const EdgeInsets.all(AppTheme.spacingM),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: AppTextStyles.titleLarge),
          const SizedBox(height: 2),
          Text(
            label,
            style: AppTextStyles.bodySmall.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
