import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/widgets/common/phone_number_field.dart';

import '../support/pump_app.dart';

void main() {
  testWidgets('renders a phone input defaulting to Côte d’Ivoire (+225)', (
    tester,
  ) async {
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

  /// A7-fix — **the gate for this branch's own headline fix.**
  ///
  /// A7 shipped a comment claiming `intl_phone_field`'s own `FormField` check
  /// "could never run" without a `Form` ancestor, and triaged a conflicting
  /// second validator as cosmetic on that basis. It was measured false: the
  /// package defaults to `AutovalidateMode.onUserInteraction`, needs no `Form`,
  /// and judged the number from the FIRST keystroke — which is what §14 rule 2
  /// forbids — while *replacing* the app's message, because `TextFormField`
  /// does `copyWith(errorText: field.errorText)` and `InputDecoration.copyWith`
  /// keeps the non-null one. Two rules, disagreeing, with the wrong one winning.
  ///
  /// The fix is one line (`autovalidateMode: disabled`) and the branch's review
  /// found that **deleting it left the entire suite green** — every other phone
  /// assertion in the repo uses an empty value (the package never fires) or a
  /// valid 10-digit number (it returns null). This is the case that separates
  /// them: a SHORT national number, which the package rejects and our rule has
  /// no opinion about until submit.
  testWidgets('the package’s own validator is silenced — one rule, on submit', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrapApp(
        home: Scaffold(body: PhoneNumberField(onChanged: (_) {})),
      ),
    );
    await tester.pumpAndSettle();

    // Nine digits: below Côte d'Ivoire's length, so the package would object.
    await tester.enterText(find.byType(TextField).first, '071234567');
    await tester.pump();

    expect(
      find.text('Saisissez un numéro de téléphone valide.'),
      findsNothing,
      reason:
          '§14 rule 2 — nothing may judge this field mid-typing. With '
          '`autovalidateMode` back at the package default this renders on '
          'the ninth keystroke.',
    );
  });

  /// The other half of the same defect: when both rules have an opinion, the
  /// package's used to WIN. This pins that the app's message is the one on
  /// screen — the regression is silent otherwise, because both are red text.
  testWidgets('the app’s message is the one that renders, not the package’s', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrapApp(
        home: const Scaffold(
          body: PhoneNumberField(
            onChanged: _noop,
            // The app's own fault, as `FieldErrors` would supply it.
            errorText: 'Saisissez un numéro de téléphone.',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, '071234567');
    await tester.pump();

    expect(
      find.text('Saisissez un numéro de téléphone.'),
      findsOneWidget,
      reason: 'the app owns the message',
    );
    expect(
      find.text('Saisissez un numéro de téléphone valide.'),
      findsNothing,
      reason:
          'the package must not overwrite it — `copyWith(errorText:)` '
          'keeps whichever is non-null, so its message used to win',
    );
  });
}

void _noop(String _) {}
