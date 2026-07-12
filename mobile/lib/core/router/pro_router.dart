import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../providers/pro_auth_provider.dart';
import '../../screens/provider/appointments/appointment_list_screen.dart';
import '../../screens/provider/appointments/pro_appointment_detail_screen.dart';
import '../../screens/provider/appointments/pro_manual_booking_screen.dart';
import '../../screens/provider/artists/artist_form_screen.dart';
import '../../screens/provider/artists/artist_list_screen.dart';
import '../../screens/provider/auth/pro_login_screen.dart';
import '../../screens/provider/auth/pro_register_screen.dart';
import '../../screens/provider/auth/pro_splash_screen.dart';
import '../../screens/provider/availability/availability_screen.dart';
import '../../screens/provider/clients/client_detail_screen.dart';
import '../../screens/provider/clients/client_list_screen.dart';
import '../../screens/provider/dashboard/dashboard_screen.dart';
import '../../screens/provider/earnings/earnings_screen.dart';
import '../../screens/provider/journal/pro_journal_screen.dart';
import '../../screens/provider/onboarding/pro_kyc_screen.dart';
import '../../screens/provider/onboarding/pro_onboarding_screen.dart';
import '../../screens/provider/photos/pro_before_after_screen.dart';
import '../../screens/provider/photos/pro_photos_screen.dart';
import '../../screens/provider/profile/pro_data_export_screen.dart';
import '../../screens/provider/profile/pro_profile_screen.dart';
import '../../screens/provider/profile/pro_salon_profile_screen.dart';
import '../../screens/provider/reviews/reviews_screen.dart';
import '../../screens/provider/services/service_form_screen.dart';
import '../../screens/provider/services/service_list_screen.dart';
import '../../screens/provider/settings/deposit_settings_screen.dart';
import '../../screens/provider/staff/staff_home_screen.dart';
import '../../screens/provider/subscription/pro_subscription_screen.dart';
import '../../screens/provider/team/pro_invitations_screen.dart';
import '../../screens/provider/team/team_screen.dart';
import '../../screens/providers/provider_detail_screen.dart';

