import 'package:equatable/equatable.dart';

// Design: docs/design/multi-pays-end-version.md §2 — the locality tree
// served by GET /localities (docs/modules/multi-pays.md §2): countries →
// Mobile-Money operator catalog + cities → areas (communes). The one source
// of every locality picker, discovery filter and « Près de moi » resolution;
// clients never hardcode a market fact (multi-pays §9).

class LocalityArea extends Equatable {
  const LocalityArea({
    required this.id,
    required this.slug,
    required this.name,
    required this.labelKind,
    this.lat,
    this.lng,
  });

  final String id;
  final String slug;
  final String name;
  final String labelKind; // commune | quartier | arrondissement
  final double? lat;
  final double? lng;

  factory LocalityArea.fromJson(Map<String, dynamic> json) => LocalityArea(
        id: json['id'] as String,
        slug: json['slug'] as String,
        name: json['name'] as String,
        labelKind: json['labelKind'] as String? ?? 'commune',
        lat: (json['lat'] as num?)?.toDouble(),
        lng: (json['lng'] as num?)?.toDouble(),
      );

  @override
  List<Object?> get props => [id, slug, name, labelKind, lat, lng];
}

class LocalityCity extends Equatable {
  const LocalityCity({
    required this.id,
    required this.slug,
    required this.name,
    required this.timezone,
    required this.areas,
    this.lat,
    this.lng,
  });

  final String id;
  final String slug;
  final String name;
  final String timezone; // IANA — drives every salon in the city
  final List<LocalityArea> areas;
  final double? lat;
  final double? lng;

  factory LocalityCity.fromJson(Map<String, dynamic> json) => LocalityCity(
        id: json['id'] as String,
        slug: json['slug'] as String,
        name: json['name'] as String,
        timezone: json['timezone'] as String,
        lat: (json['lat'] as num?)?.toDouble(),
        lng: (json['lng'] as num?)?.toDouble(),
        areas: ((json['areas'] as List?) ?? const [])
            .map((a) => LocalityArea.fromJson(a as Map<String, dynamic>))
            .toList(),
      );

  @override
  List<Object?> get props => [id, slug, name, timezone, areas, lat, lng];
}

class MomoOperatorInfo extends Equatable {
  const MomoOperatorInfo({
    required this.id,
    required this.label,
    this.deepLinkKind,
  });

  /// The wire value (deposit policy `mobileMoneyOperator`).
  final String id;
  final String label;

  /// Closed vocabulary driving payment deep links (`wave` today) — never a
  /// URL from the payload (threat T56).
  final String? deepLinkKind;

  factory MomoOperatorInfo.fromJson(Map<String, dynamic> json) =>
      MomoOperatorInfo(
        id: json['id'] as String,
        label: json['label'] as String,
        deepLinkKind: json['deepLinkKind'] as String?,
      );

  @override
  List<Object?> get props => [id, label, deepLinkKind];
}

class LocalityCountry extends Equatable {
  const LocalityCountry({
    required this.code,
    required this.name,
    required this.currency,
    required this.phonePrefix,
    required this.operators,
    required this.cities,
  });

  final String code; // ISO-3166 alpha-2
  final String name;
  final String currency; // ISO-4217
  final String phonePrefix;
  final List<MomoOperatorInfo> operators;
  final List<LocalityCity> cities;

  factory LocalityCountry.fromJson(Map<String, dynamic> json) =>
      LocalityCountry(
        code: json['code'] as String,
        name: json['name'] as String,
        currency: json['currency'] as String,
        phonePrefix: json['phonePrefix'] as String,
        operators: ((json['operators'] as List?) ?? const [])
            .map((o) => MomoOperatorInfo.fromJson(o as Map<String, dynamic>))
            .toList(),
        cities: ((json['cities'] as List?) ?? const [])
            .map((c) => LocalityCity.fromJson(c as Map<String, dynamic>))
            .toList(),
      );

  @override
  List<Object?> get props =>
      [code, name, currency, phonePrefix, operators, cities];
}
