import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'core/a11y/reduce_motion.dart';
import 'core/router/admin_router.dart';
import 'core/theme/app_theme.dart';
import 'core/utils/app_locale.dart';
import 'core/utils/logger.dart';
import 'core/utils/salon_time.dart';
import 'providers/admin/admin_audit_provider.dart';
import 'providers/admin/admin_auth_provider.dart';
import 'providers/admin/admin_dashboard_provider.dart';
import 'providers/admin/admin_dispute_detail_provider.dart';
import 'providers/admin/admin_disputes_provider.dart';
import 'providers/admin/admin_kyc_provider.dart';
import 'providers/admin/admin_moderation_provider.dart';
import 'providers/admin/admin_provider_detail_provider.dart';
import 'providers/admin/admin_providers_provider.dart';
import 'providers/admin/admin_user_detail_provider.dart';
import 'providers/admin/admin_users_provider.dart';

/// Myweli admin/ops console — a 3rd Flutter (Web) entrypoint, behind admin
/// login. Design: docs/design/admin-console-ui.md.
void main() {
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
      runApp(const MyweliAdminApp());
    },
    (error, stack) =>
        AppLogger.error('Uncaught zone error', error: error, stackTrace: stack),
  );
}

class MyweliAdminApp extends StatelessWidget {
  const MyweliAdminApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AdminAuthProvider()..restore(),
      child: MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => AdminDashboardProvider()),
          ChangeNotifierProvider(create: (_) => AdminKycProvider()),
          ChangeNotifierProvider(create: (_) => AdminModerationProvider()),
          ChangeNotifierProvider(create: (_) => AdminProvidersProvider()),
          ChangeNotifierProvider(create: (_) => AdminUsersProvider()),
          ChangeNotifierProvider(create: (_) => AdminProviderDetailProvider()),
          ChangeNotifierProvider(create: (_) => AdminUserDetailProvider()),
          ChangeNotifierProvider(create: (_) => AdminDisputesProvider()),
          ChangeNotifierProvider(create: (_) => AdminDisputeDetailProvider()),
          ChangeNotifierProvider(create: (_) => AdminAuditProvider()),
        ],
        child: Builder(
          builder: (context) {
            final auth = context.read<AdminAuthProvider>();
            // Above MaterialApp so the whole tree rebuilds when iOS Reduce
            // Motion is toggled mid-session — nothing in the framework reads
            // that flag (§9, A8).
            return ReduceMotionObserver(
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
                title: 'Myweli Admin',
                debugShowCheckedModeBanner: false,
                theme: AppTheme.lightTheme,
                routerConfig: createAdminRouter(auth),
              ),
            );
          },
        ),
      ),
    );
  }
}
