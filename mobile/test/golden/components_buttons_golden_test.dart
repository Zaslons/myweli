import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/core/theme/app_theme.dart';
import 'package:myweli/core/theme/colors.dart';
import 'package:myweli/widgets/common/app_button.dart';

import '../support/golden.dart';

/// The buttons (docs/design/SYSTEM.md §11.1), at their real theme sizes.
///
/// This is the sheet A3 will change. Two of the register's rows are visible here
/// as SHAPE, not colour:
///   · row 10 — `textButtonTheme.minimumSize = Size(0, 40)`, below the 48px
///     minimum. The text button is measurably shorter than its siblings.
///   · row 11 — `elevatedButtonTheme.minimumSize = Size(double.infinity, 48)`.
///     Every raw ElevatedButton is forced full-width; `isFullWidth: false` only
///     works because AppButton overrides the theme.
///
/// `isLoading` is deliberately NOT captured: it renders `BrandLoader`, an
/// infinitely-repeating Lottie, and a golden of an animation frame is a flake
/// (SYSTEM.md §20). Its behaviour is covered by widget tests instead.
void main() {
  group('goldens', () {
    setUpAll(loadGoldenFonts);

    testWidgets('the buttons', (tester) async {
      await pumpGolden(
        tester,
        const _ButtonSheet(),
        size: const Size(390, 940),
      );
      await expectGolden(tester, 'components_buttons');
    });
  }, skip: kGoldensSkip);
}

class _ButtonSheet extends StatelessWidget {
  const _ButtonSheet();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.background,
      padding: const EdgeInsets.all(AppTheme.spacingM),
      child: ListView(
        physics: const NeverScrollableScrollPhysics(),
        children: [
          GoldenSection(
            title: 'AppButton — enabled',
            child: Column(
              children: [
                const AppButton(text: 'Réserver', onPressed: _noop),
                const SizedBox(height: AppTheme.spacingS),
                const AppButton(
                  text: 'Voir le salon',
                  onPressed: _noop,
                  type: AppButtonType.secondary,
                ),
                const SizedBox(height: AppTheme.spacingS),
                const AppButton(
                  text: 'Annuler',
                  onPressed: _noop,
                  type: AppButtonType.text,
                ),
                const SizedBox(height: AppTheme.spacingS),
                const AppButton(
                  text: 'Continuer avec Google',
                  onPressed: _noop,
                  type: AppButtonType.secondary,
                  icon: Icons.g_mobiledata,
                ),
              ],
            ),
          ),
          const GoldenSection(
            title: 'AppButton — disabled (onPressed: null)',
            child: Column(
              children: [
                AppButton(text: 'Réserver'),
                SizedBox(height: AppTheme.spacingS),
                AppButton(text: 'Voir le salon', type: AppButtonType.secondary),
                SizedBox(height: AppTheme.spacingS),
                AppButton(text: 'Annuler', type: AppButtonType.text),
              ],
            ),
          ),
          const GoldenSection(
            title: 'AppButton — isFullWidth: false',
            child: Row(
              children: [
                AppButton(
                  text: 'Confirmer',
                  onPressed: _noop,
                  isFullWidth: false,
                ),
                SizedBox(width: AppTheme.spacingS),
                AppButton(
                  text: 'Plus tard',
                  onPressed: _noop,
                  type: AppButtonType.secondary,
                  isFullWidth: false,
                ),
              ],
            ),
          ),
          // Raw Material buttons — i.e. what the THEME does, unmediated by
          // AppButton. The TextButton's 40px height (< 48) is the violation.
          const GoldenSection(
            title: 'Raw M3 buttons (the theme, unmediated)',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ElevatedButton(onPressed: _noop, child: Text('ElevatedButton')),
                SizedBox(height: AppTheme.spacingS),
                OutlinedButton(onPressed: _noop, child: Text('OutlinedButton')),
                SizedBox(height: AppTheme.spacingS),
                TextButton(onPressed: _noop, child: Text('TextButton — 48px')),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

void _noop() {}
