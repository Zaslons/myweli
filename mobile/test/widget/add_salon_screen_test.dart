import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/core/access/pro_salon_scope.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/core/push/push_registration.dart';
import 'package:myweli/providers/pro_auth_provider.dart';
import 'package:myweli/screens/provider/salons/add_salon_screen.dart';
import 'package:myweli/services/mock/mock_auth_service.dart';
import 'package:myweli/services/mock/mock_data.dart';
import 'package:myweli/services/mock/mock_device_registration_service.dart';
import 'package:myweli/services/mock/mock_pro_service.dart';
import 'package:myweli/services/mock/mock_push_notification_service.dart';
import 'package:myweli/services/mock/mock_subscription_service.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/pump_app.dart';
import '../support/settle.dart';
import '../support/sign_in.dart';

/// « Ajouter un salon » after the companion path
/// (docs/design/pro-companion-path.md §2.2): the intro no longer promises an
/// offer and a trial, and a refusal reads the shared neutral sentence — it
/// used to tell the salon to upgrade from « Mon abonnement » (mock) or read
/// « Une erreur est survenue. » (API). Both tests run on BOTH platforms — no
/// platform branch may exist (pro-companion-path §8), and `flutter test`
/// alone only ever renders Android.
void main() {
  final bothPlatforms = TargetPlatformVariant(const {
    TargetPlatform.android,
    TargetPlatform.iOS,
  });

  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    serviceLocator.authService = MockAuthService();
    serviceLocator.proService = MockProService();
    serviceLocator.subscriptionService = MockSubscriptionService();
    serviceLocator.proPushRegistration = PushRegistration(
      push: MockPushNotificationService(),
      devices: MockDeviceRegistrationService(),
    );
  });

  setUp(() {
    MockData.resetTeam();
    ProSalonScope.clear();
    (serviceLocator.subscriptionService as MockSubscriptionService)
        .resetForTests();
  });

  Future<void> pumpScreen(WidgetTester tester) async {
    final auth = await signInPro(tester);
    await tester.pumpWidget(
      wrapApp(
        providers: [ChangeNotifierProvider<ProAuthProvider>.value(value: auth)],
        home: const AddSalonScreen(),
      ),
    );
    await settleMocks(tester);
  }

  testWidgets('the intro states the new salon\'s own setup — no offer, no '
      'trial', (tester) async {
    await pumpScreen(tester);

    expect(
      find.text(
        'Le nouveau salon démarre en brouillon avec sa propre configuration : '
        'fiche, catalogue, équipe.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('période d’essai'), findsNothing);
  }, variant: bothPlatforms);

  testWidgets('a refusal (no live Réseau offer) reads the neutral sentence — '
      'no « Passez à l’offre Réseau »', (tester) async {
    await pumpScreen(tester);

    await tester.enterText(
      find.widgetWithText(TextField, 'Nom du salon'),
      'Salon Trois',
    );
    final submit = find.text('Créer le salon');
    // The form's own scroller — each TextField carries one too.
    await tester.scrollUntilVisible(
      submit,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(submit);
    await settleMocks(tester, rounds: 2);

    expect(
      find.text(
        'L’ajout de salons n’est pas disponible avec l’offre actuelle.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('Passez à'), findsNothing);
    expect(find.textContaining('Mon abonnement'), findsNothing);
  }, variant: bothPlatforms);
}
