import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'core/a11y/reduce_motion.dart';
import 'core/access/pro_salon_scope.dart';
import 'core/config/build_config_guard.dart';
import 'core/di/dependency_injection.dart';
import 'core/observability/error_reporting.dart';
import 'core/push/firebase_bootstrap.dart';
import 'core/push/push_message_handler.dart';
import 'core/router/pro_router.dart';
import 'core/theme/app_theme.dart';
import 'core/utils/app_locale.dart';
import 'core/utils/logger.dart';
import 'core/utils/salon_time.dart';
import 'providers/locality_provider.dart';
import 'providers/notifications_provider.dart';
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
import 'widgets/common/content_width_cap.dart';

void main() {
  // Run inside a guarded zone so framework errors and uncaught async errors
  // both funnel through AppLogger (the single seam a crash reporter plugs into).
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      // Refuse a release build compiled without the backend defines, BEFORE any
      // startup work — it would otherwise run on mocks and look healthy
      // (docs/design/infra-staging.md §1.3).
      final misconfigured = misconfiguredBuildScreen();
      if (misconfigured != null) {
        runApp(misconfigured);
        return;
      }

      // Error reporting BEFORE anything that can fail, so a failure during
      // startup is itself reported. Inert without --dart-define=SENTRY_DSN, and
      // it never throws (core/observability/error_reporting.dart).
      await initErrorReporting();
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
      // adapter and PushRegistration subscribes to its token stream.
      final pushReady = await initFirebaseForPush();
      setupDependencyInjection();

      // Hoisted: the push handler gates on the session, replays a cold-start
      // tap once it lands, and switches salon before opening a booking.
      final proAuth = ProAuthProvider();
      if (pushReady) await _startPush(proAuth);

      runApp(MyweliProApp(auth: proAuth));
    },
    (error, stack) =>
        AppLogger.error('Uncaught zone error', error: error, stackTrace: stack),
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
        // The salon's notification feed (the bell). ACCOUNT-scoped, not
        // salon-scoped: /me/notifications is keyed by the token subject, so a
        // multi-salon owner sees one merged feed and a switch must not reset
        // it — hence no ProSalonScope.track here.
        ChangeNotifierProvider(
          create: (_) => NotificationsProvider(
            service: serviceLocator.proNotificationService,
          ),
        ),
        ChangeNotifierProvider(
          create: (_) => ProSalonScope.track(ProDashboardProvider()),
        ),
        ChangeNotifierProvider(
          create: (_) => ProSalonScope.track(ProAppointmentProvider()),
        ),
        ChangeNotifierProvider(
          create: (_) => ProSalonScope.track(ProServiceProvider()),
        ),
        ChangeNotifierProvider(
          create: (_) => ProSalonScope.track(ProArtistProvider()),
        ),
        ChangeNotifierProvider(
          create: (_) => ProSalonScope.track(ProClientsProvider()),
        ),
        ChangeNotifierProvider(
          create: (_) => ProSalonScope.track(ProJournalProvider()),
        ),
        ChangeNotifierProvider(
          create: (_) => ProSalonScope.track(ProAvailabilityProvider()),
        ),
        ChangeNotifierProvider(
          create: (_) => ProSalonScope.track(ProEarningsProvider()),
        ),
        ChangeNotifierProvider(
          create: (_) => ProSalonScope.track(ProReviewsProvider()),
        ),
        ChangeNotifierProvider(
          create: (_) => ProSalonScope.track(ProSalonProfileProvider()),
        ),
        ChangeNotifierProvider(
          create: (_) => ProSalonScope.track(ProDepositSettingsProvider()),
        ),
        ChangeNotifierProvider(create: (_) => ProKycProvider()),
        ChangeNotifierProvider(
          create: (_) => ProSalonScope.track(ProOnboardingProvider()),
        ),
        ChangeNotifierProvider(
          create: (_) => ProSalonScope.track(ProGalleryProvider()),
        ),
        ChangeNotifierProvider(
          create: (_) => ProSalonScope.track(ProBeforeAfterProvider()),
        ),
        ChangeNotifierProvider(
          create: (_) => ProSalonScope.track(ProSubscriptionProvider()),
        ),
        ChangeNotifierProvider(
          create: (_) => ProSalonScope.track(ProTeamProvider()),
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
          title: 'MyWeli Pro',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          // §10's content cap. Above the Router and below ScaffoldMessenger,
          // so no screen has to know it exists — and below 720 it is the
          // identity, which is every phone this ships to. See
          // ContentWidthCap: `main_admin.dart` deliberately does NOT install
          // it, and a source pin holds that.
          builder: (context, child) =>
              ContentWidthCap(child: child ?? const SizedBox.shrink()),
          routerConfig: ProRouter.router,
        ),
      ),
    );
  }
}
