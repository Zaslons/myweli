import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'core/a11y/reduce_motion.dart';
import 'core/di/dependency_injection.dart';
import 'core/push/firebase_bootstrap.dart';
import 'core/push/push_message_handler.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/utils/app_locale.dart';
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
import 'widgets/common/content_width_cap.dart';

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
      // A9: CLDR data + `Intl.defaultLocale`, in that order. The delegates do
      // NOT reach `intl` — see core/utils/app_locale.dart.
      await initAppFormatting();
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
      // Above MaterialApp so the whole tree rebuilds when iOS Reduce Motion is
      // toggled mid-session — nothing in the framework reads that flag (§9, A8).
      child: ReduceMotionObserver(
        child: MaterialApp.router(
          // A9/§17 — French everywhere, including the strings we did not write.
          // **`delegates` (plural), not `delegate`.** `MaterialApp` always
          // appends `DefaultCupertinoLocalizations.delegate`
          // (`material/app.dart:931`), which supports only `en`; the singular
          // Material+Widgets pairing leaves Cupertino unsupported for `fr`, and
          // `_debugCheckLocalizations` turns that into a hard failure in every
          // widget test. The plural declares all three — and iOS genuinely needs
          // the Cupertino one: it is where the text-selection toolbar's
          // Couper/Copier/Coller come from.
          //
          // `Locale('fr','FR')` with the COUNTRY code, because
          // `basicLocaleListResolution` matches at the language rung and would
          // otherwise resolve to a country-less `Locale('fr')`.
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          supportedLocales: const [Locale('fr', 'FR')],
          title: 'Myweli',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          // §10's content cap. Above the Router and below ScaffoldMessenger,
          // so no screen has to know it exists — and below 720 it is the
          // identity, which is every phone this ships to. See
          // ContentWidthCap: `main_admin.dart` deliberately does NOT install
          // it, and a source pin holds that.
          builder: (context, child) =>
              ContentWidthCap(child: child ?? const SizedBox.shrink()),
          routerConfig: AppRouter.router,
        ),
      ),
    );
  }
}
