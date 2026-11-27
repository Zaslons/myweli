import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/core/theme/colors.dart';
import 'package:myweli/core/utils/formatters.dart';
import 'package:myweli/widgets/common/code_sent_to.dart';

import '../support/pump_app.dart';

/// `CodeSentTo` (docs/design/account-email-change.md §12, SYSTEM.md §13.3):
/// the sentence in the secondary colour, the address under it in ink with its
/// break marks, the screen's alignment on both, and ONE node a screen reader
/// reads as the sentence it always heard. Where the lines fall at 200 % is
/// `test/a11y/code_sent_to_test.dart`'s.
void main() {
  Text paragraph(WidgetTester tester, String data) =>
      tester.widget<Text>(find.text(data));

  Future<void> pump(WidgetTester tester, Widget subject) =>
      tester.pumpWidget(wrapApp(home: Scaffold(body: subject)));

  testWidgets('by e-mail: the sentence, then the address in ink', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    const address = 'aminata.kone@exemple.ci';
    await pump(
      tester,
      const CodeSentTo.byEmail(address, textAlign: TextAlign.center),
    );

    final lead = paragraph(tester, 'Entrez le code reçu par e-mail à');
    final drawn = paragraph(tester, Formatters.breakableEmail(address));
    expect(lead.style?.color, AppColors.textSecondary);
    expect(drawn.style?.color, AppColors.textPrimary);
    expect(lead.textAlign, TextAlign.center);
    expect(drawn.textAlign, TextAlign.center);

    expect(
      find.bySemanticsLabel('Entrez le code reçu par e-mail à $address.'),
      findsOneWidget,
    );
    // The parts are not read again, and the marks never are.
    expect(find.bySemanticsLabel(RegExp('\u200B')), findsNothing);
    expect(
      find.bySemanticsLabel('Entrez le code reçu par e-mail à'),
      findsNothing,
    );
    handle.dispose();
  });

  testWidgets('the current address: its comma heard, not drawn', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    const address = 'awa.kone@exemple.ci';
    await pump(tester, const CodeSentTo.currentAddress(address));

    expect(
      find.text('Entrez le code reçu à votre adresse actuelle'),
      findsOneWidget,
    );
    expect(
      paragraph(tester, Formatters.breakableEmail(address)).textAlign,
      TextAlign.start,
    );
    expect(
      find.bySemanticsLabel(
        'Entrez le code reçu à votre adresse actuelle, $address.',
      ),
      findsOneWidget,
    );
    handle.dispose();
  });
}
