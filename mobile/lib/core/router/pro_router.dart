import 'package:go_router/go_router.dart';

import '../../screens/provider/appointments/appointment_list_screen.dart';
import '../../screens/provider/appointments/pro_appointment_detail_screen.dart';
import '../../screens/provider/artists/artist_form_screen.dart';
import '../../screens/provider/artists/artist_list_screen.dart';
import '../../screens/provider/auth/pro_login_screen.dart';
import '../../screens/provider/auth/pro_otp_verify_screen.dart';
import '../../screens/provider/auth/pro_register_screen.dart';
import '../../screens/provider/auth/pro_splash_screen.dart';
import '../../screens/provider/availability/availability_screen.dart';
import '../../screens/provider/dashboard/dashboard_screen.dart';
import '../../screens/provider/earnings/earnings_screen.dart';
import '../../screens/provider/profile/pro_profile_screen.dart';
import '../../screens/provider/reviews/reviews_screen.dart';
import '../../screens/provider/services/service_form_screen.dart';
import '../../screens/provider/services/service_list_screen.dart';

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
      GoRoute(
        path: '/pro/verify-otp',
        name: 'pro-verify-otp',
        builder: (context, state) {
          final phone = state.uri.queryParameters['phone'] ?? '';
          final returnTo = state.uri.queryParameters['returnTo'];
          return ProOtpVerifyScreen(phoneNumber: phone, returnTo: returnTo);
        },
      ),
      GoRoute(
        path: '/pro/dashboard',
        name: 'pro-dashboard',
        builder: (context, state) => const DashboardScreen(),
      ),
      GoRoute(
        path: '/pro/appointments',
        name: 'pro-appointments',
        builder: (context, state) => const AppointmentListScreen(),
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
        path: '/pro/earnings',
        name: 'pro-earnings',
        builder: (context, state) => const EarningsScreen(),
      ),
      GoRoute(
        path: '/pro/reviews',
        name: 'pro-reviews',
        builder: (context, state) => const ReviewsScreen(),
      ),
    ],
  );
}
