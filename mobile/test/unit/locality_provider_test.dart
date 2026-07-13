import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/providers/locality_provider.dart';

/// The locality tree provider (multi-pays MP2): lazy load + cache, the
/// mock mirrors the backend seed (CI → 4 operators → abidjan → 11 communes),
/// « Près de moi » resolution and the operator/country lookups.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(setupDependencyInjection);

  test('lazy-loads the seed tree once and caches it', () async {
    final p = LocalityProvider();
    expect(p.isLoaded, isFalse);
    await p.ensureLoaded();
    expect(p.isLoaded, isTrue);
    expect(p.error, isNull);
    final ci = p.countryOf('CI')!;
    expect(ci.currency, 'XOF');
    expect(ci.phonePrefix, '+225');
    expect(ci.operators, hasLength(4));
    expect(ci.cities.single.timezone, 'Africa/Abidjan');
    expect(p.areasOf(), hasLength(11));
    // Second call resolves synchronously from cache (no state churn).
    await p.ensureLoaded();
    expect(p.isLoaded, isTrue);
  });

  test('area ids match the backend slugs (accents stripped)', () async {
    final p = LocalityProvider();
    await p.ensureLoaded();
    final ids = p.areasOf().map((a) => a.id).toSet();
    expect(
      ids,
      // Includes the PRD §19 launch-focus communes (the retired
      // communes_test pin lives on here, against the live seam).
      containsAll([
        'cocody',
        'marcory',
        'plateau',
        'adjame',
        'port-bouet',
        'attecoube'
      ]),
    );
  });

  test('« Près de moi » resolves the nearest area from centroids', () async {
    final p = LocalityProvider();
    await p.ensureLoaded();
    // The historical nearestCommune fixtures: Cocody + Marcory centroids.
    expect(p.nearestArea(5.3600, -4.0083)!.name, 'Cocody');
    expect(p.nearestArea(5.2800, -4.0500)!.name, 'Marcory');
  });

  test('operator lookups: catalog per country + deep-link vocabulary',
      () async {
    final p = LocalityProvider();
    await p.ensureLoaded();
    expect(p.operatorsFor('CI').map((o) => o.id), [
      'wave',
      'orangeMoney',
      'mtnMoMo',
      'moov',
    ]);
    expect(p.operatorInfo('wave')!.deepLinkKind, 'wave');
    expect(p.operatorInfo('orangeMoney')!.label, 'Orange Money');
    expect(p.operatorInfo('mpesa'), isNull);
    expect(p.countryName('CI'), "Côte d'Ivoire");
  });
}
