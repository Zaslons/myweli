import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader, MethodChannel;
import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/core/theme/app_theme.dart';

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

/// A phone. The apps have no breakpoints (SYSTEM.md §10), so this is the only
/// surface that matters today.
const Size kGoldenPhone = Size(390, 844);

/// The typeface goldens are pinned to. Roboto is Android's system font — our
/// primary target — and it ships INSIDE the Flutter SDK, which CI pins to the
/// same version. So the bytes on the runner are the bytes here: nothing is
/// vendored, and it can never drift from the SDK.
const String kGoldenFont = 'Roboto';

/// The theme every golden renders under — the real one, with the font pinned.
ThemeData goldenTheme() => AppTheme.themeData(fontFamily: kGoldenFont);

bool _fontsLoaded = false;

/// Loads Roboto + MaterialIcons from the SDK's own font cache.
///
/// Call from `setUpAll` in each golden file — deliberately NOT from a global
/// `flutter_test_config.dart`: fonts are process-global, and loading them under
/// the other 115 tests would change text metrics for no reason.
Future<void> loadGoldenFonts() async {
  if (_fontsLoaded) return;

  final fonts =
      Directory('${_flutterRoot()}/bin/cache/artifacts/material_fonts');
  if (!fonts.existsSync()) {
    throw StateError(
      'Font cache not found at ${fonts.path}. Goldens need the SDK fonts; '
      'run `flutter precache` or check FLUTTER_ROOT.',
    );
  }

  // Every weight the type scale asks for (w400 body, w500 label/title,
  // w600 headline, bold display) — so the engine picks by weight rather than
  // faking one, and a semibold heading actually renders semibold.
  await _load(kGoldenFont, fonts, const [
    'Roboto-Thin.ttf',
    'Roboto-Light.ttf',
    'Roboto-Regular.ttf',
    'Roboto-Medium.ttf',
    'Roboto-Bold.ttf',
    'Roboto-Black.ttf',
  ]);
  // Without this every Icon renders as an empty box.
  await _load('MaterialIcons', fonts, const ['MaterialIcons-Regular.otf']);

  _fontsLoaded = true;
}

Future<void> _load(String family, Directory dir, List<String> files) async {
  final loader = FontLoader(family);
  for (final name in files) {
    loader.addFont(
      File('${dir.path}/$name').readAsBytes().then(
            (bytes) => ByteData.view(Uint8List.fromList(bytes).buffer),
          ),
    );
  }
  await loader.load();
}

/// `FLUTTER_ROOT` is set for the test process; if it ever isn't, the tester
/// binary itself lives at `<root>/bin/cache/artifacts/engine/<plat>/flutter_tester`.
String _flutterRoot() {
  final env = Platform.environment['FLUTTER_ROOT'];
  if (env != null && env.isNotEmpty) return env;
  var dir = File(Platform.resolvedExecutable).parent; // .../engine/<plat>
  for (var i = 0; i < 4; i++) {
    dir = dir.parent; // engine → artifacts → cache → bin → <root>
  }
  return dir.path;
}

/// Makes the session store answer "no session" instead of throwing.
///
/// The store is `flutter_secure_storage` — a platform channel with no
/// implementation in a test process. A real `read()` throws
/// `MissingPluginException`, `AuthProvider` catches it into `error`, and the
/// login screen dutifully renders that string **in red, on the screen**. The
/// other 34 widget tests never noticed, because they assert on finders; a golden
/// photographs everything, including the things nobody was looking at.
///
/// Stubbing it makes a signed-out session read as what it actually is: nothing.
void stubSecureStorage() {
  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (call) async {
    switch (call.method) {
      case 'readAll':
        return <String, String>{};
      case 'containsKey':
        return false;
      default:
        return null; // read / write / delete
    }
  });
}

/// Pins the surface. Restored after the test so nothing leaks into the next one.
void goldenSurface(WidgetTester tester, {Size size = kGoldenPhone}) {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// The app shell a golden renders in: the real theme, French locale, no banner.
Widget goldenApp({Widget? home, Widget? child}) => MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: goldenTheme(),
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

/// Advances past the mocks' latency WITHOUT `pumpAndSettle`.
///
/// The mocks sleep [AppConstants.mockDelay] (300ms) and the loading state is an
/// infinitely-repeating Lottie (`BrandLoader`) — so `pumpAndSettle()` never
/// returns while a screen is loading. 16 widget-test files already hand-roll
/// this; it is the house idiom, named at last. [rounds] = the number of
/// SEQUENTIAL mock calls the screen chains before it settles.
Future<void> settleMocks(WidgetTester tester, {int rounds = 1}) async {
  await tester.pump();
  for (var i = 0; i < rounds; i++) {
    await tester.pump(const Duration(milliseconds: 400));
  }
  await tester.pump();
}

/// Focuses the field under [finder] and lets the focus TRANSITION finish.
///
/// The two pumps are not superstition. Flutter's `_BorderContainer` TWEENS
/// between the enabled and focused borders, and it only *starts* that animation
/// on the frame where focus lands — so a single `pump(400ms)` renders frame 0
/// of the tween, i.e. still the OLD border. One pump applies the focus, a second
/// runs the animation out. Get this wrong and a "focused" golden silently
/// captures an UNFOCUSED field — and `borderFocus`, the app's only focus
/// indicator (SYSTEM.md §13.5), would never appear in any golden.
///
/// Focus goes straight to the node rather than through `tester.tap`, because a
/// tap also raises a text-selection handle — realistic, but noise in a sheet
/// whose subject is the border.
Future<void> focusAndSettle(WidgetTester tester, Finder finder) async {
  final editable = find.descendant(
    of: finder,
    matching: find.byType(EditableText),
  );
  tester.widget<EditableText>(editable).focusNode.requestFocus();
  await tester.pump(); // focus lands; the border tween STARTS
  await tester.pump(const Duration(milliseconds: 400)); // …and completes
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
              fontFamily: kGoldenFont,
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
