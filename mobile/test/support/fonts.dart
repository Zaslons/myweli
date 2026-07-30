import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show FontLoader;

/// The typeface the tests pin text metrics to.
///
/// Roboto is Android's system font — our primary target — and it ships INSIDE
/// the Flutter SDK, which CI pins to the same version. So the bytes on the
/// runner are the bytes here: nothing is vendored, and it can never drift from
/// the SDK.
const String kRealFont = 'Roboto';

bool _fontsLoaded = false;

/// Whether [loadRealFonts] has run in this isolate.
///
/// Exposed so a test that MEASURES text can refuse to run without it. Without
/// the real font, `flutter_test` falls back to a placeholder whose every glyph
/// is a square of the font size — see [loadRealFonts].
bool get realFontsLoaded => _fontsLoaded;

/// Loads Roboto + MaterialIcons from the SDK's own font cache.
///
/// Call from `setUpAll` — it cannot be called from inside a `testWidgets` body,
/// because it awaits real file I/O and `testWidgets` runs in a fake-async zone
/// where a real `Future` never completes. Deliberately NOT called from a global
/// `flutter_test_config.dart`: fonts are process-global, and loading them under
/// every test would change text metrics for no reason.
///
/// ## Why a test that measures WIDTH cannot skip this (A11)
///
/// Without it, Flutter renders through a built-in fallback in which **every
/// glyph is a square of the font size**. That is fine for the assertions this
/// repo made until now — contrast, tap targets, "did the height grow at 2×" —
/// because all of them are relative or non-textual. It is fatal to an absolute
/// width assertion, and the numbers are not close:
///
/// | label           | fallback | Roboto  |
/// |-----------------|----------|---------|
/// | « Aujourd'hui » | 155.1dp  |  72.2dp |
/// | « Semaine »     |  98.7dp  |  55.3dp |
/// | « À venir »     |  98.7dp  |  44.1dp |
/// | « Annulés »     |  98.7dp  |  51.4dp |
///
/// The three seven-letter words measuring **identically to a tenth of a pixel**
/// is the tell. A11's width gate first ran against the fallback and reported
/// « Semaine » as clipped in a 58dp tab — it needs 55.3dp and fits. Three of its
/// four first-round truncation findings were that artefact, and "fixing" them
/// would have been a change to the product justified by a font the product does
/// not ship.
///
/// Metrics — unlike rasterisation, which is why goldens are Linux-only — come
/// from the font file through the same shaper on every platform, so this is safe
/// in a suite that runs everywhere.
Future<void> loadRealFonts() async {
  if (_fontsLoaded) return;

  final fonts =
      Directory('${_flutterRoot()}/bin/cache/artifacts/material_fonts');
  if (!fonts.existsSync()) {
    throw StateError(
      'Font cache not found at ${fonts.path}. Goldens and the width gate need '
      'the SDK fonts; run `flutter precache` or check FLUTTER_ROOT.',
    );
  }

  // Every weight the type scale asks for (w400 body, w500 label/title,
  // w600 headline, bold display) — so the engine picks by weight rather than
  // faking one, and a semibold heading actually renders semibold.
  await _load(kRealFont, fonts, const [
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
