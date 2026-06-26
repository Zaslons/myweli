import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';

import 'core/router/admin_router.dart';
import 'core/theme/app_theme.dart';
import 'core/utils/logger.dart';
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
      await initializeDateFormatting('fr_FR', null);
      runApp(const MyweliAdminApp());
    },
    (error, stack) => AppLogger.error(
      'Uncaught zone error',
      error: error,
      stackTrace: stack,
    ),
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
        ],
        child: Builder(
          builder: (context) {
            final auth = context.read<AdminAuthProvider>();
            return MaterialApp.router(
              title: 'Myweli Admin',
              debugShowCheckedModeBanner: false,
              theme: AppTheme.lightTheme,
              routerConfig: createAdminRouter(auth),
            );
          },
        ),
      ),
    );
  }
}
