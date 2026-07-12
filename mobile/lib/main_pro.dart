import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';

import 'core/access/pro_salon_scope.dart';
import 'core/di/dependency_injection.dart';
import 'core/router/pro_router.dart';
import 'core/theme/app_theme.dart';
import 'core/utils/logger.dart';
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
      setupDependencyInjection();
      runApp(const MyweliProApp());
    },
    (error, stack) => AppLogger.error(
      'Uncaught zone error',
      error: error,
      stackTrace: stack,
    ),
  );
}

class MyweliProApp extends StatelessWidget {
  const MyweliProApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ProAuthProvider()),
        // Consumer listing data — read-only, powers « Aperçu de ma page »
        // (docs/design/pro-salon-lifecycle.md B5).
        ChangeNotifierProvider(create: (_) => ProviderProvider()),
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
