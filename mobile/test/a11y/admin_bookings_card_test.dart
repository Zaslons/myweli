import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/core/theme/app_theme.dart';
import 'package:myweli/screens/admin/widgets/admin_detail_widgets.dart';

import '../support/fonts.dart';
import '../support/pump_app.dart';
import '_a11y.dart';

/// docs/design/pro-app-batch7.md §2.10 (B7.10, SYSTEM §21 row 96) — the
/// console's booking rows split their width by fixed shares (date 3 · status
/// 2 · price 2 · client 3); a seven-digit price has to stay whole in its
/// share. The layout gate pumps phone screens only, so the console's table
/// gets a subject of its own, at console widths.
void main() {
  setUpAll(loadRealFonts);

  for (final width in [600.0, 800.0, 1024.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('a seven-digit price stays whole at ${width.toInt()}dp × '
          '$scale×', (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

        await pumpApp(
          tester,
          theme: AppTheme.themeData(fontFamily: kRealFont),
          home: Scaffold(
            body: SingleChildScrollView(
              child: AdminBookingsCard(
                items: const [
                  {
                    'id': 'a1',
                    'appointmentDate': '2026-01-15T10:00:00.000Z',
                    'status': 'completed',
                    'totalPrice': 1250000,
                    'clientName': 'Awa Koné',
                  },
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.textContaining('250'), findsOneWidget, reason: 'C');
        expect(tester.takeException(), isNull);
        expectNoGluedTokenBreaks(
          tester,
          context: 'the console bookings at ${width.toInt()}dp × $scale×',
        );
      });
    }
  }
}
