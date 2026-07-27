import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pinning the test viewport — the one mechanism, in one place (A11).
///
/// **Why this file exists separately from `golden.dart`.** The body below has
/// been the house idiom since the goldens shipped, living in `goldenSurface`.
/// `test/a11y/` needs it too — the §10 layout gate is a *width* gate, and a
/// width gate that does not pin a width is not a gate — but `test/a11y/` is
/// deliberately **platform-agnostic** (no `kGoldensSkip`, the same assertion on
/// macOS and on the CI runner) and `golden.dart` imports `dart:io` for the
/// platform check and the font cache. So the four lines move here, and
/// `goldenSurface` delegates. One implementation, no churn across 12 golden
/// files.
///
/// **`devicePixelRatio = 1.0` is load-bearing, not tidiness.** `physicalSize` is
/// in *physical* pixels and the binding derives the logical size as
/// `physicalSize / devicePixelRatio`. Set the size without pinning the ratio and
/// you silently get a third of the width you asked for — a width gate would then
/// be testing 120dp while claiming 360.
///
/// **Do not reach for the alternatives.** `MediaQueryData.size` overrides change
/// what widgets *read* without changing what the render tree is *constrained
/// to*, so a `Row` still lays out at 800 and the gate goes green against every
/// defect it exists to catch. `binding.setSurfaceSize` is legitimate but unused
/// here; a second idiom for one job is how the repo ends up with two.
void pinSurface(WidgetTester tester, {required Size size}) {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}
