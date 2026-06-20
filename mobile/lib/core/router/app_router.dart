import 'package:go_router/go_router.dart';
import '../../screens/splash/splash_screen.dart';
import '../../screens/auth/phone_login_screen.dart';
import '../../screens/auth/otp_verify_screen.dart';
import '../../screens/home/home_screen.dart';
import '../../screens/providers/provider_list_screen.dart';
import '../../screens/providers/provider_detail_screen.dart';
import '../../screens/booking/service_selection_screen.dart';
import '../../screens/booking/artist_selection_screen.dart';
import '../../screens/booking/date_time_selection_screen.dart';
import '../../screens/booking/booking_confirmation_screen.dart';
import '../../screens/booking/booking_hub_screen.dart';
import '../../screens/appointments/my_bookings_screen.dart';
import '../../screens/appointments/appointment_detail_screen.dart';
import '../../screens/profile/profile_screen.dart';
import '../../screens/profile/edit_profile_screen.dart';
import '../../screens/map/map_screen.dart';
import '../../screens/notifications/notifications_screen.dart';

class AppRouter {
  static final GoRouter router = GoRouter(
    initialLocation: '/splash',
    routes: [
      GoRoute(
        path: '/splash',
        name: 'splash',
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: '/login',
        name: 'login',
        builder: (context, state) {
          final returnTo = state.uri.queryParameters['returnTo'];
          return PhoneLoginScreen(returnTo: returnTo);
        },
      ),
      GoRoute(
        path: '/verify-otp',
        name: 'verify-otp',
        builder: (context, state) {
          final phone = state.uri.queryParameters['phone'] ?? '';
          final returnTo = state.uri.queryParameters['returnTo'];
          return OtpVerifyScreen(phoneNumber: phone, returnTo: returnTo);
        },
      ),
      GoRoute(
        path: '/home',
        name: 'home',
        builder: (context, state) => const HomeScreen(),
      ),
      GoRoute(
        path: '/providers',
        name: 'providers',
        builder: (context, state) {
          final category = state.uri.queryParameters['category'];
          return ProviderListScreen(category: category);
        },
      ),
      GoRoute(
        path: '/provider/:id',
        name: 'provider-detail',
        builder: (context, state) {
          final id = state.pathParameters['id']!;
          return ProviderDetailScreen(providerId: id);
        },
      ),
      GoRoute(
        path: '/booking',
        name: 'booking-hub',
        builder: (context, state) {
          final providerId = state.uri.queryParameters['providerId']!;
          return BookingHubScreen(providerId: providerId);
        },
      ),
      GoRoute(
        path: '/booking/service',
        name: 'service-selection',
        builder: (context, state) {
          final providerId = state.uri.queryParameters['providerId']!;
          final returnToHub = state.uri.queryParameters['returnToHub'] == '1';
          final selectedParam = state.uri.queryParameters['selectedServiceIds'];
          final initialSelectedServiceIds =
              selectedParam == null || selectedParam.isEmpty
                  ? const <String>[]
                  : selectedParam.split(',');
          final artistId = state.uri.queryParameters['artistId'];
          return ServiceSelectionScreen(
            providerId: providerId,
            returnToHub: returnToHub,
            initialSelectedServiceIds: initialSelectedServiceIds,
            artistId: artistId,
          );
        },
      ),
      GoRoute(
        path: '/booking/artist',
        name: 'artist-selection',
        builder: (context, state) {
          final providerId = state.uri.queryParameters['providerId']!;
          final serviceParam = state.uri.queryParameters['serviceIds'];
          final serviceIds =
              serviceParam == null || serviceParam.isEmpty
                  ? const <String>[]
                  : serviceParam.split(',');
          final returnToHub = state.uri.queryParameters['returnToHub'] == '1';
          final artistId = state.uri.queryParameters['artistId'];
          final dateTimeParam = state.uri.queryParameters['dateTime'];
          final initialDateTime =
              dateTimeParam == null ? null : DateTime.tryParse(dateTimeParam);
          final durationMinutes = int.tryParse(
            state.uri.queryParameters['durationMinutes'] ?? '',
          );
          return ArtistSelectionScreen(
            providerId: providerId,
            serviceIds: serviceIds,
            returnToHub: returnToHub,
            initialArtistId: artistId,
            initialDateTime: initialDateTime,
            durationMinutes: durationMinutes,
          );
        },
      ),
      GoRoute(
        path: '/booking/date-time',
        name: 'date-time-selection',
        builder: (context, state) {
          final providerId = state.uri.queryParameters['providerId']!;
          final serviceParam = state.uri.queryParameters['serviceIds'];
          final serviceIds =
              serviceParam == null || serviceParam.isEmpty
                  ? const <String>[]
                  : serviceParam.split(',');
          final artistId = state.uri.queryParameters['artistId'];
          final returnToHub = state.uri.queryParameters['returnToHub'] == '1';
          final dateTimeParam = state.uri.queryParameters['dateTime'];
          final initialDateTime =
              dateTimeParam == null ? null : DateTime.tryParse(dateTimeParam);
          final durationMinutes = int.tryParse(
            state.uri.queryParameters['durationMinutes'] ?? '',
          );
          return DateTimeSelectionScreen(
            providerId: providerId,
            serviceIds: serviceIds,
            artistId: artistId,
            returnToHub: returnToHub,
            initialDateTime: initialDateTime,
            durationMinutes: durationMinutes,
          );
        },
      ),
      GoRoute(
        path: '/booking/confirm',
        name: 'booking-confirmation',
        builder: (context, state) {
          final providerId = state.uri.queryParameters['providerId']!;
          final serviceIds = state.uri.queryParameters['serviceIds']!.split(',');
          final dateTime = DateTime.parse(state.uri.queryParameters['dateTime']!);
          final artistId = state.uri.queryParameters['artistId'];
          return BookingConfirmationScreen(
            providerId: providerId,
            serviceIds: serviceIds,
            appointmentDateTime: dateTime,
            artistId: artistId,
          );
        },
      ),
      GoRoute(
        path: '/bookings',
        name: 'bookings',
        builder: (context, state) => const MyBookingsScreen(),
      ),
      GoRoute(
        path: '/appointment/:id',
        name: 'appointment-detail',
        builder: (context, state) {
          final id = state.pathParameters['id']!;
          return AppointmentDetailScreen(appointmentId: id);
        },
      ),
      GoRoute(
        path: '/profile',
        name: 'profile',
        builder: (context, state) => const ProfileScreen(),
        routes: [
          GoRoute(
            path: 'edit',
            name: 'profile-edit',
            builder: (context, state) => const EditProfileScreen(),
          ),
        ],
      ),
      GoRoute(
        path: '/notifications',
        name: 'notifications',
        builder: (context, state) => const NotificationsScreen(),
      ),
      GoRoute(
        path: '/favorites',
        name: 'favorites',
        builder: (context, state) {
          final focusProviderId = state.uri.queryParameters['providerId'];
          return MapScreen(focusProviderId: focusProviderId);
        },
      ),
    ],
  );
}



