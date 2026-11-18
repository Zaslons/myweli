import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/core/pro_app_extensions.dart';
import 'package:myweli/providers/pro_auth_provider.dart';
import 'package:myweli/screens/provider/android/pro_android_extensions.dart';
import 'package:myweli/screens/provider/android/pro_sign_up_screen.dart';
import 'package:myweli/screens/provider/auth/pro_login_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fonts.dart';
import '../support/secure_storage.dart';
import '_a11y.dart';

/// Android's sign-up and its sign-in, across §10's compact range at 1× and
/// 200% text (docs/design/pro-android-signup.md §8.2 « Accessibility »):
/// nothing overflows, clips or is silently cut — a chip label never wraps, so
/// « Institut de manucure » is the one to watch — every target is 48dp, the
/// headings have their levels, the block's sentence is a live region, and a
/// chosen chip says so.
void main() {
  setUpAll(() async {
    await loadRealFonts();
    SharedPreferences.setMockInitialValues({});
    stubSecureStorage();
    setupDependencyInjection();
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));

  const widths = [360.0, 375.0, 390.0];
  const scales = [1.0, 2.0];
  final android = proAndroidExtensionsFor(TargetPlatform.android)!;

  SemanticsData semanticsOf(WidgetTester tester, String text) =>
      tester.getSemantics(find.text(text)).getSemanticsData();

  for (final width in widths) {
    for (final scale in scales) {
      final at = '${width.toInt()}dp × ${scale.toInt()}× text';

      testWidgets('the sign-up fits $at', (tester) async {
        await pumpPushedAtWidth(
          tester,
          width: width,
          scale: scale,
          height: 3200,
          subject: const ProSignUpScreen(),
          providers: [ChangeNotifierProvider(create: (_) => ProAuthProvider())],
        );
        final handle = tester.ensureSemantics();

        // C — the screen really rendered.
        expect(find.text('Votre identité de connexion'), findsOneWidget);
        expect(find.text('Institut de manucure'), findsOneWidget);

        expectNoUndeclaredTruncation(tester, context: at);
        expectNoLegibilityCrush(tester, context: at);
        expectNoVerticalClip(tester, context: at);
        expectAppBarTitleWhole(tester, at: at);
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));

        expect(semanticsOf(tester, 'Créer mon compte').headingLevel, 1);
        expect(semanticsOf(tester, 'Votre salon').headingLevel, 2);
        expect(
          semanticsOf(tester, 'Votre identité de connexion').headingLevel,
          2,
        );

        // A chosen chip says so (« sélectionné » on TalkBack).
        await tester.tap(find.text('Spa'));
        await tester.pump();
        expect(
          tester.getSemantics(
            find.ancestor(
              of: find.text('Spa'),
              matching: find.byType(ChoiceChip),
            ),
          ),
          isSemantics(isSelected: true),
        );
        handle.dispose();
      });

      testWidgets('the Android sign-in, with its block, fits $at', (
        tester,
      ) async {
        await pumpAtWidth(
          tester,
          width: width,
          scale: scale,
          providers: [
            ChangeNotifierProvider(create: (_) => ProAuthProvider()),
            Provider<ProLoginExtras?>.value(value: android.login),
          ],
          home: const ProLoginScreen(),
        );
        final handle = tester.ensureSemantics();

        expect(find.text('Créer le compte de mon salon'), findsOneWidget);
        expectNoUndeclaredTruncation(tester, context: at);
        expectNoLegibilityCrush(tester, context: at);
        expectNoVerticalClip(tester, context: at);
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        expect(
          tester.getSemantics(find.text('Pas encore de compte ?')),
          isSemantics(isLiveRegion: true),
          reason: 'TalkBack announces E1 → E2',
        );
        handle.dispose();
      });
    }
  }
}
