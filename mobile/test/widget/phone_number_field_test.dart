import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/widgets/common/phone_number_field.dart';

import '../support/pump_app.dart';

void main() {
  testWidgets('renders a phone input defaulting to Côte d\'Ivoire (+225)',
      (tester) async {
    var lastE164 = '';
    await tester.pumpWidget(
      wrapApp(
        home: Scaffold(
          body: PhoneNumberField(onChanged: (e164) => lastE164 = e164),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(PhoneNumberField), findsOneWidget);
    expect(find.byType(TextField), findsWidgets);
    // Default country dial code shown by the picker.
    expect(find.text('+225'), findsOneWidget);

    // Typing the national number bubbles up the full E.164.
    await tester.enterText(find.byType(TextField).first, '0712345678');
    await tester.pump();
    expect(lastE164, startsWith('+225'));
    expect(lastE164, contains('0712345678'));
  });
}
