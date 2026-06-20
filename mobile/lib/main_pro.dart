import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'core/router/pro_router.dart';
import 'core/theme/app_theme.dart';
import 'core/di/dependency_injection.dart';
import 'providers/pro_auth_provider.dart';
import 'providers/pro_dashboard_provider.dart';
import 'providers/pro_appointment_provider.dart';
import 'providers/pro_service_provider.dart';
import 'providers/pro_artist_provider.dart';
import 'providers/pro_availability_provider.dart';
import 'providers/pro_earnings_provider.dart';
import 'providers/pro_reviews_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('fr_FR', null);
  setupDependencyInjection();
  runApp(const MyweliProApp());
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
