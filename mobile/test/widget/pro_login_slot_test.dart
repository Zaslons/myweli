import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:myweli/core/constants/failure_messages.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/core/pro_app_extensions.dart';
import 'package:myweli/providers/pro_auth_provider.dart';
import 'package:myweli/screens/provider/auth/pro_login_screen.dart';
import 'package:myweli/services/mock/mock_auth_service.dart';
import 'package:myweli/services/mock/mock_data.dart';
import 'package:myweli/services/mock/mock_pro_service.dart';
import 'package:myweli/services/mock/mock_pro_team_service.dart';
import 'package:myweli/widgets/common/app_text_field.dart';
import 'package:myweli/widgets/team/revoked_access_banner.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/pump_app.dart';

/// The sign-in's slot, its reset and the late notice
/// (docs/design/pro-android-signup.md §2.2, §5.2 — B0.17 PR A).
///
/// PR A builds the slot with nothing in it: iOS, and Android until PR B,
/// mount no `ProLoginExtras`, and `pro_login_only_test` and the
/// `pro_login_w360_x2` golden hold that the screen is then exactly today's.
/// This file mounts a TEST block, so the slot's contract is held before
/// Android's real block exists: what it is told (no account in hand, the
/// e-mail and code a refused verify used), that the red feedback does not
/// repeat the sentence the block shows, and the reset it calls when the page
/// it pushed comes back.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await initializeDateFormatting('fr_FR', null);
    SharedPreferences.setMockInitialValues({});
    serviceLocator.authService = MockAuthService();
    serviceLocator.proService = MockProService();
    serviceLocator.proTeamService = MockProTeamService();
  });

  setUp(() async {
    MockData.resetTeam();
    await serviceLocator.authService.logoutProvider();
  });

  /// The test block: says what it was told, and returns on a tap.
  ProLoginExtras extras() => ProLoginExtras(
    block:
        (
          context, {
          required bool noAccount,
          String? email,
          String? code,
          required VoidCallback onReturned,
        }) => Column(
          children: [
            Text('BLOCK noAccount=$noAccount ${email ?? '-'} ${code ?? '-'}'),
            TextButton(onPressed: onReturned, child: const Text('RETURNED')),
          ],
        ),
  );

  late ProAuthProvider auth;
  late GoRouter router;

  Widget app({ProLoginExtras? login}) {
    router = GoRouter(
      initialLocation: '/pro/login',
      routes: [
        GoRoute(path: '/pro/login', builder: (_, _) => const ProLoginScreen()),
        GoRoute(
          path: '/pushed',
          builder: (_, _) => const Scaffold(body: Text('ABOVE')),
        ),
      ],
    );
    auth = ProAuthProvider(router: router);
    return wrapApp(
      providers: [
        ChangeNotifierProvider.value(value: auth),
        if (login != null) Provider<ProLoginExtras?>.value(value: login),
      ],
      routerConfig: router,
    );
  }

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

  Finder block(String told) => find.text('BLOCK $told');

  /// An address with no account and no invitation, through to the code
  /// step's refused verify.
  Future<void> codeRefused(WidgetTester tester) async {
    await tester.enterText(input('Votre e-mail'), 'personne@myweli.test');
    await tester.tap(find.text('Continuer avec e-mail'));
    await settle(tester);
    await tester.enterText(input('Code à 6 chiffres'), MockAuthService.demoOtp);
    await tester.tap(find.text('Se connecter'));
    await settle(tester);
  }

  testWidgets('no extras → no block: the iOS screen', (tester) async {
    await tester.pumpWidget(app());
    await settle(tester);
    expect(find.textContaining('BLOCK'), findsNothing);
    expect(find.text('Continuer avec Google'), findsOneWidget);
  });

  testWidgets('options step → the block, told no account is in hand (E1)', (
    tester,
  ) async {
    await tester.pumpWidget(app(login: extras()));
    await settle(tester);
    expect(block('noAccount=false - -'), findsOneWidget);
  });

  testWidgets('a code refused as provider_not_found → the block has it, with '
      'the e-mail and code the verify used; the red feedback does not repeat '
      'the sentence (E3)', (tester) async {
    await tester.pumpWidget(app(login: extras()));
    await settle(tester);
    await codeRefused(tester);

    expect(auth.errorCode, 'provider_not_found', reason: 'the premise');
    expect(
      block('noAccount=true personne@myweli.test ${MockAuthService.demoOtp}'),
      findsOneWidget,
    );
    expect(
      find.text(kNoProAccountMessage),
      findsNothing,
      reason: 'the block says it on Android; the sign-in must not repeat it',
    );

    // The field stays editable; the pair is the one the verify used.
    await tester.enterText(input('Code à 6 chiffres'), '000000');
    await tester.pump();
    expect(
      block('noAccount=true personne@myweli.test ${MockAuthService.demoOtp}'),
      findsOneWidget,
    );
  });

  testWidgets('without extras the same refusal keeps its red sentence — '
      'the iOS screen, unchanged', (tester) async {
    await tester.pumpWidget(app());
    await settle(tester);
    await codeRefused(tester);
    expect(find.text(kNoProAccountMessage), findsOneWidget);
  });

  testWidgets('the block\'s return → the options step, its feedback '
      'cleared, nothing in hand (E1 again)', (tester) async {
    await tester.pumpWidget(app(login: extras()));
    await settle(tester);
    await codeRefused(tester);

    // The block is at the bottom of a scrolling form: below the fold here.
    await tester.ensureVisible(find.text('RETURNED'));
    await tester.tap(find.text('RETURNED'));
    await settle(tester);

    expect(find.text('Continuer avec Google'), findsOneWidget);
    expect(auth.error, isNull);
    expect(auth.errorCode, isNull);
    expect(block('noAccount=false - -'), findsOneWidget);
  });

  testWidgets('the « Invitations » step has no block', (tester) async {
    await tester.pumpWidget(app(login: extras()));
    await settle(tester);
    // The mock's Google identity holds a seeded invitation: the 202 bridge.
    await tester.tap(find.text('Continuer avec Google'));
    await settle(tester);
    expect(find.text('Vous êtes invité(e)'), findsOneWidget, reason: 'premise');
    expect(find.textContaining('BLOCK'), findsNothing);
  });

  testWidgets('an « accès retiré » notice set while a page sits above the '
      'sign-in is shown when it comes back — the options step and the banner '
      '(S3b)', (tester) async {
    await tester.pumpWidget(app(login: extras()));
    await settle(tester);
    unawaited(router.push('/pushed'));
    await settle(tester);
    expect(find.text('ABOVE'), findsOneWidget, reason: 'the premise');

    // What a sign-up does when its membership refresh finds nothing left:
    // the provider signs out with the notice and goes to /pro/login.
    await tester.runAsync(auth.signOutRevoked);
    await settle(tester);

    expect(find.text('ABOVE'), findsNothing);
    expect(find.byType(RevokedAccessBanner), findsOneWidget);
    expect(find.text('Continuer avec Google'), findsOneWidget);
  });
}
