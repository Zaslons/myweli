import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:myweli/core/constants/failure_messages.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/core/push/push_registration.dart';
import 'package:myweli/models/provider.dart';
import 'package:myweli/models/provider_user.dart';
import 'package:myweli/services/mock/mock_auth_service.dart';
import 'package:myweli/services/mock/mock_data.dart';
import 'package:myweli/services/mock/mock_device_registration_service.dart';
import 'package:myweli/services/mock/mock_pro_service.dart';
import 'package:myweli/services/mock/mock_pro_team_service.dart';
import 'package:myweli/services/mock/mock_push_notification_service.dart';
import 'package:myweli/widgets/common/app_button.dart';
import 'package:myweli/widgets/common/inline_feedback.dart';
import 'package:myweli/widgets/common/phone_number_field.dart';
import 'package:myweli/widgets/provider/pro_salon_gate.dart';
import 'package:myweli/widgets/team/revoked_access_banner.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/pro_sign_up.dart';
import '../support/rejoin.dart';

/// The Android sign-in: its block, what it carries into the sign-up, and how
/// it looks when the sign-up comes back (docs/design/pro-android-signup.md
/// §2.2, §8.1 P4, P7's twin, P16). The iOS sign-in — no block — stays held by
/// `pro_login_only_test`, `pro_login_invitations_test` and the
/// `pro_login_w360_x2` golden.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final mock = ScriptedSignUpAuth();
  final h = SignUpHarness();
  late final List<ProviderUser> seededAccounts;
  late final List<Provider> seededSalons;

  setUpAll(() async {
    await initializeDateFormatting('fr_FR', null);
    SharedPreferences.setMockInitialValues({});
    seededAccounts = List.of(MockData.providerUsers);
    seededSalons = List.of(MockData.providers);
    serviceLocator
      ..authService = mock
      ..proService = MockProService()
      ..proTeamService = MockProTeamService()
      ..proPushRegistration = PushRegistration(
        push: MockPushNotificationService(),
        devices: MockDeviceRegistrationService(),
      );
  });

  var n = 0;
  String freshEmail() => 'android${n++}@salon.test';

  setUp(() async {
    MockData.resetTeam();
    MockData.providerUsers
      ..clear()
      ..addAll(seededAccounts);
    MockData.providers
      ..clear()
      ..addAll(seededSalons);
    mock.reset();
    mock.proGoogleEmail = freshEmail();
    await mock.logoutProvider();
  });

  void tall(WidgetTester tester) {
    tester.view.physicalSize = const Size(800, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  Future<void> start(WidgetTester tester, {bool gate = false}) async {
    await tester.pumpWidget(h.app(gate: gate));
    await settle(tester);
  }

  Finder sentence(String text) => find.descendant(
    of: find.byType(InlineFeedback),
    matching: find.text(text),
  );

  Finder phone() => find.descendant(
    of: find.byType(PhoneNumberField),
    matching: find.byType(TextField),
  );

  Finder createButton() => find.widgetWithText(AppButton, 'Créer mon compte');

  Future<void> fill(WidgetTester tester) async {
    await tester.enterText(input('Nom de l’entreprise'), 'Salon Awa');
    await tapOn(tester, find.text('Barbier'));
    await tester.enterText(phone(), '0707010101');
    await tester.enterText(input('Adresse'), 'Rue des Jardins');
    await tester.pump();
  }

  /// The sign-in's code step, its verify refused as provider_not_found (E3).
  Future<void> codeRefused(WidgetTester tester, String email) async {
    await tester.enterText(input('Votre e-mail'), email);
    await tapOn(tester, find.text('Continuer avec e-mail'));
    await settle(tester);
    await tester.enterText(input('Code à 6 chiffres'), MockAuthService.demoOtp);
    await tapOn(tester, find.text('Se connecter'));
    await settle(tester);
  }

  Future<void> openSignUp(WidgetTester tester) async {
    await tapOn(tester, find.text('Créer le compte de mon salon'));
    await settle(tester);
  }

  testWidgets('E1: « Pas encore de compte ? » and the button, an info live '
      'region', (tester) async {
    tall(tester);
    await start(tester);
    expect(sentence('Pas encore de compte ?'), findsOneWidget);
    final feedback = tester.widget<InlineFeedback>(
      find.ancestor(
        of: find.text('Pas encore de compte ?'),
        matching: find.byType(InlineFeedback),
      ),
    );
    expect(feedback.kind.name, 'info');
    expect(find.text('Créer le compte de mon salon'), findsOneWidget);
  });

  testWidgets('E2: after Google\'s provider_not_found, the sentence ONCE, as '
      'information, brought into view at 200% text', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await start(tester);

    await tapOn(tester, find.text('Continuer avec Google'));
    await settle(tester);

    expect(h.auth.errorCode, 'provider_not_found', reason: 'the premise');
    expect(find.text(kNoProAccountMessage), findsOneWidget, reason: 'once');
    expect(sentence(kNoProAccountMessage), findsOneWidget);
    // At 360dp × 200% the sentence alone is taller than the screen: it is
    // brought to the top, where it starts in view (TalkBack reads it whole —
    // a live region).
    final rect = tester.getRect(find.text(kNoProAccountMessage));
    final bar = tester.getRect(find.byType(AppBar));
    expect(rect.top, greaterThanOrEqualTo(bar.bottom));
    expect(rect.top, lessThan(640 / 2), reason: 'scrolled into view');
  });

  testWidgets('E3: the pair the refused verify used crosses into the sign-up, '
      'even after the field was edited', (tester) async {
    tall(tester);
    await start(tester);
    final email = freshEmail();
    await codeRefused(tester, email);
    expect(sentence(kNoProAccountMessage), findsOneWidget);
    await tester.enterText(input('Code à 6 chiffres'), '999999');
    await tester.pump();
    final requests = mock.codeRequests;

    await openSignUp(tester);
    expect(find.text('Compte : $email'), findsOneWidget);
    await fill(tester);
    await tapOn(tester, createButton());
    await settle(tester);

    expect(mock.lastEmailSignUp, (email, MockAuthService.demoOtp));
    expect(mock.codeRequests, requests, reason: 'no second e-mail');
    expect(find.text('ACCUEIL'), findsOneWidget);
  });

  testWidgets('E3, the carried code no longer valid: the e-mail path, the '
      'address filled in, the sentence', (tester) async {
    tall(tester);
    await start(tester);
    final email = freshEmail();
    await codeRefused(tester, email);
    await openSignUp(tester);
    await fill(tester);
    mock.checkRefusal = 'otp_expired';

    await tapOn(tester, createButton());
    await settle(tester);

    expect(find.text('Compte : $email'), findsNothing);
    expect(find.text(email), findsOneWidget, reason: 'the address kept');
    expect(find.text('Continuer avec e-mail'), findsOneWidget);
    expect(
      find.text('Ce code n’est plus valable. Recevez-en un nouveau.'),
      findsOneWidget,
    );
  });

  testWidgets('« Utiliser une autre adresse » opens the standard section', (
    tester,
  ) async {
    tall(tester);
    await start(tester);
    await codeRefused(tester, freshEmail());
    await openSignUp(tester);
    await tapOn(tester, find.text('Utiliser une autre adresse'));
    await tester.pump();
    expect(find.text('Continuer avec Google'), findsOneWidget);
    expect(find.text('Continuer avec e-mail'), findsOneWidget);
    expect(find.textContaining('Compte :'), findsNothing);
  });

  testWidgets('P7\'s twin: « Refuser » on the last card ends on E2 — the '
      'sentence in the block, and the way to create the account', (
    tester,
  ) async {
    tall(tester);
    mock.proGoogleEmail = MockAuthService.mockProGoogleEmail;
    await start(tester);
    await tapOn(tester, find.text('Continuer avec Google'));
    await settle(tester);
    expect(find.text('Vous êtes invité(e)'), findsOneWidget);
    expect(
      find.text('Créer le compte de mon salon'),
      findsNothing,
      reason: 'never on « Invitations »',
    );

    while (find.text('Refuser').evaluate().isNotEmpty) {
      await tapOn(tester, find.text('Refuser').first);
      await settle(tester);
    }

    expect(find.text(kNoProAccountMessage), findsOneWidget);
    expect(sentence(kNoProAccountMessage), findsOneWidget);
    expect(find.text('Créer le compte de mon salon'), findsOneWidget);
  });

  testWidgets('back from the sign-up after a failure: the sign-in fresh (E1)', (
    tester,
  ) async {
    tall(tester);
    await start(tester);
    await tapOn(tester, find.text('Continuer avec Google'));
    await settle(tester);
    expect(sentence(kNoProAccountMessage), findsOneWidget, reason: 'E2');
    await openSignUp(tester);
    await fill(tester);
    mock.checkRefusal = 'network';
    await tapOn(tester, find.text('Continuer avec Google'));
    await settle(tester);

    await tester.binding.handlePopRoute();
    await settle(tester);

    expect(sentence('Pas encore de compte ?'), findsOneWidget);
    expect(find.text(kNoProAccountMessage), findsNothing);
    expect(h.auth.errorCode, isNull);
  });

  testWidgets('after a sign-up and a sign-out: E1, not E2', (tester) async {
    tall(tester);
    await start(tester);
    await tapOn(tester, find.text('Continuer avec Google'));
    await settle(tester);
    await openSignUp(tester);
    await fill(tester);
    await tapOn(tester, find.text('Continuer avec Google'));
    await settle(tester);
    expect(find.text('ACCUEIL'), findsOneWidget);

    final out = h.auth.logout();
    await settle(tester);
    await out;
    h.router.go('/pro/login');
    await settle(tester);

    expect(sentence('Pas encore de compte ?'), findsOneWidget);
    expect(find.text(kNoProAccountMessage), findsNothing);
  });

  testWidgets('S3b from E3: back on the sign-in\'s options step, with the '
      'banner', (tester) async {
    tall(tester);
    await start(tester);
    final email = freshEmail();
    await codeRefused(tester, email);
    // Meanwhile, that address became a former member's.
    bareRevokedAccount(email);
    await openSignUp(tester);
    await fill(tester);

    await tapOn(tester, createButton());
    await settle(tester);
    await settle(tester);

    expect(find.byType(RevokedAccessBanner), findsOneWidget);
    expect(
      find.text('Continuer avec e-mail'),
      findsOneWidget,
      reason: 'options',
    );
    expect(find.text('Code à 6 chiffres'), findsNothing);
    expect(h.auth.isAuthenticated, isFalse);
  });

  testWidgets('P16: the sign-up is pushed, so the salon gate reads the '
      'sign-in and keeps the form while the new salon loads', (tester) async {
    tall(tester);
    await start(tester, gate: true);
    await openSignUp(tester);
    await fill(tester);

    await tapOn(tester, find.text('Continuer avec Google'));
    var sawGate = false;
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      if (find.byType(ProSalonUnavailableScreen).evaluate().isNotEmpty) {
        sawGate = true;
      }
      if (find.text('ACCUEIL').evaluate().isNotEmpty) break;
      expect(
        find.text('Nom de l’entreprise'),
        findsOneWidget,
        reason: 'the form stays until « Accueil »',
      );
    }
    await settle(tester);

    expect(sawGate, isFalse);
    expect(find.text('ACCUEIL'), findsOneWidget);
  });
}
