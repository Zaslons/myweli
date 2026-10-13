import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/models/api_response.dart';
import 'package:myweli/models/provider.dart' as models;
import 'package:myweli/providers/provider_provider.dart';
import 'package:myweli/screens/providers/provider_detail_screen.dart';
import 'package:myweli/services/interfaces/provider_service_interface.dart';
import 'package:myweli/services/mock/mock_data.dart';
import 'package:myweli/widgets/common/timed_cached_image.dart';
import 'package:provider/provider.dart';

import '../support/pump_app.dart';

/// A service that fails the test if the preview asks it anything.
///
/// **This is the gate the source pin cannot be.** `/pro/apercu` names no
/// forbidden token — it constructs `ProviderDetailScreen(preview: true)`, and
/// the public fetch happened inside that SHARED screen, which the consumer app
/// owns and legitimately uses. `pro_reads_own_salon_test.dart` went red on
/// three of four surfaces and would have gone green while the worst one — the
/// owner's own pre-publish preview — still knocked on the anonymous door.
///
/// So the preview is held behaviourally: the only way to pass is to not call.
class _ForbiddenProviderService implements ProviderServiceInterface {
  @override
  Future<ApiResponse<models.Provider>> getProviderById(String id) {
    fail(
      'the owner preview must not read its own salon through the PUBLIC '
      'route — it is signed in, and this route is about to stop serving '
      'drafts (T51; salon-state-and-refusals.md Decision C)',
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => fail(
    'the owner preview called ${invocation.memberName} on the public '
    'provider service',
  );
}

/// « Aperçu de ma page » in the pro app (docs/design/pro-salon-lifecycle.md
/// B5): the consumer detail screen in preview mode renders the LOGGED-OUT
/// client view with ONLY ProviderProvider registered — pumping without any
/// consumer session provider is itself the proof that preview mode never
/// reads them (a regression would throw ProviderNotFoundException).
///
/// It now also proves where the data came FROM. The salon is seeded through
/// `ProviderProvider.showPreloaded`, exactly as the pro-side preview screen
/// does after its authenticated `GET /me/provider` — mirroring web, where
/// `SalonPreviewClient` fetches `/me/provider` and passes the object into the
/// shared `ProviderView`.
void main() {
  setUpAll(() async {
    await initializeDateFormatting('fr_FR');
    serviceLocator.providerService = _ForbiddenProviderService();
  });

  Widget wrap({models.Provider? salon}) {
    final providers = ProviderProvider();
    // What the pro preview screen does with the payload of /me/provider.
    providers.showPreloaded(
      salon ?? MockData.providers.firstWhere((p) => p.id == 'provider1'),
    );
    return wrapApp(
      providers: [ChangeNotifierProvider.value(value: providers)],
      home: const ProviderDetailScreen(providerId: 'provider1', preview: true),
    );
  }

  testWidgets(
    'preview renders the salon with the owner banner + disabled CTA',
    (tester) async {
      await tester.pumpWidget(wrap());
      await tester.pumpAndSettle();

      // The salon loaded (mock seed) — the client view is on screen.
      expect(
        find.text('Aperçu — voici ce que verront vos clients.'),
        findsOneWidget,
      );
      expect(find.text('Réserver (après la mise en ligne)'), findsOneWidget);

      // The disabled CTA really is disabled. (ElevatedButton.icon builds a
      // private subtype — byType(ElevatedButton) would not match it.)
      final btn = tester.widget<ElevatedButton>(
        find.ancestor(
          of: find.text('Réserver (après la mise en ligne)'),
          matching: find.byWidgetPredicate((w) => w is ElevatedButton),
        ),
      );
      expect(btn.onPressed, isNull);

      // Consumer-session UI is absent: no favorite heart, and no
      // « Vos rendez-vous ici » at all — a signed-out client sees none, so
      // neither does the owner's preview. It used to show the sign-in
      // prompt (docs/design/salon-rating-new-and-visits-card.md §2.3).
      expect(find.byIcon(Icons.favorite_border), findsNothing);
      expect(find.text('Vos rendez-vous ici'), findsNothing);
      expect(
        find.text('Connectez-vous pour voir vos rendez-vous.'),
        findsNothing,
      );
    },
  );

  /// The App Store screenshot that could not be taken (2026-10-12): a new
  /// salon's page read « ★ 0.0 · 0 avis » under its name.
  testWidgets('a salon with no review reads « Nouveau », never « 0.0 »', (
    tester,
  ) async {
    final fresh = MockData.providers
        .firstWhere((p) => p.id == 'provider1')
        .copyWith(rating: 0, reviewCount: 0, reviews: const []);
    await tester.pumpWidget(wrap(salon: fresh));
    await tester.pumpAndSettle();

    expect(find.text('Nouveau'), findsWidgets);
    expect(find.text('Pas encore d’avis.'), findsOneWidget);
    expect(find.textContaining('0.0'), findsNothing);
    expect(find.textContaining('0,0'), findsNothing);
    expect(find.text('0 avis'), findsNothing);
  });

  /// The owner's complaint, held where it happened: « Aperçu » showed no
  /// cover where the website does (docs/design/salon-cover-photo.md §1). The
  /// photo must come from the payload the preview was SEEDED with — the
  /// forbidden public service above fails the test if anything fetches.
  testWidgets('preview renders the cover from the /me/provider payload', (
    tester,
  ) async {
    // Distinct from every MockData URL, so a cover drawn from anywhere but
    // this payload cannot match.
    const cover = 'asset:assets/images/providers/beaute_divine_photo.png';
    final salon = MockData.providers
        .firstWhere((p) => p.id == 'provider1')
        .copyWith(
          imageUrls: const [
            cover,
            'asset:assets/images/providers/spa_relax_photo.png',
          ],
        );
    await tester.pumpWidget(wrap(salon: salon));
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byType(SliverAppBar),
        matching: find.byWidgetPredicate(
          (w) => w is TimedCachedImage && w.imageUrl == cover,
        ),
      ),
      findsOneWidget,
      reason: 'the cover is imageUrls[0] of the seeded payload, at the top',
    );
    expect(
      find.bySemanticsLabel('Photo du salon ${salon.name}'),
      findsOneWidget,
    );
    // Still the owner's view: no heart, banner on.
    expect(find.byIcon(Icons.favorite_border), findsNothing);
    expect(
      find.text('Aperçu — voici ce que verront vos clients.'),
      findsOneWidget,
    );
  });

  testWidgets('a payload without photos previews the header without a cover', (
    tester,
  ) async {
    final salon = MockData.providers
        .firstWhere((p) => p.id == 'provider1')
        .copyWith(imageUrls: const []);
    await tester.pumpWidget(wrap(salon: salon));
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byType(SliverAppBar),
        matching: find.byType(TimedCachedImage),
      ),
      findsNothing,
      reason: 'no photo, no cover — and no logo URL either, so no image',
    );
    expect(find.bySemanticsLabel(RegExp('^Photo du salon')), findsNothing);
    expect(find.byIcon(Icons.store_outlined), findsOneWidget);
    expect(find.text('Aucune photo pour le moment.'), findsOneWidget);
  });
}
