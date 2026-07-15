import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/widgets/common/salon_time_hint.dart';

import '../support/pump_app.dart';

/// The « heure du salon » viewer hint (docs/design/timezone-salon-time.md §2):
/// visible ONLY when the device offset differs from the salon's (UTC+0) —
/// users in Côte d'Ivoire never see it. Offsets are injected so the test is
/// deterministic on any machine.
void main() {
  Widget host(Duration offset) => wrapApp(
        home: Scaffold(
          body: SalonTimeHint(deviceOffsetOverride: offset),
        ),
      );

  testWidgets('a foreign device sees the hint', (tester) async {
    await tester.pumpWidget(host(const Duration(hours: 1))); // Paris (winter)
    expect(
      find.text('Heures affichées : heure du salon (Côte d\'Ivoire)'),
      findsOneWidget,
    );
  });

  testWidgets('a device on salon time sees NOTHING', (tester) async {
    await tester.pumpWidget(host(Duration.zero)); // Abidjan
    expect(
      find.text('Heures affichées : heure du salon (Côte d\'Ivoire)'),
      findsNothing,
    );
    expect(find.byType(SizedBox), findsOneWidget);
  });
}
