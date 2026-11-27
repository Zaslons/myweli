import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/core/theme/colors.dart';
import 'package:myweli/providers/pro_auth_provider.dart';
import 'package:myweli/screens/provider/android/pro_sign_up_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/drawn_email.dart';
import '../support/fonts.dart';
import '../support/secure_storage.dart';
import '_a11y.dart';

/// The Android Pro sign-up's E3 line under SYSTEM.md §13.3's e-mail rule
/// (docs/design/app-pro-profile-email-seams.md §4.2): « Compte : », then the
/// carried address on a line of its own, broken only at its seams.
///
/// **What was broken, measured on #905's head**, 360 dp, real font, a 312 dp
/// line: one `Text`, « Compte : {adresse} ». At 1× an address that fit began
/// on the line « Compte : » had started. At 2× it broke mid-word:
/// « Compte : aminata.ko » / « ne@exemple.ci », « Compte : adjoua.kou » /
/// « ame.konan@hotmail. » / « com ».
void main() {
  setUpAll(() async {
    await loadRealFonts();
    SharedPreferences.setMockInitialValues({});
    stubSecureStorage();
    setupDependencyInjection();
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));

  /// First: it fails today at both sizes — on « Compte : »'s line at 1×,
  /// broken mid-word at 2×.
  const long = 'aminata.kone@exemple.ci';

  const addresses = [
    long,
    'adjoua.kouame.konan@hotmail.com',
    'awa.kone.nouvelle@outlook.com',
    'retard@myweli.com',
    'koffi.yao@gmail.com',
    'awa@exemple.ci',
  ];

  Future<void> openCarried(
    WidgetTester tester,
    String address, {
    required double scale,
  }) async {
    await pumpPushedAtWidth(
      tester,
      width: 360,
      scale: scale,
      height: 3200,
      subject: ProSignUpScreen(carried: ProSignUpCarry(address, '123456')),
      providers: [ChangeNotifierProvider(create: (_) => ProAuthProvider())],
    );
    expect(
      find.text('Utiliser une autre adresse'),
      findsOneWidget,
      reason: 'E3, the carried identity',
    );
  }

  for (final (scale, at) in [(2.0, '360 dp × 2×'), (1.0, '360 dp × 1×')]) {
    testWidgets('E3 at $at: « Compte : », then the address on a line of its '
        'own, broken only at its seams', (tester) async {
      for (final address in addresses) {
        await openCarried(tester, address, scale: scale);
        expectEmailAddressOnItsOwnLine(tester, address, 'E3, $at');
      }
    });
  }

  testWidgets('E3: « Compte : » alone, in secondary; the address in ink; one '
      'node heard, as it always was', (tester) async {
    final handle = tester.ensureSemantics();
    await openCarried(tester, long, scale: 1);

    expect(find.text('Compte :'), findsOneWidget, reason: 'its own line');
    expect(
      tester.widget<Text>(find.text('Compte :')).style?.color,
      AppColors.textSecondary,
      reason:
          'a label, the colour of « Entrez le code reçu par e-mail à » on '
          'the same screen (§5, decision 2)',
    );
    expect(
      tester.widget<Text>(drawnEmail(long)).style?.color,
      AppColors.textPrimary,
      reason: 'the address in ink',
    );
    expect(
      find.bySemanticsLabel('Compte : $long'),
      findsOneWidget,
      reason: 'one node, the words a screen reader always heard',
    );
    expect(
      find.bySemanticsLabel(RegExp('​')),
      findsNothing,
      reason: 'the break marks are drawn, never heard (§13.3)',
    );
    handle.dispose();
  });
}
