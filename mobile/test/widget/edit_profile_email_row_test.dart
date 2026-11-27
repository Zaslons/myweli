import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/providers/auth_provider.dart';
import 'package:myweli/screens/profile/edit_profile_screen.dart';
import 'package:myweli/services/api/api_auth_service.dart';
import 'package:myweli/services/interfaces/session_store.dart';
import 'package:myweli/widgets/common/app_text_field.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/pump_app.dart';
import '../support/secure_storage.dart';

/// « Modifier le profil »'s e-mail (B16.3b — docs/design/account-email-change.md
/// §5.4, decisions 260–265). Since B16.3a the server proves an address before
/// it reaches an account, and `PATCH /me` answers `409
/// email_change_requires_code` to any other address than the stored one. The
/// screen sent its e-mail field's text on EVERY save — changed or not — so an
/// edited address met that 409 as « Une erreur est survenue. Réessayez. ».
///
/// Through the real `ApiAuthService` over a fake HTTP client, so what is
/// asserted is the body the server would receive, not a double's arguments.
void main() {
  // What the server says the account is; each test sets it.
  late Map<String, dynamic> serverUser;
  final patches = <Map<String, dynamic>>[];

  final client = MockClient((req) async {
    if (req.url.path == '/auth/email/otp/verify') {
      return http.Response(
        jsonEncode({
          'tokens': {
            'accessToken': 'access-1',
            'refreshToken': 'refresh-1',
            'expiresAt': DateTime(2026).toIso8601String(),
          },
          'user': serverUser,
        }),
        200,
      );
    }
    if (req.url.path == '/me' && req.method == 'PATCH') {
      final body = jsonDecode(req.body) as Map<String, dynamic>;
      patches.add(body);
      return http.Response(jsonEncode({...serverUser, ...body}), 200);
    }
    return http.Response(jsonEncode({'error': 'not_found'}), 404);
  });
  final service = ApiAuthService(
    client: client,
    baseUrl: 'http://x',
    sessionStore: InMemorySessionStore(),
  );

  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    stubSecureStorage();
    serviceLocator.authService = service;
  });

  setUp(patches.clear);

  Map<String, dynamic> userWith({String? email, bool? emailVerified}) => {
    'id': 'user_1',
    'phoneNumber': '+2250707123456',
    'phoneVerified': false,
    'name': 'Awa Koné',
    'email': email,
    'emailVerified': ?emailVerified,
    'authProvider': 'google',
    'avatarUrl': null,
    'createdAt': DateTime(2026).toIso8601String(),
  };

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
  }

  /// Signed in as [serverUser], on « Modifier le profil » pushed from a
  /// stand-in « Profil ». The change screen is a stand-in too: what is
  /// asserted here is where the row sends the person.
  Future<void> openForm(WidgetTester tester) async {
    late final AuthProvider auth;
    await tester.runAsync(() async {
      final res = await service.verifyEmailOtp('awa@exemple.ci', '123456');
      expect(res.success, isTrue);
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
                  builder: (_, state) =>
                      Scaffold(body: Text('CHANGE ${state.uri}')),
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
    expect(find.text('Modifier le profil'), findsOneWidget);
  }

  Future<void> save(WidgetTester tester) async {
    await tester.ensureVisible(find.text('Enregistrer'));
    await tester.tap(find.text('Enregistrer'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await settle(tester);
  }

  testWidgets(
    'Save sends the name and the phone, never an address (§5.4, §3.2)',
    (tester) async {
      serverUser = userWith(email: 'awa@exemple.ci', emailVerified: true);
      await openForm(tester);

      await save(tester);

      expect(patches, hasLength(1), reason: 'one PATCH /me per save');
      expect(
        patches.single.keys,
        isNot(contains('email')),
        reason:
            'an address changes only by a code (decision 261); sending it '
            'on every save is how an edited one met `409 '
            'email_change_requires_code`',
      );
      expect(patches.single['name'], 'Awa Koné');
    },
  );

  testWidgets(
    'a proven address: the row, « Modifier », and the code sign-in line',
    (tester) async {
      serverUser = userWith(email: 'awa@exemple.ci', emailVerified: true);
      await openForm(tester);

      expect(find.text('Adresse e-mail'), findsOneWidget);
      expect(find.text('awa@exemple.ci'), findsOneWidget);
      expect(find.text('Modifier'), findsOneWidget);
      expect(
        find.text(
          'Vous pouvez aussi vous connecter avec un code envoyé à cette '
          'adresse.',
        ),
        findsOneWidget,
      );
      expect(find.text('Non vérifiée'), findsNothing);
      expect(
        find.byType(AppTextField),
        findsOneWidget,
        reason:
            'the name is the only AppTextField left (the phone is a '
            'PhoneNumberField): the address is a row, not a field',
      );
    },
  );

  testWidgets('an unproven address: « Non vérifiée » and « Vérifier »', (
    tester,
  ) async {
    serverUser = userWith(email: 'awa@exemple.ci', emailVerified: false);
    await openForm(tester);

    expect(find.text('awa@exemple.ci'), findsOneWidget);
    expect(find.text('Non vérifiée'), findsOneWidget);
    expect(find.text('Vérifier'), findsOneWidget);
    expect(
      find.textContaining('Vous pouvez aussi vous connecter'),
      findsNothing,
      reason: 'an unproven address signs nobody in (decision 260)',
    );
  });

  testWidgets('no address: « Aucune adresse » and « Modifier »', (
    tester,
  ) async {
    serverUser = userWith(email: null, emailVerified: false);
    await openForm(tester);

    expect(find.text('Aucune adresse'), findsOneWidget);
    expect(find.text('Modifier'), findsOneWidget);
    expect(find.text('Vérifier'), findsNothing);
  });

  testWidgets('« Modifier » opens the change screen', (tester) async {
    serverUser = userWith(email: 'awa@exemple.ci', emailVerified: true);
    await openForm(tester);

    await tester.tap(find.text('Modifier'));
    await settle(tester);

    expect(find.text('CHANGE /profile/edit/email'), findsOneWidget);
  });

  testWidgets('« Vérifier » opens it on the address, straight to its code', (
    tester,
  ) async {
    serverUser = userWith(email: 'awa@exemple.ci', emailVerified: false);
    await openForm(tester);

    await tester.tap(find.text('Vérifier'));
    await settle(tester);

    expect(find.text('CHANGE /profile/edit/email?verifier=1'), findsOneWidget);
  });
}
