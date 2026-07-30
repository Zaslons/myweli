import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/screens/provider/features/loyalty_programs_screen.dart';

import '../support/pump_app.dart';

void main() {
  testWidgets('a gated V2/V3 screen shows the coming-soon placeholder',
      (tester) async {
    await tester.pumpWidget(
      wrapApp(home: LoyaltyProgramsScreen()),
    );

    // Flag is off → placeholder instead of the mock feature UI.
    expect(find.text('Bientôt disponible'), findsWidgets);
    expect(find.text('Programmes de fidélité'), findsNothing);
  });
}
