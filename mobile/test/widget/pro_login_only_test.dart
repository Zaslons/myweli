import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:myweli/core/constants/failure_messages.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/core/utils/external_link.dart';
import 'package:myweli/providers/pro_auth_provider.dart';
import 'package:myweli/screens/provider/auth/pro_login_screen.dart';
import 'package:myweli/services/mock/mock_auth_service.dart';
import 'package:myweli/services/mock/mock_data.dart';
import 'package:myweli/services/mock/mock_pro_service.dart';
import 'package:myweli/widgets/common/app_text_field.dart';
import 'package:myweli/widgets/common/inline_feedback.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/dart_source.dart';
import '../support/pro_closure.dart';
import '../support/pump_app.dart';

/// docs/design/pro-app-login-only.md (B0.11) — Apple refused MyWeli Pro 0.0.1
/// under 3.1.1: « Remove the account registration features for business and
/// organizations ». The Pro app signs salons IN; it no longer signs them up
/// or creates salons. Sign-up and « Ajouter un salon » live on myweli.com.
/// Invitations stay.
///
/// docs/design/app-review-round-2.md — Apple refused build 698 too, for the
/// login's call to action « S'inscrire sur myweli.com ». The link is gone on
/// both platforms (the owner's call, one behaviour), and the screen points
/// nowhere: this file pins that, and `test/infra/pro_site_links_test.dart` pins
/// the links the Pro app has left.
void main() {
  /// Every Dart file under `lib/`, comments removed — the comments here and
  /// in the code quote the removed copy to explain it.
  Map<String, String> code() => {
    for (final f in Directory('lib').listSync(recursive: true))
      if (f is File && f.path.endsWith('.dart'))
        f.path: stripDartComments(f.readAsStringSync()),
  };

  group('nothing in the app signs a business up', () {
    test('the routes are gone', () {
      final router = code()['lib/core/router/pro_router.dart']!;
      expect(router, isNot(contains("'/pro/register'")));
      expect(router, isNot(contains("'/pro/salons/nouveau'")));
    });

    test('the two screens are gone, not just unrouted', () {
      expect(
        File('lib/screens/provider/auth/pro_register_screen.dart').existsSync(),
        isFalse,
      );
      expect(
        File('lib/screens/provider/salons/add_salon_screen.dart').existsSync(),
        isFalse,
      );
    });

    test('no code path registers an account or creates a salon', () {
      final calls = RegExp(
        r'\b(registerProviderWith(Google|Apple|Email)|'
        r'registerWith(Google|Apple|Email)|addSalon)\s*\(',
      );
      final found = <String>[
        for (final e in code().entries)
          if (calls.hasMatch(e.value)) e.key,
      ];
      expect(
        found,
        isEmpty,
        reason:
            'POST /auth/provider/register* and '
            'POST /me/salons are the web\'s alone',
      );
    });

    test('no copy offers to sign up or to add a salon', () {
      // `Créer un compte` is not in the list: the CONSUMER app registers its
      // clients, and that is not what Apple named.
      const removed = [
        'Inscription Pro',
        'S’inscrire avec',
        'Ajouter un salon',
        'Inscrivez-vous',
        'Créez votre compte',
      ];
      final hits = <String>[
        for (final e in code().entries)
          for (final phrase in removed)
            if (e.value.contains(phrase)) '${e.key}: « $phrase »',
      ];
      expect(hits, isEmpty);
    });

    test('the Pro surfaces never say « Créer un compte »', () {
      final hits = <String>[
        for (final e in code().entries)
          if ((e.key.contains('/screens/provider/') ||
                  e.key.contains('/widgets/provider/') ||
                  e.key.contains('/widgets/team/')) &&
              e.value.contains('Créer un compte'))
            e.key,
      ];
      expect(hits, isEmpty);
    });
  });

  group('the Pro sign-in holds no sign-up prompt', () {
    test('its words, its getter and its destination are nowhere in Pro', () {
      final closure = proClosure();
      expect(
        closure.keys,
        contains('lib/screens/provider/auth/pro_login_screen.dart'),
        reason: 'the scan no longer reaches the sign-in',
      );
      // asCopy puts every apostrophe in one spelling; `\u2019` is the one it
      // does not know, and a golden test here once wrote the phrase that way.
      const removed = [
        'S’inscrire',
        'Pas encore de compte',
        'proSignUpUrl',
        '/pro/inscription',
        'AuthSwitchPrompt',
      ];
      final hits = <String>[
        for (final e in closure.entries)
          for (final phrase in removed)
            if (asCopy(
              e.value,
            ).replaceAll(r'\u2019', "'").contains(asCopy(phrase)))
              '${e.key}: « $phrase »',
      ];
      expect(
        hits,
        isEmpty,
        reason:
            'Apple refused « S’inscrire sur myweli.com » on build 698: '
            'docs/design/app-review-round-2.md §4',
      );
    });

    test('the widget that carried it is gone, not just unused', () {
      expect(
        File('lib/widgets/common/auth_switch_prompt.dart').existsSync(),
        isFalse,
      );
    });
  });

  group('the login screen', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    const channel = MethodChannel('plugins.flutter.io/url_launcher');
    late List<Map<Object?, Object?>> launched;

    setUpAll(() async {
      await initializeDateFormatting('fr_FR', null);
      SharedPreferences.setMockInitialValues({});
      serviceLocator.authService = MockAuthService();
      serviceLocator.proService = MockProService();
    });

    setUp(() async {
      MockData.resetTeam();
      await serviceLocator.authService.logoutProvider();
      launched = [];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'launch') {
              launched.add(call.arguments as Map<Object?, Object?>);
            }
            return true;
          });
    });

    tearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );

    Widget app() => wrapApp(
      providers: [ChangeNotifierProvider(create: (_) => ProAuthProvider())],
      routerConfig: GoRouter(
        initialLocation: '/pro/login',
        routes: [
          GoRoute(
            path: '/pro/login',
            builder: (_, _) => const ProLoginScreen(),
          ),
          GoRoute(
            path: '/pro/dashboard',
            builder: (_, _) => const Scaffold(body: Text('DASHBOARD')),
          ),
        ],
      ),
    );

    Future<void> settle(WidgetTester tester) async {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
    }

    Finder input(String label) => find.descendant(
      of: find.byWidgetPredicate((w) => w is AppTextField && w.label == label),
      matching: find.byType(TextField),
    );

    /// docs/design/app-review-round-2.md §4.2, the exact offer of each step.
    /// « Continuer avec Apple » is iOS only, which is why this reads the
    /// platform and why the tests below run on both.
    List<String> optionsActions() => [
      'Continuer avec Google',
      if (defaultTargetPlatform == TargetPlatform.iOS) 'Continuer avec Apple',
      'Votre e-mail',
      'Continuer avec e-mail',
    ];
    const codeActions = [
      'Code à 6 chiffres',
      'Se connecter',
      'Changer d’e-mail',
    ];

    /// What can be acted on, as assistive technology reads the screen: every
    /// node with a tap, by its label. Not the known words of one link: a
    /// reworded link, an `InkWell` or a `TextSpan` recognizer is on this list
    /// too, which is why this and not `find.text`. Disabled controls have no
    /// tap (« Renvoyer le code » during its cooldown).
    List<String> actions() => [
      for (final node
          in find.semantics.byAction(SemanticsAction.tap).evaluate())
        node.label,
    ];

    /// What can be read, line by line: every paragraph on the screen, a
    /// `Text`, a `Text.rich` or a bare `RichText`, a field's label and hint
    /// included. docs/design/app-review-round-2.md §4.1: « No new copy on the
    /// login screen ». [actions] cannot see a sentence with no tap, and the word
    /// lists only know the words they name, so « Créez-le en ligne » passed both.
    /// An `Icon` is a paragraph too, of one glyph, so those are left out.
    ///
    /// Three values move, so they are generalised and the words around them are
    /// not: the resend countdown, the invitation's date, and the mock's salon
    /// and role.
    Set<String> sentences(WidgetTester tester) {
      final icons = find.descendant(
        of: find.byType(Icon),
        matching: find.byType(RichText),
      );
      final glyphs = tester.widgetList(icons).toSet();
      return {
        for (final paragraph in tester.widgetList<RichText>(
          find.byType(RichText),
        ))
          if (!glyphs.contains(paragraph))
            paragraph.text
                .toPlainText()
                .replaceFirst(RegExp(r'\(\d+s\)$'), '(Ns)')
                .replaceFirst(RegExp(r'^Expire le .+$'), 'Expire le {date}')
                .replaceFirst(
                  RegExp(r'^.+ vous invite comme .+$'),
                  '{salon} vous invite comme {rôle}',
                ),
      };
    }

    /// §4.1, each step's words. Only the mock sends « Code (dev) »: it is the
    /// server's `devCode`, which production never answers.
    Set<String> optionsSentences() => {
      'Espace Pro',
      'Connectez-vous à votre espace salon.',
      'Continuer avec Google',
      if (defaultTargetPlatform == TargetPlatform.iOS) 'Continuer avec Apple',
      'ou',
      'Votre e-mail',
      'exemple@email.com',
      'Continuer avec e-mail',
    };
    Set<String> codeSentences(String email, {required String count}) => {
      'Espace Pro',
      'Entrez le code reçu par e-mail à $email.',
      'Code à 6 chiffres',
      count,
      'Code (dev) : ${MockAuthService.demoOtp}',
      'Se connecter',
      'Renvoyer le code (Ns)',
      'Changer d’e-mail',
    };
    const invitationSentences = {
      'Espace Pro',
      'Vous êtes invité(e)',
      'Rejoignez l’équipe — aucun salon à créer.',
      '{salon} vous invite comme {rôle}',
      'Expire le {date}',
      'Rejoindre',
      'Refuser',
      'Retour',
    };

    Future<void> toCodeStep(WidgetTester tester, String email) async {
      await tester.pumpWidget(app());
      await settle(tester);
      await tester.enterText(input('Votre e-mail'), email);
      await tester.pump();
      // Below the fold of the test window once « Continuer avec Apple » is there.
      await tester.ensureVisible(find.text('Continuer avec e-mail'));
      await tester.pump();
      await tester.tap(find.text('Continuer avec e-mail'));
      await settle(tester);
    }

    Future<void> submitCode(WidgetTester tester) async {
      await tester.enterText(
        input('Code à 6 chiffres'),
        MockAuthService.demoOtp,
      );
      await tester.pump();
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      await tester.ensureVisible(find.text('Se connecter'));
      await tester.pump();
      await tester.tap(find.text('Se connecter'));
      await settle(tester);
    }

    /// The prompt's two halves, on any step — on top of the list of actions,
    /// because the question was not an action and must go as well.
    void expectNoPrompt() {
      expect(find.textContaining('compte ?'), findsNothing);
      expect(find.textContaining('inscrire'), findsNothing);
      expect(find.textContaining('myweli.com'), findsNothing);
    }

    /// On both platforms, because « Continuer avec Apple » is iOS only and
    /// `flutter test` is Android: without the variant the screen Apple reviews
    /// never renders here. Semantics on, because [actions] reads them.
    void testOnBoth(
      String description,
      Future<void> Function(WidgetTester tester) body,
    ) => testWidgets(
      description,
      (tester) async {
        final semantics = tester.ensureSemantics();
        try {
          await body(tester);
        } finally {
          semantics.dispose();
        }
      },
      variant: const TargetPlatformVariant({
        TargetPlatform.android,
        TargetPlatform.iOS,
      }),
    );

    testOnBoth('the options step offers signing in, and nothing else', (
      tester,
    ) async {
      await tester.pumpWidget(app());
      await settle(tester);

      expect(actions(), unorderedEquals(optionsActions()));
      expect(sentences(tester), optionsSentences());
      expectNoPrompt();
      expect(launched, isEmpty);
    });

    testOnBoth('the code step offers the code, and nothing else', (
      tester,
    ) async {
      await toCodeStep(tester, 'inconnu@salon.test');

      expect(find.text('Se connecter'), findsOneWidget);
      expect(actions(), unorderedEquals(codeActions));
      expect(
        sentences(tester),
        codeSentences('inconnu@salon.test', count: '0/6'),
      );
      expectNoPrompt();
      expect(launched, isEmpty);
    });

    testOnBoth('the invitations step offers the invitation, and nothing else', (
      tester,
    ) async {
      await toCodeStep(tester, 'invitee@myweli.test');
      await submitCode(tester);

      expect(find.text('Vous êtes invité(e)'), findsOneWidget);
      expect(actions(), unorderedEquals(['Rejoindre', 'Refuser', 'Retour']));
      expect(sentences(tester), invitationSentences);
      expectNoPrompt();
      expect(launched, isEmpty);
    });

    testOnBoth('« Refuser » on the last invitation: the sentence, the options, '
        'no button of its own, nothing opened', (tester) async {
      await toCodeStep(tester, 'invitee@myweli.test');
      await submitCode(tester);
      await tester.tap(find.text('Refuser'));
      await settle(tester);

      expect(find.text(kNoProAccountMessage), findsOneWidget);
      expect(actions(), unorderedEquals(optionsActions()));
      expect(sentences(tester), {...optionsSentences(), kNoProAccountMessage});
      expectNoPrompt();
      expect(launched, isEmpty);
    });

    // The oracle for every `launched` above: on a fake that heard nothing,
    // « nothing was opened » would be true of any screen.
    testWidgets('control: the fake browser does hear a real link', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrapApp(
          routerConfig: GoRouter(
            routes: [
              GoRoute(
                path: '/',
                builder: (context, _) => Scaffold(
                  body: TextButton(
                    onPressed: () =>
                        openExternalUrl(context, 'https://example.test/'),
                    child: const Text('OUVRIR'),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
      await settle(tester);
      await tester.tap(find.text('OUVRIR'));
      await settle(tester);

      expect(launched, hasLength(1));
      expect(launched.single['url'], 'https://example.test/');
    });

    testOnBoth('a sign-in with no account says so, with the invitation hint, '
        'offers no button of its own and opens nothing', (tester) async {
      await toCodeStep(tester, 'inconnu@salon.test');
      await submitCode(tester);

      final sentence = find.descendant(
        of: find.byType(InlineFeedback),
        matching: find.text(
          'Aucun compte MyWeli Pro n’est associé à cette adresse. Si votre '
          'salon vous a invité, connectez-vous avec l’adresse qui a reçu '
          'l’invitation.',
        ),
      );
      expect(sentence, findsOneWidget);
      expect(find.text('Créer un compte'), findsNothing);
      expectNoPrompt();
      // The same actions as before the refusal: the sentence brought none.
      expect(actions(), unorderedEquals(codeActions));
      expect(sentences(tester), {
        ...codeSentences('inconnu@salon.test', count: '6/6'),
        kNoProAccountMessage,
      });

      // Reading it is all it does.
      await tester.ensureVisible(sentence);
      await tester.pump();
      await tester.tap(sentence);
      await settle(tester);
      expect(launched, isEmpty);
      expect(find.byType(ProLoginScreen), findsOneWidget);
    });
  });
}
