import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/providers/auth_provider.dart';
import 'package:myweli/providers/pro_auth_provider.dart';
import 'package:myweli/screens/auth/login_screen.dart';
import 'package:myweli/screens/provider/auth/pro_login_screen.dart';
import 'package:myweli/screens/provider/auth/pro_register_screen.dart';
import 'package:myweli/widgets/common/auth_switch_prompt.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fonts.dart';
import '../support/secure_storage.dart';
import '_a11y.dart';

/// The three auth screens, across §10's compact range (A11 C8).
///
/// ## These were a subject of no width test at all
///
/// `layout_test.dart` measures nine subjects and the screens people **sign in
/// on** are not among them — the consumer login, the pro login and the pro
/// register form were checked at one width (390) by one golden, at 1× only.
///
/// So this shipped: at 200% text the pro login's « Pas encore de compte ? »
/// prompt ran **149px** past a 360dp screen, and the pro register form's
/// « Déjà un compte ? » did the same. Both are a centred `Row` holding a
/// sentence and a `TextButton`, neither able to give way. The overflow barely
/// moved across the range — 149px at 360, 134 at 375, 119 at 390 — because the
/// content has a fixed intrinsic width; it is not a layout that adapts badly,
/// it is one that does not adapt.
///
/// It is the last line of the **first screen a pro ever sees**, and the only
/// route from it to registration.
///
/// Found by running the app on a 360dp Android device at 200% text. The banner
/// is debug-only, so on a release build the line is simply cut in half.
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

  /// Each screen with a string that proves **it** rendered, not a Scaffold.
  ///
  /// Assertion C, and it is not a formality. `expectNoUndeclaredTruncation`
  /// walks `RenderParagraph`s and flags only `didExceedMaxLines` or
  /// `!softWrap` — and `grep -n 'maxLines\|softWrap' ` returns **zero hits**
  /// for both login screens and every widget they compose. So B cannot fire on
  /// two of the three subjects, and A (no overflow) is satisfied by an empty
  /// tree. Without C, a screen that renders a bare AppBar — behind a feature
  /// flag, or with the provider in a state these tests do not seed — is
  /// eighteen green tests about nothing.
  final screens = <String, ({Widget screen, String proof})>{
    'the consumer login': (
      screen: const LoginScreen(),
      proof: 'Continuer avec e-mail',
    ),
    'the pro login': (
      screen: const ProLoginScreen(),
      proof: 'Pas encore de compte ?',
    ),
    'the pro register form': (
      screen: const ProRegisterScreen(),
      proof: 'Déjà un compte ?',
    ),
  };

  for (final width in widths) {
    for (final scale in scales) {
      final at = '${width.toInt()}dp × ${scale.toInt()}× text';

      for (final entry in screens.entries) {
        testWidgets('${entry.key} fits $at', (tester) async {
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
            reason: '« ${entry.value.proof} » is not on ${entry.key} at $at, '
                'so whatever this measured, it was not the screen',
          );

          // A — reaching here already means no RenderFlex overflowed; those
          // are reported FlutterErrors and the pump dies on them. That is the
          // assertion for THIS defect.
          // B — and what an overflow-free layout can still get wrong.
          expectNoUndeclaredTruncation(tester, context: at);
        });
      }
    }
  }

  // ---- the prompt itself, where the defect lived -------------------------

  for (final width in widths) {
    testWidgets(
        'the auth prompt keeps both halves and stays tappable at '
        '${width.toInt()}dp × 2× text', (tester) async {
      await pumpAtWidth(
        tester,
        width: width,
        scale: 2,
        providers: [ChangeNotifierProvider(create: (_) => ProAuthProvider())],
        home: const ProLoginScreen(),
      );

      // Both halves present and whole. The failure this replaces did not
      // truncate — it drew the line at full width, past the screen edge — so
      // "the text exists" is not enough on its own; the box has to be inside
      // the window.
      final prompt = tester.getRect(find.byType(AuthSwitchPrompt));
      expect(
        prompt.right,
        lessThanOrEqualTo(width),
        reason: 'the prompt runs to ${prompt.right}dp on a ${width}dp screen',
      );

      for (final part in ['Pas encore de compte ?', 'S’inscrire']) {
        expect(find.text(part), findsOneWidget, reason: '« $part » vanished');
        expectNoMidWordBreak(tester, part, '${width.toInt()}dp @2x');
      }

      // §13.2: the link is the only way to reach registration from here, and a
      // wrapped Wrap run must not squeeze it below the tap minimum.
      final link = tester.getSize(find.byType(TextButton));
      expect(
        link.height,
        greaterThanOrEqualTo(48.0),
        reason: 'the « S’inscrire » target is ${link.height}dp tall',
      );
    });
  }
}
