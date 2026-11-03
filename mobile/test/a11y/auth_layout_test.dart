import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/providers/auth_provider.dart';
import 'package:myweli/providers/pro_auth_provider.dart';
import 'package:myweli/screens/auth/login_screen.dart';
import 'package:myweli/screens/provider/auth/pro_login_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fonts.dart';
import '../support/secure_storage.dart';
import '_a11y.dart';

/// The auth screens, across §10's compact range (A11 C8).
///
/// ## These were a subject of no width test at all
///
/// `layout_test.dart` measures nine subjects and the screens people **sign in
/// on** are not among them — the consumer login and the pro login were checked
/// at one width (390) by one golden, at 1× only.
///
/// That is how a prompt at the bottom of the pro login shipped running **149px**
/// past a 360dp screen at 200% text, found by running the app on a 360dp
/// Android device. The prompt has since left the app
/// (docs/design/app-review-round-2.md §4); the width test stays, because a
/// sign-in screen with less on it can still overflow, and the banner that says
/// so is debug-only.
///
/// ## On both platforms, because Apple reviews the other one
///
/// `flutter test` is Android, and « Continuer avec Apple » is iOS only. So until
/// this ran on both, the login Apple has cited twice, with that button in it, was
/// never measured at any width or at 200 %. It is still not photographed:
/// `pro_login_w360_x2` is Android. This measures; it does not look.
void main() {
  setUpAll(() async {
    await loadRealFonts();
    SharedPreferences.setMockInitialValues({});
    stubSecureStorage();
    // ONCE — `serviceLocator`'s fields are `late final`, so a second call is a
    // LateInitializationError rather than a re-setup.
    setupDependencyInjection();
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));

  /// 360 is the floor the PRD's device class actually is; 375 and 390 are the
  /// two points the rest of the suite already stands on.
  const widths = [360.0, 375.0, 390.0];
  const scales = [1.0, 2.0];
  const bothPlatforms = TargetPlatformVariant({
    TargetPlatform.android,
    TargetPlatform.iOS,
  });

  /// Each screen with a string that proves **it** rendered, not a Scaffold.
  ///
  /// Assertion C, and it is not a formality. `expectNoUndeclaredTruncation`
  /// walks `RenderParagraph`s and flags only `didExceedMaxLines` or
  /// `!softWrap` — and `grep -n 'maxLines\|softWrap' ` returns **zero hits**
  /// for both login screens and every widget they compose. So B cannot fire on
  /// either subject, and A (no overflow) is satisfied by an empty tree. Without
  /// C, a screen that renders a bare AppBar — behind a feature flag, or with the
  /// provider in a state these tests do not seed — is twelve green tests about
  /// nothing.
  final screens = <String, ({Widget screen, String proof})>{
    'the consumer login': (
      screen: const LoginScreen(),
      proof: 'Continuer avec e-mail',
    ),
    'the pro login': (
      screen: const ProLoginScreen(),
      proof: 'Connectez-vous à votre espace salon.',
    ),
  };

  for (final width in widths) {
    for (final scale in scales) {
      final at = '${width.toInt()}dp × ${scale.toInt()}× text';

      for (final entry in screens.entries) {
        testWidgets('${entry.key} fits $at', variant: bothPlatforms, (
          tester,
        ) async {
          await pumpAtWidth(
            tester,
            width: width,
            scale: scale,
            providers: [
              ChangeNotifierProvider(create: (_) => AuthProvider()),
              ChangeNotifierProvider(create: (_) => ProAuthProvider()),
            ],
            home: entry.value.screen,
          );

          // C — the screen is really on the surface. See the note above.
          expect(
            find.text(entry.value.proof),
            findsOneWidget,
            reason:
                '« ${entry.value.proof} » is not on ${entry.key} at $at, '
                'so whatever this measured, it was not the screen',
          );
          // The variant really reached the screen: this is the one row that
          // differs, and the reason both platforms run.
          expect(
            find.text('Continuer avec Apple'),
            defaultTargetPlatform == TargetPlatform.iOS
                ? findsOneWidget
                : findsNothing,
          );

          // A — reaching here already means no RenderFlex overflowed; those
          // are reported FlutterErrors and the pump dies on them. That is the
          // assertion for THIS defect.
          // B — and what an overflow-free layout can still get wrong.
          expectNoUndeclaredTruncation(tester, context: at);
          expectNoLegibilityCrush(tester, context: at);
          expectNoVerticalClip(tester, context: at);
        });
      }
    }
  }
}
