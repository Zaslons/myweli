import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/models/api_response.dart';
import 'package:myweli/models/appointment.dart';
import 'package:myweli/models/provider.dart' as models;
import 'package:myweli/providers/appointment_provider.dart';
import 'package:myweli/providers/auth_provider.dart';
import 'package:myweli/providers/favorites_provider.dart';
import 'package:myweli/services/mock/mock_appointment_service.dart';
import 'package:myweli/services/mock/mock_auth_service.dart';
import 'package:myweli/services/mock/mock_favorites_service.dart';
import 'package:myweli/widgets/common/account_loader.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/pump_app.dart';
import '../support/secure_storage.dart';

/// consumer-signin-push.md §2.3: the account's lists load once, from the
/// root, when someone signs in — the screens stayed open under the sign-in
/// and are not built again. Never for the session restored at launch, which
/// each screen's own `initState` already loads.
void main() {
  final favorites = _CountingFavorites();
  final bookings = _CountingBookings();

  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    stubSecureStorage();
    serviceLocator
      ..authService = MockAuthService()
      ..favoritesService = favorites
      ..appointmentService = bookings;
  });
  setUp(() {
    favorites.reads = 0;
    bookings.reads = 0;
  });

  Future<AuthProvider> pump(WidgetTester tester) async {
    final auth = AuthProvider();
    await tester.pumpWidget(
      wrapApp(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(value: auth),
          ChangeNotifierProvider(create: (_) => FavoritesProvider()),
          ChangeNotifierProvider(create: (_) => AppointmentProvider()),
        ],
        home: const AccountLoader(child: Text('ÉCRAN')),
      ),
    );
    return auth;
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
  }

  testWidgets('a sign-in made here loads the favourites and the bookings, '
      'once', (tester) async {
    final auth = await pump(tester);
    final sent = auth.requestEmailOtp('awa@test.com');
    await settle(tester);
    expect(await sent, isTrue);
    final signedIn = auth.verifyEmailOtp(
      'awa@test.com',
      MockAuthService.demoOtp,
    );
    await settle(tester);
    expect(await signedIn, isTrue);
    expect(favorites.reads, 1);
    expect(bookings.reads, 1);

    // Profile edits notify the same AuthProvider: no reload for them.
    auth.notifyListeners();
    await settle(tester);
    expect(favorites.reads, 1);
    expect(bookings.reads, 1);
  });

  testWidgets('the session restored at launch loads nothing from here', (
    tester,
  ) async {
    // A session on the phone, as after a previous run.
    final mock = serviceLocator.authService as MockAuthService;
    await tester.runAsync(() async {
      await mock.requestEmailOtp('restore@test.com');
      await mock.verifyEmailOtp('restore@test.com', MockAuthService.demoOtp);
    });
    // AuthProvider restores it as it is built, as at launch.
    final auth = await pump(tester);
    await settle(tester);
    expect(auth.isAuthenticated, isTrue, reason: 'the scenario: restored');
    expect(favorites.reads, 0);
    expect(bookings.reads, 0);
  });
}

class _CountingFavorites extends MockFavoritesService {
  int reads = 0;

  @override
  Future<ApiResponse<List<models.Provider>>> getFavoriteProviders(
    String userId,
  ) {
    reads++;
    return super.getFavoriteProviders(userId);
  }
}

class _CountingBookings extends MockAppointmentService {
  int reads = 0;

  @override
  Future<ApiResponse<List<Appointment>>> getUserAppointments({
    AppointmentStatus? status,
  }) {
    reads++;
    return super.getUserAppointments(status: status);
  }
}
