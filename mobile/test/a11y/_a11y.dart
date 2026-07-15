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
