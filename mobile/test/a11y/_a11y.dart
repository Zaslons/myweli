import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/core/theme/app_theme.dart';
import 'package:provider/single_child_widget.dart';

import '../support/fonts.dart';
import '../support/pump_app.dart';
import '../support/settle.dart';
import '../support/surface.dart';

/// The accessibility gate (docs/design/SYSTEM.md §13.4 / §20). Flutter ships the
/// `AccessibilityGuideline`s — `androidTapTargetGuideline` (≥48×48),
/// `labeledTapTargetGuideline` (every tap target has a semantics label),
/// `textContrastGuideline` — we simply had not been calling them. Unlike the
/// goldens these are **platform-agnostic**, so they run everywhere (no
/// `kGoldensSkip`): the same assertion on macOS and on the CI runner.
///
/// Usage:
/// ```dart
/// final handle = await pumpForA11y(tester, const MyWidget());
/// await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
/// handle.dispose();
/// ```
/// The caller disposes the returned handle after the expect.
Future<SemanticsHandle> pumpForA11y(
  WidgetTester tester,
  Widget child, {
  List<SingleChildWidget>? providers,
}) async {
  final handle = tester.ensureSemantics();
  await pumpApp(tester, home: Scaffold(body: child), providers: providers);
  await tester.pumpAndSettle();
  return handle;
}

/// Pumps [child] with the OS text scale turned up (SYSTEM.md §13.3 — 200% is a
/// first-class input, not an edge case). The `Builder` sits UNDER the MaterialApp
/// so this MediaQuery overrides the app's own.
///
/// A layout that can't grow throws a `RenderFlex` overflow during layout, which
/// the test binding records — so the assertion is simply:
/// ```dart
/// await pumpAtTextScale(tester, const MyWidget());
/// expect(tester.takeException(), isNull);
/// ```
/// Pumps [child] at 1× and again at [scale], and asserts the laid-out height of
/// [finder] actually **grew**.
///
/// This is the assertion `takeException` cannot make. A box with a *fixed* height
/// around text (`SizedBox(height: 50)`) doesn't overflow — it **clips, silently**:
/// no `RenderFlex` error, no exception, just text the user can't read. The tell is
/// that its height is identical at 1× and 2×. So: text-bearing layouts must grow
/// with the OS text scale (§13.3).
///
/// Give [child] an **unbounded vertical axis** (wrap it in a `SingleChildScrollView`)
/// unless it already sizes to its content. A widget whose `Column` fills the
/// Scaffold body measures the 600px *viewport* at both scales, and this reports
/// "it did not grow" about the screen rather than the widget — a false alarm that
/// reads exactly like a real clip.
Future<void> expectGrowsWithTextScale(
  WidgetTester tester,
  Widget child,
  Finder finder, {
  double scale = 2.0,
  List<SingleChildWidget>? providers,
}) async {
  await pumpAtTextScale(tester, child, scale: 1, providers: providers);
  final baseline = tester.getSize(finder).height;
  await pumpAtTextScale(tester, child, scale: scale, providers: providers);
  final scaled = tester.getSize(finder).height;
  expect(
    scaled,
    greaterThan(baseline),
    reason: 'height is $baseline at 1× and $scaled at $scale× — it did not '
        'grow, so the text is being clipped by a fixed bound (§13.3).',
  );
}

