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
///
/// **It pins a phone (A12).** Until this slice it pinned nothing, so every
/// subject of `contrast_test`, `label_test` and `tap_target_test` was measured on
/// `flutter_test`'s default **800×600** — wider than any device this app ships
/// to, and the same defect A11 C8d found in `pumpAtTextScale`. §21 row 60 filed
/// it; this closes it. A tap target that is 48dp on a 800dp desktop and 44 on a
/// 360dp phone was green, and the guideline it was asserting is §13.2's floor.
///
/// 1600 tall, not 780, for `pumpAtWidth`'s reason: an overflow is reported from
/// **paint**, so a row scrolled out of a short viewport is a row the gate cannot
/// see. The short-surface question is `vertical_fit_test.dart`'s, deliberately
/// separate.
Future<SemanticsHandle> pumpForA11y(
  WidgetTester tester,
  Widget child, {
  List<SingleChildWidget>? providers,
}) async {
  pinSurface(tester, size: const Size(360, 1600));
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

/// **The font is pinned here for the same reason `pumpAtWidth` pins it** (A11
/// C5). With none loaded, `flutter_test` draws every glyph as a square of the
/// font size — up to 79% wider than Roboto — so a bounded subject that fits in
/// the product can report an overflow here. That is *conservative* for a
/// "did it overflow" assertion and therefore harmless for years, right up until
/// someone narrows a bound to a real shipping width: C5 narrowed
/// `CompactAppointmentTile` from 340 to its true 270 floor and got a 58dp
/// overflow that Roboto does not produce — the width gate pumps that exact
/// configuration and is green.
///
/// `loadRealFonts()` must have run in `setUpAll`; naming the family without
/// loading it silently falls back to the placeholder again.
Future<void> pumpAtTextScale(
  WidgetTester tester,
  Widget child, {
  double scale = 2.0,
  List<SingleChildWidget>? providers,
}) async {
  expect(
    realFontsLoaded,
    isTrue,
    reason: 'pumpAtTextScale names Roboto in the theme, and nothing has loaded '
        'it — so every subject would silently render the placeholder square '
        'glyph again. Call `await loadRealFonts()` in setUpAll.',
  );
  pinSurface(tester, size: const Size(360, 1600));
  await pumpApp(
    tester,
    providers: providers,
    theme: AppTheme.themeData(fontFamily: kRealFont),
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
/// 2. It injects the scale through a `MediaQuery` placed at `home:`, which
///    reaches a screen only when the screen was pumped that way. ⚠️ **An
///    earlier version of this note said "three of the eight subjects are built
///    by a `routerConfig`" — that is false**: `grep routerConfig
///    test/a11y/layout_test.dart` returns 0, and all nine are pumped with
///    `home:`. The mechanism is still the reason, and it is real: a
///    `MediaQuery` cannot reach a `routerConfig`-built screen, so a
///    `MediaQuery`-based helper is one refactor away from silently measuring
///    1× while its name says 2×. The gate should not depend on nobody making
///    that refactor.
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

/// Fails if [text] is being broken INSIDE a word (§13.3, A11 C8).
///
/// **The gate could not see this, and could not have.**
/// `expectNoUndeclaredTruncation` permits wrapping *deliberately* — a heading
/// that wraps to two lines is C5's entire fix — and no overflow ever fires,
/// because wrapping is how the layout succeeds. So a date rendered
/// « 13/03/20 » / « 26 » and a button reading « Appel » / « er » both passed 846
/// tests. They were found by looking at C7's first 2× pictures.
///
/// The predicate is exact rather than heuristic: a paragraph breaks inside a
/// word **iff** its box is narrower than its widest single word. Measure the
/// widest word's intrinsic width with the paragraph's own style and compare.
///
/// **Applied by name, never as a sweep.** §13.3 says a *value the user reads as
/// one token* and a *control's label* may not break; a heading may. A blanket
/// walk would red on « Salon Ex/cellence » and « Prom/o W… », which §21 row 62
/// deliberately leaves to the slice that decides them.
void expectNoMidWordBreak(WidgetTester tester, String text, String at) {
  final p = tester.renderObject<RenderParagraph>(
    find.descendant(of: find.text(text), matching: find.byType(RichText)),
  );
  final style = p.text.style;
  var widest = 0.0;
  var widestWord = '';
  for (final word in text.split(RegExp(r'\s+'))) {
    if (word.isEmpty) continue;
    final tp = TextPainter(
      text: TextSpan(text: word, style: style),
      textDirection: TextDirection.ltr,
      textScaler: p.textScaler,
    )..layout();
    if (tp.width > widest) {
      widest = tp.width;
      widestWord = word;
    }
  }

  expect(
    p.size.width + _kWidthEpsilon,
    greaterThanOrEqualTo(widest),
    reason: '« $text » has ${p.size.width.toStringAsFixed(1)}dp at $at and its '
        'longest word « $widestWord » needs ${widest.toStringAsFixed(1)} — so it '
        'is being broken mid-word. §13.3: a value the user reads as one token, '
        'and a control\'s label, may wrap between words but never inside one.',
  );
}

/// How many characters a squeezed label must still show (§13.3, A12).
///
/// **8, and the two numbers either side of it are the whole justification.**
/// Measured by shipping this file report-only first (`0` prints the table and
/// asserts nothing) and running the width gate's six configurations:
///
/// | | shows | verdict |
/// |---|---|---|
/// | « Salon Excellence », salon page @360×2× | **0** | nothing but an ellipsis |
/// | « Beauté Divine », consumer home @360×2× | **2** | |
/// | « Salon Excellence », salon page app bar @390×2× | **7** | worst defect |
/// | « avec Kouassi Jean », review tile @360×2× | **9** | best legitimate |
/// | « Rechercher un salon… » @360×2× | 13 | declared, §21 row 56 |
///
/// So the data separates at **7 / 9** and 8 is the only value strictly between
/// them. **That is a one-character margin, which is tighter than a threshold
/// should be**, and it is recorded rather than smoothed over: if a future
/// legitimate site lands on 8, the answer is to re-measure and move the number,
/// not to widen `_kWidthEpsilon`.
///
/// The 7-char case is caught deliberately — a screen title showing 7 of 16
/// characters is a defect, not a tight fit. An earlier design pass proposed 12
/// without measuring; that would have reddened the review tile at 9.
///
/// Set to `0` to return to report-only mode when re-calibrating.
const int kMinLegibleChars = 8;

/// Is [o] flexed by its nearest enclosing `Flex`?
///
/// `Expanded` and `Flexible` create **no render object** — they are
/// `ParentDataWidget`s that write `FlexParentData.flex` onto the child's. So
/// this is a parent walk, not a widget lookup.
///
/// It stops at the FIRST `FlexParentData`, and that is the point: a paragraph
/// inside `Expanded(child: Column(child: Row(child: Text)))` is **unflexed**
/// with respect to the Row that actually squeezes it, and the Row is the
/// subject.
bool _isFlexed(RenderObject o) {
  for (RenderObject? n = o; n != null; n = n.parent) {
    final pd = n.parentData;
    if (pd is FlexParentData) return (pd.flex ?? 0) > 0;
  }
  return false;
}

/// The width `prefix…` needs under [p]'s own style and scaler.
double _prefixWidth(RenderParagraph p, String text, int n) {
  final painter = TextPainter(
    text: TextSpan(text: '${text.substring(0, n)}…', style: p.text.style),
    textDirection: TextDirection.ltr,
    textScaler: p.textScaler,
  )..layout();
  return painter.width;
}

/// Fails if a FLEXED label has been squeezed below legibility (§13.3, A12).
///
/// **The truncating twin of [expectNoMidWordBreak].** That one asks whether a
/// *wrapping* paragraph was given a box narrower than its widest word; this asks
/// whether a *truncating* one was given a box narrower than a readable prefix.
/// Between them they cover both ways a flex slot collapses — and neither can be
/// expressed by [expectNoUndeclaredTruncation], which skips a declared ellipsis
/// **by design** (`ellipsisIsFine`). That is why `NotificationTile`'s title,
/// crushed to ~86dp of a 240dp row by an unflexed timestamp, passed every
/// assertion this repo had (§21 row 68).
///
/// ## Two preconditions, and the second is the whole design
///
/// A subject must be **flexed** ([_isFlexed]) *and* have **`didExceedMaxLines`**.
/// Without the second, every framing of this rule fires on `CommunePill`: a
/// `Flexible` in a `mainAxisSize: min` row lays out at `min(intrinsic,
/// available)`, so « Cocody » is narrow and entirely correct. The question is
/// not "is this label narrow" but "did this label spend an ellipsis on a squeeze
/// it did not choose".
///
/// ⚠️ `didExceedMaxLines` is false whenever `maxLines` is null, and that is
/// right here — a flexed paragraph with no `maxLines` wraps rather than
/// truncates, and its crush belongs to [expectNoMidWordBreak]. It does mean a
/// site like `client_list_screen.dart`'s name (ellipsis, no `maxLines`) is out
/// of this sweep's reach. Said rather than assumed.
///
/// ## Applied as a SWEEP, unlike [expectNoMidWordBreak]
///
/// That one is applied by name because §13.3 gives it a **role exception** — a
/// date may not break, a heading may. Legibility has none: three characters and
/// an ellipsis is illegible in a heading too. [except] exists for a different
/// reason — a shape where the ellipsis *is* the design, e.g. `AppSearchBar`'s
/// placeholder in a fixed-shape pill (§21 row 56) — and each entry should cite
/// its register row on the line.
void expectNoLegibilityCrush(
  WidgetTester tester, {
  int minChars = kMinLegibleChars,
  String? context,
  Iterable<String> except = const <String>[],
}) {
  final crushed = <String>[];
  final report = <String>[];

  for (final p in tester.allRenderObjects.whereType<RenderParagraph>()) {
    if (!p.didExceedMaxLines) continue;
    if (!_isFlexed(p)) continue;
    final text = p.text.toPlainText();
    if (text.isEmpty || except.contains(text)) continue;

    if (minChars <= 0) {
      // Report mode: how many characters DO fit?
      var fits = 0;
      for (var n = 1; n <= text.length; n++) {
        if (_prefixWidth(p, text, n) <= p.size.width + _kWidthEpsilon) {
          fits = n;
        } else {
          break;
        }
      }
      report.add('    « $text »  ${p.size.width.toStringAsFixed(1)}dp '
          '→ $fits chars + …');
      continue;
    }

    final n = minChars < text.length ? minChars : text.length;
    final need = _prefixWidth(p, text, n);
    if (p.size.width + _kWidthEpsilon < need) {
      crushed.add('    « $text » has ${p.size.width.toStringAsFixed(1)}dp and '
          'needs ${need.toStringAsFixed(1)} to show $n characters');
    }
  }

  if (minChars <= 0) {
    if (report.isNotEmpty) {
      // ignore: avoid_print
      print('LEGIBILITY${context == null ? '' : ' ($context)'}:\n'
          '${report.join('\n')}');
    }
    return;
  }

  expect(
    crushed,
    isEmpty,
    reason: 'a flexed label was squeezed below $minChars characters'
        '${context == null ? '' : ' at $context'}:\n${crushed.join('\n')}\n'
        'The ellipsis is declared, so nothing else in this suite can see it — '
        'but a label showing three characters says nothing. §13.3: the fix is '
        'more width (flex the sibling, or wrap the row), never a smaller font.',
  );
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
///   `overflow: fade`); the app declares `TextOverflow.ellipsis` at all **47**
///   of its own overflow sites and `softWrap` at none. (46 on `main`; A11 added
///   the 47th itself — `AppSearchBar`'s declared ellipsis, §21 row 56.)
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
