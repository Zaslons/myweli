import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/widgets/common/legal_consent_text.dart';

import '_a11y.dart';

/// docs/design/pro-app-batch7.md §2.12 (B7.12) — a screen reader finds TWO
/// links in the consent sentence, each its own node, each named and each
/// activatable. The widget built them as two real buttons from the start
/// (no `TextSpan` recognizer); what was missing was the proof — SYSTEM §21
/// row 49, « the semantics half is still unasserted ».
void main() {
  testWidgets('two link nodes: « Conditions d’utilisation » and « Politique '
      'de confidentialité », each tappable', (tester) async {
    final handle = await pumpForA11y(tester, const LegalConsentText());

    final terms = tester.getSemantics(find.text('Conditions d’utilisation'));
    final privacy = tester.getSemantics(
      find.text('Politique de confidentialité'),
    );

    expect(terms.id, isNot(privacy.id), reason: 'one node, two links');
    for (final (node, name) in [
      (terms, 'Conditions d’utilisation'),
      (privacy, 'Politique de confidentialité'),
    ]) {
      final data = node.getSemanticsData();
      expect(data.hasFlag(SemanticsFlag.isLink), isTrue, reason: name);
      expect(data.hasAction(SemanticsAction.tap), isTrue, reason: name);
      expect(data.label, name, reason: 'the link says only its own name');
    }
    handle.dispose();
  });
}
