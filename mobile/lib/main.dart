import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';

import 'core/di/dependency_injection.dart';
import 'core/push/firebase_bootstrap.dart';
import 'core/push/push_message_handler.dart';
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
      // adapter and PushRegistration subscribes to its token stream. Off in
      // demo mode / on web / when the platform config is missing.
      final pushReady = await initFirebaseForPush();
      setupDependencyInjection();

      // Hoisted so the push handler can gate on the session and replay a
      // cold-start tap once it lands (everything else stays inline below).
      final auth = AuthProvider();
      if (pushReady) await _startPush(auth);

      runApp(MyweliApp(auth: auth));
    },
    (error, stack) => AppLogger.error(
      'Uncaught zone error',
      error: error,
      stackTrace: stack,
    ),
  );
}

/// Tapped notifications → the consumer router. A tap that LAUNCHED the app
/// arrives before the session is restored, so the handler buffers it and the
/// auth listener flushes it the moment we're signed in.
Future<void> _startPush(AuthProvider auth) async {
  final handler = PushMessageHandler(
    navigate: (route) async => AppRouter.router.push(route),
    allowedRoutePrefixes: kConsumerRoutePrefixes,
    isAuthenticated: () => auth.isAuthenticated,
  );
  auth.addListener(() {
    if (auth.isAuthenticated) unawaited(handler.flushPending());
  });
  await FcmMessageBridge(handler).init();
}

class MyweliApp extends StatelessWidget {
  const MyweliApp({super.key, required this.auth});

  final AuthProvider auth;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: auth),
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
