import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/core/theme/text_styles.dart';
import 'package:myweli/core/utils/formatters.dart';
import 'package:myweli/providers/auth_provider.dart';
import 'package:myweli/providers/pro_auth_provider.dart';
import 'package:myweli/screens/auth/login_screen.dart';
import 'package:myweli/screens/provider/android/pro_sign_up_screen.dart';
import 'package:myweli/screens/provider/auth/pro_login_screen.dart';
import 'package:myweli/widgets/common/phone_number_field.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fonts.dart';
import '../support/pro_sign_up.dart' show input, tapOn;
import '../support/secure_storage.dart';
import '../support/settle.dart';
import '_a11y.dart';

/// « Entrez le code reçu par e-mail à » / {adresse}, on the three sign-in
/// screens' code steps (docs/design/account-email-change.md §12 — found by
/// B16.3b's golden), at the floor and 200 % text, in the real font.
///
/// **What was broken, measured** (360 dp × 2×, a line is 312 px): an address
/// wider than a line — about 18 characters, so most real ones — began on the
/// line « à » had started and was cut where the line ran out: « par e-mail à
/// aminata. » / « kone@exemple.ci. ». A SHORT address was never cut (the
/// engine moves a word that fits a line to the next one, whole): the change
/// for it is the agreed shape — a line of its own, no period drawn after it.
///
/// The change screen's two sentences and « Modifier le profil »'s row are
/// gated in `email_change_screen_test.dart`, where their pumps live.
void main() {
  setUpAll(() async {
    await loadRealFonts();
    SharedPreferences.setMockInitialValues({});
    stubSecureStorage();
    setupDependencyInjection(); // every service, all mocks
  });

  const at = '360 dp × 2×';

  /// Wider than a line: its name part and its domain each fit one.
  const long = 'aminata.kone@exemple.ci';

  /// Wider than a line by a hair (313 px): break points before EVERY « . »
  /// orphan its « .com ».
  const seam = 'koffi.yao@gmail.com';

  /// Fits a line (248 px): never cut, and now on a line of its own.
  const short = 'awa@exemple.ci';

  String spoken(String address) => 'Entrez le code reçu par e-mail à $address.';

  Future<void> send(WidgetTester tester, String address) async {
    await tester.enterText(input('Votre e-mail'), address);
    await tester.pump();
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await tapOn(tester, find.text('Continuer avec e-mail'));
    await settleMocks(tester, rounds: 2);
    expect(find.text('Code à 6 chiffres'), findsOneWidget);
  }

  Future<void> consumer(WidgetTester tester, String address) async {
    await pumpAtWidth(
      tester,
      width: 360,
      scale: 2,
      home: const LoginScreen(),
      providers: [ChangeNotifierProvider(create: (_) => AuthProvider())],
    );
    await send(tester, address);
  }

  Future<void> pro(WidgetTester tester, String address) async {
    await pumpAtWidth(
      tester,
      width: 360,
      scale: 2,
      home: const ProLoginScreen(),
      providers: [ChangeNotifierProvider(create: (_) => ProAuthProvider())],
    );
    await send(tester, address);
  }

  Future<void> signUp(WidgetTester tester, String address) async {
    await pumpPushedAtWidth(
      tester,
      width: 360,
      scale: 2,
      height: 3200,
      subject: const ProSignUpScreen(),
      providers: [ChangeNotifierProvider(create: (_) => ProAuthProvider())],
    );
    await tester.enterText(input('Nom de l’entreprise'), 'Salon Awa');
    await tapOn(tester, find.text('Institut de manucure'));
    await tester.enterText(
      find.descendant(
        of: find.byType(PhoneNumberField),
        matching: find.byType(TextField),
      ),
      '0707010101',
    );
    await tester.enterText(input('Adresse'), 'Rue des Jardins, Cocody');
    await send(tester, address);
  }

  final sites = {
    'the sign-in': consumer,
    'the Pro sign-in': pro,
    'the Android Pro sign-up': signUp,
  };

  for (final MapEntry(key: site, value: open) in sites.entries) {
    group('$site\'s code step, at $at', () {
      testWidgets('a long address breaks at its « @ », on a line of its own', (
        tester,
      ) async {
        await open(tester, long);
        expectEmailAddressOnItsOwnLine(tester, long, '$site, $at');
      });

      testWidgets('its domain stays whole', (tester) async {
        await open(tester, seam);
        expectEmailAddressOnItsOwnLine(tester, seam, '$site, $at');
      });

      testWidgets('a short address: a line of its own, read as one sentence', (
        tester,
      ) async {
        final handle = tester.ensureSemantics();
        await open(tester, short);
        expectEmailAddressOnItsOwnLine(tester, short, '$site, $at');
        // A screen reader hears the sentence it always heard, period and all,
        // with no break mark in it.
        expect(find.bySemanticsLabel(spoken(short)), findsOneWidget);
        handle.dispose();
      });
    });
  }

  // The gate's own falsifiers: each wrong drawing must fail it, and for ITS
  // reason. On correct code a check has nothing to catch, so without these a
  // check could be deleted and every test above stay green (the mutation run
  // found exactly that for the seam check).
  group('expectEmailAddressOnItsOwnLine fails a wrong drawing', () {
    Future<void> draw(WidgetTester tester, String text) => pumpAtWidth(
      tester,
      width: 360,
      scale: 2,
      home: Scaffold(
        // The product's size: at the theme's default 14 px, « koffi.yao@gmail.com »
        // fits a line and there is no break to judge.
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(text, style: AppTextStyles.bodyLarge),
        ),
      ),
    );

    void fails(WidgetTester tester, String address, String because) => expect(
      () => expectEmailAddressOnItsOwnLine(tester, address, 'instrument'),
      throwsA(
        isA<TestFailure>().having(
          (e) => e.message,
          'message',
          contains(because),
        ),
      ),
    );

    testWidgets('cut inside a word', (tester) async {
      await draw(tester, long);
      fails(tester, long, 'being broken mid-word');
    });

    testWidgets('broken at the wrong seam: « .com » orphaned', (tester) async {
      await draw(tester, 'koffi\u200B.yao\u200B@gmail\u200B.com');
      fails(tester, seam, 'breaks between');
    });

    testWidgets('started on the line the sentence began', (tester) async {
      await draw(
        tester,
        'Entrez le code reçu par e-mail à aminata\u200B.kone\u200B@exemple.ci',
      );
      fails(tester, long, 'starts on the line');
    });

    testWidgets('a period drawn after it', (tester) async {
      await draw(tester, 'awa\u200B@exemple.ci.');
      fails(tester, short, 'is drawn after');
    });

    testWidgets('control: the app\'s own marks pass', (tester) async {
      await draw(tester, Formatters.breakableEmail(seam));
      expectEmailAddressOnItsOwnLine(tester, seam, 'instrument');
    });
  });
}
