import 'package:postgres/postgres.dart';

import '../slug.dart';

// Design: docs/design/multi-pays-end-version.md §2 — the locality tree
// (docs/modules/multi-pays.md §2): countries → cities → areas + the
// per-country Mobile-Money operator catalog. Pure reference data: seeded by
// migration/boot, changed only by reviewed deploys (threat T56 — no write
// endpoint exists), served read-only to every surface.

class Country {
  const Country({
    required this.code,
    required this.name,
    required this.currency,
    required this.phonePrefix,
    this.active = true,
  });

  final String code; // ISO-3166 alpha-2
  final String name;
  final String currency; // ISO-4217
  final String phonePrefix;
  final bool active;
}

class City {
  const City({
    required this.id,
    required this.countryCode,
    required this.name,
    required this.slug,
    required this.timezone,
    this.lat,
    this.lng,
    this.active = true,
  });

  final String id;
  final String countryCode;
  final String name;
  final String slug;
  final String timezone; // IANA — drives every salon in the city
  final double? lat;
  final double? lng;
  final bool active;
}

class Area {
  const Area({
    required this.id,
    required this.cityId,
    required this.name,
    required this.slug,
    required this.labelKind,
    this.lat,
    this.lng,
    this.active = true,
  });

  final String id;
  final String cityId;
  final String name;
  final String slug;
  final String labelKind; // commune | quartier | arrondissement
  final double? lat;
  final double? lng;
  final bool active;
}

class MomoOperator {
  const MomoOperator({
    required this.countryCode,
    required this.id,
    required this.label,
    this.deepLinkKind,
    this.active = true,
  });

  final String countryCode;
  final String id; // the wire value (deposit policy `mobileMoneyOperator`)
  final String label;

  /// Closed vocabulary driving client deep links (`wave` today). Clients
  /// never build payment links from free-form payload URLs (T56).
  final String? deepLinkKind;
  final bool active;
}

// ---- The seed (Wave 0: Côte d'Ivoire) --------------------------------------
// A new market = appending rows here (+ the Postgres seed runs from this same
// list) and walking docs/modules/multi-pays.md §8. Area centroids come from
// the app's historical commune constants (« Près de moi » resolution).

const List<Country> seedCountries = [
  Country(
    code: 'CI',
    name: "Côte d'Ivoire",
    currency: 'XOF',
    phonePrefix: '+225',
  ),
];

const List<City> seedCities = [
  City(
    id: 'abidjan',
    countryCode: 'CI',
    name: 'Abidjan',
    slug: 'abidjan',
    timezone: 'Africa/Abidjan',
    lat: 5.336,
    lng: -4.026,
  ),
];

const List<Area> seedAreas = [
  Area(
    id: 'cocody',
    cityId: 'abidjan',
    name: 'Cocody',
    slug: 'cocody',
    labelKind: 'commune',
    lat: 5.3600,
    lng: -4.0083,
  ),
  Area(
    id: 'marcory',
    cityId: 'abidjan',
    name: 'Marcory',
    slug: 'marcory',
    labelKind: 'commune',
    lat: 5.2800,
    lng: -4.0500,
  ),
  Area(
    id: 'plateau',
    cityId: 'abidjan',
    name: 'Plateau',
    slug: 'plateau',
    labelKind: 'commune',
    lat: 5.3200,
    lng: -4.0300,
  ),
  Area(
    id: 'yopougon',
    cityId: 'abidjan',
    name: 'Yopougon',
    slug: 'yopougon',
    labelKind: 'commune',
    lat: 5.3200,
    lng: -4.0800,
  ),
  Area(
    id: 'treichville',
    cityId: 'abidjan',
    name: 'Treichville',
    slug: 'treichville',
    labelKind: 'commune',
    lat: 5.2930,
    lng: -4.0100,
  ),
  Area(
    id: 'adjame',
    cityId: 'abidjan',
    name: 'Adjamé',
    slug: 'adjame',
    labelKind: 'commune',
    lat: 5.3660,
    lng: -4.0250,
  ),
  Area(
    id: 'abobo',
    cityId: 'abidjan',
    name: 'Abobo',
    slug: 'abobo',
    labelKind: 'commune',
    lat: 5.4200,
    lng: -4.0200,
  ),
  Area(
    id: 'koumassi',
    cityId: 'abidjan',
    name: 'Koumassi',
    slug: 'koumassi',
    labelKind: 'commune',
    lat: 5.2900,
    lng: -3.9450,
  ),
  Area(
    id: 'port-bouet',
    cityId: 'abidjan',
    name: 'Port-Bouët',
    slug: 'port-bouet',
    labelKind: 'commune',
    lat: 5.2550,
    lng: -3.9260,
  ),
  Area(
    id: 'attecoube',
    cityId: 'abidjan',
    name: 'Attécoubé',
    slug: 'attecoube',
    labelKind: 'commune',
    lat: 5.3400,
    lng: -4.0350,
  ),
  Area(
    id: 'bingerville',
    cityId: 'abidjan',
    name: 'Bingerville',
    slug: 'bingerville',
    labelKind: 'commune',
    lat: 5.3550,
    lng: -3.8900,
  ),
];

