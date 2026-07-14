import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';

import 'core/access/pro_salon_scope.dart';
import 'core/di/dependency_injection.dart';
import 'core/push/firebase_bootstrap.dart';
import 'core/push/push_message_handler.dart';
import 'core/router/pro_router.dart';
import 'core/theme/app_theme.dart';
import 'core/utils/logger.dart';
import 'core/utils/salon_time.dart';
import 'providers/locality_provider.dart';
import 'providers/pro_appointment_provider.dart';
import 'providers/pro_artist_provider.dart';
import 'providers/pro_auth_provider.dart';
import 'providers/pro_availability_provider.dart';
import 'providers/pro_before_after_provider.dart';
import 'providers/pro_clients_provider.dart';
import 'providers/pro_dashboard_provider.dart';
import 'providers/pro_deposit_settings_provider.dart';
import 'providers/pro_earnings_provider.dart';
import 'providers/pro_gallery_provider.dart';
import 'providers/pro_journal_provider.dart';
import 'providers/pro_kyc_provider.dart';
import 'providers/pro_onboarding_provider.dart';
import 'providers/pro_reviews_provider.dart';
import 'providers/pro_salon_profile_provider.dart';
import 'providers/pro_service_provider.dart';
import 'providers/pro_subscription_provider.dart';
import 'providers/pro_team_provider.dart';
import 'providers/provider_provider.dart';
import 'services/push/fcm_message_bridge.dart';

void main() {
  // Run inside a guarded zone so framework errors and uncaught async errors
  // both funnel through AppLogger (the single seam a crash reporter plugs into).
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      FlutterError.onError = (details) {
        FlutterError.presentError(details);
        AppLogger.error(
          'FlutterError: ${details.exceptionAsString()}',
          error: details.exception,
          stackTrace: details.stack,
        );
      };
      await initializeDateFormatting('fr_FR', null);
      // Multi-pays MP2: load the tz database once — salon times
      // render in each salon's own timezone (salon_time.dart).
      initSalonTime();
      // Push (FR-NOTIF-001): must precede DI — the wiring builds the FCM
      // adapter and PushRegistration subscribes to its token stream.
      final pushReady = await initFirebaseForPush();
      setupDependencyInjection();

      // Hoisted: the push handler gates on the session, replays a cold-start
      // tap once it lands, and switches salon before opening a booking.
      final proAuth = ProAuthProvider();
      if (pushReady) await _startPush(proAuth);

      runApp(MyweliProApp(auth: proAuth));
    },
    (error, stack) => AppLogger.error(
      'Uncaught zone error',
      error: error,
      stackTrace: stack,
    ),
  );
}

/// Tapped notifications → the pro router. A salon push carries its
/// `providerId` (and the feed row its `?salon=`), so a multi-salon owner who
/// is signed in on ANOTHER salon switches first — `switchSalon` also resets
/// every salon-scoped provider (R6). A refused switch (revoked, unknown)
/// lands on the dashboard rather than a booking the active scope can't load.
Future<void> _startPush(ProAuthProvider auth) async {
  final handler = PushMessageHandler(
    navigate: (route) async => ProRouter.router.push(route),
    allowedRoutePrefixes: kProRoutePrefixes,
    isAuthenticated: () => auth.isAuthenticated,
    ensureSalon:
        auth.switchSalon, // returns true immediately when already there
    salonSwitchFallbackRoute: '/pro/dashboard',
  );
  auth.addListener(() {
    if (auth.isAuthenticated) unawaited(handler.flushPending());
  });
  await FcmMessageBridge(handler).init();
}

class MyweliProApp extends StatelessWidget {
  const MyweliProApp({super.key, required this.auth});

  final ProAuthProvider auth;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: auth),
        // Consumer listing data — read-only, powers « Aperçu de ma page »
        // (docs/design/pro-salon-lifecycle.md B5).
        ChangeNotifierProvider(create: (_) => ProviderProvider()),
        ChangeNotifierProvider(create: (_) => LocalityProvider()),
        ChangeNotifierProvider(
            create: (_) => ProSalonScope.track(ProDashboardProvider())),
        ChangeNotifierProvider(
            create: (_) => ProSalonScope.track(ProAppointmentProvider())),
        ChangeNotifierProvider(
            create: (_) => ProSalonScope.track(ProServiceProvider())),
        ChangeNotifierProvider(
            create: (_) => ProSalonScope.track(ProArtistProvider())),
        ChangeNotifierProvider(
            create: (_) => ProSalonScope.track(ProClientsProvider())),
        ChangeNotifierProvider(
            create: (_) => ProSalonScope.track(ProJournalProvider())),
        ChangeNotifierProvider(
            create: (_) => ProSalonScope.track(ProAvailabilityProvider())),
        ChangeNotifierProvider(
            create: (_) => ProSalonScope.track(ProEarningsProvider())),
        ChangeNotifierProvider(
            create: (_) => ProSalonScope.track(ProReviewsProvider())),
        ChangeNotifierProvider(
            create: (_) => ProSalonScope.track(ProSalonProfileProvider())),
        ChangeNotifierProvider(
            create: (_) => ProSalonScope.track(ProDepositSettingsProvider())),
        ChangeNotifierProvider(create: (_) => ProKycProvider()),
        ChangeNotifierProvider(
            create: (_) => ProSalonScope.track(ProOnboardingProvider())),
        ChangeNotifierProvider(
            create: (_) => ProSalonScope.track(ProGalleryProvider())),
        ChangeNotifierProvider(
            create: (_) => ProSalonScope.track(ProBeforeAfterProvider())),
        ChangeNotifierProvider(
            create: (_) => ProSalonScope.track(ProSubscriptionProvider())),
        ChangeNotifierProvider(
            create: (_) => ProSalonScope.track(ProTeamProvider())),
      ],
      child: MaterialApp.router(
        title: 'Myweli Pro',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        routerConfig: ProRouter.router,
      ),
    );
  }
}
