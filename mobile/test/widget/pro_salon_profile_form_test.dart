import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/models/api_response.dart';
import 'package:myweli/models/pro_membership.dart';
import 'package:myweli/models/provider.dart' as models;
import 'package:myweli/models/team_member.dart';
import 'package:myweli/providers/pro_auth_provider.dart';
import 'package:myweli/providers/pro_salon_profile_provider.dart';
import 'package:myweli/screens/provider/profile/pro_salon_profile_screen.dart';
import 'package:myweli/services/interfaces/pro_service_interface.dart';
import 'package:myweli/services/mock/mock_auth_service.dart';
import 'package:myweli/services/mock/mock_data.dart';
import 'package:myweli/services/mock/mock_provider_service.dart';
import 'package:myweli/widgets/common/carto_basemap_layer.dart';
import 'package:myweli/widgets/common/phone_number_field.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/pump_app.dart';

class _MockProService extends Mock implements ProServiceInterface {}

/// The screen resolves its salon from the session (R6 — `activeSalonId`, never
/// `provider.id`). A full pro sign-in would only be a slower way to say this.
class _SignedInAuth extends ProAuthProvider {
  @override
  String? get activeSalonId => 'provider1';
}

/// The seeded salon the form loads — « Salon Excellence », phone and WhatsApp
/// both stored in E.164.
models.Provider seededSalon() =>
    MockData.providers.firstWhere((p) => p.id == 'provider1');

