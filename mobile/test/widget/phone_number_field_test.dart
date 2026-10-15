import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/core/forms/field_errors.dart';
import 'package:myweli/core/utils/validators.dart';
import 'package:myweli/widgets/common/phone_number_field.dart';

import '../support/pump_app.dart';

/// The rule's message for a +225 number of the wrong length
/// (docs/design/phone-national-length.md §2.1).
const _tenDigits = 'Le numéro doit comporter 10 chiffres après +225.';

void main() {
  Finder input() => find.byType(TextField).first;

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
    await tester.enterText(input(), '0712345678');
    await tester.pump();
    expect(lastE164, '+2250712345678');
  });

  /// phone-national-length.md §2.3 — **what is checked is what is sent.** The
  /// field emitted `+225` + the raw text: separators went to a server that
  /// refuses them, and a cleared field emitted `+225`, which every screen read
  /// as a number (« valide » instead of « Saisissez un numéro », and the
  /// optional profile phone could never be cleared).
  group('the emitted value is normalized', () {
    testWidgets('separators are dropped; a cleared field emits nothing', (
      tester,
    ) async {
      String? last;
      await tester.pumpWidget(
        wrapApp(
          home: Scaffold(body: PhoneNumberField(onChanged: (v) => last = v)),
        ),
      );
      await tester.pumpAndSettle();

      // Ten characters is the CI cap, separators included — 7 digits here.
      await tester.enterText(input(), '07 12 34 5');
      await tester.pump();
      expect(last, '+2250712345');

      await tester.enterText(input(), '');
      await tester.pump();
      expect(
        last,
        '',
        reason:
            'no national digit → an EMPTY value, not the calling code '
            'alone — the required field then says « Saisissez un numéro de '
            'téléphone. » and an optional one can be cleared',
      );
    });

    testWidgets('picking another country re-emits the number under it', (
      tester,
    ) async {
      String? last;
      await tester.pumpWidget(
        wrapApp(
          home: Scaffold(body: PhoneNumberField(onChanged: (v) => last = v)),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(input(), '612345678');
      await tester.pump();
      expect(last, '+225612345678');

      // The picker. Only `onCountryChanged` fires on a switch — not the
      // field's `onChanged` — so a parent fed from `onChanged` alone kept the
      // previous country's number until the next keystroke.
      await tester.tap(find.text('+225'));
      await tester.pumpAndSettle();
      final dialog = find.byType(Dialog);
      await tester.enterText(
        find.descendant(of: dialog, matching: find.byType(TextField)),
        'France',
      );
      await tester.pumpAndSettle();
      // The ROW — `find.text` also matches the search box now holding
      // « France ».
      await tester.tap(find.widgetWithText(ListTile, 'France').first);
      await tester.pumpAndSettle();

      expect(dialog, findsNothing, reason: 'the picker closed on the pick');
      expect(find.text('+33'), findsOneWidget, reason: 'France is picked');
      expect(
        last,
        '+33612345678',
        reason: 'the switch alone re-emits — the screen judges +33, not +225',
      );
    });
  });

  /// A stored number is shown under ITS country. The doc comment said the
  /// picker derived the country from `initialValue`; it never did, because
  /// `initialCountryCode` was always passed ('CI'), and the package parses the
  /// value only when that is null — so `+33…` sat under the Ivorian flag, over
  /// the 10-character cap, and an edit emitted `+225+33…`.
  group('a prefilled number', () {
    testWidgets('a French number shows under France and is not re-emitted '
        'until edited', (tester) async {
      final emitted = <String>[];
      await tester.pumpWidget(
        wrapApp(
          home: Scaffold(
            body: PhoneNumberField(
              initialValue: '+33612345678',
              onChanged: emitted.add,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('+33'), findsOneWidget, reason: 'France, not +225');
      expect(find.text('+225'), findsNothing);
      expect(
        tester.widget<TextField>(input()).controller?.text,
        '612345678',
        reason: 'the national part, without its calling code',
      );
      expect(
        emitted,
        isEmpty,
        reason:
            'untouched, the screen keeps the stored value it passed in — '
            'the field says nothing until the user edits',
      );

      await tester.enterText(input(), '612345679');
      await tester.pump();
      expect(emitted.last, '+33612345679');
    });

    testWidgets('an Ivorian number shows its ten national digits under +225', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrapApp(
          home: Scaffold(
            body: PhoneNumberField(
              initialValue: '+2250707123456',
              onChanged: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('+225'), findsOneWidget);
      expect(tester.widget<TextField>(input()).controller?.text, '0707123456');
    });
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
  ///
  /// phone-national-length.md extends it to the message that now exists for
  /// exactly this number: « 10 chiffres après +225 » must not leak mid-typing
  /// either.
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
    await tester.enterText(input(), '071234567');
    await tester.pump();

    for (final message in [
      'Saisissez un numéro de téléphone valide.',
      _tenDigits,
    ]) {
      expect(
        find.text(message),
        findsNothing,
        reason:
            '§14 rule 2 — nothing may judge this field mid-typing. With '
            '`autovalidateMode` back at the package default this renders on '
            'the ninth keystroke.',
      );
    }
  });

  /// §14 rule 2 end to end, the way every screen wires it: silent while
  /// typing, judged on submit, cleared on the keystroke that fixes it — with
  /// the short number the sign-in step saved on 2026-10-15.
  testWidgets('seven digits: silent while typing, « 10 chiffres » under the '
      'field on submit, cleared once fixed', (tester) async {
    await tester.pumpWidget(wrapApp(home: const _Form()));
    await tester.pumpAndSettle();

    await tester.enterText(input(), '0700000');
    await tester.pump();
    expect(find.text(_tenDigits), findsNothing, reason: 'still typing');

    await tester.tap(find.text('Continuer'));
    await tester.pump();
    expect(
      find.descendant(
        of: find.byType(PhoneNumberField),
        matching: find.text(_tenDigits),
      ),
      findsOneWidget,
      reason: 'the fault renders under the field it belongs to (§14 rule 1)',
    );

    await tester.enterText(input(), '0700000001');
    await tester.pump();
    expect(find.text(_tenDigits), findsNothing, reason: '§14 rule 2');
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

    await tester.enterText(input(), '071234567');
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

/// A one-field form wired the way the screens wire it (login's phone step).
class _Form extends StatefulWidget {
  const _Form();

  @override
  State<_Form> createState() => _FormState();
}

class _FormState extends State<_Form> {
  final _errors = FieldErrors({'phone': Validators.phoneNumber});
  String _phone = '';

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Column(
      children: [
        PhoneNumberField(
          errorText: _errors['phone'],
          onChanged: (v) => setState(() {
            _phone = v;
            _errors.revalidate('phone', v);
          }),
        ),
        TextButton(
          onPressed: () => setState(() => _errors.validate({'phone': _phone})),
          child: const Text('Continuer'),
        ),
      ],
    ),
  );
}
