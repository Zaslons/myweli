import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/core/auth/open_sign_in.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/providers/appointment_provider.dart';
import 'package:myweli/providers/auth_provider.dart';
import 'package:myweli/providers/notification_preferences_provider.dart';
import 'package:myweli/providers/provider_provider.dart';
import 'package:myweli/screens/appointments/my_bookings_screen.dart';
import 'package:myweli/screens/auth/login_screen.dart';
import 'package:myweli/screens/notifications/notifications_screen.dart';
import 'package:myweli/screens/profile/notification_preferences_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fonts.dart';
import '../support/secure_storage.dart';
import '_a11y.dart';

/// consumer-signin-push.md §8, accessibility: what A3 adds to a screen holds
/// at the floor's widths and at 200 % text — the sign-in's « Fermer » and its
/// longest reason line, the two signed-out pages, and Préférences' card.
/// This measures; the goldens look.
void main() {
  setUpAll(() async {
    await loadRealFonts();
    SharedPreferences.setMockInitialValues({});
    stubSecureStorage();
    setupDependencyInjection();
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));

  const widths = [360.0, 375.0, 390.0];
  const scales = [1.0, 2.0];

  /// Each screen with a string that proves IT rendered (see
  /// auth_layout_test.dart: an empty tree passes every other check).
  final screens = <String, ({Widget screen, String proof})>{
    'the sign-in for a heart': (
      screen: const LoginScreen(reason: SignInReason.heart),
      proof: 'Connectez-vous pour ajouter ce salon à vos favoris.',
    ),
    '« Rendez-vous », signed out': (
      screen: const MyBookingsScreen(),
      proof:
          'Connectez-vous pour retrouver vos rendez-vous et en suivre l’état.',
    ),
    '« Actu », signed out': (
      screen: const NotificationsScreen(),
      proof:
          'Connectez-vous pour suivre vos rendez-vous et les réponses des '
          'salons.',
    ),
    'Préférences, this phone never asked': (
      screen: const NotificationPreferencesScreen(),
      proof: 'Activer les notifications',
    ),
  };

  for (final width in widths) {
    for (final scale in scales) {
      final at = '${width.toInt()}dp × ${scale.toInt()}× text';
      for (final entry in screens.entries) {
        testWidgets('${entry.key} fits $at', (tester) async {
          await pumpAtWidth(
            tester,
            width: width,
            scale: scale,
            providers: [
              ChangeNotifierProvider(create: (_) => AuthProvider()),
              ChangeNotifierProvider(create: (_) => AppointmentProvider()),
              ChangeNotifierProvider(create: (_) => ProviderProvider()),
              ChangeNotifierProvider(
                create: (_) => NotificationPreferencesProvider(),
              ),
            ],
            home: entry.value.screen,
          );
          expect(
            find.text(entry.value.proof),
            findsOneWidget,
            reason: '« ${entry.value.proof} » is not on ${entry.key} at $at',
          );
          expectNoUndeclaredTruncation(tester, context: '${entry.key} $at');
          expectNoLegibilityCrush(tester, context: '${entry.key} $at');
          expectNoVerticalClip(tester, context: '${entry.key} $at');
          expect(tester.takeException(), isNull);
        });
      }
    }
  }

  testWidgets('« Fermer » is a 48 × 48 target with its tooltip', (
    tester,
  ) async {
    await pumpAtWidth(
      tester,
      width: 360,
      providers: [ChangeNotifierProvider(create: (_) => AuthProvider())],
      home: const LoginScreen(),
    );
    final button = find.ancestor(
      of: find.byTooltip('Fermer'),
      matching: find.byType(IconButton),
    );
    expect(button, findsOneWidget);
    expect(tester.getSize(button).width, greaterThanOrEqualTo(48));
    expect(tester.getSize(button).height, greaterThanOrEqualTo(48));
  });
}
