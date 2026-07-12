import 'package:equatable/equatable.dart';

/// The offer ladder (pricing pivot, team access R2a): Pro (5 places) ·
/// Business (15) · Réseau (multi-salons, 15/salon, tarif personnalisé).
enum SalonTier { pro, business, reseau }

/// Derived billing status: trial → paid → grace (7 j) → expired.
enum SalonOfferStatus { trial, paid, grace, expired }

String salonTierLabel(SalonTier tier) => switch (tier) {
      SalonTier.pro => 'Pro',
      SalonTier.business => 'Business',
      SalonTier.reseau => 'Réseau',
    };

class SalonSeats extends Equatable {
  const SalonSeats({required this.cap, required this.used});

  final int cap;
  final int used;

  factory SalonSeats.fromJson(Map<String, dynamic> json) => SalonSeats(
        cap: (json['cap'] as num?)?.toInt() ?? 0,
        used: (json['used'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toJson() => {'cap': cap, 'used': used};

  @override
  List<Object?> get props => [cap, used];
}

/// The salon's offer & billing state — mirrors the backend
/// `SalonSubscription` DTO (GET/PUT /providers/{id}/subscription). The
/// SETUP state (no offer yet) is a 404, not a row — the service maps it to
/// code `no_offer`. Design: docs/design/team-access-r3-app.md.
class SalonSubscription extends Equatable {
  const SalonSubscription({
    required this.tier,
    required this.status,
    required this.trialEndsAt,
    required this.graceEndsAt,
    required this.seats,
    this.paidUntil,
    this.unpublishedForBilling = false,
  });

  final SalonTier tier;
  final SalonOfferStatus status;
  final DateTime trialEndsAt;
  final DateTime? paidUntil;
  final DateTime graceEndsAt;
  final bool unpublishedForBilling;
  final SalonSeats seats;

  /// Whole days left on the trial, clamped ≥ 0.
  int get trialDaysLeft {
    final left = trialEndsAt.difference(DateTime.now()).inDays;
    return left < 0 ? 0 : left;
  }

  /// trial | paid | grace — the salon can operate and invite.
  bool get isLive => status != SalonOfferStatus.expired;

  String get tierLabel => salonTierLabel(tier);

  factory SalonSubscription.fromJson(Map<String, dynamic> json) =>
      SalonSubscription(
        tier: SalonTier.values.firstWhere(
          (e) => e.name == json['tier'],
          orElse: () => SalonTier.pro,
        ),
        status: SalonOfferStatus.values.firstWhere(
          (e) => e.name == json['status'],
          orElse: () => SalonOfferStatus.expired,
        ),
        trialEndsAt: DateTime.tryParse(json['trialEndsAt'] as String? ?? '') ??
            DateTime.now(),
        paidUntil: json['paidUntil'] == null
            ? null
            : DateTime.tryParse(json['paidUntil'] as String),
        graceEndsAt: DateTime.tryParse(json['graceEndsAt'] as String? ?? '') ??
            DateTime.now(),
        unpublishedForBilling: json['unpublishedForBilling'] as bool? ?? false,
        seats: SalonSeats.fromJson(
          (json['seats'] as Map?)?.cast<String, dynamic>() ?? const {},
        ),
      );

  Map<String, dynamic> toJson() => {
        'tier': tier.name,
        'status': status.name,
        'trialEndsAt': trialEndsAt.toIso8601String(),
        'paidUntil': paidUntil?.toIso8601String(),
        'graceEndsAt': graceEndsAt.toIso8601String(),
        'unpublishedForBilling': unpublishedForBilling,
        'seats': seats.toJson(),
      };

  @override
  List<Object?> get props => [
        tier,
        status,
        trialEndsAt,
        paidUntil,
        graceEndsAt,
        unpublishedForBilling,
        seats,
      ];
}
