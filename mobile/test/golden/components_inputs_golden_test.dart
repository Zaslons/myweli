import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/core/theme/app_theme.dart';
import 'package:myweli/core/theme/colors.dart';
import 'package:myweli/widgets/common/app_text_field.dart';

import '../support/golden.dart';

/// The text field in all five of its states (docs/design/SYSTEM.md §11.1, §14).
///
/// **This is the golden for the WCAG 1.4.11 failure** (register row 2). Today
/// `inputDecorationTheme` draws its border with `AppColors.border` — `#D0D0D0`,
/// **1.44:1** against the background. The outline of every text field in the
/// product is, to a low-vision user, not there. A1 moves it to `borderStrong`
/// (3.22:1) and this image is where that becomes undeniable.
///
/// The `error` row is also the ONE pattern §14 says every form should use — and
/// which exactly one caller in the codebase actually uses (register row 19).
void main() {
  group('goldens', () {
    setUpAll(loadGoldenFonts);

    testWidgets('the text field, in every state', (tester) async {
      goldenSurface(tester, size: const Size(390, 720));
      await tester.pumpWidget(goldenApp(child: const _InputSheet()));
      await tester.pump();

      // The focused state has to be REAL — `borderFocus` at 2px is a token, and
      // a sheet that never focuses anything would never render it. Focus it the
      // way a user would, and let the border tween finish (see focusAndSettle:
      // one pump short and this captures an unfocused field).
      await focusAndSettle(
          tester, find.byKey(const Key('golden-focused-field')));

      await expectGolden(tester, 'components_inputs');
    });
  }, skip: kGoldensSkip);
}

class _InputSheet extends StatelessWidget {
  const _InputSheet();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.background,
      padding: const EdgeInsets.all(AppTheme.spacingM),
      child: ListView(
        physics: const NeverScrollableScrollPhysics(),
        children: [
          GoldenSection(
            title: 'enabled — border #D0D0D0, 1.44:1',
            child: AppTextField(
              label: 'Nom complet',
              controller: TextEditingController(text: 'Awa Koné'),
            ),
          ),
          const GoldenSection(
            title: 'hint only',
            child: AppTextField(
              label: 'Adresse e-mail',
              hint: 'awa@exemple.ci',
            ),
          ),
          GoldenSection(
            title: 'focused — borderFocus, 2px',
            child: AppTextField(
              key: const Key('golden-focused-field'),
              label: 'Numéro de téléphone',
              controller: TextEditingController(text: '07 07 12 34 56'),
            ),
          ),
          const GoldenSection(
            title: 'error — the field-anchored message (§14)',
            child: AppTextField(
              label: 'Code de vérification',
              errorText: 'Le code doit comporter 6 chiffres.',
            ),
          ),
          GoldenSection(
            title: 'disabled',
            child: AppTextField(
              label: 'Salon',
              controller: TextEditingController(text: 'Beauté Divine'),
              enabled: false,
            ),
          ),
        ],
      ),
    );
  }
}
