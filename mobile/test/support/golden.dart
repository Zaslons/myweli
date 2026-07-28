import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/core/theme/app_theme.dart';

import 'fonts.dart';
import 'surface.dart';

// A11 moved `stubSecureStorage` and `settleMocks` out, so `test/a11y/` can stub
// the channel and pump past the mocks without importing this file's `dart:io`
// and its Linux-only authority rule. Re-exported rather than re-imported at each
// call site: a dozen golden files already say `stubSecureStorage()` and
// `settleMocks(...)`, and none of them should have to change for a file move.
export 'fonts.dart' show kRealFont, loadRealFonts;
export 'secure_storage.dart' show stubSecureStorage;
export 'settle.dart' show settleMocks;

/// The golden-test harness (docs/design/SYSTEM.md §20).
///
/// Goldens are the only thing in this repo that renders the REAL design system:
/// none of the 34 widget tests passes `theme:`, so they would all stay green
/// while the product restyled underneath them. These catch what they can't.
///
/// ## Why goldens only run on Linux
///
/// Flutter rasterizes glyphs through CoreText on macOS and FreeType on Linux —
/// same font, same Skia, different pixels. A golden authored on a Mac fails in
/// CI forever. So **Linux is the sole authority**: CI (ubuntu, Flutter 3.38.6)
/// runs and gates them; everywhere else they SKIP with a reason. Regenerate with
/// `tool/update_goldens.sh` (the pinned Linux image).
///
/// To eyeball a change locally without committing it, run with
/// `MYWELI_GOLDEN_LOCAL=1` — but the committed bytes must come from Linux, and
/// CI will say so immediately if they don't.

/// Wrap every golden file's tests in `group('…', () {…}, skip: kGoldensSkip)`.
///
/// A `skip:` reason needs no `@TestOn` and no `dart_test.yaml` — it cannot
/// silently stop working, and off Linux the runner PRINTS the reason instead of
/// failing with a mystery pixel diff. (`group` takes an `Object? skip`, so it
/// carries the message; `testWidgets` only takes a `bool?`.)
final Object? kGoldensSkip =
    Platform.isLinux || Platform.environment['MYWELI_GOLDEN_LOCAL'] == '1'
        ? null
        : 'goldens are authored on Linux — run tool/update_goldens.sh '
            '(or MYWELI_GOLDEN_LOCAL=1 to preview locally, without committing)';

/// A phone — and **not the only surface that matters**, which is what this
/// comment used to say (A11).
///
/// §10 defines `compact` as a RANGE, and this is one point in it: 390 is an
/// iPhone 14, while the modal Android device in Côte d'Ivoire is **360**. Every
/// rendering test in this repo measured this width and only this width, which is
/// how eight layout defects shipped at 360 and 375 with 777 tests green. The
/// range is gated by `test/a11y/layout_test.dart`; **most** baselines stay at 390
/// because a golden's job is to notice a restyle, not to survey widths.
///
/// C7 added five that deliberately do not, and the distinction is the point: they
/// are not a survey, they are the **floor**, photographed once. They exist
/// because a gate cannot see everything a picture can — `tabAlignment` reddens
/// nothing in `flutter test`, and four of A11's fixes are identity at 1× — and
/// because five of the fixes were photographed by nothing at all. See §20.1.
const Size kGoldenPhone = Size(390, 844);

/// The theme every golden renders under — the real one, with the font pinned.
///
/// The loader itself moved to `fonts.dart` in A11: the width gate has to measure
/// the typeface the product ships, and the fallback `flutter_test` uses when no
/// font is loaded draws every glyph as a square of the font size — « Semaine »
/// and « Annulés » come out the same width, 79% too wide. That is harmless to a
/// picture (a golden loads the font) and fatal to a measurement.
ThemeData goldenTheme() => AppTheme.themeData(fontFamily: kRealFont);

/// Pins the surface. Restored after the test so nothing leaks into the next one.
///
/// A11 moved the body to `surface.dart` so `test/a11y/` can pin a width without
/// importing this file's `dart:io`. Same four lines, one home.
void goldenSurface(
  WidgetTester tester, {
  Size size = kGoldenPhone,
  double scale = 1.0,
}) =>
    pinSurface(tester, size: size, scale: scale);

