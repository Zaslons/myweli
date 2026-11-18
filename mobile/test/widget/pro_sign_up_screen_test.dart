import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:myweli/core/constants/failure_messages.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/core/push/push_registration.dart';
import 'package:myweli/core/utils/validators.dart';
import 'package:myweli/models/provider.dart';
import 'package:myweli/models/provider_user.dart';
import 'package:myweli/services/mock/mock_auth_service.dart';
import 'package:myweli/services/mock/mock_data.dart';
import 'package:myweli/services/mock/mock_device_registration_service.dart';
import 'package:myweli/services/mock/mock_pro_service.dart';
import 'package:myweli/services/mock/mock_pro_team_service.dart';
import 'package:myweli/services/mock/mock_push_notification_service.dart';
import 'package:myweli/widgets/common/app_button.dart';
import 'package:myweli/widgets/common/app_chip.dart';
import 'package:myweli/widgets/common/phone_number_field.dart';
import 'package:myweli/widgets/team/revoked_access_banner.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/pro_sign_up.dart';
import '../support/rejoin.dart';

/// Android's sign-up screen (docs/design/pro-android-signup.md §2.4, §2.5,
/// §8.2 « Widget, the sign-up screen »), ported from the deleted
/// `pro_register_form_test` (A7: a fault answers under its field, the first
/// one focused, nothing sent) and grown to the new states: the sign-in check
/// first (S3, S4), the carried code (E3), and the lost answer (S12).
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

  var fresh = 0;
  String freshEmail() =>
      'nouveau$fresh@salon.test'.replaceFirst('$fresh', '${fresh++}');

  setUp(() async {
    MockData.resetTeam();
    MockData.providerUsers
      ..clear()
      ..addAll(seededAccounts);
    MockData.providers
      ..clear()
      ..addAll(seededSalons);
    mock.reset();
    // A no-account Google identity unless a test wants another.
    mock.proGoogleEmail = freshEmail();
    await mock.logoutProvider();
  });

  /// The whole form fits: every tap is a real one.
  void tall(WidgetTester tester) {
    tester.view.physicalSize = const Size(800, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  /// The sign-in, then its block's button (E1).
  Future<void> open(WidgetTester tester, {bool gate = false}) async {
    await tester.pumpWidget(h.app(gate: gate));
    await settle(tester);
    await tapOn(tester, find.text('Créer le compte de mon salon'));
    await settle(tester);
    expect(find.text('Créer mon compte'), findsWidgets);
  }

  /// The button, not the app bar's title of the same words.
  Finder createButton() => find.widgetWithText(AppButton, 'Créer mon compte');

  Finder phone() => find.descendant(
    of: find.byType(PhoneNumberField),
    matching: find.byType(TextField),
  );

  Future<void> fill(
    WidgetTester tester, {
    String name = 'Salon Awa',
    bool type = true,
    String number = '0707010101',
    String address = 'Rue des Jardins, Cocody',
  }) async {
    await tester.enterText(input('Nom de l’entreprise'), name);
    if (type) await tapOn(tester, find.text('Institut de manucure'));
    await tester.enterText(phone(), number);
    await tester.enterText(input('Adresse'), address);
    await tester.pump();
  }

  Future<void> google(WidgetTester tester) async {
    await tapOn(tester, find.text('Continuer avec Google'));
    await settle(tester);
  }

  /// The e-mail path from E1: a code, then « Créer mon compte ».
  Future<void> emailPath(WidgetTester tester, String email) async {
    await tester.enterText(input('Votre e-mail'), email);
    await tapOn(tester, find.text('Continuer avec e-mail'));
    await settle(tester);
    await tester.enterText(input('Code à 6 chiffres'), MockAuthService.demoOtp);
    await tapOn(tester, createButton());
    await settle(tester);
  }

  group('the salon\'s fields (A7, §14)', () {
    testWidgets('an empty form answers under each field, focuses the first, '
        'and opens no Google sheet', (tester) async {
      tall(tester);
      await open(tester);

      await google(tester);

      expect(find.text('Indiquez le nom de l’entreprise.'), findsOneWidget);
      expect(find.text('Choisissez le type d’entreprise.'), findsOneWidget);
      expect(find.text(Validators.phoneNumber('')!), findsOneWidget);
      expect(find.text('Indiquez l’adresse de l’entreprise.'), findsOneWidget);
      expect(mock.googleChecks, 0, reason: 'the sheet never opened');
      expect(find.byType(SnackBar), findsNothing, reason: '§14 rule 3');
      final focused = FocusManager.instance.primaryFocus?.context;
      expect(
        focused == null
            ? null
            : find
                  .descendant(
                    of: input('Nom de l’entreprise'),
                    matching: find.byWidget(focused.widget),
                  )
                  .evaluate()
                  .isNotEmpty,
        isTrue,
        reason: 'the name, first in reading order',
      );
    });

    testWidgets('the e-mail path checks the salon AND the e-mail before a '
        'code is sent', (tester) async {
      tall(tester);
      await open(tester);
      await tester.enterText(input('Votre e-mail'), 'pas-un-email');

      await tapOn(tester, find.text('Continuer avec e-mail'));
      await settle(tester);

      expect(find.text('Indiquez le nom de l’entreprise.'), findsOneWidget);
      expect(
        find.text(Validators.email('pas-un-email')!),
        findsOneWidget,
        reason: 'under the e-mail',
      );
      expect(mock.codeRequests, 0);
    });

    testWidgets('only the type missing, scrolled to the bottom: the chips '
        'are brought back into view', (tester) async {
      await open(tester); // the default phone-sized view
      await fill(tester, type: false);
      await tapOn(tester, find.text('Continuer avec Google'));
      await settle(tester);

      expect(find.text('Choisissez le type d’entreprise.'), findsOneWidget);
      final chip = tester.getRect(find.text('Salon de beauté'));
      final screen = tester.getRect(find.byType(Scaffold).last);
      expect(screen.contains(chip.center), isTrue, reason: 'scrolled to it');
      expect(mock.googleChecks, 0);
    });

    testWidgets('the name: 120 code points pass, 121 do not — an emoji '
        'sequence counts as the server counts it', (tester) async {
      tall(tester);
      await open(tester);
      // 💇🏾 is two code points: 60 of them are 120.
      await fill(tester, name: '💇🏾' * 60);
      await google(tester);
      expect(find.text('120 caractères au plus.'), findsNothing);
      expect(find.text('ACCUEIL'), findsOneWidget);
    });

    testWidgets('121 code points: the cap\'s sentence, nothing sent', (
      tester,
    ) async {
      tall(tester);
      await open(tester);
      await fill(tester, name: '${'💇🏾' * 60}a');
      await google(tester);
      expect(find.text('120 caractères au plus.'), findsOneWidget);
      expect(mock.googleChecks, 0);
    });

    testWidgets('no type is chosen for you', (tester) async {
      tall(tester);
      await open(tester);
      final chips = tester.widgetList<AppChip>(find.byType(AppChip));
      expect(chips, hasLength(6));
      expect(chips.where((c) => c.selected ?? false), isEmpty);
    });

    testWidgets('a fault clears on change once shown (rule 2)', (tester) async {
      tall(tester);
      await open(tester);
      await google(tester);
      await tester.enterText(input('Nom de l’entreprise'), 'Salon Awa');
      await tester.pump();
      expect(find.text('Indiquez le nom de l’entreprise.'), findsNothing);
    });

    testWidgets('the consent sentence, with both documents, above the first '
        'button that creates the account', (tester) async {
      tall(tester);
      await open(tester);
      expect(
        find.text('En créant votre compte professionnel, vous acceptez nos '),
        findsOneWidget,
      );
      expect(find.text('Conditions d’utilisation'), findsOneWidget);
      expect(find.text('Politique de confidentialité'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Conditions d’utilisation')).dy,
        lessThan(tester.getTopLeft(find.text('Continuer avec Google')).dy),
      );
    });
  });

  group('created (S2)', () {
    testWidgets('Google: the check, the account, « Accueil » — no snackbar '
        '(R5)', (tester) async {
      tall(tester);
      await open(tester);
      await fill(tester);
      await google(tester);
      expect(find.text('ACCUEIL'), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
      expect(h.auth.isAuthenticated, isTrue);
    });

    testWidgets('e-mail: a code, then « Créer mon compte »', (tester) async {
      tall(tester);
      await open(tester);
      await fill(tester);
      await emailPath(tester, freshEmail());
      expect(find.text('ACCUEIL'), findsOneWidget);
    });
  });

  testWidgets('an account exists: S3 in place of the form, Back acts as '
      '« Continuer »', (tester) async {
    tall(tester);
    mock.proGoogleEmail = 'jean@salon-excellence.test';
    await open(tester);
    await fill(tester);
    await google(tester);

    expect(find.textContaining('Le salon saisi n’a pas été créé.'), findsOne);
    expect(find.text('Nom de l’entreprise'), findsNothing);
    final salons = MockData.providers.length;

    await tester.binding.handlePopRoute();
    await settle(tester);

    expect(find.text('ACCUEIL'), findsOneWidget, reason: 'not the sign-in');
    expect(MockData.providers, hasLength(salons));
  });

  testWidgets('S3\'s « Continuer » lands where a sign-in lands', (
    tester,
  ) async {
    tall(tester);
    mock.proGoogleEmail = 'jean@salon-excellence.test';
    await open(tester);
    await fill(tester);
    await google(tester);
    await tapOn(tester, find.text('Continuer'));
    await settle(tester);
    expect(find.text('ACCUEIL'), findsOneWidget);
  });

  testWidgets('a former member with nothing pending: back on the sign-in, '
      'with the banner (S3b)', (tester) async {
    tall(tester);
    final email = freshEmail();
    bareRevokedAccount(email);
    mock.proGoogleEmail = email;
    await open(tester);
    await fill(tester);
    await google(tester);
    // The refresh, the invitations asked for, the re-check, the sign-out,
    // then the page leaving: longer than one settle.
    await settle(tester);
    expect(
      h.router.routerDelegate.currentConfiguration.matches.map(
        (m) => m.matchedLocation,
      ),
      ['/pro/login'],
      reason: 'the sign-up page is gone, not under the banner',
    );

    expect(find.byType(RevokedAccessBanner), findsOneWidget);
    expect(find.text('Créer mon compte'), findsNothing);
    expect(find.text('Pas encore de compte ?'), findsOneWidget);
  });

  group('invitations (S4)', () {
    Future<void> invited(WidgetTester tester) async {
      tall(tester);
      mock.proGoogleEmail = MockAuthService.mockProGoogleEmail;
      await open(tester);
      await fill(tester);
      await google(tester);
      expect(find.text('Vous êtes invité(e)'), findsOneWidget);
    }

    testWidgets('the cards in place of the form, the three choices', (
      tester,
    ) async {
      await invited(tester);
      expect(
        find.text(
          'Cette adresse a reçu une invitation. Rejoignez l’équipe, ou créez '
          'plutôt votre propre salon.',
        ),
        findsOneWidget,
      );
      expect(find.text('Rejoindre'), findsWidgets);
      expect(find.text('Refuser'), findsWidgets);
      expect(find.text('Créer plutôt mon propre salon'), findsOneWidget);
      expect(find.text('Nom de l’entreprise'), findsNothing);
      expect(mock.registers, 0, reason: 'nothing created');
    });

    testWidgets('« Rejoindre » accepts with the held proof and lands', (
      tester,
    ) async {
      tall(tester);
      await open(tester);
      await fill(tester);
      await emailPath(tester, 'invitee@myweli.test');
      expect(find.text('Vous êtes invité(e)'), findsOneWidget);

      await tapOn(tester, find.text('Rejoindre').first);
      await settle(tester);

      expect(find.text('Vous êtes invité(e)'), findsNothing);
      expect(h.auth.isAuthenticated, isTrue);
      expect(mock.registers, 0);
    });

    testWidgets('an accept refused: the sign-in\'s sentence under the cards', (
      tester,
    ) async {
      await invited(tester);
      mock.acceptRefusal = 'invitation_expired';
      await tapOn(tester, find.text('Rejoindre').first);
      await settle(tester);
      expect(find.text(sentenceFor('invitation_expired')), findsOneWidget);
      expect(find.text('Vous êtes invité(e)'), findsOneWidget);
    });

    testWidgets('« Refuser » the last card: the form back as it was, no '
        'message', (tester) async {
      await invited(tester);
      while (find.text('Refuser').evaluate().isNotEmpty) {
        await tapOn(tester, find.text('Refuser').first);
        await settle(tester);
      }
      expect(find.text('Vous êtes invité(e)'), findsNothing);
      expect(find.text('Salon Awa'), findsOneWidget, reason: 'fields kept');
      expect(find.text(kNoProAccountMessage), findsNothing);
    });

    testWidgets('« Créer plutôt mon propre salon »: the account with the held '
        'proof, « Accueil »', (tester) async {
      await invited(tester);
      final checks = mock.googleChecks;
      await tapOn(tester, find.text('Créer plutôt mon propre salon'));
      await settle(tester);
      expect(find.text('ACCUEIL'), findsOneWidget);
      expect(mock.googleChecks, checks, reason: 'no second check');
      expect(mock.registers, 1);
    });

    testWidgets('its refusal brings the form back with the fault; the '
        'corrected submit registers directly, without the check', (
      tester,
    ) async {
      await invited(tester);
      mock.registerRefusals.add('invalid_phone');
      await tapOn(tester, find.text('Créer plutôt mon propre salon'));
      await settle(tester);

      expect(find.text('Saisissez un numéro de téléphone valide.'), findsOne);
      expect(find.text('Vous êtes invité(e)'), findsNothing);
      final checks = mock.googleChecks;

      await tester.enterText(phone(), '0505050505');
      await google(tester);

      expect(find.text('ACCUEIL'), findsOneWidget);
      expect(mock.googleChecks, checks, reason: 'the choice is remembered');
      expect(mock.registers, 2);
    });

    testWidgets('Back drops what the check surfaced; the sign-in is fresh', (
      tester,
    ) async {
      await invited(tester);
      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(h.auth.hasPendingInvitations, isFalse);
      expect(find.text('Pas encore de compte ?'), findsOneWidget);
    });
  });

  group('refusals, each where it belongs', () {
    Future<void> refusedAtRegister(WidgetTester tester, String code) async {
      tall(tester);
      await open(tester);
      await fill(tester);
      mock.registerRefusals.add(code);
      await google(tester);
    }

    testWidgets('invalid_phone: under « Téléphone du salon » (S5)', (
      tester,
    ) async {
      await refusedAtRegister(tester, 'invalid_phone');
      expect(find.text('Saisissez un numéro de téléphone valide.'), findsOne);
      expect(find.text(sentenceFor('invalid_phone')), findsNothing);
    });

    testWidgets('invalid_area: under the commune (S6)', (tester) async {
      await refusedAtRegister(tester, 'invalid_area');
      expect(find.text('Choisissez une commune dans la liste.'), findsOne);
    });

    testWidgets('register\'s invalid_input: the salon, at form level (S7)', (
      tester,
    ) async {
      await refusedAtRegister(tester, 'invalid_input');
      expect(
        find.text('Vérifiez les informations du salon, puis réessayez.'),
        findsOneWidget,
      );
      expect(find.text('Code incorrect.'), findsNothing);
    });

    testWidgets('provider_exists: the sentence and « Se connecter », which '
        'returns to a fresh sign-in (S8)', (tester) async {
      await refusedAtRegister(tester, 'provider_exists');
      expect(
        find.text('Un compte existe déjà pour cette identité. Connectez-vous.'),
        findsOneWidget,
      );
      await tapOn(tester, find.text('Se connecter'));
      await settle(tester);
      expect(find.text('Pas encore de compte ?'), findsOneWidget);
    });

    testWidgets('a wrong code: under « Code à 6 chiffres » (S9)', (
      tester,
    ) async {
      tall(tester);
      await open(tester);
      await fill(tester);
      await tester.enterText(input('Votre e-mail'), freshEmail());
      await tapOn(tester, find.text('Continuer avec e-mail'));
      await settle(tester);
      await tester.enterText(input('Code à 6 chiffres'), '000000');
      await tapOn(tester, createButton());
      await settle(tester);
      expect(find.text('Code incorrect.'), findsOneWidget);
      expect(find.text('Renvoyer le code (60s)'), findsNothing);
      expect(find.textContaining('Renvoyer le code'), findsOneWidget);
    });

    testWidgets('a refused address: under « Votre e-mail »; the resend '
        'limit: at form level (S10)', (tester) async {
      tall(tester);
      await open(tester);
      await fill(tester);
      await tester.enterText(input('Votre e-mail'), freshEmail());
      mock.sendRefusal = 'invalid_email';
      await tapOn(tester, find.text('Continuer avec e-mail'));
      await settle(tester);
      expect(find.text('Saisissez une adresse e-mail valide.'), findsOne);

      mock.sendRefusal = 'otp_resend_limit';
      await tester.enterText(input('Votre e-mail'), freshEmail());
      await tapOn(tester, find.text('Continuer avec e-mail'));
      await settle(tester);
      expect(find.text(sentenceFor('otp_resend_limit')), findsOneWidget);
    });

    testWidgets('anything else keeps the sign-in\'s sentence (S11)', (
      tester,
    ) async {
      tall(tester);
      await open(tester);
      await fill(tester);
      mock.checkRefusal = 'token_rejected';
      await google(tester);
      expect(find.text('Connexion impossible. Réessayez.'), findsOneWidget);
    });

    testWidgets('no network: the sentence, the fields kept (S13)', (
      tester,
    ) async {
      tall(tester);
      await open(tester);
      await fill(tester);
      mock.checkRefusal = 'network';
      await google(tester);
      expect(find.text(kNoConnectionMessage), findsOneWidget);
      expect(find.text('Salon Awa'), findsOneWidget);
    });

    testWidgets('Google\'s sheet closed: nothing (S14)', (tester) async {
      tall(tester);
      await open(tester);
      await fill(tester);
      mock.checkRefusal = 'cancelled';
      await google(tester);
      expect(find.text(kGenericErrorMessage), findsNothing);
      expect(find.text('Salon Awa'), findsOneWidget);
      expect(find.text('ACCUEIL'), findsNothing);
    });
  });

  testWidgets('a lost answer, then a retry whose check says 200: « Accueil », '
      'not S3 — that salon exists (S12)', (tester) async {
    tall(tester);
    await open(tester);
    await fill(tester);
    mock.loseNextRegister = true;
    await google(tester);
    expect(find.text(kNoConnectionMessage), findsOneWidget);

    await google(tester);

    expect(find.text('ACCUEIL'), findsOneWidget);
    expect(
      find.textContaining('Le salon saisi n’a pas été créé.'),
      findsNothing,
    );
    expect(mock.registers, 1, reason: 'one account, made once');
  });

  testWidgets('Back is held while a request runs (S1)', (tester) async {
    tall(tester);
    await open(tester);
    await fill(tester);
    final hold = Completer<void>();
    mock.holdCheck = hold;
    await tapOn(tester, find.text('Continuer avec Google'));
    await tester.pump();

    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.text('Créer mon compte'), findsWidgets, reason: 'still here');

    hold.complete();
    await settle(tester);
    expect(find.text('ACCUEIL'), findsOneWidget);
  });

  testWidgets('/pro/register while signed in goes to « Accueil » (S15)', (
    tester,
  ) async {
    tall(tester);
    await tester.pumpWidget(h.app());
    await settle(tester);
    // The mock's latency runs on the test's clock: pump while it waits.
    final sent = h.auth.requestEmailOtp('jean@salon-excellence.test');
    await settle(tester);
    await sent;
    final signedIn = h.auth.verifyEmailOtp(
      'jean@salon-excellence.test',
      h.auth.emailDevCode!,
    );
    await settle(tester);
    expect(await signedIn, isTrue);

    unawaited(h.router.push('/pro/register'));
    await settle(tester);

    expect(find.text('ACCUEIL'), findsOneWidget);
    expect(find.text('Nom de l’entreprise'), findsNothing);
  });
}
