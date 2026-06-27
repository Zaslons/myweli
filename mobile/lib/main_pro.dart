import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';

import 'core/di/dependency_injection.dart';
import 'core/router/pro_router.dart';
import 'core/theme/app_theme.dart';
import 'core/utils/logger.dart';
import 'providers/pro_appointment_provider.dart';
import 'providers/pro_artist_provider.dart';
import 'providers/pro_auth_provider.dart';
import 'providers/pro_availability_provider.dart';
import 'providers/pro_before_after_provider.dart';
import 'providers/pro_dashboard_provider.dart';
import 'providers/pro_deposit_settings_provider.dart';
import 'providers/pro_earnings_provider.dart';
import 'providers/pro_gallery_provider.dart';
import 'providers/pro_kyc_provider.dart';
import 'providers/pro_onboarding_provider.dart';
import 'providers/pro_reviews_provider.dart';
import 'providers/pro_service_provider.dart';

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
        ChangeNotifierProvider(create: (_) => ProDashboardProvider()),
        ChangeNotifierProvider(create: (_) => ProAppointmentProvider()),
        ChangeNotifierProvider(create: (_) => ProServiceProvider()),
        ChangeNotifierProvider(create: (_) => ProArtistProvider()),
        ChangeNotifierProvider(create: (_) => ProAvailabilityProvider()),
        ChangeNotifierProvider(create: (_) => ProEarningsProvider()),
        ChangeNotifierProvider(create: (_) => ProReviewsProvider()),
        ChangeNotifierProvider(create: (_) => ProDepositSettingsProvider()),
        ChangeNotifierProvider(create: (_) => ProKycProvider()),
        ChangeNotifierProvider(create: (_) => ProOnboardingProvider()),
        ChangeNotifierProvider(create: (_) => ProGalleryProvider()),
        ChangeNotifierProvider(create: (_) => ProBeforeAfterProvider()),
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