/// The app shell a golden renders in: the real theme, French locale, no banner.
///
/// **A9: the `locale:` below was inert for the whole life of the baseline.**
/// With the default `supportedLocales: [Locale('en','US')]`,
/// `basicLocaleListResolution` cannot match `fr_FR` at any rung and falls
/// through to `supportedLocales.first` — **`en_US`** — which
/// `DefaultMaterialLocalizations` supports, so nothing ever complained. Every
/// golden was photographed in English localizations while claiming French.
Widget goldenApp({Widget? home, Widget? child}) => MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: goldenTheme(),
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      supportedLocales: const [Locale('fr', 'FR')],
      locale: const Locale('fr', 'FR'),
      home: home ?? Scaffold(body: child),
    );

/// Pumps a bare widget (the token catalogue: no DI, no async, no network).
Future<void> pumpGolden(
  WidgetTester tester,
  Widget child, {
  Size size = kGoldenPhone,
}) async {
  goldenSurface(tester, size: size);
  await tester.pumpWidget(goldenApp(child: child));
  await tester.pump();
}

/// Focuses the field under [finder] and lets the focus TRANSITION finish.
///
/// Flutter's `_BorderContainer` TWEENS between the enabled and focused borders,
/// and it only *starts* that tween on the frame where focus lands — so pumping
/// too few times renders frame 0 of it, i.e. still the OLD border. The result is
/// a focused field wearing its unfocused outline, and `borderFocus` — the app's
/// only focus indicator (SYSTEM.md §13.5) — never appearing in any golden.
///
/// This is not hypothetical: **the PR-0.5 baseline shipped exactly that bug.**
/// It is why the assertion below exists, and why the pump count is spelled out.
///
/// Focus goes straight to the node rather than through `tester.tap`, because a
/// tap also raises a text-selection handle — realistic, but noise in a sheet
/// whose subject is the border. The catch is that a tap consumes an extra frame
/// for free, and `requestFocus` does not: see the three pumps below.
Future<void> focusAndSettle(WidgetTester tester, Finder finder) async {
  final editable = find.descendant(
    of: finder,
    matching: find.byType(EditableText),
  );
  tester.widget<EditableText>(editable).focusNode.requestFocus();

  // THREE pumps, and every one of them is load-bearing:
  //   1. `FocusManager` applies the request in a microtask — i.e. AFTER this
  //      frame's build — so the field is not focused until it lands.
  //   2. Now the rebuild happens with `isFocused: true`, and only NOW does
  //      `_BorderContainer` start tweening enabled → focused. This frame still
  //      paints the OLD border (t=0 of the tween).
  //   3. …and this one runs the tween out.
  // Two pumps look like enough and are not: you get a focused field wearing its
  // unfocused border. (`tester.tap` hides this by consuming a frame internally,
  // which is why the tap-based version of this helper appeared to work.)
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));

  // ASSERT it, don't assume it. A golden cannot tell you it photographed the
  // wrong thing — it quietly becomes the new truth instead. This one already did:
  // the PR-0.5 baseline shipped a "focused" field that was never focused.
  final decorator = tester.widget<InputDecorator>(
    find.descendant(of: finder, matching: find.byType(InputDecorator)),
  );
  expect(
    decorator.isFocused,
    isTrue,
    reason:
        'the field never took focus — this golden would capture the ENABLED '
        'border and call it the focus ring',
  );
}

/// Captures the whole surface. [name] → `test/golden/goldens/<name>.png`.
Future<void> expectGolden(WidgetTester tester, String name) async {
  await expectLater(
    find.byType(MaterialApp),
    matchesGoldenFile('goldens/$name.png'),
  );
}

/// A labelled section, so a reviewer reading the PNG knows what they're looking
/// at without cross-referencing the source.
class GoldenSection extends StatelessWidget {
  const GoldenSection({super.key, required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.toUpperCase(),
            style: const TextStyle(
              fontFamily: kRealFont,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
              color: Color(0xFF8A8A8A),
            ),
          ),
          const SizedBox(height: AppTheme.spacingS),
          child,
          const SizedBox(height: AppTheme.spacingL),
        ],
      );
}
