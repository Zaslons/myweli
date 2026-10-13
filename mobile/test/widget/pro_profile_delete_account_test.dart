import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/core/push/push_registration.dart';
import 'package:myweli/core/utils/team_error_messages.dart';
import 'package:myweli/models/api_response.dart';
import 'package:myweli/providers/pro_auth_provider.dart';
import 'package:myweli/providers/pro_team_provider.dart';
import 'package:myweli/screens/provider/profile/pro_profile_screen.dart';
import 'package:myweli/services/api/api_pro_service.dart';
import 'package:myweli/services/interfaces/session_store.dart';
import 'package:myweli/services/mock/mock_auth_service.dart';
import 'package:myweli/services/mock/mock_data.dart';
import 'package:myweli/services/mock/mock_device_registration_service.dart';
import 'package:myweli/services/mock/mock_pro_service.dart';
import 'package:myweli/services/mock/mock_pro_team_service.dart';
import 'package:myweli/services/mock/mock_push_notification_service.dart';
import 'package:myweli/widgets/common/app_snack_bar.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/pump_app.dart';
import '../support/settle.dart';
import '../support/sign_in.dart';

/// The mock world with ONE knob: what the server answers to the account
/// deletion. `deletion == null` runs the real mock (a success).
///
/// There is no demo identity in the mock database, on purpose: the app has
/// no notion of « the demo account ». It knows one error code.
class _ScenarioProService extends MockProService {
  Future<ApiResponse<void>> Function()? deletion;
  int deletionCalls = 0;

  @override
  Future<ApiResponse<void>> deleteProviderAccount() {
    deletionCalls++;
    return (deletion ?? super.deleteProviderAccount)();
  }
}

const _futureBookingsSentence =
    'Terminez ou annulez vos rendez-vous à venir avant de supprimer votre '
    'compte.';

