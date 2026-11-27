import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/core/theme/colors.dart';
import 'package:myweli/core/utils/formatters.dart';
import 'package:myweli/widgets/common/email_sentence.dart';

import '../support/pump_app.dart';

/// `EmailSentence` (SYSTEM.md §13.3, docs/design/app-team-email-seams.md §4):
/// a sentence that names an address, drawn with the address on a line of its
/// own, in ink, and heard as ONE node — the sentence, never the break marks.
/// Where the lines fall at 200 % is `test/a11y/team_email_test.dart`'s and
/// `test/a11y/code_sent_to_test.dart`'s.
void main() {
  const address = 'aminata.kone@exemple.ci';
  final drawn = Formatters.breakableEmail(address);

  /// A dialog's body: the ambient style the sentence should take.
  const ambient = TextStyle(fontSize: 15, color: AppColors.textSecondary);

  Future<void> pump(WidgetTester tester, Widget subject) => tester.pumpWidget(
    wrapApp(
      home: Scaffold(
        body: DefaultTextStyle(style: ambient, child: subject),
      ),
    ),
  );

  Text text(WidgetTester tester, String data) =>
      tester.widget<Text>(find.text(data));

  double top(WidgetTester tester, String data) =>
      tester.getTopLeft(find.text(data)).dy;

  testWidgets('address first: the address, then the rest, under it', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    const rest = 'perdra immédiatement l’accès à Salon Excellence.';
    await pump(
      tester,
      const EmailSentence.addressFirst(address: address, rest: rest),
    );

    expect(top(tester, drawn), lessThan(top(tester, rest)));
    // The address in ink; the rest in the dialog's own style.
    expect(text(tester, drawn).style?.color, AppColors.textPrimary);
    expect(text(tester, drawn).style?.fontSize, 15);
    expect(text(tester, rest).style?.color, AppColors.textSecondary);
    expect(text(tester, rest).style?.fontSize, 15);

    // One node, the sentence as it is said; the parts are not read again,
    // and the marks never are.
    expect(find.bySemanticsLabel('$address $rest'), findsOneWidget);
    expect(find.bySemanticsLabel(rest), findsNothing);
    expect(find.bySemanticsLabel(RegExp('\u200B')), findsNothing);
    handle.dispose();
  });

  testWidgets('address last: the lead, then the address; its own ending '
      'heard, not drawn', (tester) async {
    final handle = tester.ensureSemantics();
    await pump(
      tester,
      const EmailSentence.addressLast(
        lead: 'Quel rôle pour',
        address: address,
        spoken: 'Quel rôle pour $address ?',
        textAlign: TextAlign.center,
      ),
    );

    expect(top(tester, 'Quel rôle pour'), lessThan(top(tester, drawn)));
    expect(text(tester, drawn).textAlign, TextAlign.center);
    expect(text(tester, 'Quel rôle pour').textAlign, TextAlign.center);
    expect(find.textContaining('?'), findsNothing);
    expect(find.bySemanticsLabel('Quel rôle pour $address ?'), findsOneWidget);
    expect(find.bySemanticsLabel('Quel rôle pour'), findsNothing);
    handle.dispose();
  });

  testWidgets('the caller\'s style is merged over the ambient one', (
    tester,
  ) async {
    await pump(
      tester,
      const EmailSentence.addressLast(
        lead: 'Entrez le code',
        address: address,
        style: TextStyle(fontSize: 18),
      ),
    );
    final lead = text(tester, 'Entrez le code').style!;
    expect(lead.fontSize, 18, reason: 'the caller\'s size');
    expect(lead.color, AppColors.textSecondary, reason: 'the ambient colour');
    expect(text(tester, drawn).style?.fontSize, 18);
    expect(text(tester, drawn).style?.color, AppColors.textPrimary);
  });
}