class ProRouter {
  static final GoRouter router = GoRouter(
    initialLocation: '/pro/splash',
    routes: [
      GoRoute(
        path: '/pro/splash',
        name: 'pro-splash',
        builder: (context, state) => const ProSplashScreen(),
      ),
      GoRoute(
        path: '/pro/login',
        name: 'pro-login',
        builder: (context, state) {
          final returnTo = state.uri.queryParameters['returnTo'];
          return ProLoginScreen(returnTo: returnTo);
        },
      ),
      GoRoute(
        path: '/pro/register',
        name: 'pro-register',
        builder: (context, state) => const ProRegisterScreen(),
      ),
      // /pro/verify-otp unrouted — phone-OTP login is dormant at launch
      // (AUTH_METHODS gates the backend; ProOtpVerifyScreen kept for the
      // Termii-era phone VERIFICATION reuse). docs/design/pro-auth-social.md.
      // The Collaborateur shell (access R4b): Journée · Calendrier · Profil.
      GoRoute(
        path: '/pro/staff',
        name: 'pro-staff',
        builder: (context, state) => const StaffHomeScreen(),
      ),
      GoRoute(
        path: '/pro/dashboard',
        name: 'pro-dashboard',
        builder: (context, state) => const DashboardScreen(),
      ),
      GoRoute(
        path: '/pro/clients',
        name: 'pro-clients',
        builder: (context, state) => const ClientListScreen(),
      ),
      GoRoute(
        path: '/pro/clients/:id',
        name: 'pro-client-detail',
        builder: (context, state) =>
            ClientDetailScreen(clientId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/pro/journal',
        name: 'pro-journal',
        builder: (context, state) => const ProJournalScreen(),
      ),
      GoRoute(
        path: '/pro/appointments',
        name: 'pro-appointments',
        builder: (context, state) => const AppointmentListScreen(),
      ),
      GoRoute(
        // Registered before ':id' so "new" isn't matched as an appointment id.
        path: '/pro/appointment/new',
        name: 'pro-appointment-new',
        builder: (context, state) {
          // Prefill from the client card (module clients C1c).
          final extra = state.extra as Map<String, dynamic>?;
          final dt = extra?['dateTime'] as String?;
          return ProManualBookingScreen(
            initialClientName: extra?['clientName'] as String?,
            initialClientPhone: extra?['clientPhone'] as String?,
            initialDateTime: dt == null ? null : DateTime.tryParse(dt),
            initialArtistId: extra?['artistId'] as String?,
          );
        },
      ),
      GoRoute(
        path: '/pro/appointment/:id',
        name: 'pro-appointment-detail',
        builder: (context, state) {
          final id = state.pathParameters['id']!;
          return ProAppointmentDetailScreen(appointmentId: id);
        },
      ),
      GoRoute(
        path: '/pro/services',
        name: 'pro-services',
        builder: (context, state) => const ServiceListScreen(),
      ),
      GoRoute(
        path: '/pro/service/new',
        name: 'pro-service-new',
        builder: (context, state) => const ServiceFormScreen(),
      ),
      GoRoute(
        path: '/pro/service/:id/edit',
        name: 'pro-service-edit',
        builder: (context, state) {
          final id = state.pathParameters['id']!;
          return ServiceFormScreen(serviceId: id);
        },
      ),
      GoRoute(
        path: '/pro/artists',
        name: 'pro-artists',
        builder: (context, state) => const ArtistListScreen(),
      ),
      GoRoute(
        path: '/pro/artist/new',
        name: 'pro-artist-new',
        builder: (context, state) => const ArtistFormScreen(),
      ),
      GoRoute(
        path: '/pro/artist/:id/edit',
        name: 'pro-artist-edit',
        builder: (context, state) {
          final id = state.pathParameters['id']!;
          return ArtistFormScreen(artistId: id);
        },
      ),
      GoRoute(
        path: '/pro/availability',
        name: 'pro-availability',
        builder: (context, state) => const AvailabilityScreen(),
      ),
      GoRoute(
        path: '/pro/profile',
        name: 'pro-profile',
        builder: (context, state) => const ProProfileScreen(),
      ),
      GoRoute(
        path: '/pro/salon-profile',
        name: 'pro-salon-profile',
        builder: (context, state) => const ProSalonProfileScreen(),
      ),
      GoRoute(
        path: '/pro/deposit-settings',
        name: 'pro-deposit-settings',
        builder: (context, state) {
          final providerId =
              context.read<ProAuthProvider>().activeSalonId ?? '';
          return DepositSettingsScreen(providerId: providerId);
        },
      ),
      GoRoute(
        path: '/pro/subscription',
        name: 'pro-subscription',
        builder: (context, state) => const ProSubscriptionScreen(),
      ),
      // Team access R3 (docs/design/team-access-r3-app.md).
      GoRoute(
        path: '/pro/team',
        name: 'pro-team',
        builder: (context, state) => const TeamScreen(),
      ),
      GoRoute(
        path: '/pro/invitations',
        name: 'pro-invitations',
        builder: (context, state) => const ProInvitationsScreen(),
      ),
      GoRoute(
        path: '/pro/verification',
        name: 'pro-verification',
        builder: (context, state) => const ProKycScreen(),
      ),
      GoRoute(
        path: '/pro/apercu',
        name: 'pro-apercu',
        builder: (context, state) {
          // Owner preview of the public listing (pro-salon-lifecycle B5).
          final providerId =
              context.read<ProAuthProvider>().activeSalonId ?? '';
          return ProviderDetailScreen(providerId: providerId, preview: true);
        },
      ),
      GoRoute(
        path: '/pro/onboarding',
        name: 'pro-onboarding',
        builder: (context, state) => const ProOnboardingScreen(),
      ),
      GoRoute(
        path: '/pro/earnings',
        name: 'pro-earnings',
        builder: (context, state) => const EarningsScreen(),
      ),
      GoRoute(
        path: '/pro/data-export',
        name: 'pro-data-export',
        builder: (context, state) => const ProDataExportScreen(),
      ),
      GoRoute(
        path: '/pro/photos',
        name: 'pro-photos',
        builder: (context, state) => const ProPhotosScreen(),
      ),
      GoRoute(
        path: '/pro/before-after',
        name: 'pro-before-after',
        builder: (context, state) => const ProBeforeAfterScreen(),
      ),
      GoRoute(
        path: '/pro/reviews',
        name: 'pro-reviews',
        builder: (context, state) => const ReviewsScreen(),
      ),
    ],
  );
}
