import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:myweli/widgets/common/brand_refresh.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/text_styles.dart';
import '../../core/utils/booking_error_cta.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/visit_history.dart';
import '../../models/appointment.dart';
import '../../providers/appointment_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/provider_provider.dart';
import '../../widgets/booking/appointment_card.dart';
import '../../widgets/booking/visit_summary.dart';
import '../../widgets/common/app_async_view.dart';
import '../../widgets/common/app_button.dart';
import '../../widgets/common/app_skeleton.dart';
import '../../widgets/common/app_snack_bar.dart';
import '../../widgets/common/consumer_bottom_nav.dart';
import '../../widgets/common/empty_state.dart';
import '../../widgets/common/inline_feedback.dart';

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
          AppSnackBar.show(
            context,
            'Veuillez vous connecter pour voir vos rendez-vous',
          );
          context.go('/login?returnTo=${Uri.encodeComponent('/bookings')}');
        });
        return;
      }

      final appointmentProvider = Provider.of<AppointmentProvider>(
        context,
        listen: false,
      );
      final providerProvider = Provider.of<ProviderProvider>(
        context,
        listen: false,
      );

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
          // §13.3's width twin — see otp_code_row.dart and
          // earnings_screen.dart for the full argument. Three tabs fit at
          // 1× and « Passés » (91.9dp) and « Annulés » (102.0dp) do not fit
          // their 88.0/93.0dp shares at 200% text, where they fade away in
          // silence. `center` keeps today's look while they fit.
          isScrollable: true,
          tabAlignment: TabAlignment.center,
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
              _tab(
                provider,
                provider.upcomingAppointments,
                const EmptyState(
                  icon: Icons.calendar_today,
                  title: 'Aucun rendez-vous',
                  description:
                      'Vous n’avez pas de rendez-vous dans cette catégorie',
                ),
                _buildAppointmentsList,
              ),
              _tab(
                provider,
                provider.visitHistory,
                const EmptyState(
                  icon: Icons.history,
                  title: 'Aucune visite',
                  description: 'Vos rendez-vous passés apparaîtront ici.',
                ),
                _buildHistory,
              ),
              _tab(
                provider,
                provider.cancelledAppointments,
                const EmptyState(
                  icon: Icons.calendar_today,
                  title: 'Aucun rendez-vous',
                  description:
                      'Vous n’avez pas de rendez-vous dans cette catégorie',
                ),
                _buildAppointmentsList,
              ),
            ],
          );
        },
      ),
      bottomNavigationBar: const ConsumerBottomNav(
        current: ConsumerTab.rendezVous,
      ),
    );
  }

  /// One tab's four states. The three read one list, so they fail together.
  Widget _tab(
    AppointmentProvider provider,
    List<Appointment> items,
    Widget empty,
    Widget Function(List<Appointment> items) builder,
  ) => AppAsyncView<List<Appointment>>(
    isLoading: provider.isLoading,
    error: provider.listError,
    data: items,
    isEmpty: (d) => d.isEmpty,
    loading: const SkeletonCardList(lead: SkeletonLead.thumbnail),
    empty: empty,
    onRetry: provider.loadAppointments,
    onRefresh: provider.loadAppointments,
    builder: (_, d) => builder(d),
  );

  Widget _buildAppointmentsList(List<Appointment> appointments) {
    return BrandRefresh(
      onRefresh: () async {
        final provider = Provider.of<AppointmentProvider>(
          context,
          listen: false,
        );
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

  Widget _buildHistory(List<Appointment> visits) {
    final groups = groupVisitsByMonth(visits);
    final spent = totalSpent(visits);

    final children = <Widget>[
      VisitSummary(
        visits: visits.length,
        spent: spent,
        // MVP: a mixed-currency history sums nominally and reads the first
        // visit's currency (per-currency grouping is post-MP2).
        currency: visits.first.currency ?? visits.first.providerCurrency,
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
                  appointment: visit.copyWith(
                    status: AppointmentStatus.completed,
                  ),
                  onTap: () => context.push('/appointment/${visit.id}'),
                ),
                const SizedBox(height: AppTheme.spacingS),
                // A stopped salon offers no rebook: the server refuses the
                // booking, and after Decision C its page 404s. Web's
                // `rebookHref` has gated this since PR1c; this list renders
                // from the client's OWN appointments, which are deliberately
                // NOT status-filtered, so it was the one live route left onto
                // a salon that is no longer on Myweli.
                if (visit.salonIsLive)
                  SizedBox(
                    width: double.infinity,
                    child: AppButton(
                      text: 'Réserver à nouveau',
                      type: AppButtonType.secondary,
                      icon: Icons.refresh,
                      onPressed: () => _rebook(visit),
                    ),
                  )
                else
                  // The block would otherwise lose its only action with no
                  // explanation. Same widget and same sentences the
                  // appointment detail already uses.
                  InlineFeedback(
                    salonStoppedMessage(visit.providerStatus),
                    kind: SnackKind.info,
                  ),
              ],
            ),
          ),
        );
      }
    }

    return BrandRefresh(
      onRefresh: () async {
        final provider = Provider.of<AppointmentProvider>(
          context,
          listen: false,
        );
        await provider.loadAppointments();
      },
      child: ListView(
        padding: const EdgeInsets.all(AppTheme.spacingM),
        children: children,
      ),
    );
  }

  void _rebook(Appointment appointment) {
    final uri = Uri(
      path: '/booking',
      queryParameters: {
        'providerId': appointment.providerId,
        if (appointment.serviceIds.isNotEmpty)
          'serviceIds': appointment.serviceIds.join(','),
        if (appointment.artistId != null) 'artistId': appointment.artistId!,
      },
    );
    context.push(uri.toString());
  }
}
