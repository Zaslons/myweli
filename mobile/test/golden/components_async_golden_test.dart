import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/core/constants/failure_messages.dart';
import 'package:myweli/core/theme/app_theme.dart';
import 'package:myweli/core/theme/colors.dart';
import 'package:myweli/core/theme/text_styles.dart';
import 'package:myweli/widgets/common/app_async_view.dart';
import 'package:myweli/widgets/common/app_card.dart';
import 'package:myweli/widgets/common/app_skeleton.dart';

import '../support/golden.dart';

/// The shared async pieces of B9.8 (docs/design/hygiene-batch9.md §2.7.2):
/// the one load error, the card, and the skeletons — one photo each, as
/// §2.7 promised.
///
/// The skeletons can be photographed BECAUSE they are still (Q11): the
/// spinner they replace is `BrandLoader`, an endless Lottie no golden can pin.
void main() {
  group('goldens', () {
    setUpAll(loadRealFonts);

    testWidgets('the load error: no connection, anything else', (tester) async {
      await pumpGolden(
        tester,
        const _Page(
          children: [
            SizedBox(
              height: 300,
              child: AppErrorView(
                message: kNoConnectionMessage,
                onRetry: _noop,
              ),
            ),
            SizedBox(
              height: 260,
              child: AppErrorView(message: kGenericErrorMessage),
            ),
          ],
        ),
        size: const Size(390, 620),
      );
      await expectGolden(tester, 'components_async_error');
    });

    testWidgets('the card: plain, outlined, tappable', (tester) async {
      await pumpGolden(
        tester,
        _Page(
          children: [
            const AppCard(
              child: Text('Une carte', style: AppTextStyles.bodyLarge),
            ),
            const SizedBox(height: AppTheme.spacingM),
            const AppCard(
              outlined: true,
              child: Text('Une carte choisie', style: AppTextStyles.bodyLarge),
            ),
            const SizedBox(height: AppTheme.spacingM),
            AppCard(
              onTap: _noop,
              child: const Text(
                'Une carte à toucher',
                style: AppTextStyles.bodyLarge,
              ),
            ),
          ],
        ),
        size: const Size(390, 300),
      );
      await expectGolden(tester, 'components_async_card');
    });

    testWidgets('the skeletons: cards, rows, a page, photos, choices', (
      tester,
    ) async {
      await pumpGolden(
        tester,
        const _Page(
          padding: EdgeInsets.zero,
          children: [
            SkeletonCardList(count: 1),
            SkeletonCardList(count: 1, lead: SkeletonLead.avatar),
            SkeletonCardList(count: 1, lead: SkeletonLead.thumbnail),
            SkeletonCardList(count: 1, block: true),
            SkeletonTileList(count: 2),
            SkeletonDetail(sections: 1),
            SkeletonGrid(count: 3),
            Padding(
              padding: EdgeInsets.all(AppTheme.spacingM),
              child: SkeletonPills(count: 5),
            ),
          ],
        ),
        size: const Size(390, 1380),
      );
      await expectGolden(tester, 'components_async_skeletons');
    });
  }, skip: kGoldensSkip);
}

void _noop() {}

class _Page extends StatelessWidget {
  const _Page({
    required this.children,
    this.padding = const EdgeInsets.all(AppTheme.spacingM),
  });

  final List<Widget> children;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: AppColors.background,
    child: Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    ),
  );
}