/// A7 « Profil du salon » (SYSTEM.md §14 / §21 row 19, docs/design/
/// mobile-a7-forms.md) — **the per-funnel gate §20 claims, made real for the
/// salon profile.**
///
/// Two defects live here, and neither had a test.
///
/// 1. « Le nom est requis » was a **SNACKBAR** — §14 rule 3's textbook
///    violation: a field-level fault in a bar that names no field, scrolls to
///    nothing and vanishes on a timer. It is now `errorText: _errors['name']`
///    reading « Indiquez le nom du salon. ».
/// 2. **The lockout.** A7's first pass validated the phone/WhatsApp fields as
///    10 LOCAL digits, while the controllers are prefilled from the stored
///    value — which `openapi.yaml` specifies as **E.164** (`+225 …`). The rule
///    could never match the data the app had just loaded, so pressing
///    « Enregistrer » on an untouched form failed on a field the salon had
///    never typed in: the profile could not be saved again, at all. It now uses
///    `Validators.phoneNumber` (E.164; exactly 10 digits after +225 since
///    phone-national-length.md), in a `PhoneNumberField` each.
///
/// The shape asserted is §14's: the press **answers under the field it belongs
/// to** (rule 1) · **no `SnackBar`** (rule 3) · nothing is saved and the flow
/// does not advance · fixing the value clears the message **without a second
/// submit** (rule 2). Plus the one nothing in the suite held: **a form the app
/// just filled from the server must still validate.**
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _MockProService pro;

  setUpAll(() {
    registerFallbackValue(<String, dynamic>{});
    SharedPreferences.setMockInitialValues({});
    serviceLocator.authService = MockAuthService();
    // The LOAD side still yields the SEEDED salon: the lockout test is only
    // meaningful if the form is prefilled exactly as production fills it
    // (E.164 « +2250711223344 »). What changed is the door — the screen
    // reads its own salon by account now (`GET /me/provider`), not through the
    // public `getProviderById`, so the seed arrives through `getMyProvider`.
    serviceLocator.providerService = MockProviderService();
    pro = _MockProService();
    serviceLocator.proService = pro;
  });

  setUp(() {
    reset(pro);
    when(
      () => pro.updateSalonProfile(any(), any()),
    ).thenAnswer((_) async => ApiResponse.success(seededSalon()));
    when(() => pro.getMyProvider()).thenAnswer(
      (_) async => ApiResponse.success(
        MyProviderInfo(
          salon: seededSalon(),
          membership: ProMembership(
            role: TeamRole.owner,
            capabilities: presetCapabilitiesFor(TeamRole.owner),
            salonId: seededSalon().id,
            salonName: seededSalon().name,
          ),
        ),
      ),
    );
  });

  Widget app() {
    final router = GoRouter(
      initialLocation: '/pro/profile',
      routes: [
        GoRoute(
          path: '/pro/profile',
          builder: (context, _) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => context.push('/pro/salon-profile'),
                child: const Text('PROFIL'),
              ),
            ),
          ),
        ),
        GoRoute(
          path: '/pro/salon-profile',
          builder: (_, _) => const ProSalonProfileScreen(),
        ),
      ],
    );
    return wrapApp(
      providers: [
        ChangeNotifierProvider<ProAuthProvider>(create: (_) => _SignedInAuth()),
        ChangeNotifierProvider(create: (_) => ProSalonProfileProvider()),
      ],
      routerConfig: router,
    );
  }

  /// Advance past the mock latency without pumpAndSettle (the brand loader
  /// animates forever, so pumpAndSettle would never settle mid-load).
  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
  }

  /// Push the screen the way the pro app does (from « Profil ») and let the
  /// listing land, so every field is prefilled from the server payload.
  ///
  /// A tall surface, because the form is one long `ListView` ending in the
  /// map and « Enregistrer » — off-screen at 800×600, and a test that has to
  /// scroll past a `FlutterMap` to reach the submit is a test about scrolling.
  Future<void> openForm(WidgetTester tester, {double width = 1000}) async {
    tester.view.physicalSize = Size(width, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(app());
    await settle(tester);
    await tester.tap(find.text('PROFIL'));
    await settle(tester);
    await settle(tester);

    expect(
      find.text('Profil du salon'),
      findsOneWidget,
      reason: 'the form must be on screen before anything is asserted',
    );
  }

  // Field order in the ListView: nom · description · adresse ·
  // (commune is a picker row, not a field) · téléphone · WhatsApp.
  Finder nameField() => find.byType(TextField).at(0);

  testWidgets('an empty name answers UNDER the field — the « nom » fault is no '
      'longer a snackbar', (tester) async {
    await openForm(tester);

    expect(
      find.text('Salon Excellence'),
      findsOneWidget,
      reason: 'the name field is prefilled from the loaded listing',
    );

    // The logo field heads the form (salon-logo.md §2) — « Ajouter un logo »
    // for a salon without one; the affordance existing at all is the point,
    // logoUrl having been displayed-but-never-settable since the audit
    // parked it.
    expect(find.text('Ajouter un logo'), findsOneWidget);

    // Clear it and submit. Rule 5 keeps « Enregistrer » live, so the press
    // MUST answer rather than silently do nothing.
    await tester.enterText(nameField(), '');
    await tester.pump();
    await tester.tap(find.text('Enregistrer'));
    await settle(tester);

    expect(
      find.text('Indiquez le nom du salon.'),
      findsOneWidget,
      reason: 'the fault renders under the field it belongs to (§14 rule 1)',
    );
    expect(
      find.byType(SnackBar),
      findsNothing,
      reason:
          '§14 rule 3 — a field fault is never a bar, and this exact '
          'message used to BE one (« Le nom est requis »)',
    );
    verifyNever(() => pro.updateSalonProfile(any(), any()));
    expect(
      find.text('Profil du salon'),
      findsOneWidget,
      reason: 'a refused submit must not pop back to « Profil »',
    );

    // Rule 2: fixing it clears the message without another submit.
    await tester.enterText(nameField(), 'Salon Excellence');
    await tester.pump();
    expect(
      find.text('Indiquez le nom du salon.'),
      findsNothing,
      reason: '§14 rule 2 — the message clears on change, not on re-submit',
    );
  });

  // « Téléphone » and « WhatsApp » are [PhoneNumberField]s since
  // phone-national-length.md: the free-text fields showed a hint (« Ex : 07 07
  // 12 34 56 ») the rule refused, and checked a separator-free value while
  // sending the raw one — which the server refuses.
  Finder phoneInput(int i) => find.descendant(
    of: find.byType(PhoneNumberField).at(i),
    matching: find.byType(TextField),
  );
  Finder phone() => phoneInput(0);
  Finder whatsapp() => phoneInput(1);

  Finder under(int i, String message) => find.descendant(
    of: find.byType(PhoneNumberField).at(i),
    matching: find.text(message),
  );

  const tenDigits = 'Le numéro doit comporter 10 chiffres après +225.';

  /// The body of the one `updateSalonProfile` call.
  Map<String, dynamic> sentBody() =>
      verify(
            () => pro.updateSalonProfile('provider1', captureAny()),
          ).captured.single
          as Map<String, dynamic>;

  testWidgets('THE LOCKOUT: an untouched form saves — the stored E.164 numbers '
      'pass their own rule', (tester) async {
    await openForm(tester);

    // The precondition that made the 10-local-digit rule unsatisfiable: the
    // phone AND the WhatsApp field are prefilled from E.164 (openapi.yaml), by
    // the app itself, before the salon touches anything — each shown as its
    // national part under +225.
    expect(find.byType(PhoneNumberField), findsNWidgets(2));
    for (final i in [0, 1]) {
      expect(
        tester.widget<TextField>(phoneInput(i)).controller?.text,
        '0711223344',
        reason: 'téléphone + WhatsApp both prefilled from the stored listing',
      );
    }

    // Press save having changed NOTHING. This is the whole regression: a
    // salon opening its profile and pressing « Enregistrer ».
    await tester.tap(find.text('Enregistrer'));
    await settle(tester);
    await settle(tester);

    expect(
      find.text('Saisissez un numéro de téléphone valide.'),
      findsNothing,
      reason:
          'THE LOCKOUT — a rule that rejects the value the app just '
          'loaded locks the salon out of its own profile forever',
    );
    expect(
      find.text('Saisissez un numéro de téléphone.'),
      findsNothing,
      reason: 'the field is not empty either — it is prefilled',
    );
    expect(
      find.text('Indiquez le nom du salon.'),
      findsNothing,
      reason: 'nothing on an untouched, server-filled form may fail',
    );

    final body = sentBody();
    expect(
      [body['phoneNumber'], body['whatsapp']],
      ['+2250711223344', '+2250711223344'],
      reason: 'what was checked is what is sent — E.164, no separator',
    );
    expect(
      find.text('PROFIL'),
      findsOneWidget,
      reason:
          'a saved profile pops back to « Profil » (A6: success is a '
          'bar + a pop, not a dead screen)',
    );
  });

  testWidgets('a short phone answers under ITS field', (tester) async {
    await openForm(tester);

    // Seven national digits — the number the consumer sign-in saved on
    // 2026-10-15 — refused under the phone field, not in a bar.
    await tester.enterText(phone(), '0711223');
    await tester.pump();
    await tester.tap(find.text('Enregistrer'));
    await settle(tester);

    expect(
      under(0, tenDigits),
      findsOneWidget,
      reason: 'the message sits under téléphone, saying what to do',
    );
    expect(
      find.byType(SnackBar),
      findsNothing,
      reason: '§14 rule 3 — a field fault is never a bar',
    );
    verifyNever(() => pro.updateSalonProfile(any(), any()));

    await tester.enterText(phone(), '0711223344');
    await tester.pump();
    expect(
      find.text(tenDigits),
      findsNothing,
      reason: '§14 rule 2 — cleared on change, without a second submit',
    );
  });

  testWidgets('WhatsApp is OPTIONAL — an empty one does not block the save', (
    tester,
  ) async {
    await openForm(tester);

    // The optional field's own trap: reusing the required phone rule here
    // would refuse every salon without a WhatsApp number.
    await tester.enterText(whatsapp(), '');
    await tester.pump();
    await tester.tap(find.text('Enregistrer'));
    await settle(tester);
    await settle(tester);

    expect(
      find.text('Saisissez un numéro de téléphone.'),
      findsNothing,
      reason:
          'blank WhatsApp passes — only a typed one must be a real '
          'number',
    );
    expect(
      sentBody()['whatsapp'],
      '',
      reason: 'emptied, it is sent empty — the server clears it',
    );
  });

  testWidgets('a typed WhatsApp is judged like the phone — under ITS field', (
    tester,
  ) async {
    await openForm(tester);

    await tester.enterText(whatsapp(), '0711223');
    await tester.pump();
    await tester.tap(find.text('Enregistrer'));
    await settle(tester);

    expect(under(1, tenDigits), findsOneWidget);
    expect(under(0, tenDigits), findsNothing, reason: 'not under téléphone');
    verifyNever(() => pro.updateSalonProfile(any(), any()));
  });

  // ---- phone-leftovers.md §2: the server's verdict, under ITS field -------
  //
  // `PATCH /providers/{id}` refused either number as `invalid_input` — the
  // code of every other field too — so the screen could only print
  // « Informations invalides. » in a bar that named no field. Two phone fields
  // on one form: the server now says which, `invalid_phone` (téléphone) or
  // `invalid_whatsapp`.

  const refusedNumber = 'Saisissez un numéro de téléphone valide.';

  /// The save refused by the server under [code], with the message
  /// `ApiProService._messageFor` gives it.
  void refuseSave(String code, String message) => when(
    () => pro.updateSalonProfile(any(), any()),
  ).thenAnswer((_) async => ApiResponse.error(message, code: code));

  testWidgets('the server\'s `invalid_phone` lands under « Téléphone », not in '
      'a bar', (tester) async {
    refuseSave(
      'invalid_phone',
      'Numéro invalide (format international, ex. +2250700000000).',
    );
    await openForm(tester);

    await tester.tap(find.text('Enregistrer'));
    await settle(tester);

    verify(() => pro.updateSalonProfile(any(), any())).called(1);
    expect(
      under(0, refusedNumber),
      findsOneWidget,
      reason: '§14 rule 1 — under the field the server refused',
    );
    expect(under(1, refusedNumber), findsNothing, reason: 'not under WhatsApp');
    expect(
      find.byType(SnackBar),
      findsNothing,
      reason: '§14 rule 3 — a field fault is never a bar',
    );
    expect(
      find.text('Profil du salon'),
      findsOneWidget,
      reason: 'a refused save does not pop',
    );

    // Rule 2: a changed number that passes the client rule clears it.
    await tester.enterText(phone(), '0711223355');
    await tester.pump();
    expect(find.text(refusedNumber), findsNothing);
  });

  testWidgets('the server\'s `invalid_whatsapp` lands under « WhatsApp », not '
      'under « Téléphone »', (tester) async {
    refuseSave('invalid_whatsapp', 'Une erreur est survenue.');
    await openForm(tester);

    await tester.tap(find.text('Enregistrer'));
    await settle(tester);

    verify(() => pro.updateSalonProfile(any(), any())).called(1);
    expect(under(1, refusedNumber), findsOneWidget);
    expect(
      under(0, refusedNumber),
      findsNothing,
      reason: 'the code says which of the two numbers',
    );
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('any other refusal is still the bar it was', (tester) async {
    refuseSave('invalid_input', 'Informations invalides.');
    await openForm(tester);

    await tester.tap(find.text('Enregistrer'));
    await settle(tester);

    expect(
      find.widgetWithText(SnackBar, 'Informations invalides.'),
      findsOneWidget,
    );
    expect(find.text(refusedNumber), findsNothing);
  });

  // The position map is a fixed 240dp box. flutter_map's own credits popup
  // opened INSIDE it and overflowed at 2× text on a phone (140px), and the
  // « Utiliser ma position » row overflowed sideways from 1.5× (134px; 272 at
  // 2×) — both measured at 390dp, invisible on the 1000dp surface the other
  // tests use. The credits now open in a sheet and the row wraps.
  for (final scale in [1.5, 2.0]) {
    testWidgets(
      'at $scale× on a phone: the form fits, and the map credits « i » '
      'opens a sheet with the credits whole',
      (tester) async {
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await openForm(tester, width: 390);
        expect(tester.takeException(), isNull, reason: 'the form at $scale×');

        final info = find.descendant(
          of: find.byType(FlutterMap),
          matching: find.byTooltip(CartoAttribution.sheetTooltip),
        );
        expect(info, findsOneWidget, reason: 'the credits button on the map');
        await tester.ensureVisible(info);
        await tester.pump();
        await tester.tap(info);
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        final sheet = find.byType(BottomSheet);
        expect(sheet, findsOneWidget);
        for (final credit in [CartoAttribution.sheetTitle, ...cartoCredits]) {
          final text = find.descendant(of: sheet, matching: find.text(credit));
          expect(text, findsOneWidget, reason: credit);
          expect(
            tester.renderObject<RenderParagraph>(text).didExceedMaxLines,
            isFalse,
            reason: credit,
          );
        }
      },
    );
  }
}
