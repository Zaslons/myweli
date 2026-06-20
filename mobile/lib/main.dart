import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/di/dependency_injection.dart';
import 'providers/auth_provider.dart';
import 'providers/provider_provider.dart';
import 'providers/appointment_provider.dart';
import 'providers/favorites_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('fr_FR', null);
  setupDependencyInjection();
  runApp(const MyweliApp());
}

class MyweliApp extends StatelessWidget {
  const MyweliApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => ProviderProvider()),
        ChangeNotifierProvider(create: (_) => AppointmentProvider()),
        ChangeNotifierProvider(create: (_) => FavoritesProvider()),
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



