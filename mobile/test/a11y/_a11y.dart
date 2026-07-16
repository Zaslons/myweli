import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/single_child_widget.dart';

import '../support/pump_app.dart';

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
