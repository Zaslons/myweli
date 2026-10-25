import 'package:equatable/equatable.dart';

import '../core/utils/salon_id.dart';

import 'provider.dart';

/// The acting salon's MARKET facts — the part of its GET /me/provider payload
/// every Pro time and money call site needs (multi-pays MP2): its IANA
/// [timezone], ISO-4217 [currency], country and area. All server-derived from
/// the salon's city (threat T57).
///
/// Kept in the persisted provider session next to the membership, so a cold
/// start whose GET /me/provider fails still knows the salon's clock
/// (docs/design/pro-app-salon-not-loaded.md §3.1). [salonId] is what makes it
/// safe to keep: the facts answer only for that salon, never for another the
/// session has since moved to.
class SalonMarket extends Equatable {
  const SalonMarket({
    required this.salonId,
    this.timezone,
    this.currency,
    this.countryCode,
    this.areaId,
  });

  factory SalonMarket.of(Provider salon) => SalonMarket(
    // A Provider's id stays a String until H2 types `Provider.id`.
    salonId: SalonId(salon.id),
    timezone: salon.timezone,
    currency: salon.currency,
    countryCode: salon.countryCode,
    areaId: salon.areaId,
  );

  final SalonId salonId;

  /// Null on a LOADED salon is the server's own default (Africa/Abidjan,
  /// `backend/lib/src/salon_time.dart`) — not a missing value.
  final String? timezone;
  final String? currency;
  final String? countryCode;
  final String? areaId;

  factory SalonMarket.fromJson(Map<String, dynamic> json) => SalonMarket(
    salonId: SalonId(json['salonId'] as String),
    timezone: json['timezone'] as String?,
    currency: json['currency'] as String?,
    countryCode: json['countryCode'] as String?,
    areaId: json['areaId'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'salonId': salonId,
    'timezone': timezone,
    'currency': currency,
    'countryCode': countryCode,
    'areaId': areaId,
  };

  @override
  List<Object?> get props => [salonId, timezone, currency, countryCode, areaId];
}