const List<MomoOperator> seedMomoOperators = [
  MomoOperator(
    countryCode: 'CI',
    id: 'wave',
    label: 'Wave',
    deepLinkKind: 'wave',
  ),
  MomoOperator(countryCode: 'CI', id: 'orangeMoney', label: 'Orange Money'),
  MomoOperator(countryCode: 'CI', id: 'mtnMoMo', label: 'MTN MoMo'),
  MomoOperator(countryCode: 'CI', id: 'moov', label: 'Moov Money'),
];

/// Seed-list area lookup for a commune DISPLAY NAME (accent/case-insensitive
/// slug match) — the sync self-heal used by the backfill and the publish
/// gate. The seed lists are the source the DB tables are seeded from, so
/// both backends agree.
Area? seedAreaForCommuneName(String name) {
  final wanted = slugify(name);
  if (wanted.isEmpty) return null;
  for (final a in seedAreas) {
    if (a.slug == wanted || slugify(a.name) == wanted) return a;
  }
  return null;
}

/// The provider-document changes a seed area implies (server-derived market
/// facts — clients never write these; threat T57).
Map<String, dynamic> marketChangesForArea(Area a) {
  final city = seedCities.firstWhere((c) => c.id == a.cityId);
  final country = seedCountries.firstWhere((c) => c.code == city.countryCode);
  return {
    'areaId': a.id,
    'commune': a.name,
    'city': city.name,
    'citySlug': city.slug,
    'countryCode': country.code,
    'timezone': city.timezone,
    'currency': country.currency,
  };
}

// ---- Repository -------------------------------------------------------------

abstract class LocalitiesRepository {
  Future<List<Country>> countries();
  Future<List<City>> cities();
  Future<List<Area>> areas();
  Future<List<MomoOperator>> operators();
}

class InMemoryLocalitiesRepository implements LocalitiesRepository {
  @override
  Future<List<Country>> countries() async => seedCountries;

  @override
  Future<List<City>> cities() async => seedCities;

  @override
  Future<List<Area>> areas() async => seedAreas;

  @override
  Future<List<MomoOperator>> operators() async => seedMomoOperators;
}

/// Reads the four reference tables once and caches for the process lifetime —
/// reference data changes only by deploy (the seed is the source of truth).
class PostgresLocalitiesRepository implements LocalitiesRepository {
  PostgresLocalitiesRepository(this._pool);

  final Pool<void> _pool;
  List<Country>? _countries;
  List<City>? _cities;
  List<Area>? _areas;
  List<MomoOperator>? _operators;

  @override
  Future<List<Country>> countries() async {
    if (_countries != null) return _countries!;
    final rows = await _pool.execute(
      'SELECT code, name, currency, phone_prefix, active FROM countries '
      'WHERE active ORDER BY name',
    );
    return _countries = [
      for (final r in rows.map((r) => r.toColumnMap()))
        Country(
          code: r['code'] as String,
          name: r['name'] as String,
          currency: r['currency'] as String,
          phonePrefix: r['phone_prefix'] as String,
        ),
    ];
  }

  @override
  Future<List<City>> cities() async {
    if (_cities != null) return _cities!;
    final rows = await _pool.execute(
      'SELECT id, country_code, name, slug, timezone, lat, lng, active '
      'FROM cities WHERE active ORDER BY name',
    );
    return _cities = [
      for (final r in rows.map((r) => r.toColumnMap()))
        City(
          id: r['id'] as String,
          countryCode: r['country_code'] as String,
          name: r['name'] as String,
          slug: r['slug'] as String,
          timezone: r['timezone'] as String,
          lat: (r['lat'] as num?)?.toDouble(),
          lng: (r['lng'] as num?)?.toDouble(),
        ),
    ];
  }

  @override
  Future<List<Area>> areas() async {
    if (_areas != null) return _areas!;
    final rows = await _pool.execute(
      'SELECT id, city_id, name, slug, label_kind, lat, lng, active '
      'FROM areas WHERE active ORDER BY name',
    );
    return _areas = [
      for (final r in rows.map((r) => r.toColumnMap()))
        Area(
          id: r['id'] as String,
          cityId: r['city_id'] as String,
          name: r['name'] as String,
          slug: r['slug'] as String,
          labelKind: r['label_kind'] as String,
          lat: (r['lat'] as num?)?.toDouble(),
          lng: (r['lng'] as num?)?.toDouble(),
        ),
    ];
  }

  @override
  Future<List<MomoOperator>> operators() async {
    if (_operators != null) return _operators!;
    final rows = await _pool.execute(
      'SELECT country_code, id, label, deep_link_kind, active '
      'FROM momo_operators WHERE active ORDER BY id',
    );
    return _operators = [
      for (final r in rows.map((r) => r.toColumnMap()))
        MomoOperator(
          countryCode: r['country_code'] as String,
          id: r['id'] as String,
          label: r['label'] as String,
          deepLinkKind: r['deep_link_kind'] as String?,
        ),
    ];
  }
}
