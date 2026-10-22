import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/core/theme/colors.dart';
import 'package:myweli/screens/admin/widgets/admin_segmented_control.dart';

import '../support/pump_app.dart';

/// docs/design/pro-app-batch7.md §2.13 (B7.13, SYSTEM §21 row 26) — every
/// segment has a visible edge. Inactive segments had none: transparent, on a
/// #F5F5F5 track over the console's #F6F7F9 background, a segment you can
/// press drew no boundary at all. `borderStrong` is the token for « the sole
/// boundary of an interactive control »; the selected one is brand black.
void main() {
  BoxBorder? edgeOf(WidgetTester tester, String label) {
    final box = tester
        .widgetList<Container>(
          find.ancestor(of: find.text(label), matching: find.byType(Container)),
        )
        .map((c) => c.decoration)
        .whereType<BoxDecoration>()
        .first;
    return box.border;
  }

  testWidgets('inactive segments draw borderStrong; the selected one '
      'draws brand black', (tester) async {
    await pumpApp(
      tester,
      home: Scaffold(
        body: AdminSegmentedControl(
          labels: const ['En attente', 'Vérifiés', 'Rejetés'],
          selected: 0,
          onSelect: (_) {},
        ),
      ),
    );
    final selected = edgeOf(tester, 'En attente') as Border?;
    expect(selected?.top.color, AppColors.primary);
    for (final label in ['Vérifiés', 'Rejetés']) {
      final edge = edgeOf(tester, label) as Border?;
      expect(edge, isNotNull, reason: '« $label » has no boundary');
      expect(edge!.top.color, AppColors.borderStrong, reason: label);
    }
  });
}
