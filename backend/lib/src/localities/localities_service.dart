import '../slug.dart';
import 'localities_repository.dart';

// Design: docs/design/multi-pays-end-version.md §2 — the read-side of the
// locality tree: the public `GET /localities` DTO, the areaId/commune-name
// resolvers the salon write paths use to DERIVE market facts (the salon never
// picks a timezone or currency — threat T57), and the per-country operator
// catalog behind deposit-policy validation.

/// Everything a salon inherits from its locality, resolved in one lookup.
class SalonMarket {
  const SalonMarket({
    required this.areaId,
    required this.areaName,
    required this.areaSlug,
    required this.cityId,
    required this.citySlug,
    required this.cityName,
    required this.timezone,
    required this.countryCode,
    required this.currency,
  });

  final String areaId;
  final String areaName;
  final String areaSlug;
  final String cityId;
  final String citySlug;
  final String cityName;
  final String timezone;
  final String countryCode;
  final String currency;

  /// The provider-document changes this market implies (server-derived —
  /// clients never write these; threat T57).
  Map<String, dynamic> get providerChanges => {
    'areaId': areaId,
    'commune': areaName,
    'city': cityName,
    'citySlug': citySlug,
    'countryCode': countryCode,
    'timezone': timezone,
    'currency': currency,
  };
}

class LocalitiesService {
  LocalitiesService(this._repo);

  final LocalitiesRepository _repo;
  Map<String, dynamic>? _treeCache;

  /// The public reference tree (`GET /localities`) — cacheable, no PII.
  Future<Map<String, dynamic>> tree() async {
    if (_treeCache != null) return _treeCache!;
    final countries = await _repo.countries();
    final cities = await _repo.cities();
    final areas = await _repo.areas();
    final operators = await _repo.operators();
    return _treeCache = {
      'countries': [
        for (final c in countries)
          {
            'code': c.code,
            'name': c.name,
            'currency': c.currency,
            'phonePrefix': c.phonePrefix,
            'operators': [
              for (final o in operators.where((o) => o.countryCode == c.code))
                {'id': o.id, 'label': o.label, 'deepLinkKind': o.deepLinkKind},
            ],
            'cities': [
              for (final city in cities.where((x) => x.countryCode == c.code))
                {
                  'id': city.id,
                  'slug': city.slug,
                  'name': city.name,
                  'timezone': city.timezone,
                  'lat': city.lat,
                  'lng': city.lng,
                  'areas': [
                    for (final a in areas.where((x) => x.cityId == city.id))
                      {
                        'id': a.id,
                        'slug': a.slug,
                        'name': a.name,
                        'labelKind': a.labelKind,
                        'lat': a.lat,
                        'lng': a.lng,
                      },
                  ],
                },
            ],
          },
      ],
    };
  }

  /// Resolves an explicit [areaId] to the full market record, or null when
  /// unknown/inactive (the write paths answer 400 `invalid_area`).
  Future<SalonMarket?> resolveArea(String areaId) async {
    final areas = await _repo.areas();
    for (final a in areas) {
      if (a.id == areaId) return _market(a);
    }
    return null;
  }

  /// Resolves a legacy free-text commune NAME (accent/case-insensitive slug
  /// match) — the self-heal path for pre-MP1 clients and historical rows.
  Future<SalonMarket?> resolveCommuneName(String name) async {
    final wanted = slugify(name);
    if (wanted.isEmpty) return null;
    final areas = await _repo.areas();
    for (final a in areas) {
      if (a.slug == wanted || slugify(a.name) == wanted) return _market(a);
    }
    return null;
  }

  /// The deposit-policy accept-list for a salon's country (threat T57 —
  /// operators are data, not a hardcoded enum).
  Future<Set<String>> operatorIdsForCountry(String countryCode) async {
    final operators = await _repo.operators();
    return {
      for (final o in operators.where((o) => o.countryCode == countryCode))
        o.id,
    };
  }

  Future<SalonMarket> _market(Area a) async {
    final cities = await _repo.cities();
    final city = cities.firstWhere((c) => c.id == a.cityId);
    final countries = await _repo.countries();
    final country = countries.firstWhere((c) => c.code == city.countryCode);
    return SalonMarket(
      areaId: a.id,
      areaName: a.name,
      areaSlug: a.slug,
      cityId: city.id,
      citySlug: city.slug,
      cityName: city.name,
      timezone: city.timezone,
      countryCode: country.code,
      currency: country.currency,
    );
  }
}
