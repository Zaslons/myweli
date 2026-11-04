import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/core/theme/app_theme.dart';
import 'package:myweli/core/theme/text_styles.dart';
import 'package:myweli/core/utils/salon_id.dart';
import 'package:myweli/models/provider.dart' as models;
import 'package:myweli/providers/provider_provider.dart';
import 'package:myweli/screens/providers/provider_detail_screen.dart';
import 'package:myweli/services/mock/mock_data.dart';
import 'package:myweli/services/mock/mock_provider_service.dart';
import 'package:provider/provider.dart';

import '../support/fonts.dart';
import '_a11y.dart';

/// The salon header's stacking threshold, at the scales the matrix skips (A13).
///
/// **Two blind spots let a live defect through, and this file closes both.**
/// `layout_test.dart` samples `scales = [1, 2]` and the whole defective band
/// lies strictly between them; and `MockData` sets `verified` on no provider at
/// all, so the badge that causes it never renders in any test.
///
/// The badge is a SIBLING of the name's `Flexible` in the same `Row`, and a
/// `RenderFlex` lays non-flex children out first — so `spacingS` + `iconS` (28)
/// come off the name's box. 224dp becomes **196dp at 360**, and the crossing
/// moves from 1.66× down to **1.45×**. A13's first threshold was 1.6, taken
/// from the unverified population, which left the defect live across
/// 1.45×–1.60× on exactly the salons the marketplace promotes.
///
/// This reproduces the header's geometry rather than pumping the screen: the
/// screen needs a signed-in session, a provider fetch and five settle rounds
/// per configuration, and what is under test is one `Row`'s arithmetic.
///
/// **Since the cover there are two headers** (docs/design/salon-cover-photo.md
/// §2), and the replicas below describe only the one WITHOUT a photo. So the
/// file also pumps the real screen — through the owner preview, which is
/// seeded and fetches nothing, so it costs one pump — for both branches: the
/// no-photo header must still stack a verified salon inside the band, and the
/// cover header must not need to, because its name has the whole row.
void main() {
  setUpAll(() async {
    await loadRealFonts();
    // `ProviderProvider` takes its service at construction. The preview never
    // calls it (salon_preview_test.dart holds that); this only lets it exist.
    serviceLocator.providerService = MockProviderService();
  });

  /// `W − screen padding (24×2) − logo (72) − gap (16)`, then minus the badge.
  Widget header({required bool verified, required double width}) => Scaffold(
    body: Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacingL),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(width: 72, height: 72),
          const SizedBox(width: AppTheme.spacingM),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Flexible(
                  child: Text(
                    'Salon Excellence',
                    style: AppTextStyles.headlineMedium,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (verified) ...[
                  const SizedBox(width: AppTheme.spacingS),
                  const Icon(Icons.verified, size: AppTheme.iconS),
                ],
              ],
            ),
          ),
        ],
      ),
    ),
  );

  // **Per width, because the crossing moves with it.** A verified name box is
  // 196 / 211 / 226dp and « Excellence » is 134.85dp at 1×, so it breaks above
  // 1.453 / 1.565 / 1.676. Each pair below sits just past its own crossing and
  // inside the band `layout_test`'s `[1, 2]` cannot see — a single scale would
  // have been green at 375 and 390 and taught us nothing, which is exactly how
  // the first version of this file over-generalised and went red.
  for (final (width, scale) in [(360.0, 1.5), (375.0, 1.6), (390.0, 1.7)]) {
    testWidgets(
      'a verified salon breaks un-stacked at $scale× on ${width.toInt()}dp',
      (tester) async {
        await pumpAtWidth(
          tester,
          width: width,
          scale: scale,
          home: header(verified: true, width: width),
        );
        expect(
          () => expectNoMidWordBreak(
            tester,
            'Salon Excellence',
            '${width.toInt()}dp × $scale×',
          ),
          throwsA(isA<TestFailure>()),
          reason:
              'if this stops breaking, the 28dp badge no longer costs the '
              'name its box and _headerStacksAboveVerified can be re-derived',
        );
      },
    );
  }

  // …and the same geometry WITHOUT the badge is fine at 1.5×, which is why the
  // two thresholds are different numbers rather than one conservative one.
  testWidgets('an unverified salon is still fine un-stacked at 1.5× on 360dp', (
    tester,
  ) async {
    await pumpAtWidth(
      tester,
      width: 360,
      scale: 1.5,
      home: header(verified: false, width: 360),
    );
    expectNoMidWordBreak(tester, 'Salon Excellence', '360dp × 1.5×');
  });

  // ---- the real screen, both branches ------------------------------------

  models.Provider salon({required bool withPhotos}) {
    final seed = MockData.providers.firstWhere((p) => p.id == 'provider1');
    return seed.copyWith(
      verified: true, // the worse population: the badge costs the name 28dp
      imageUrls: withPhotos ? null : const [],
    );
  }

  Future<void> pumpPreview(
    WidgetTester tester, {
    required models.Provider salon,
    required double width,
    required double scale,
  }) => pumpAtWidth(
    tester,
    width: width,
    scale: scale,
    providers: [
      ChangeNotifierProvider.value(
        value: ProviderProvider()..showPreloaded(salon),
      ),
    ],
    home: const ProviderDetailScreen(
      providerId: SalonId('provider1'),
      preview: true,
    ),
  );

  // Branch B, inside the band `layout_test`'s `[1, 2]` cannot see: the same
  // three just-past-the-crossing pairs as the replicas, on the real header.
  for (final (width, scale) in [(360.0, 1.5), (375.0, 1.6), (390.0, 1.7)]) {
    testWidgets('without photos, a verified salon stacks at $scale× on '
        '${width.toInt()}dp and keeps its name whole', (tester) async {
      await pumpPreview(
        tester,
        salon: salon(withPhotos: false),
        width: width,
        scale: scale,
      );
      final at = '${width.toInt()}dp × $scale×';
      // No logo → the « shop » disc, which is the thing that stacks.
      final logo = tester.getRect(find.byIcon(Icons.store_outlined));
      final name = tester.getRect(find.text('Salon Excellence').first);
      expect(
        name.top,
        greaterThanOrEqualTo(logo.bottom),
        reason: 'the logo must sit ABOVE the name at $at (A13)',
      );
      expectNoMidWordBreak(tester, 'Salon Excellence', at);
      expect(tester.takeException(), isNull, reason: 'A: $at');
    });
  }

  // Branch A, at the contract point: under the cover the name is not beside
  // a logo, so a verified salon gets `W − 48 − 28` — 284dp at 360 — and
  // « Excellence » (269.7dp at 2×) fits without stacking anything.
  for (final width in [360.0, 375.0, 390.0]) {
    testWidgets('under a cover, a verified salon keeps its name whole at 2× on '
        '${width.toInt()}dp with the full row', (tester) async {
      await pumpPreview(
        tester,
        salon: salon(withPhotos: true),
        width: width,
        scale: 2,
      );
      final at = '${width.toInt()}dp × 2×';
      expect(
        find.byIcon(Icons.store_outlined),
        findsNothing,
        reason: 'C: the cover header draws no logo disc beside the name',
      );
      expect(
        tester.getTopLeft(find.text('Salon Excellence').first).dx,
        AppTheme.spacingL,
        reason:
            'the name starts at the page gutter at $at — nothing sits '
            'beside it, which is why this branch needs no stacking',
      );
      expectNoMidWordBreak(tester, 'Salon Excellence', at);
      expect(tester.takeException(), isNull, reason: 'A: $at');
    });
  }
}
