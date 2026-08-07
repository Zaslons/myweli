import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/core/theme/app_theme.dart';
import 'package:myweli/core/theme/colors.dart';
import 'package:myweli/widgets/common/app_button.dart';
import 'package:myweli/widgets/common/apple_logo.dart';
import 'package:myweli/widgets/common/google_g_logo.dart';

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
    setUpAll(loadRealFonts);

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
              ],
            ),
          ),
          // The two social buttons, side by side — the ONLY place they are seen
          // together. They live on three screens (consumer login, pro login,
          // pro register) and drifted into three different appearances there,
          // because nothing ever rendered them next to each other.
          //
          // The previous specimen here was `icon: Icons.g_mobiledata` — a
          // Material glyph no screen has ever used — so this golden depicted a
          // button that did not exist while the real one went unwatched.
          GoldenSection(
            title: 'Social sign-in — one family, two fills',
            child: Column(
              children: [
                const AppButton(
                  text: 'Continuer avec Google',
                  onPressed: _noop,
                  type: AppButtonType.secondary,
                  leading: GoogleGLogo(),
                ),
                const SizedBox(height: AppTheme.spacingS),
                const AppButton(
                  text: 'Continuer avec Apple',
                  onPressed: _noop,
                  leading: AppleLogo(),
                ),
                const SizedBox(height: AppTheme.spacingS),
                // Disabled, because `leading:` is NOT tinted the way `icon:`
                // is: a hardcoded-white mark would be invisible against the
                // grey disabled fill, and only a rendered pixel shows it.
                // Both marks must still read here.
                const AppButton(
                  text: 'Continuer avec Google',
                  type: AppButtonType.secondary,
                  leading: GoogleGLogo(),
                ),
                const SizedBox(height: AppTheme.spacingS),
                const AppButton(
                  text: 'Continuer avec Apple',
                  leading: AppleLogo(),
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
