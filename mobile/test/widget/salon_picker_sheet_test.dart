import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/core/access/pro_salon_scope.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/core/push/push_registration.dart';
import 'package:myweli/models/salon_subscription.dart';
import 'package:myweli/providers/pro_auth_provider.dart';
import 'package:myweli/services/mock/mock_auth_service.dart';
import 'package:myweli/services/mock/mock_data.dart';
import 'package:myweli/services/mock/mock_device_registration_service.dart';
import 'package:myweli/services/mock/mock_pro_service.dart';
import 'package:myweli/services/mock/mock_push_notification_service.dart';
import 'package:myweli/services/mock/mock_subscription_service.dart';
import 'package:myweli/widgets/provider/salon_picker_sheet.dart';
import 'package:provider/provider.dart';

import '../support/pump_app.dart';

/// Team access R6b — the « Mes salons » switcher sheet: both memberships
/// render with role + state, the active salon carries the check, a tap
/// switches, and « Ajouter un salon » appears only when the gate is open.
void main() {
  setUpAll(() {
    serviceLocator.authService = MockAuthService();
    serviceLocator.proService = MockProService();
    serviceLocator.subscriptionService = MockSubscriptionService();
    serviceLocator.proPushRegistration = PushRegistration(
      push: MockPushNotificationService(),
      devices: MockDeviceRegistrationService(),
    );
  });

  setUp(() async {
    MockData.resetTeam();
    ProSalonScope.clear();
    (serviceLocator.subscriptionService as MockSubscriptionService)
        .resetForTests();
    await serviceLocator.authService.logoutProvider();
  });

  Future<ProAuthProvider> signInOwner(WidgetTester tester) async {
    late ProAuthProvider auth;
    await tester.runAsync(() async {
      auth = ProAuthProvider();
      await auth.requestEmailOtp('jean@salon-excellence.test');
      final ok = await auth.verifyEmailOtp(
        'jean@salon-excellence.test',
        auth.emailDevCode!,
      );
      expect(ok, isTrue, reason: 'owner login failed');
      // Poll (not a fixed sleep — the suite runs under load): the unawaited
      // post-login loadMySalons must land before the sheet opens.
      for (var i = 0; i < 100 && auth.salons.isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      expect(auth.salons, isNotEmpty, reason: 'salon list never loaded');
    });
    return auth;
  }

  /// Fire the mock-latency timers the sheet's refresh started (FakeAsync
  /// would otherwise flag them as pending at teardown — the R4b lesson).
  Future<void> drain(WidgetTester tester) =>
      tester.pump(const Duration(seconds: 2));

  Future<void> pumpPicker(WidgetTester tester, ProAuthProvider auth) async {
    await tester.pumpWidget(
      wrapApp(
        providers: [ChangeNotifierProvider<ProAuthProvider>.value(value: auth)],
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showSalonPicker(context),
                child: const Text('ouvrir'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('ouvrir'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('lists both salons with roles; the active one is checked',
      (tester) async {
    final auth = await signInOwner(tester);
    await pumpPicker(tester, auth);

    expect(find.text('Mes salons'), findsOneWidget);
    expect(find.text('Salon Excellence'), findsOneWidget);
    expect(find.text('Beauté Divine'), findsOneWidget);
    expect(find.text('Propriétaire'), findsNWidgets(2));
    expect(find.byIcon(Icons.check), findsOneWidget);
    // No live Réseau offer → no add row.
    expect(find.text('Ajouter un salon'), findsNothing);
    await drain(tester);
  });

  testWidgets('tapping the other salon switches and pops with its id',
      (tester) async {
    final auth = await signInOwner(tester);
    await pumpPicker(tester, auth);

    await tester.runAsync(() async {
      await tester.tap(find.text('Beauté Divine'));
      // Poll until the switch lands (two sequential mock calls inside).
      for (var i = 0; i < 100 && auth.activeSalonId != 'provider2'; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(auth.activeSalonId, 'provider2');
    expect(auth.salonName, 'Beauté Divine');
    // The sheet closed.
    expect(find.text('Mes salons'), findsNothing);
    await drain(tester);
  });

  testWidgets('« Ajouter un salon » appears once the Réseau gate opens',
      (tester) async {
    final auth = await signInOwner(tester);
    await tester.runAsync(() async {
      final chosen = await serviceLocator.subscriptionService
          .chooseOffer('provider1', SalonTier.reseau);
      expect(chosen.success, isTrue);
      await auth.loadMySalons();
    });
    await pumpPicker(tester, auth);

    expect(find.text('Ajouter un salon'), findsOneWidget);
    await drain(tester);
  });
}
