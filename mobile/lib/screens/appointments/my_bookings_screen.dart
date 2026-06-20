import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../providers/appointment_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/provider_provider.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/common/empty_state.dart';
import '../../widgets/booking/appointment_card.dart';

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
              content: Text('Veuillez vous connecter pour voir vos rendez-vous'),
              duration: Duration(seconds: 2),
            ),
          );
          context.go('/login?returnTo=${Uri.encodeComponent('/bookings')}');
        });
        return;
      }
      
      final appointmentProvider = Provider.of<AppointmentProvider>(context, listen: false);
      final providerProvider = Provider.of<ProviderProvider>(context, listen: false);
      
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
              _buildAppointmentsList(
                provider.pastAppointments,
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

  Widget _buildAppointmentsList(List appointments, bool isLoading) {
    if (isLoading && appointments.isEmpty) {
      return const Center(child: CircularProgressIndicator());
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
        final provider = Provider.of<AppointmentProvider>(context, listen: false);
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
}



