import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/core/router/admin_router.dart';
import 'package:myweli/core/theme/app_theme.dart';
import 'package:myweli/screens/admin/admin_login_screen.dart';
import 'package:myweli/screens/admin/admin_salon_validation_detail_screen.dart';
import 'package:myweli/services/interfaces/session_store.dart';

import '../support/admin_console.dart';
import '../support/fonts.dart';
import '../support/pump_app.dart';
import '../support/surface.dart';

/// The admin e-mail's « Ouvrir la demande » lands on the request (B0.18 —
/// docs/design/salon-go-live-approval.md §4.1, §8.2), through the console's
/// REAL router: `createAdminRouter`, its redirect and its routes. The link is
/// `https://admin.myweli.com/#/admin/salon-validations/{id}`; the console
/// uses hash URLs, so the browser hands go_router the fragment.
void main() {
  setUpAll(loadRealFonts);

  final link = Uri.parse(
    'https://admin.myweli.com/#/admin/salon-validations/provider_1',
  );

  Future<ConsoleProviders> open(
    WidgetTester t, {
    required bool signedIn,
  }) async {
    final store = signedIn ? await signedInStore() : InMemorySessionStore();
    final p = ConsoleProviders(FakeAdminServer(), store);
    await p.auth.restore();
    final router = createAdminRouter(p.auth);
    addTearDown(router.dispose);
    pinSurface(t, size: const Size(1400, 900));
    await t.pumpWidget(
      wrapApp(
        providers: p.list(),
        routerConfig: router,
        theme: AppTheme.themeData(fontFamily: kRealFont),
      ),
    );
    await t.pumpAndSettle();
    router.go(link.fragment);
    await t.pumpAndSettle();
    return p;
  }

  testWidgets('signed in: the link opens that request', (t) async {
    final p = await open(t, signedIn: true);
    final screen = t.widget<AdminSalonValidationDetailScreen>(
      find.byType(AdminSalonValidationDetailScreen),
    );
    expect(screen.id, 'provider_1');
    expect(p.detail.id, 'provider_1');
    expect(find.text('Valider la mise en ligne'), findsOneWidget);
  });

  testWidgets('signed out: the login, then — signed in — the request, not '
      'the dashboard', (t) async {
    final p = await open(t, signedIn: false);
    expect(find.byType(AdminLoginScreen), findsOneWidget);
    expect(find.byType(AdminSalonValidationDetailScreen), findsNothing);

    expect(await p.auth.login('admin@myweli.com', 'secret'), isTrue);
    await t.pumpAndSettle();
    expect(find.byType(AdminSalonValidationDetailScreen), findsOneWidget);
    expect(find.text('Valider la mise en ligne'), findsOneWidget);
  });
}
