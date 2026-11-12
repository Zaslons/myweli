import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/core/theme/app_theme.dart';
import 'package:myweli/core/theme/colors.dart';
import 'package:myweli/core/utils/validation_labels.dart';
import 'package:myweli/models/salon_validation.dart';
import 'package:myweli/screens/admin/widgets/refusal_dialog.dart';

import '../support/fonts.dart';
import '../support/pump_app.dart';
import '../support/surface.dart';

/// « Refuser » a salon's request (B0.18 — docs/design/salon-go-live-approval.md
/// §4.3 « Refusing (Q1) », §8.2): a code is required; the note is required
/// for « Autre » and capped at 500 characters counted as the server counts
/// them; its rules are printed under it; the final codes say so; errors
/// belong to their field (SYSTEM.md §14).
void main() {
  setUpAll(loadRealFonts);

  late List<(String, String?)> calls;
  late RefusalDialogResult? result;

  RefuseCall answering(RefusalAnswer answer) => (code, note) async {
    calls.add((code, note));
    return answer;
  };

  const ok = (ok: true, code: null, message: null);

  Future<void> open(WidgetTester t, RefuseCall refuse) async {
    calls = [];
    result = null;
    pinSurface(t, size: const Size(1280, 1400));
    await t.pumpWidget(
      wrapApp(
        theme: AppTheme.themeData(fontFamily: kRealFont),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async =>
                  result = await showRefusalDialog(context, refuse: refuse),
              child: const Text('ouvrir'),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.text('ouvrir'));
    await t.pumpAndSettle();
  }

  Finder submit() => find.widgetWithText(TextButton, 'Refuser');

  Future<void> press(WidgetTester t) async {
    await t.tap(submit());
    await t.pumpAndSettle();
  }

  Text counter(WidgetTester t) => t.widget<Text>(
    find.byWidgetPredicate(
      (w) => w is Text && RegExp(r'^\d+ / 500$').hasMatch(w.data ?? ''),
    ),
  );

  testWidgets('the six codes in §4.3’s order, each with what the salon '
      'reads — verbatim — and the two final ones say so in words', (t) async {
    await open(t, answering(ok));
    expect(find.text('Refuser la mise en ligne'), findsOneWidget);
    final names = [
      for (final c in kSalonRefusalCodes) ValidationLabels.refusalName(c),
    ];
    final ys = [for (final n in names) t.getTopLeft(find.text(n)).dy];
    expect(ys, orderedEquals([...ys]..sort()), reason: 'in the list order');
    for (final code in kSalonRefusalCodes) {
      final sentence = ValidationLabels.salonSentences[code];
      expect(
        find.text(
          sentence == null
              ? 'Le salon lira votre note seule.'
              : 'Le salon lira : « $sentence »',
        ),
        findsOneWidget,
        reason: code,
      );
    }
    expect(
      find.text('Définitif : le salon ne pourra pas renvoyer sa demande.'),
      findsNWidgets(kFinalSalonRefusalCodes.length),
    );
    // The note's rules, under it, before anything is typed.
    expect(find.text(kRefusalNoteRules), findsOneWidget);
    expect(counter(t).data, '0 / 500');
    // Destructive (§15): the submit is drawn in the error colour.
    final style = t.widget<TextButton>(submit()).style!;
    expect(style.foregroundColor!.resolve({}), AppColors.error);
  });

  testWidgets('the first code takes focus on open (§13.5)', (t) async {
    await open(t, answering(ok));
    final focused = FocusManager.instance.primaryFocus!.context!;
    expect(
      find.ancestor(
        of: find.byWidget(focused.widget),
        matching: find.widgetWithText(
          RadioListTile<String>,
          ValidationLabels.refusalName(kSalonRefusalCodes.first),
        ),
      ),
      findsOneWidget,
    );
  });

  testWidgets('keyboard: Space chooses the focused code, the arrows move '
      'between them', (t) async {
    await open(t, answering(ok));
    await t.sendKeyEvent(LogicalKeyboardKey.space);
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await t.pumpAndSettle();
    await press(t);
    expect(calls, [('photos', null)]);
    expect(result, RefusalDialogResult.refused);
  });

  group('a code is required', () {
    testWidgets('submitted without one: « Choisissez un motif. » under the '
        'codes — no request, no snackbar, the dialog still open', (t) async {
      await open(t, answering(ok));
      await press(t);
      expect(find.text(kRefusalCodeRequired), findsOneWidget);
      expect(calls, isEmpty);
      expect(find.byType(SnackBar), findsNothing);
      expect(find.text('Refuser la mise en ligne'), findsOneWidget);
      // Under the codes: below the last one, above the note.
      final error = t.getTopLeft(find.text(kRefusalCodeRequired)).dy;
      expect(error, greaterThan(t.getTopLeft(find.text('Autre')).dy));
      expect(error, lessThan(t.getTopLeft(find.byType(TextField)).dy));
    });

    testWidgets('choosing one clears it, without a second submit', (t) async {
      await open(t, answering(ok));
      await press(t);
      await t.tap(find.text('Salon non confirmé'));
      await t.pump();
      expect(find.text(kRefusalCodeRequired), findsNothing);
      await press(t);
      expect(calls, [('unconfirmed', null)]);
    });
  });

  group('the note', () {
    const required = 'Une note est obligatoire pour le motif « Autre ».';
    const tooLong = 'La note dépasse 500 caractères.';

    testWidgets('required for « Autre » — the label says so, the error sits '
        'under the field, and typing clears it', (t) async {
      await open(t, answering(ok));
      expect(find.text('Note pour le salon (facultative)'), findsOneWidget);
      await t.tap(find.text('Autre'));
      await t.pump();
      expect(find.text('Note pour le salon (obligatoire)'), findsOneWidget);
      await t.enterText(find.byType(TextField), '   ');
      await press(t);
      expect(find.text(required), findsOneWidget);
      expect(calls, isEmpty);
      final decorator = t.widget<InputDecorator>(find.byType(InputDecorator));
      expect(decorator.decoration.errorText, required, reason: 'the field’s');

      await t.enterText(find.byType(TextField), 'Salon introuvable sur place');
      await t.pump();
      expect(find.text(required), findsNothing);
      await press(t);
      expect(calls, [('other', 'Salon introuvable sur place')]);
    });

    testWidgets('…and not for another code: leaving « Autre » lifts the '
        'error', (t) async {
      await open(t, answering(ok));
      await t.tap(find.text('Autre'));
      await press(t);
      expect(find.text(required), findsOneWidget);
      await t.tap(find.text('Photos insuffisantes'));
      await t.pump();
      expect(find.text(required), findsNothing);
      await press(t);
      expect(calls, [('photos', null)]);
    });

    testWidgets('500 characters at most, counted as the server counts them: '
        'code points of the trimmed note', (t) async {
      await open(t, answering(ok));
      await t.tap(find.text('Photos insuffisantes'));
      // 250 « 👍🏽 »: 250 graphemes, 500 code points — the cap exactly.
      final thumbs = List.filled(250, '👍🏽').join();
      await t.enterText(find.byType(TextField), '  $thumbs  ');
      await t.pump();
      expect(counter(t).data, '500 / 500');
      expect(counter(t).style!.color, isNot(AppColors.error));
      await t.enterText(find.byType(TextField), '$thumbs👍🏽');
      await t.pump();
      expect(counter(t).data, '502 / 500');
      expect(counter(t).style!.color, AppColors.error);
      expect(
        counter(t).semanticsLabel,
        '502 caractères sur 500',
        reason: 'read as a sentence',
      );
      await press(t);
      expect(find.text(tooLong), findsOneWidget);
      expect(calls, isEmpty);
      // The rules stay under the field, error or not.
      expect(find.text(kRefusalNoteRules), findsOneWidget);

      await t.enterText(find.byType(TextField), thumbs);
      await t.pump();
      expect(find.text(tooLong), findsNothing);
      await press(t);
      expect(calls.single.$2, thumbs);
    });

    testWidgets('the server’s refusal of the note lands under the note, the '
        'dialog open and the note still typed', (t) async {
      await open(
        t,
        answering((ok: false, code: 'note_too_long', message: tooLong)),
      );
      await t.tap(find.text('Photos insuffisantes'));
      await t.enterText(find.byType(TextField), 'Une note');
      await press(t);
      expect(find.text(tooLong), findsOneWidget);
      expect(find.text('Une note'), findsOneWidget);
      expect(find.text('Refuser la mise en ligne'), findsOneWidget);
      expect(result, isNull, reason: 'still open');
    });
  });

  group('what the server answers', () {
    testWidgets('refused: the dialog closes, and says so', (t) async {
      await open(t, answering(ok));
      await t.tap(find.text('Hors de Côte d’Ivoire'));
      await t.enterText(find.byType(TextField), '  Adresse à Dakar  ');
      await press(t);
      expect(calls, [('outside_ci', 'Adresse à Dakar')]);
      expect(result, RefusalDialogResult.refused);
      expect(find.text('Refuser la mise en ligne'), findsNothing);
    });

    testWidgets('decided elsewhere (409): it closes as a conflict — the '
        'screen’s bar says why', (t) async {
      await open(
        t,
        answering((
          ok: false,
          code: 'validation_not_pending',
          message: 'Cette demande a déjà été traitée.',
        )),
      );
      await t.tap(find.text('Salon de test'));
      await press(t);
      expect(result, RefusalDialogResult.conflict);
      expect(find.text('Refuser la mise en ligne'), findsNothing);
    });

    testWidgets('offline: said inside the dialog — a snackbar under a modal '
        'is neither seen nor heard (§15) — and the note is kept', (t) async {
      await open(
        t,
        answering((
          ok: false,
          code: 'unauthorized',
          message: 'Session expirée ou hors ligne',
        )),
      );
      await t.tap(find.text('Photos insuffisantes'));
      await t.enterText(find.byType(TextField), 'Une note');
      await press(t);
      expect(find.text('Session expirée ou hors ligne'), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
      expect(find.text('Une note'), findsOneWidget);
      expect(result, isNull);
    });

    testWidgets('while the refusal is out, neither Escape nor a click outside '
        'closes the dialog — it closes on the answer, refused', (t) async {
      final answer = Completer<RefusalAnswer>();
      await open(t, (code, note) {
        calls.add((code, note));
        return answer.future;
      });
      await t.tap(find.text('Photos insuffisantes'));
      await t.tap(submit());
      await t.pump();
      expect(calls, hasLength(1));
      await t.sendKeyEvent(LogicalKeyboardKey.escape);
      await t.pump();
      expect(find.text(kRefusalDialogTitle), findsOneWidget, reason: 'Escape');
      await t.tapAt(const Offset(4, 4)); // the scrim
      await t.pump();
      expect(find.text(kRefusalDialogTitle), findsOneWidget, reason: 'scrim');
      expect(result, isNull);
      answer.complete(ok);
      await t.pumpAndSettle();
      expect(result, RefusalDialogResult.refused);
      expect(find.text(kRefusalDialogTitle), findsNothing);
    });

    testWidgets('« Annuler »: nothing sent', (t) async {
      await open(t, answering(ok));
      await t.tap(find.text('Photos insuffisantes'));
      await t.tap(find.text('Annuler'));
      await t.pumpAndSettle();
      expect(calls, isEmpty);
      expect(result, RefusalDialogResult.cancelled);
    });
  });
}
