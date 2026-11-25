import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/core/utils/salon_id.dart';
import 'package:myweli/providers/auth_provider.dart';
import 'package:myweli/providers/favorites_provider.dart';
import 'package:myweli/providers/provider_provider.dart';
import 'package:myweli/screens/providers/provider_list_screen.dart';
import 'package:myweli/services/mock/mock_auth_service.dart';
import 'package:myweli/services/mock/mock_data.dart';
import 'package:myweli/services/mock/mock_favorites_service.dart';
import 'package:myweli/services/mock/mock_provider_service.dart';
import 'package:myweli/widgets/common/commune_pill.dart';
import 'package:provider/provider.dart' hide Provider;
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fonts.dart';
import '../support/secure_storage.dart';
import '../support/settle.dart';
import '_a11y.dart';

/// docs/design/consumer-search.md §8, « A4 (app) — A11y »: the field's name,
/// the 48 × 48 targets, and the count row at 200 % on a 360dp phone.

/// 25 salons, all in Cocody: more than a page, and a commune to name.
final _salons = [
  for (var i = 0; i < 25; i++)
    MockData.providers.first.copyWith(
      id: SalonId('c${'$i'.padLeft(2, '0')}'),
      name: 'Salon Cocody $i',
      commune: 'Cocody',
    ),
];

void main() {
  setUpAll(() async {
    await initializeDateFormatting('fr_FR', null);
    await loadRealFonts();
    SharedPreferences.setMockInitialValues({});
    stubSecureStorage();
    serviceLocator.providerService = MockProviderService(salons: _salons);
    serviceLocator.authService = MockAuthService();
    serviceLocator.favoritesService = MockFavoritesService();
  });

  late ProviderProvider providers;

  /// Signed out, its session read finished outside the fake clock (as
  /// salon_location_map_test.dart does).
  Future<AuthProvider> signedOut(WidgetTester tester) async {
    late AuthProvider auth;
    await tester.runAsync(() async {
      auth = AuthProvider();
      for (var i = 0; i < 60 && auth.isLoading; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }
    });
    return auth;
  }

  Future<void> pumpList(
    WidgetTester tester, {
    required double width,
    double scale = 1,
    double height = 1600,
    String? commune,
  }) async {
    // The commune as the app restores it at start — no read, so nothing to
    // wait for under the fake clock (`setCommune` reloads the home's list).
    SharedPreferences.setMockInitialValues({
      'myweli_selected_commune_v1': ?commune,
    });
    providers = ProviderProvider();
    await providers.restoreSelectedCommune();
    final auth = await signedOut(tester);
    await pumpPushedAtWidth(
      tester,
      width: width,
      scale: scale,
      height: height,
      providers: [
        ChangeNotifierProvider.value(value: providers),
        ChangeNotifierProvider(create: (_) => FavoritesProvider()),
        ChangeNotifierProvider.value(value: auth),
      ],
      subject: const ProviderListScreen(),
      rounds: 3,
    );
  }

  Future<void> type(WidgetTester tester, String text) async {
    await tester.enterText(find.byType(TextField), text);
    await tester.pump(const Duration(milliseconds: 350));
    await settleMocks(tester);
  }

  for (final scale in [1.0, 2.0]) {
    final at = '360dp × $scale× text';

    testWidgets('every target is 48 × 48 and named, with a text and '
        '« Afficher plus », at $at', (tester) async {
      final handle = tester.ensureSemantics();
      // Tall enough that the twentieth card and the button are built.
      await pumpList(tester, width: 360, scale: scale, height: 12000);
      await type(tester, 'salon');

      final clear = find.widgetWithIcon(IconButton, Icons.close);
      expect(clear, findsOneWidget, reason: 'C: ✕ shows with a text');
      expect(find.byTooltip('Effacer la recherche'), findsOneWidget);
      final clearSize = tester.getSize(clear);
      expect(clearSize.width, greaterThanOrEqualTo(48));
      expect(clearSize.height, greaterThanOrEqualTo(48));

      final more = find.widgetWithText(
        OutlinedButton,
        'Afficher plus de salons',
      );
      expect(more, findsOneWidget, reason: 'C: 25 salons, 20 shown');
      expect(tester.getSize(more).height, greaterThanOrEqualTo(48));

      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      handle.dispose();
    });

    testWidgets('the helper line and the field fit, at $at', (tester) async {
      await pumpList(tester, width: 360, scale: scale);
      await tester.enterText(find.byType(TextField), 's');
      await tester.pump();
      expect(find.text('Tapez au moins 2 lettres'), findsOneWidget);
      expectNoUndeclaredTruncation(tester, context: 'helper at $at');
      expectNoVerticalClip(tester, context: 'helper at $at');
      expect(tester.takeException(), isNull);
    });

    testWidgets('an empty search fits, its sentence whole, at $at', (
      tester,
    ) async {
      await pumpList(tester, width: 360, scale: scale);
      await type(tester, 'une prestation que personne ne propose');
      expect(
        find.text(
          'Aucun résultat pour « une prestation que personne ne propose »',
        ),
        findsOneWidget,
      );
      expectNoUndeclaredTruncation(tester, context: 'empty at $at');
      expectNoVerticalClip(tester, context: 'empty at $at');
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('the field is « Rechercher un salon », its hint an example', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pumpList(tester, width: 360);
    final node = tester.getSemantics(find.byType(TextField));
    expect(node.label, startsWith('Rechercher un salon'));
    expect(node.label, contains('Salon, prestation ou commune'));
    handle.dispose();
  });

  // §2.5: the count is the server's total and names the commune, so it can
  // be long; a `Row(spaceBetween)` would squeeze the pill under A12's
  // 8-character floor to keep it on one line.
  testWidgets('at 360dp × 2×, the count moves under the commune pill', (
    tester,
  ) async {
    await pumpList(tester, width: 360, scale: 2, commune: 'Cocody');
    final pill = tester.getRect(find.byType(CommunePill));
    final count = tester.getRect(find.text('25 salons à Cocody'));
    expect(count.top, greaterThanOrEqualTo(pill.bottom - 0.5));
    expect(find.text('Cocody'), findsWidgets, reason: 'the pill, whole');
    expectNoUndeclaredTruncation(tester, context: 'count row at 2×');
  });

  testWidgets('at 360dp × 1×, it sits beside the pill', (tester) async {
    await pumpList(tester, width: 360, commune: 'Cocody');
    final pill = tester.getRect(find.byType(CommunePill));
    final count = tester.getRect(find.text('25 salons à Cocody'));
    expect(count.top, lessThan(pill.bottom));
    expect(count.left, greaterThan(pill.right));
  });
}
