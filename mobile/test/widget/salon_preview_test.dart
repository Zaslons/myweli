import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/providers/provider_provider.dart';
import 'package:myweli/screens/providers/provider_detail_screen.dart';
import 'package:myweli/services/mock/mock_provider_service.dart';
import 'package:provider/provider.dart';

import '../support/pump_app.dart';

/// « Aperçu de ma page » in the pro app (docs/design/pro-salon-lifecycle.md
/// B5): the consumer detail screen in preview mode renders the LOGGED-OUT
/// client view with ONLY ProviderProvider registered — pumping without any
/// consumer session provider is itself the proof that preview mode never
/// reads them (a regression would throw ProviderNotFoundException).
void main() {
  setUpAll(() async {
    await initializeDateFormatting('fr_FR');
    serviceLocator.providerService = MockProviderService();
  });

  Widget wrap() => wrapApp(
        providers: [
          ChangeNotifierProvider(create: (_) => ProviderProvider()),
        ],
        home:
            const ProviderDetailScreen(providerId: 'provider1', preview: true),
      );

  testWidgets('preview renders the salon with the owner banner + disabled CTA',
      (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    // The salon loaded (mock seed) — the client view is on screen.
    expect(find.text('Aperçu — voici ce que verront vos clients.'),
        findsOneWidget);
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
        find.text('Connectez-vous pour voir vos rendez-vous.'), findsOneWidget);
  });
}
