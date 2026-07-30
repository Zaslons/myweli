import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/core/theme/app_theme.dart';
import 'package:myweli/core/theme/colors.dart';
import 'package:myweli/core/theme/text_styles.dart';
import 'package:myweli/widgets/common/app_text_field.dart';

import '../support/fonts.dart';
import '../support/pump_app.dart';
import '_a11y.dart';

/// A7 — the field error is legible, unclipped and audible (SYSTEM.md §14
/// rule 1, §13.1, §13.3; register row 19).
///
/// Nothing in `test/a11y/` had ever pumped an **input** before this file, which
/// is how `inputDecorationTheme` shipped with error borders but no error TEXT:
/// `errorMaxLines` defaults to **1**, so the sentence telling the user how to
/// fix the form was the sentence they could not finish reading.
void main() {
  setUpAll(loadRealFonts);

  // The real message, from the real validator — not a fixture. It is the
  // longest one the product can produce, which is the case that clips.
  const longest = 'Le numéro doit comporter 10 chiffres (ex : 07 07 12 34 56).';

  Widget field({String? error = longest}) => Padding(
    padding: const EdgeInsets.all(AppTheme.spacingM),
    child: AppTextField(label: 'Numéro Mobile Money', errorText: error),
  );

  testWidgets('a two-clause error does not clip at 200 % text (§13.3)', (
    tester,
  ) async {
    await pumpAtTextScale(tester, SingleChildScrollView(child: field()));
    expect(tester.takeException(), isNull);

    // `takeException` alone would pass on a truncation, because clipping to
    // one line is not an overflow — it is a silent amputation. `InputDecorator`
    // always sets `overflow: ellipsis` on the error and bounds it with
    // `errorMaxLines`, so the line count IS the assertion.
    final rendered = tester.widget<Text>(find.text(longest));
    expect(
      rendered.maxLines,
      greaterThan(1),
      reason:
          'at errorMaxLines: 1 — the Material default this theme used to '
          'inherit — the sentence telling the user how to fix the form is '
          'cut off mid-instruction',
    );
    expect(find.text(longest), findsOneWidget);
  });

  testWidgets('the error grows the field instead of overlapping it', (
    tester,
  ) async {
    await pumpApp(tester, home: Scaffold(body: field(error: null)));
    final clean = tester.getSize(find.byType(AppTextField)).height;

    await pumpApp(tester, home: Scaffold(body: field()));
    final errored = tester.getSize(find.byType(AppTextField)).height;

    expect(
      errored,
      greaterThan(clean),
      reason:
          'the message needs its own room — a fixed-height field would '
          'paint it over the next control (§13.3)',
    );
  });

  testWidgets('the message is IN the field’s semantics — that is the '
      'association §14 rule 1 asks for', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpApp(tester, home: Scaffold(body: field()));

    // MEASURED, because the obvious assumption is wrong: Flutter does NOT fold
    // `errorText` into the field's own label. It renders as a CHILD node of the
    // field's semantics node, so a screen reader reaches it immediately after
    // the input rather than hearing it with the input. `MergeSemantics` cannot
    // change that — a TextField's node is a semantics boundary; wrapping one
    // produces a byte-identical tree.
    //
    // So Flutter has no `aria-describedby`. What it does give is structural
    // association, and that is what this gate holds: the message is a
    // descendant of the field it belongs to, and it is REACHABLE — the
    // opposite of A6's modal-pruned snackbar, which was on screen and absent
    // from the tree.
    //
    // Not `SemanticsService` — A6 proved `supportsAnnounce` is false on
    // Android, where a direct announcement clears TalkBack's queue.
    expect(
      find.bySemanticsLabel(longest),
      findsOneWidget,
      reason: 'the error must be in the semantics tree at all',
    );

    var foundUnderTheField = false;
    void walk(SemanticsNode node) {
      if (node.label == longest) foundUnderTheField = true;
      node.visitChildren((child) {
        walk(child);
        return true;
      });
    }

    walk(tester.getSemantics(find.byType(TextField)));
    expect(
      foundUnderTheField,
      isTrue,
      reason:
          'if this goes red the message detached from its field — it '
          'became decoration: visible, but orphaned from the input the user '
          'has to fix',
    );
    handle.dispose();
  });

  testWidgets('it renders on token, at the §13.1 text floor', (tester) async {
    await pumpApp(tester, home: Scaffold(body: field()));
    final style = tester.widget<Text>(find.text(longest)).style!;
    // INHERITED, not configured: A3's ColorScheme.error and textTheme.bodySmall
    // already resolve to these. A7 briefly added an `errorStyle` to the theme
    // and measured it byte-identical, so the theme says nothing about the error
    // text and this gate guards the inheritance instead — if either token moves
    // out from under the field, it goes red.
    //
    // `error` #8B0000 is pinned ≥ 4.5:1 on all four surfaces by
    // design_contrast_test.dart; this proves the field actually wears it.
    expect(style.color, AppColors.error);
    expect(style.fontSize, AppTextStyles.bodySmall.fontSize);
  });
}
