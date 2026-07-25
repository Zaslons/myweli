import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/core/theme/colors.dart';
import 'package:myweli/widgets/common/confirm_dialog.dart';

import '../support/pump_app.dart';

/// A6 — the single destructive-confirm (SYSTEM.md §15, §21 row 18).
///
/// Before A6, 13 hand-built `AlertDialog`s: verb labels 4/11, destructive red
/// 8/11, and **cancel-gets-focus 0/11** — a rule §15 and §13.5 both state.
void main() {
  /// Opens the dialog from a real route (a `Builder` context), because the
  /// `DialogRoute`'s own `FocusScope` is what resolves `autofocus`.
  Future<Future<T?>> open<T>(
    WidgetTester tester,
    Future<T?> Function(BuildContext) show,
  ) async {
    late Future<T?> result;
    await tester.pumpWidget(wrapApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => result = show(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    return result;
  }

  testWidgets('the CANCEL path takes focus — the safe default (§15, §13.5)',
      (tester) async {
    await open(
      tester,
      (c) => showConfirmDialog(c,
          title: 'Supprimer la photo ?',
          message: 'Elle disparaîtra de votre galerie publique.',
          confirmLabel: 'Supprimer la photo'),
    );

    final focused = tester.binding.focusManager.primaryFocus;
    expect(
      find.descendant(
        of: find.widgetWithText(TextButton, 'Annuler'),
        matching: find.byWidgetPredicate((w) => w is Focus),
      ),
      findsWidgets,
    );
    // The focused node belongs to the cancel button's subtree, not the confirm's.
    final cancelBox = tester.getRect(find.text('Annuler'));
    final focusedBox = focused!.rect;
    expect(focusedBox.overlaps(cancelBox), isTrue,
        reason: 'primary focus should sit on « Annuler », not the destructive '
            'action — never place danger under the resting finger');
  });

  testWidgets('a dialog WITH a field focuses the field instead',
      (tester) async {
    // The friction IS the doctrine: you cannot proceed without typing.
    await open(
      tester,
      (c) => showInputDialog(c,
          title: 'Signaler cet avis ?',
          confirmLabel: 'Signaler',
          field: const ConfirmField(hint: 'Raison (optionnel)')),
    );
    expect(
      tester.binding.focusManager.primaryFocus!.context!.widget,
      isA<Widget>(),
    );
    expect(find.byType(TextField), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).autofocus,
      isTrue,
    );
  });

  group('type-to-confirm — the irreversible rung', () {
    testWidgets('the confirm is DEAD until the word matches', (tester) async {
      await open(
        tester,
        (c) => showConfirmDialog(c,
            title: 'Supprimer votre salon ?',
            message: 'Cette action est définitive.',
            confirmLabel: 'Supprimer définitivement',
            confirmWord: 'SUPPRIMER'),
      );

      TextButton confirm() => tester.widget<TextButton>(
          find.widgetWithText(TextButton, 'Supprimer définitivement'));
      expect(confirm().onPressed, isNull, reason: 'disabled before typing');

      await tester.enterText(find.byType(TextField), 'SUPPRIM');
      await tester.pump();
      expect(confirm().onPressed, isNull, reason: 'a prefix is not the word');

      await tester.enterText(find.byType(TextField), 'supprimer');
      await tester.pump();
      expect(confirm().onPressed, isNotNull,
          reason: 'case-insensitive — the field upcases as you type');
    });
  });

  testWidgets('a REQUIRED field gates the confirm (the admin contract)',
      (tester) async {
    await open(
      tester,
      (c) => showInputDialog(c,
          title: 'Motif du rejet',
          confirmLabel: 'Rejeter',
          field: const ConfirmField(hint: 'Visible par le salon')),
    );
    TextButton confirm() =>
        tester.widget<TextButton>(find.widgetWithText(TextButton, 'Rejeter'));
    expect(confirm().onPressed, isNull);

    await tester.enterText(find.byType(TextField), 'Document illisible');
    await tester.pump();
    expect(confirm().onPressed, isNotNull);
  });

  group('what it returns', () {
    testWidgets('confirm → true · cancel → false · barrier → false',
        (tester) async {
      for (final (action, expected) in <(String, bool)>[
        ('Supprimer', true),
        ('Annuler', false),
      ]) {
        final result = await open(
          tester,
          (c) => showConfirmDialog(c,
              title: 'Supprimer ce service ?',
              message: 'Il ne sera plus réservable.',
              confirmLabel: 'Supprimer'),
        );
        await tester.tap(find.text(action));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(await result, expected);
      }

      // Barrier dismiss — the case all 11 hand-rolled sites handled by accident.
      final dismissed = await open(
        tester,
        (c) => showConfirmDialog(c,
            title: 'Supprimer ce service ?',
            message: 'Il ne sera plus réservable.',
            confirmLabel: 'Supprimer'),
      );
      await tester.tapAt(const Offset(10, 10));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(await dismissed, isFalse, reason: 'dismiss is the SAFE path');
    });

    testWidgets('showInputDialog returns the text, null on cancel',
        (tester) async {
      final result = await open(
        tester,
        (c) => showInputDialog(c,
            title: 'Motif',
            confirmLabel: 'Envoyer',
            field: const ConfirmField(hint: 'Raison')),
      );
      await tester.enterText(find.byType(TextField), '  Doublon  ');
      await tester.pump();
      await tester.tap(find.text('Envoyer'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(await result, 'Doublon', reason: 'trimmed');
    });
  });

  group('destructive is a CLASSIFICATION, not a default look', () {
    testWidgets('destructive → the confirm is error red', (tester) async {
      await open(
        tester,
        (c) => showConfirmDialog(c,
            title: 'Révoquer l’accès ?',
            message: 'Le membre perdra immédiatement l’accès.',
            confirmLabel: 'Révoquer'),
      );
      final style = tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'Révoquer'))
          .style!;
      expect(
        style.foregroundColor!.resolve(<WidgetState>{}),
        AppColors.error,
      );
    });

    testWidgets('NOT destructive → no red (logout, report, no-show)',
        (tester) async {
      // Forcing red on a non-destructive action dilutes the signal — recorded
      // doctrine, not an oversight.
      await open(
        tester,
        (c) => showConfirmDialog(c,
            title: 'Déconnexion',
            message: 'Vous devrez vous reconnecter.',
            confirmLabel: 'Se déconnecter',
            isDestructive: false),
      );
      expect(
        tester
            .widget<TextButton>(
                find.widgetWithText(TextButton, 'Se déconnecter'))
            .style,
        isNull,
      );
    });
  });

  testWidgets('the dialog owns its controller — it disposes cleanly',
      (tester) async {
    // Three hand-rolled dialogs leaked theirs.
    await open(
      tester,
      (c) => showInputDialog(c,
          title: 'Légende',
          confirmLabel: 'Ajouter',
          cancelLabel: 'Passer',
          field: const ConfirmField(
              hint: 'Légende (optionnel)', isRequired: false)),
    );
    await tester.enterText(find.byType(TextField), 'Avant/après tresses');
    await tester.tap(find.text('Passer'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
  });
}
