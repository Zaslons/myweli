import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/models/api_response.dart';
import 'package:myweli/models/user.dart';
import 'package:myweli/providers/auth_provider.dart';
import 'package:myweli/screens/profile/edit_profile_screen.dart';
import 'package:myweli/services/mock/mock_auth_service.dart';
import 'package:myweli/services/mock/mock_data.dart';
import 'package:myweli/widgets/common/phone_number_field.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/pump_app.dart';
import '../support/secure_storage.dart';
import '../support/sign_in.dart';

/// « Modifier le profil » — the consumer's contact phone, which is OPTIONAL
/// here (docs/design/phone-national-length.md §2.3). Until this file the screen
/// had no widget test at all, and its phone could not be cleared: an emptied
/// `PhoneNumberField` emitted `+225`, which the hand-rolled optional rule did
/// not read as empty, so the press answered « Saisissez un numéro de téléphone
/// valide. » under a field holding nothing.
void main() {
  // `authService` is a `late final` — one spy for the file.
  final spy = _SpyAuthService();
  late User seededUser1;

  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    stubSecureStorage();
    serviceLocator.authService = spy;
    seededUser1 = MockData.users.firstWhere((u) => u.id == 'user1');
  });

  setUp(spy.phonesSent.clear);

  tearDown(() {
    spy.rejectPhoneWith = null;
    // A saved edit writes through to the seed; the next test signs in by it.
    final i = MockData.users.indexWhere((u) => u.id == 'user1');
    MockData.users[i] = seededUser1;
  });

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
  }

  /// Signed in as `user1` (a stored contact phone), on the edit screen pushed
  /// from a stand-in « Profil ».
  Future<void> openForm(WidgetTester tester) async {
    final auth = await signInConsumer(tester);
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
        ),
        GoRoute(
          path: '/profile/edit',
          builder: (_, _) => const EditProfileScreen(),
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

  Finder phoneInput() => find.descendant(
    of: find.byType(PhoneNumberField),
    matching: find.byType(TextField),
  );

  Finder underThePhone(String message) => find.descendant(
    of: find.byType(PhoneNumberField),
    matching: find.text(message),
  );

  Future<void> save(WidgetTester tester) async {
    await tester.tap(find.text('Enregistrer'));
    await settle(tester);
    await settle(tester);
  }

  testWidgets('clearing the phone sends \'\' — the server clears it', (
    tester,
  ) async {
    await openForm(tester);

    await tester.enterText(phoneInput(), '');
    await tester.pump();
    await save(tester);

    expect(
      find.text('Saisissez un numéro de téléphone valide.'),
      findsNothing,
      reason: 'an emptied optional phone is not a fault',
    );
    expect(spy.phonesSent, [
      '',
    ], reason: '`PATCH /me` documents \'\' as « clear it »');
    expect(find.text('PROFIL'), findsOneWidget, reason: 'saved, and popped');
  });

  testWidgets('a short +225 number answers under the field — nothing sent', (
    tester,
  ) async {
    await openForm(tester);

    await tester.enterText(phoneInput(), '0707123');
    await tester.pump();
    await save(tester);

    expect(
      underThePhone('Le numéro doit comporter 10 chiffres après +225.'),
      findsOneWidget,
    );
    expect(spy.phonesSent, isEmpty);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('a server `invalid_phone` lands under the field, not in a bar', (
    tester,
  ) async {
    await openForm(tester);
    spy.rejectPhoneWith = 'invalid_phone';

    await tester.enterText(phoneInput(), '0707123457');
    await tester.pump();
    await save(tester);

    expect(spy.phonesSent, ['+2250707123457']);
    expect(
      underThePhone('Saisissez un numéro de téléphone valide.'),
      findsOneWidget,
      reason: 'the server\'s verdict on the number belongs to the number',
    );
    expect(
      find.text('Numéro ou code invalide.'),
      findsNothing,
      reason: 'there is no code on this screen — and a fault is never a bar',
    );
    expect(find.text('Modifier le profil'), findsOneWidget);
  });
}

/// The mock, recording every `updateUser` phone — and optionally refusing it
/// the way `PATCH /me` does (400 `invalid_phone`, mapped by `ApiAuthService`).
class _SpyAuthService extends MockAuthService {
  String? rejectPhoneWith;
  final phonesSent = <String?>[];

  @override
  Future<ApiResponse<User>> updateUser({
    String? name,
    String? email,
    String? avatarUrl,
    String? phone,
  }) async {
    phonesSent.add(phone);
    if (rejectPhoneWith != null) {
      return ApiResponse.error(
        'Numéro ou code invalide.',
        code: rejectPhoneWith,
      );
    }
    return super.updateUser(
      name: name,
      email: email,
      avatarUrl: avatarUrl,
      phone: phone,
    );
  }
}
