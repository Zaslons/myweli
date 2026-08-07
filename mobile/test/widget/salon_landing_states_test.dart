import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/models/api_response.dart';
import 'package:myweli/models/provider.dart' as models;
import 'package:myweli/providers/appointment_provider.dart';
import 'package:myweli/providers/auth_provider.dart';
import 'package:myweli/providers/favorites_provider.dart';
import 'package:myweli/providers/locality_provider.dart';
import 'package:myweli/providers/provider_provider.dart';
import 'package:myweli/screens/booking/booking_confirmation_screen.dart';
import 'package:myweli/screens/booking/booking_hub_screen.dart';
import 'package:myweli/screens/providers/provider_detail_screen.dart';
import 'package:myweli/services/mock/mock_appointment_service.dart';
import 'package:myweli/services/mock/mock_auth_service.dart';
import 'package:myweli/services/mock/mock_favorites_service.dart';
import 'package:myweli/services/mock/mock_locality_service.dart';
import 'package:myweli/services/mock/mock_provider_service.dart';
import 'package:myweli/widgets/common/loading_indicator.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/pump_app.dart';

/// The three screens whose whole subject is one salon, when that salon is gone
/// (§21 row 82 · §12 · `salon-state-and-refusals.md` §6 cell 5).
///
/// **Decision C is what makes this reachable.** `GET /providers/{id}` now 404s a
/// salon that is `draft` or `suspended`, so « the salon this screen is about is
/// not there » stops being theoretical. Before PR1d the three screens answered
/// it three different ways, none of them right:
///
/// - the salon detail hand-rolled a red `error_outline` and a « Retour » that
///   pops to nothing on a deep link;
/// - the booking hub rendered a bare centred grey sentence — no icon, no way
///   out;
/// - the booking CONFIRMATION, the screen immediately before payment, had **no
///   error branch at all** and spun forever.
///
/// And all three flashed the ERROR state on frame 1, because the load is
/// scheduled post-frame so the first build saw « not loading, nothing loaded »
/// — a state machine where `null` meant both « not asked » and « asked and
/// failed ».

/// One instance, registered once (`serviceLocator.providerService` is `late
/// final`), whose behaviour each test sets. `hang` is the only way to observe
/// frame 1: a future that never completes.
class _ScriptedProviderService extends MockProviderService {
  String? code;
  bool hang = false;

  @override
  Future<ApiResponse<models.Provider>> getProviderById(String id) {
    if (hang) return Completer<ApiResponse<models.Provider>>().future;
    return Future.value(ApiResponse.error('peu importe la phrase', code: code));
  }
}

final service = _ScriptedProviderService();

void main() {
  setUpAll(() async {
    await initializeDateFormatting('fr_FR', null);
    SharedPreferences.setMockInitialValues({});
    serviceLocator.authService = MockAuthService();
    serviceLocator.localityService = MockLocalityService();
    serviceLocator.appointmentService = MockAppointmentService();
    serviceLocator.favoritesService = MockFavoritesService();
    serviceLocator.providerService = service;
  });

  setUp(() {
    service
      ..code = null
      ..hang = false;
  });

  Widget host(Widget home, AuthProvider auth) => wrapApp(
    providers: [
      ChangeNotifierProvider(create: (_) => ProviderProvider()),
      ChangeNotifierProvider(create: (_) => AppointmentProvider()),
      ChangeNotifierProvider(create: (_) => FavoritesProvider()),
      ChangeNotifierProvider<AuthProvider>.value(value: auth),
      ChangeNotifierProvider(create: (_) => LocalityProvider()),
    ],
    home: home,
  );

  /// The confirmation screen redirects an anonymous visitor to `/login` before
  /// it ever loads a salon (`initState`), so its error state is only reachable
  /// signed in — which is also the only state a real client reaches it in.
  /// `runAsync`, because `AuthProvider` hydrates from the session store with a
  /// real timer and fake-async never advances it — the constructor has to have
  /// finished before the screen's post-frame callback reads `isAuthenticated`.
  Future<AuthProvider> signedIn(WidgetTester tester) async {
    late AuthProvider auth;
    await tester.runAsync(() async {
      final sent = await serviceLocator.authService.sendOtp('+2250700000000');
      await serviceLocator.authService.verifyOtp('+2250700000000', sent.data!);
      auth = AuthProvider();
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    return auth;
  }

  final screens = <String, Widget>{
    'la fiche du salon': const ProviderDetailScreen(providerId: 'gone'),
    'le tunnel de réservation': const BookingHubScreen(providerId: 'gone'),
    'la confirmation': BookingConfirmationScreen(
      providerId: 'gone',
      serviceIds: const ['service1'],
      appointmentDateTime: DateTime.now().add(const Duration(days: 3)),
    ),
  };

  group('a salon that is gone — the 404 lands softly', () {
    for (final entry in screens.entries) {
      testWidgets('${entry.key}: says so, and points somewhere', (
        tester,
      ) async {
        service.code = 'not_found';
        await tester.pumpWidget(host(entry.value, await signedIn(tester)));
        await tester.pump();
        await tester.pump();

        expect(
          find.text('Ce salon n’est plus disponible sur MyWeli.'),
          findsOneWidget,
        );
        // The way out leads somewhere. « Réessayer » would not: the salon is
        // not coming back this session, and §12 as amended by row 82 says a
        // retry control that cannot succeed is the dead end with a button on
        // it.
        expect(find.text('Découvrir des salons'), findsOneWidget);
        expect(find.text('Réessayer'), findsNothing);
        // And the spinner is gone — the confirmation screen used to sit here
        // forever, on the screen immediately before payment.
        expect(find.byType(LoadingIndicator), findsNothing);
        await tester.pump(const Duration(seconds: 5));
      });

      testWidgets('${entry.key}: a DROPPED CONNECTION offers the retry', (
        tester,
      ) async {
        // The pair. Without it, a screen that never offers a retry would pass
        // every assertion above — and the two failures need opposite
        // treatments, which is the entire reason `code` went on the wire.
        service.code = 'network';
        await tester.pumpWidget(host(entry.value, await signedIn(tester)));
        await tester.pump();
        await tester.pump();

        expect(find.text('Réessayer'), findsOneWidget);
        expect(find.text('Découvrir des salons'), findsNothing);
        expect(
          find.text('Ce salon n’est plus disponible sur MyWeli.'),
          findsNothing,
        );
        await tester.pump(const Duration(seconds: 5));
      });

      testWidgets('${entry.key}: frame ONE is the loader, never the error', (
        tester,
      ) async {
        // No `pumpAndSettle`, no post-frame flush: the very first build. The
        // load is scheduled post-frame (it must be — notifying during build
        // throws), so without `beginProviderLoad` this frame had
        // `isLoading == false, selectedProvider == null` and rendered the
        // ERROR state for one frame on all three screens.
        service.hang = true;
        await tester.pumpWidget(host(entry.value, await signedIn(tester)));

        expect(find.byType(LoadingIndicator), findsOneWidget);
        expect(find.text('Découvrir des salons'), findsNothing);
        expect(find.text('Réessayer'), findsNothing);
        await tester.pump(const Duration(seconds: 5));
      });
    }
  });
}