Future<void> pumpAtTextScale(
  WidgetTester tester,
  Widget child, {
  double scale = 2.0,
  List<SingleChildWidget>? providers,
}) async {
  await pumpApp(
    tester,
    providers: providers,
    home: Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(scale),
        ),
        child: Scaffold(body: child),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

// ---------------------------------------------------------------------------
// A11 — the §10 width gate
// ---------------------------------------------------------------------------

/// Pumps a WHOLE SCREEN at a pinned width and OS text scale (SYSTEM.md §10).
///
/// **Why this is not `pumpAtTextScale` with a width argument**, though that is
/// the obvious refactor and the next reader will propose it:
///
/// 1. `pumpAtTextScale` wraps its subject in `Scaffold(body: child)`. That is
///    right for a component and wrong for a screen — every subject here already
///    has its own `Scaffold`, and nesting them gives the inner one a body inset
///    by the outer one's padding, i.e. a width the product never renders at.
/// 2. It injects the scale through a `MediaQuery` placed at `home:`. Three of
///    the eight subjects are built by a `routerConfig`, where there is no `home:`
///    to wrap — a `MediaQuery` there cannot reach the screen at all, and the
///    test would silently measure 1× while its name said 2×.
///
/// So the scale goes in at the platform dispatcher instead, which
/// `MediaQueryData.fromView` reads through `SystemTextScaler`
/// (`media_query.dart:319-321`) no matter how the subtree was built.
///
/// [height] defaults to a tall 1600 on purpose. Overflow is reported from
/// `paint` (`flex.dart`), not from layout — so a row that never gets painted
/// because a short viewport scrolled it away is a row this gate cannot see. A
/// tall surface builds more of the screen and paints more of what it built.
///
/// The theme is [AppTheme.themeData] with the font PINNED, and the caller must
/// have run `loadRealFonts()` in `setUpAll` — asserted below rather than
/// assumed, because the failure mode is silent: with no font loaded Flutter
/// draws every glyph as a square of the font size, and this gate would measure
/// labels up to 79% too wide (test/support/fonts.dart carries the table).
/// `loadRealFonts` cannot be awaited from here — it does real file I/O, and a
/// `testWidgets` body runs in a fake-async zone where that never completes.
///
/// Never `pumpAndSettle`: see [settleMocks].
Future<void> pumpAtWidth(
  WidgetTester tester, {
  required double width,
  double scale = 1.0,
  double height = 1600,
  Widget? home,
  RouterConfig<Object>? routerConfig,
  List<SingleChildWidget>? providers,
  int rounds = 3,
}) async {
  expect(
    realFontsLoaded,
    isTrue,
    reason: 'pumpAtWidth measures text, and no real font is loaded — every '
        'width it reports would be the placeholder square glyph. Call '
        '`await loadRealFonts()` in setUpAll.',
  );

  pinSurface(tester, size: Size(width, height));
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

  await tester.pumpWidget(
    wrapApp(
      home: home,
      routerConfig: routerConfig,
      providers: providers,
      theme: AppTheme.themeData(fontFamily: kRealFont),
    ),
  );
  await settleMocks(tester, rounds: rounds);
}

/// Half a logical pixel — below anything a reader can see, above the rounding
/// noise between two `TextPainter` passes.
///
/// NOT `precisionErrorTolerance` (1e-10): the laid-out width and the intrinsic
/// width are measured by *different* painters, so they disagree in the last
/// couple of decimal places on text that fits perfectly well. At 1e-10 that
/// disagreement is a failure. The defects this gate exists to catch overrun by
/// tens of pixels.
const double _kWidthEpsilon = 0.5;

/// Fails if any text in the tree is being CUT OFF without saying so (§13.3).
///
/// **This is the assertion `takeException` cannot make.** A `RenderFlex`
/// overflow throws and paints the yellow-and-black stripes; text that runs out
/// of room inside its own box does neither — it is silently clipped or faded,
/// and the test stays green about a label the user cannot finish reading. The
/// pro earnings bar clipped « Aujourd'hui » at every compact width — including
/// the 390 its golden was taken at — and 777 tests and 26 goldens had nothing to
/// say about it. This walk is what found it; A11 C4 is what fixed it.
///
/// The predicate is Flutter's own, from `RenderParagraph.performLayout`
/// (`paragraph.dart:921-922`), split into the two cases that can actually occur:
///
/// * **`didExceedMaxLines`** — the paragraph had a line budget and blew it. This
///   is the public getter the framework itself uses; it is true only when text
///   was really dropped.
/// * **`!softWrap` and the box is narrower than one line** — a paragraph that is
///   forbidden to wrap cannot spend its overflow on a second line, so an
///   intrinsic width wider than the box is text that is gone. `Tab` is the only
///   shape in `lib/` that reaches here (`tabs.dart:183` — `softWrap: false`,
///   `overflow: fade`); the app declares `TextOverflow.ellipsis` at all 46 of
///   its own overflow sites and `softWrap` at none.
///
/// **What is deliberately NOT flagged: wrapping.** An earlier draft compared
/// `size.width` against `getMaxIntrinsicWidth` for every paragraph. That is a
/// measure of "does this sentence fit on one line", which on a 360dp phone is
/// false for most sentences and desirable for all of them — `LegalConsentText`
/// says in its own docstring that it costs four lines at 390. A gate that is red
/// on correct behaviour gets deleted, and takes the true positives with it.
///
/// [ellipsisIsFine] declares that clipping is intentional (SYSTEM.md §13.3
/// allows a declared ellipsis); pass `false` only to audit those too.
void expectNoUndeclaredTruncation(
  WidgetTester tester, {
  bool ellipsisIsFine = true,
  String? context,
}) {
  final cut = <String>[];

  for (final p in tester.allRenderObjects.whereType<RenderParagraph>()) {
    if (ellipsisIsFine && p.overflow == TextOverflow.ellipsis) continue;

    final String why;
    if (p.didExceedMaxLines) {
      why = 'exceeded maxLines: ${p.maxLines}';
    } else if (!p.softWrap &&
        p.size.width + _kWidthEpsilon <
            p.getMaxIntrinsicWidth(double.infinity)) {
      why = 'softWrap: false, needs '
          '${p.getMaxIntrinsicWidth(double.infinity).toStringAsFixed(1)}dp '
          'in a ${p.size.width.toStringAsFixed(1)}dp box';
    } else {
      continue;
    }

    // The plain text, one line, short enough to read in a failure message.
    var label = p.text.toPlainText().replaceAll('\n', ' ');
    if (label.length > 60) label = '${label.substring(0, 57)}…';
    cut.add('  · « $label » — $why (overflow: ${p.overflow.name})');
  }

  expect(
    cut,
    isEmpty,
    reason: '${context ?? 'this layout'} cuts text off without declaring it '
        '(SYSTEM.md §13.3 — a label the user cannot finish reading is not a '
        'label):\n${cut.join('\n')}',
  );
}
