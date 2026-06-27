import 'package:equatable/equatable.dart';

enum SubscriptionTier { free, pro }

enum SubscriptionStatus { trial, free, active, pastDue, cancelled }

/// Provider plan & trial status (FR-PRO-SUB-001) — mirrors the backend
/// `Subscription` DTO. V1 is derived from signup (no billing state).
/// Design: docs/design/pro-subscription.md.
class Subscription extends Equatable {
  const Subscription({
    required this.tier,
    required this.status,
    required this.trialEndsAt,
    required this.trialDaysLeft,
  });

  final SubscriptionTier tier;
  final SubscriptionStatus status;
  final DateTime? trialEndsAt;
  final int trialDaysLeft;

  bool get isTrialing => status == SubscriptionStatus.trial;

  factory Subscription.fromJson(Map<String, dynamic> json) => Subscription(
        tier: SubscriptionTier.values.firstWhere(
          (e) => e.name == json['tier'],
          orElse: () => SubscriptionTier.free,
        ),
        status: SubscriptionStatus.values.firstWhere(
          (e) => e.name == json['status'],
          orElse: () => SubscriptionStatus.free,
        ),
        trialEndsAt: json['trialEndsAt'] == null
            ? null
            : DateTime.tryParse(json['trialEndsAt'] as String),
        trialDaysLeft: (json['trialDaysLeft'] as num?)?.toInt() ?? 0,
      );

  @override
  List<Object?> get props => [tier, status, trialEndsAt, trialDaysLeft];
}
