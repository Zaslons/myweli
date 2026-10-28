import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/providers/auth_provider.dart';
import 'package:myweli/providers/pro_auth_provider.dart';
import 'package:myweli/screens/auth/login_screen.dart';
import 'package:myweli/screens/provider/auth/pro_login_screen.dart';
import 'package:myweli/services/api/api_auth_service.dart';
import 'package:myweli/services/mock/mock_pro_service.dart';
import 'package:myweli/widgets/common/inline_feedback.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../a11y/_a11y.dart';
import '../support/fonts.dart';
import '../support/secure_storage.dart';
import '../support/settle.dart';

/// docs/design/apple-signin-error-1000.md §2.2, §8 (B0.14) — iOS error 1000
/// through the REAL chain: `ApiAuthService` (its Apple seam throwing what the
/// plugin throws for 1000) → the real provider → the real login screen, on
/// iOS, where alone the Apple button exists.
///
/// The sentence must land under the form, in `InlineFeedback` (a live region,
/// so VoiceOver reads it), and still fit on a 360dp phone at 200 % text.
void main() {
  const sentence =
      'Connexion Apple impossible sur cet appareil. Vérifiez dans Réglages '
      'qu’un compte Apple est connecté, puis réessayez.';

  final sent = <http.Request>[];

  setUpAll(() async {
    await loadRealFonts();
    SharedPreferences.setMockInitialValues({});
    stubSecureStorage();
    // `late final` — set once for the file.
    serviceLocator.authService = ApiAuthService(
      client: MockClient((req) async {
        sent.add(req);
        return http.Response('{}', 500);
      }),
      baseUrl: 'http://x',
      // What sign_in_with_apple 8.2.0 throws for ASAuthorizationError 1000.
      appleCredential: (_) async =>
          throw const SignInWithAppleAuthorizationException(
            code: AuthorizationErrorCode.unknown,
            message:
                'The operation couldn’t be completed. '
                '(com.apple.AuthenticationServices.AuthorizationError error 1000.)',
          ),
    );
    serviceLocator.proService = MockProService();
  });

  setUp(sent.clear);

  final screens =
      <String, ({Widget screen, SingleChildWidget Function() provider})>{
        'MyWeli Pro': (
          screen: const ProLoginScreen(),
          provider: () =>
              ChangeNotifierProvider(create: (_) => ProAuthProvider()),
        ),
        'MyWeli': (
          screen: const LoginScreen(),
          provider: () => ChangeNotifierProvider(create: (_) => AuthProvider()),
        ),
      };

  for (final entry in screens.entries) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('${entry.key}: error 1000 says what to check, under the '
          'form, at 360dp × ${scale.toInt()}× text', (tester) async {
        // `flutter test` reports android, where the Apple button does not
        // exist. Reset in a `finally`: the framework checks the debug vars at
        // the end of the body, before tearDowns run.
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
        try {
          await pumpAtWidth(
            tester,
            width: 360,
            scale: scale,
            providers: [entry.value.provider()],
            home: entry.value.screen,
          );

          final apple = find.text('Continuer avec Apple');
          await tester.ensureVisible(apple);
          await tester.tap(apple);
          await settleMocks(tester);

          expect(
            find.descendant(
              of: find.byType(InlineFeedback),
              matching: find.text(sentence),
            ),
            findsOneWidget,
          );
          expect(find.text('Connexion Apple impossible.'), findsNothing);
          expect(sent, isEmpty, reason: '1000 happens before the server');

          final at = '360dp × ${scale.toInt()}× text';
          expectNoUndeclaredTruncation(tester, context: at);
          expectNoVerticalClip(tester, context: at);
          expectNoMidWordBreak(tester, sentence, at);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      });
    }
  }
}
