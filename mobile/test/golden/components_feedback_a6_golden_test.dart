import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/core/theme/colors.dart';
import 'package:myweli/widgets/common/app_snack_bar.dart';
import 'package:myweli/widgets/common/confirm_dialog.dart';

import '../support/golden.dart';

/// A6's feedback layer, photographed (docs/design/mobile-a6-feedback.md).
///
/// The dialog golden this replaces was a hand-written `AlertDialog` fixture —
/// a picture of a dialog that did not exist anywhere in the product (its
/// « Retour » cancel and `ElevatedButton` confirm appear at zero call sites).
/// These render the REAL components through their real entry points, so the
/// baseline is evidence rather than an illustration.
void main() {
  group('goldens', () {
    setUpAll(loadGoldenFonts);

    /// Opens a dialog from a real route: the scrim, the elevation and
    /// `dialogTheme` are all in frame, and `autofocus` resolves the way it
    /// does in the app (the `DialogRoute`'s own `FocusScope`).
    Future<void> pumpDialog(
      WidgetTester tester,
      void Function(BuildContext) open, {
      Size size = const Size(390, 420),
    }) async {
      goldenSurface(tester, size: size);
      await tester.pumpWidget(
        goldenApp(
          home: Builder(
            builder: (context) {
              WidgetsBinding.instance
                  .addPostFrameCallback((_) => open(context));
              return const Scaffold(backgroundColor: AppColors.background);
            },
          ),
        ),
      );
      await tester.pump(); // push the route
      await tester.pump(const Duration(milliseconds: 400)); // past the fade
    }

    testWidgets('the confirm — hard to undo', (tester) async {
      // §15's middle rung: name the thing, state the consequence, label the
      // button with the VERB. The destructive action is `error`; « Annuler »
      // is the safe default and holds focus.
      await pumpDialog(
        tester,
        (context) => unawaited(showConfirmDialog(
          context,
          title: 'Supprimer cette photo ?',
          message: 'Elle disparaîtra de votre galerie publique.',
          confirmLabel: 'Supprimer la photo',
        )),
      );
      await expectGolden(tester, 'components_dialog');
    });

    testWidgets('the confirm — irreversible, type-to-confirm', (tester) async {
      // The top rung, and the state nobody had ever looked at: the confirm is
      // DISABLED until the word matches. A6 put the pro salon delete on this
      // rung too — it used to take one tap.
      await pumpDialog(
        tester,
        (context) => unawaited(showConfirmDialog(
          context,
          title: 'Supprimer mon compte',
          // Verbatim from `profile_screen.dart` — this golden photographs the
          // REAL account-deletion dialog, so the two move together. L1 changed
          // it because it was false: appointments and reviews are not deleted,
          // they survive without you.
          message: 'Cette action est définitive. Votre profil, vos favoris et '
              'vos notifications sont supprimés ; vos rendez-vous et vos avis '
              'restent chez le salon, sans votre nom. Pensez à exporter vos '
              'données avant.',
          confirmLabel: 'Supprimer définitivement',
          icon: Icons.warning_amber_rounded,
          confirmWord: 'SUPPRIMER',
        )),
        size: const Size(390, 520),
      );
      await expectGolden(tester, 'components_dialog_confirm');
    });

    testWidgets('the snackbar kinds + an action', (tester) async {
      // The product's FIRST snackbar golden. Four sibling messengers, each
      // driven through the real `AppSnackBar`, so the sheet cannot drift from
      // the component the way a hand-built fixture can.
      //
      // Deterministic without `pumpAndSettle` (an infinite Lottie elsewhere
      // rules that out): the entrance is a finite 250ms, and the earliest
      // dismissal is 3s — the 400ms shutter sits in a 2.6s-wide still window.
      final keys = List.generate(4, (_) => GlobalKey<ScaffoldMessengerState>());
      goldenSurface(tester, size: const Size(390, 460));
      await tester.pumpWidget(
        goldenApp(
          home: Column(
            children: [
              for (final k in keys)
                Expanded(
                  child: ScaffoldMessenger(
                    key: k,
                    child: const Scaffold(
                      backgroundColor: AppColors.background,
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
      await tester.pump();

      AppSnackBar.showOn(keys[0].currentState!, 'Rendez-vous accepté',
          kind: SnackKind.success);
      AppSnackBar.showOn(keys[1].currentState!, 'Fonctionnalité à venir');
      AppSnackBar.showOn(keys[2].currentState!, 'Impossible d’ouvrir WhatsApp.',
          kind: SnackKind.error);
      AppSnackBar.showOn(
        keys[3].currentState!,
        'Photo supprimée',
        kind: SnackKind.success,
        action: SnackAction(label: 'Annuler', onPressed: () {}),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await expectGolden(tester, 'components_snackbar');
    });
  }, skip: kGoldensSkip);
}
