import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/screens/auth/otp_verify_screen.dart';

void main() {
  testWidgets(
      'OTP entry is an AutofillGroup whose first box requests the '
      'one-time code', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: OtpVerifyScreen(phoneNumber: '+2250700000000'),
      ),
    );
    await tester.pump();

    expect(find.byType(AutofillGroup), findsOneWidget);

    final hasOneTimeCodeHint = tester
        .widgetList<TextField>(find.byType(TextField))
        .any((f) =>
            f.autofillHints?.contains(AutofillHints.oneTimeCode) ?? false);
    expect(hasOneTimeCodeHint, isTrue);

    // Dispose the screen so its resend-cooldown timer is cancelled.
    await tester.pumpWidget(const SizedBox());
  });
}
