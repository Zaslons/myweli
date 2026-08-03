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

  Widget wrap() {
    final providers = ProviderProvider();
    // What the pro preview screen does with the payload of /me/provider.
    providers.showPreloaded(
      MockData.providers.firstWhere((p) => p.id == 'provider1'),
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

      // Consumer-session UI is absent: no favorite heart, and the
      // rendez-vous section shows the logged-out copy.
      expect(find.byIcon(Icons.favorite_border), findsNothing);
      expect(
        find.text('Connectez-vous pour voir vos rendez-vous.'),
        findsOneWidget,
      );
    },
  );
}
