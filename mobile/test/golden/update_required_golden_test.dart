import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/screens/update/update_required_app.dart';

import '../support/golden.dart';

/// The blocking screen, at the floor phone and at 200%.
///
/// Worth a golden even though it is one `EmptyState`: it is the only screen a
/// user cannot navigate away from, so a regression here is not "a page looks
/// wrong" but "the app is bricked with no way out". The 2× frame is the one
/// that matters — a truncated « Mettre à jour » would strand someone on a build
/// we deliberately blocked.
void main() {
  group('update required', () {
    testWidgets('at the floor', (tester) async {
      // `UpdateRequiredApp` is its own MaterialApp (it replaces the app at
      // `runApp`), so it cannot go through `goldenApp` — the surface is pinned
      // directly instead.
      goldenSurface(tester);
      await tester.pumpWidget(
        const UpdateRequiredApp(
          updateUrl:
              'https://play.google.com/store/apps/details?id=com.myweli.app',
        ),
      );
      await tester.pump();
      await expectGolden(tester, 'update_required_w360');
    });

    testWidgets('at 200% — the action still whole', (tester) async {
      goldenSurface(tester);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(
        const UpdateRequiredApp(
          updateUrl:
              'https://play.google.com/store/apps/details?id=com.myweli.app',
        ),
      );
      await tester.pump();
      await expectGolden(tester, 'update_required_w360_x2');
    });
  });
}
