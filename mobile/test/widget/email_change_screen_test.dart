import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:myweli/core/constants/failure_messages.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/models/api_response.dart';
import 'package:myweli/models/email_change_request.dart';
import 'package:myweli/models/user.dart';
import 'package:myweli/providers/auth_provider.dart';
import 'package:myweli/screens/profile/edit_profile_screen.dart';
import 'package:myweli/screens/profile/email_change_screen.dart';
import 'package:myweli/services/mock/mock_auth_service.dart';
import 'package:myweli/services/mock/mock_data.dart';
import 'package:myweli/widgets/common/app_text_field.dart';
import 'package:myweli/widgets/common/inline_feedback.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/pump_app.dart';
import '../support/secure_storage.dart';

/// « Changer d’adresse e-mail » (B16.3b — docs/design/account-email-change.md
/// §5.4, decisions 260–265), from « Modifier le profil », on the mock — which
/// answers as the server B16.3a deployed (`mock_email_change_test.dart`). Every
/// state §5.4 lists: each refusal under its field or in the form's slot, the
/// focus on the first fault, the second code of decision 265, « taken » and
/// its way on, back, « Vérifier », 200 % text, 48 px.
void main() {
  // `authService` is a `late final` — one spy for the file; it IS the mock
  // unless a test arms it.
  final spy = _Spy();
  const code = MockAuthService.demoOtp;
  var n = 0;
  String address(String who) => '$who.${n++}@exemple.ci';

  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    stubSecureStorage();
    serviceLocator.authService = spy;
  });

  tearDown(spy.disarm);

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
  }

  /// Signs in on the mock, then opens « Modifier le profil » over a stand-in
  /// « Profil ». [by]: an e-mail code (a proven address that is the account's
  /// only way in), Google (a proven address and a link), or a planted
  /// account signed in by its phone (no address, or an unproven one).
  Future<AuthProvider> openProfile(
    WidgetTester tester, {
    required Future<void> Function() by,
  }) async {
    late final AuthProvider auth;
    await tester.runAsync(() async {
      await by();
      auth = AuthProvider();
      for (var i = 0; i < 60 && auth.isLoading; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    });
    expect(auth.isAuthenticated, isTrue);
    final router = GoRouter(
      initialLocation: '/profile',
      routes: [
        GoRoute(
          path: '/profile',
          builder: (context, _) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => context.push('/profile/edit'),
                child: const Text('PROFIL'),
              ),
            ),
          ),
          routes: [
            GoRoute(
              path: 'edit',
              builder: (_, _) => const EditProfileScreen(),
              routes: [
                GoRoute(
                  path: 'email',
                  builder: (_, state) => EmailChangeScreen(
                    verifyCurrent: state.uri.queryParameters['verifier'] == '1',
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    );
    await tester.pumpWidget(
      wrapApp(
        providers: [ChangeNotifierProvider<AuthProvider>.value(value: auth)],
        routerConfig: router,
      ),
    );
    await settle(tester);
    await tester.tap(find.text('PROFIL'));
    await settle(tester);
    return auth;
  }

  Future<void> Function() byCode(String email) => () async {
    await spy.requestEmailOtp(email);
    expect((await spy.verifyEmailOtp(email, code)).success, isTrue);
  };

  Future<void> byGoogle() async {
    expect((await spy.signInWithGoogle()).success, isTrue);
  }

  /// An account the mock signs in by its phone: [email] unproven, or none.
  Future<void> Function() planted({String? email}) => () async {
    final phone = '+22507071${(n++).toString().padLeft(5, '0')}';
    MockData.users.add(
      User(
        id: 'planted_${n++}',
        phoneNumber: phone,
        email: email,
        authProvider: 'google',
        createdAt: DateTime(2026),
      ),
    );
    await spy.sendOtp(phone);
    expect((await spy.verifyOtp(phone, code)).success, isTrue);
  };

  Finder field(String label) => find.descendant(
    of: find.widgetWithText(AppTextField, label),
    matching: find.byType(TextField),
  );

  Finder under(String label, String message) => find.descendant(
    of: find.widgetWithText(AppTextField, label),
    matching: find.text(message),
  );

  Finder inForm(String message) => find.descendant(
    of: find.byType(InlineFeedback),
    matching: find.text(message),
  );

  bool focused(String label) => find
      .descendant(
        of: find.widgetWithText(AppTextField, label),
        matching: find.byType(EditableText),
      )
      .evaluate()
      .map((e) => (e.widget as EditableText).focusNode.hasFocus)
      .single;

  Future<void> tapText(WidgetTester tester, String text) async {
    await tester.ensureVisible(find.text(text).last);
    await tester.tap(find.text(text).last);
    await settle(tester);
  }

  Future<void> openChange(WidgetTester tester) async {
    await tapText(tester, 'Modifier');
    expect(find.text('Nouvelle adresse e-mail'), findsOneWidget);
  }

  Future<void> requestFor(WidgetTester tester, String email) async {
    await tester.enterText(field('Nouvelle adresse e-mail'), email);
    await tester.pump();
    await tapText(tester, 'Recevoir un code');
  }

  const newCode = 'Code de la nouvelle adresse';
  const currentCode = 'Code de l’adresse actuelle';
  const oneCode = 'Code à 6 chiffres';
  const oldLine =
      'Vous ne pourrez plus vous connecter par code avec votre ancienne '
      'adresse.';

  testWidgets(
    'an e-mail-code account: both codes, then the row shows the new address',
    (tester) async {
      final old = address('awa');
      final next = address('awa.new');
      await openProfile(tester, by: byCode(old));
      await openChange(tester);
      expect(find.text(oldLine), findsOneWidget);

      await requestFor(tester, next);

      expect(
        find.text('Entrez le code reçu par e-mail à $next.'),
        findsOneWidget,
      );
      expect(
        find.text('Entrez le code reçu à votre adresse actuelle, $old.'),
        findsOneWidget,
        reason: 'decision 265: the address is the account\'s only way in',
      );
      expect(find.text('Renvoyer le code (60s)'), findsOneWidget);

      await tester.enterText(field(newCode), code);
      await tester.enterText(field(currentCode), code);
      await tester.pump();
      await tapText(tester, 'Confirmer');

      expect(find.text('Modifier le profil'), findsOneWidget);
      expect(find.text(next), findsOneWidget);
      expect(
        find.text(
          'Adresse e-mail mise à jour. Connectez-vous désormais avec '
          'celle-ci.',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets('not an address: under the field, focused, nothing sent', (
    tester,
  ) async {
    await openProfile(tester, by: byGoogle);
    await openChange(tester);
    expect(
      tester.widget<TextField>(field('Nouvelle adresse e-mail')).autofillHints,
      [AutofillHints.email],
      reason: 'the keyboard may suggest the person\'s own address (§5.4)',
    );

    await requestFor(tester, 'awa@');

    expect(
      under('Nouvelle adresse e-mail', 'Saisissez une adresse e-mail valide.'),
      findsOneWidget,
    );
    expect(focused('Nouvelle adresse e-mail'), isTrue);
    expect(spy.requests, isEmpty);
  });

  testWidgets('its own proven address: « C’est déjà votre adresse. »', (
    tester,
  ) async {
    final own = address('awa');
    await openProfile(tester, by: byCode(own));
    await openChange(tester);

    await requestFor(tester, own);

    expect(
      under('Nouvelle adresse e-mail', 'C’est déjà votre adresse.'),
      findsOneWidget,
    );
    expect(focused('Nouvelle adresse e-mail'), isTrue);
    expect(find.text('Confirmer'), findsNothing);
  });

  for (final limit in ['otp_resend_limit', 'rate_limited']) {
    testWidgets('`$limit`: under the button, the address kept', (tester) async {
      await openProfile(tester, by: byGoogle);
      await openChange(tester);
      spy.refuseRequestWith = ApiResponse.error('…', code: limit);

      await requestFor(tester, 'n@exemple.ci');

      expect(
        inForm('Trop de demandes de code. Réessayez plus tard.'),
        findsOneWidget,
      );
      expect(
        tester.getTopLeft(find.byType(InlineFeedback)).dy,
        greaterThan(tester.getTopLeft(find.text('Recevoir un code')).dy),
      );
      expect(find.text('n@exemple.ci'), findsOneWidget);
    });
  }

  testWidgets('no connection: the form says so, what was typed is kept', (
    tester,
  ) async {
    await openProfile(tester, by: byGoogle);
    await openChange(tester);
    spy.refuseRequestWith = ApiResponse.error(
      kNoConnectionMessage,
      code: 'network',
    );

    await requestFor(tester, 'n@exemple.ci');

    expect(inForm(kNoConnectionMessage), findsOneWidget);
    expect(find.text('n@exemple.ci'), findsOneWidget);
    expect(find.text('Recevoir un code'), findsOneWidget);
  });

  testWidgets('a Google account: one code; a wrong one under it, focused', (
    tester,
  ) async {
    await openProfile(tester, by: byGoogle);
    await openChange(tester);
    expect(find.text(oldLine), findsOneWidget);
    await requestFor(tester, address('g'));

    expect(field(currentCode), findsNothing);
    await tester.enterText(field(oneCode), '000000');
    await tester.pump();
    await tapText(tester, 'Confirmer');

    expect(under(oneCode, 'Code incorrect.'), findsOneWidget);
    expect(focused(oneCode), isTrue);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('the current address\'s refusal goes under ITS field', (
    tester,
  ) async {
    await openProfile(tester, by: byCode(address('awa')));
    await openChange(tester);
    await requestFor(tester, address('awa.new'));

    await tester.enterText(field(newCode), code);
    await tester.enterText(field(currentCode), '000000');
    await tester.pump();
    await tapText(tester, 'Confirmer');

    expect(under(currentCode, 'Code incorrect.'), findsOneWidget);
    expect(under(newCode, 'Code incorrect.'), findsNothing);
    expect(focused(currentCode), isTrue);
  });

  testWidgets('an empty second code is the field\'s fault, nothing sent', (
    tester,
  ) async {
    await openProfile(tester, by: byCode(address('awa')));
    await openChange(tester);
    await requestFor(tester, address('awa.new'));

    await tester.enterText(field(newCode), code);
    await tester.pump();
    await tapText(tester, 'Confirmer');

    expect(under(currentCode, 'Saisissez le code reçu.'), findsOneWidget);
    expect(spy.confirms, isEmpty);
  });

  testWidgets(
    'taken: the sentence in the form, then « Choisir une autre adresse »',
    (tester) async {
      final taken = address('owner');
      MockData.users.add(
        User(
          id: 'owner_${n++}',
          email: taken,
          emailVerified: true,
          authProvider: 'email',
          createdAt: DateTime(2026),
        ),
      );
      await openProfile(tester, by: byGoogle);
      await openChange(tester);
      await requestFor(tester, taken);
      await tester.enterText(field(oneCode), code);
      await tester.pump();
      await tapText(tester, 'Confirmer');

      expect(inForm(kEmailTakenMessage), findsOneWidget);
      expect(under(oneCode, kEmailTakenMessage), findsNothing);

      await tapText(tester, 'Choisir une autre adresse');

      expect(find.text('Recevoir un code'), findsOneWidget);
      expect(
        tester
            .widget<TextField>(field('Nouvelle adresse e-mail'))
            .controller!
            .text,
        isEmpty,
      );
      expect(find.text(kEmailTakenMessage), findsNothing);
      expect(focused('Nouvelle adresse e-mail'), isTrue);
    },
  );

  testWidgets('« Changer d’e-mail » and back: the address step, kept', (
    tester,
  ) async {
    await openProfile(tester, by: byGoogle);
    await openChange(tester);
    final next = address('g');
    await requestFor(tester, next);

    await tapText(tester, 'Changer d’e-mail');
    expect(find.text('Recevoir un code'), findsOneWidget);
    expect(find.text(next), findsOneWidget);

    await tapText(tester, 'Recevoir un code');
    expect(find.text('Confirmer'), findsOneWidget);
    // The app bar's arrow (`pageBack` looks for an English « Back »).
    await tester.tap(find.byType(BackButton));
    await settle(tester);
    expect(
      find.text('Recevoir un code'),
      findsOneWidget,
      reason: 'back on the code step returns to the address, not the profile',
    );
    expect(find.text(next), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await settle(tester);
    expect(find.text('Modifier le profil'), findsOneWidget);
  });

  testWidgets('the resend opens after its 60 seconds, and sends again', (
    tester,
  ) async {
    await openProfile(tester, by: byGoogle);
    await openChange(tester);
    await requestFor(tester, address('g'));
    expect(spy.requests, hasLength(1));

    await tester.pump(const Duration(seconds: 61));
    expect(find.text('Renvoyer le code'), findsOneWidget);
    await tapText(tester, 'Renvoyer le code');

    expect(spy.requests, hasLength(2));
    expect(find.text('Renvoyer le code (60s)'), findsOneWidget);
  });

  testWidgets(
    '« Vérifier »: straight to the code, and « vérifiée » once proven',
    (tester) async {
      final typed = address('typed');
      await openProfile(tester, by: planted(email: typed));
      expect(find.text('Non vérifiée'), findsOneWidget);

      await tapText(tester, 'Vérifier');

      expect(spy.requests, [typed]);
      expect(
        find.text('Entrez le code reçu par e-mail à $typed.'),
        findsOneWidget,
      );
      expect(find.text(oldLine), findsNothing);
      await tester.enterText(field(oneCode), code);
      await tester.pump();
      await tapText(tester, 'Confirmer');

      expect(find.text('Adresse e-mail vérifiée.'), findsOneWidget);
      expect(find.text('Non vérifiée'), findsNothing);
      expect(
        find.text(
          'Vous pouvez aussi vous connecter avec un code envoyé à cette '
          'adresse.',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets('no address: no « ancienne adresse » to lose', (tester) async {
    await openProfile(tester, by: planted());
    expect(find.text('Aucune adresse'), findsOneWidget);
    await openChange(tester);
    expect(find.text(oldLine), findsNothing);
  });

  testWidgets('the row reads as one node: what, which, and « Modifier »', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final own = address('awa');
    await openProfile(tester, by: byCode(own));

    // What assistive tech receives: the MERGED data, not the node's own
    // label from before the merge.
    final data = tester.getSemantics(find.text('Modifier')).getSemanticsData();
    expect(data.label, 'Adresse e-mail\n$own\nModifier');
    expect(data.hasAction(SemanticsAction.tap), isTrue);
    expect(data.flagsCollection.isButton, isTrue);
    handle.dispose();
  });

  testWidgets('every target is at least 48 px', (tester) async {
    final handle = tester.ensureSemantics();
    await openProfile(tester, by: planted(email: address('typed')));
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await openChange(tester);
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    handle.dispose();
  });

  testWidgets('at 200 % text on 360 dp, « Confirmer » stays reachable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await openProfile(tester, by: byCode(address('awa.long.adresse')));
    await openChange(tester);
    await requestFor(tester, address('une.adresse.assez.longue'));
    await tester.enterText(field(newCode), code);
    await tester.enterText(field(currentCode), code);
    await tester.pump();
    await tapText(tester, 'Confirmer');

    expect(tester.takeException(), isNull);
    expect(find.text('Modifier le profil'), findsOneWidget);
  });
}

/// The mock, recording each request — and refusing one when armed, the way
/// the server and the network do.
class _Spy extends MockAuthService {
  ApiResponse<EmailChangeRequest>? refuseRequestWith;
  final requests = <String>[];
  final confirms = <String>[];

  void disarm() {
    refuseRequestWith = null;
    requests.clear();
    confirms.clear();
  }

  @override
  Future<ApiResponse<EmailChangeRequest>> requestEmailChange(
    String email,
  ) async {
    requests.add(email);
    final refusal = refuseRequestWith;
    if (refusal != null) {
      await Future<void>.delayed(const Duration(milliseconds: 300));
      return refusal;
    }
    return super.requestEmailChange(email);
  }

  @override
  Future<ApiResponse<User>> confirmEmailChange(
    String email,
    String code, {
    String? currentCode,
  }) {
    confirms.add(email);
    return super.confirmEmailChange(email, code, currentCode: currentCode);
  }
}
