import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';

import 'core/di/dependency_injection.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/utils/logger.dart';
import 'core/utils/salon_time.dart';
import 'providers/appointment_provider.dart';
import 'providers/auth_provider.dart';
import 'providers/favorites_provider.dart';
import 'providers/locality_provider.dart';
import 'providers/messaging_provider.dart';
import 'providers/notification_preferences_provider.dart';
import 'providers/notifications_provider.dart';
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
      // Multi-pays MP2: load the tz database once — salon times
      // render in each salon's own timezone (salon_time.dart).
      initSalonTime();
      setupDependencyInjection();
      runApp(const MyweliApp());
    },
    (error, stack) => AppLogger.error(
      'Uncaught zone error',
      error: error,
      stackTrace: stack,
    ),
  );
}

class MyweliApp extends StatelessWidget {
  const MyweliApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => ProviderProvider()),
        ChangeNotifierProvider(create: (_) => LocalityProvider()),
        ChangeNotifierProvider(create: (_) => AppointmentProvider()),
        ChangeNotifierProvider(create: (_) => FavoritesProvider()),
        ChangeNotifierProvider(create: (_) => MessagingProvider()),
        ChangeNotifierProvider(create: (_) => NotificationsProvider()),
        ChangeNotifierProvider(
          create: (_) => NotificationPreferencesProvider(),
        ),
      ],
      child: MaterialApp.router(
        title: 'Myweli',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        routerConfig: AppRouter.router,
      ),
    );
  }
}
