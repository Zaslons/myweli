// Pro subscription state — derived (V1 has no billing state to store).
// Design: docs/design/pro-subscription.md (FR-PRO-SUB-001).

/// Default free-trial length (3 months). Single source of truth for the
/// derivation; the app shows the dynamic days-left from the response.
const int kProTrialDays = 90;

class Subscription {
  const Subscription({
    required this.tier,
    required this.status,
    required this.trialEndsAt,
    required this.trialDaysLeft,
  });

  /// 'pro' during the trial, else 'free'.
  final String tier;

  /// 'trial' during the trial, else 'free'.
  final String status;

  final DateTime trialEndsAt;
  final int trialDaysLeft;

  Map<String, dynamic> toJson() => {
    'tier': tier,
    'status': status,
    'trialEndsAt': trialEndsAt.toIso8601String(),
    'trialDaysLeft': trialDaysLeft,
  };
}

/// Derive the subscription from the provider account's [accountCreatedAt]:
/// during the [trialDays] window → Pro/trial with days-left (rounded up); after
/// → the Free tier. Pure — no billing, no persistence (none exists in V1).
Subscription computeSubscription({
  required DateTime accountCreatedAt,
  required DateTime now,
  int trialDays = kProTrialDays,
}) {
  final trialEndsAt = accountCreatedAt.add(Duration(days: trialDays));
  if (now.isBefore(trialEndsAt)) {
    final remaining = trialEndsAt.difference(now);
    final daysLeft = (remaining.inSeconds / Duration.secondsPerDay).ceil();
    return Subscription(
      tier: 'pro',
      status: 'trial',
      trialEndsAt: trialEndsAt,
      trialDaysLeft: daysLeft < 0 ? 0 : daysLeft,
    );
  }
  return Subscription(
    tier: 'free',
    status: 'free',
    trialEndsAt: trialEndsAt,
    trialDaysLeft: 0,
  );
}