/// Profil > « Supprimer mon compte » when the server refuses — the shared
/// App Review demo account cannot delete itself (403 `demo_account_locked`).
///
/// What the review notes promise, and what is pinned here: the entry is
/// THERE for the demo account, the refusal comes after the `SUPPRIMER`
/// confirmation with « Compte de démonstration — cette action est
/// désactivée. », and the reviewer stays signed in.
///
/// On both platforms: the review happens on an iPhone, and `flutter test`
/// reports Android unless told otherwise.
/// Design: docs/design/demo-account-deletion-lock.md §7.1.
void main() {
  final pro = _ScenarioProService();
  final bothPlatforms = TargetPlatformVariant(const {
    TargetPlatform.android,
    TargetPlatform.iOS,
  });

  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    serviceLocator.authService = MockAuthService();
    serviceLocator.proService = pro;
    serviceLocator.proTeamService = MockProTeamService();
    serviceLocator.proPushRegistration = PushRegistration(
      push: MockPushNotificationService(),
      devices: MockDeviceRegistrationService(),
    );
  });

  setUp(() {
    MockData.resetTeam();
    pro
      ..deletion = null
      ..deletionCalls = 0;
  });

  Future<ProAuthProvider> pumpProfile(WidgetTester tester) async {
    final auth = await signInPro(tester);
    final router = GoRouter(
      initialLocation: '/pro/profile',
      routes: [
        GoRoute(
          path: '/pro/profile',
          builder: (_, _) => const ProProfileScreen(),
        ),
        GoRoute(
          path: '/pro/login',
          builder: (_, _) => const Scaffold(body: Text('ÉCRAN DE CONNEXION')),
        ),
      ],
    );
    await tester.pumpWidget(
      wrapApp(
        providers: [
          ChangeNotifierProvider<ProAuthProvider>.value(value: auth),
          ChangeNotifierProvider(create: (_) => ProTeamProvider()),
        ],
        routerConfig: router,
      ),
    );
    await settleMocks(tester, rounds: 2);
    return auth;
  }

  /// The reviewer's three gestures: the entry, the word, the button.
  Future<void> confirmDeletion(WidgetTester tester) async {
    final entry = find.text('Supprimer mon compte');
    await tester.ensureVisible(entry);
    await tester.pump();
    await tester.tap(entry);
    await settleMocks(tester);

    expect(find.text('Supprimer votre compte ?'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'SUPPRIMER');
    await tester.pump();
    await tester.tap(
      find.widgetWithText(TextButton, 'Supprimer définitivement'),
    );
    // The dialog closes, the request answers, the snackbar comes in.
    await settleMocks(tester, rounds: 3);
  }

  Future<void> expectStillSignedInOnProfil(
    WidgetTester tester,
    ProAuthProvider auth,
  ) async {
    expect(auth.isAuthenticated, isTrue, reason: 'the app-side session');
    expect(find.text('ÉCRAN DE CONNEXION'), findsNothing);
    expect(find.byType(ProProfileScreen), findsOneWidget);
    expect(
      find.text('Supprimer mon compte'),
      findsOneWidget,
      reason: 'the entry is still offered after a refusal',
    );
    await tester.runAsync(() async {
      expect(
        await serviceLocator.authService.getCurrentProvider(),
        isNotNull,
        reason: 'nothing local was cleared',
      );
    });
  }

  /// A refusal is feedback ON THE SCREEN, in the error tone.
  ///
  /// - The dialog is gone. A snackbar raised under an open dialog is painted
  ///   under the scrim and pruned from the semantics tree (SYSTEM.md §15):
  ///   `find.text` would still find its sentence, and nobody could read it.
  /// - The bar is the ERROR kind — its colour and its six seconds. The
  ///   sentence alone does not say that: an `info` bar carries the same
  ///   words for three seconds, in the neutral tone.
  void expectErrorSnackOnTheScreen(WidgetTester tester, String sentence) {
    expect(
      find.text('Supprimer votre compte ?'),
      findsNothing,
      reason: 'the confirmation dialog is closed when the refusal shows',
    );
    final bar = tester.widget<SnackBar>(find.byType(SnackBar));
    expect(bar.backgroundColor, SnackKind.error.color);
    expect(bar.duration, SnackKind.error.duration);
    expect(
      find.descendant(of: find.byType(SnackBar), matching: find.text(sentence)),
      findsOneWidget,
      reason: 'the sentence is IN the snackbar',
    );
  }

  testWidgets('the entry is offered and ENABLED before anything is asked of '
      'the server', (tester) async {
    await pumpProfile(tester);

    final entry = find.widgetWithText(TextButton, 'Supprimer mon compte');
    await tester.ensureVisible(entry);
    expect(tester.widget<TextButton>(entry).onPressed, isNotNull);
    expect(pro.deletionCalls, 0);
  }, variant: bothPlatforms);

  testWidgets('demo_account_locked: the demo sentence, after SUPPRIMER — and '
      'the reviewer stays signed in', (tester) async {
    // A different sentence from the service, on purpose: the screen maps
    // the CODE, as it does for `future_bookings`.
    pro.deletion = () async => ApiResponse.error(
      'Une autre phrase du service.',
      code: 'demo_account_locked',
    );
    final auth = await pumpProfile(tester);

    await confirmDeletion(tester);

    expect(pro.deletionCalls, 1, reason: 'the request was really sent');
    expect(find.text(demoAccountLockedMessage), findsOneWidget);
    expectErrorSnackOnTheScreen(tester, demoAccountLockedMessage);
    expect(find.text('Une autre phrase du service.'), findsNothing);
    expect(find.text(_futureBookingsSentence), findsNothing);
    await expectStillSignedInOnProfil(tester, auth);
  }, variant: bothPlatforms);

  testWidgets('demo_account_locked through the REAL ApiProService: an HTTP '
      '403 from DELETE /me/provider reads as the demo sentence', (
    tester,
  ) async {
    // What a reviewer's phone does: the app's own HTTP service, a server
    // answering 403. No stubbed sentence anywhere on the path.
    final requests = <String>[];
    final store = InMemorySessionStore();
    await store.save(jsonEncode({'token': 'tok', 'refreshToken': 'r1'}));
    final api = ApiProService(
      client: MockClient((req) async {
        requests.add('${req.method} ${req.url.path}');
        return http.Response(
          jsonEncode({'error': 'demo_account_locked'}),
          403,
          headers: {'content-type': 'application/json'},
        );
      }),
      baseUrl: 'http://api.test',
      providerSessionStore: store,
    );
    pro.deletion = api.deleteProviderAccount;
    final auth = await pumpProfile(tester);

    await confirmDeletion(tester);

    expect(requests, ['DELETE /me/provider']);
    expect(find.text(demoAccountLockedMessage), findsOneWidget);
    expectErrorSnackOnTheScreen(tester, demoAccountLockedMessage);
    await expectStillSignedInOnProfil(tester, auth);
  }, variant: bothPlatforms);

  testWidgets('CONTROL — future_bookings keeps its own sentence', (
    tester,
  ) async {
    pro.deletion = () async => ApiResponse.error(
      'Une autre phrase du service.',
      code: 'future_bookings',
    );
    final auth = await pumpProfile(tester);

    await confirmDeletion(tester);

    expect(find.text(_futureBookingsSentence), findsOneWidget);
    expectErrorSnackOnTheScreen(tester, _futureBookingsSentence);
    expect(find.text(demoAccountLockedMessage), findsNothing);
    await expectStillSignedInOnProfil(tester, auth);
  }, variant: bothPlatforms);

  testWidgets('CONTROL — any other failure shows the service\'s own '
      'message', (tester) async {
    pro.deletion = () async =>
        ApiResponse.error('Connexion au serveur impossible');
    final auth = await pumpProfile(tester);

    await confirmDeletion(tester);

    expect(find.text('Connexion au serveur impossible'), findsOneWidget);
    expectErrorSnackOnTheScreen(tester, 'Connexion au serveur impossible');
    expect(find.text(demoAccountLockedMessage), findsNothing);
    expect(find.text(_futureBookingsSentence), findsNothing);
    await expectStillSignedInOnProfil(tester, auth);
  }, variant: bothPlatforms);

  testWidgets('CONTROL — a deletion the server accepts signs out, to the '
      'login screen', (tester) async {
    // Without this, « stays signed in » above would be true of a screen
    // that never signs anyone out.
    final auth = await pumpProfile(tester);

    await confirmDeletion(tester);
    await settleMocks(tester, rounds: 3);

    expect(pro.deletionCalls, 1);
    expect(auth.isAuthenticated, isFalse);
    expect(find.text('ÉCRAN DE CONNEXION'), findsOneWidget);
    expect(find.text(demoAccountLockedMessage), findsNothing);
  }, variant: bothPlatforms);
}
