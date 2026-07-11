import '../access/capabilities.dart';
import '../access/membership_repository.dart';
import '../access/membership_service.dart';
import '../auth/provider_auth_repository.dart';
import '../providers_repository.dart';
import '../salon_provisioning_service.dart';
import 'salon_subscription_repository.dart';
import 'subscription.dart';

/// The pricing pivot's server core (docs/design/team-access-r2a-offers.md):
/// offers hang on the SALON — Pro/Business/Réseau, ONE 3-month trial per
/// salon starting at the first offer choice, then manual billing
/// (« Nous contacter », admin-confirmed), a 7-day grace window, and
/// unpublish-not-lockout on expiry (threat T54).
class SalonSubscriptionService {
  SalonSubscriptionService(
    this._subscriptions,
    this._memberService,
    this._memberships,
    this._providers,
    this._providerAuth, {
    DateTime Function()? clock,
  }) : _now = clock ?? (() => DateTime.now().toUtc());

  final SalonSubscriptionRepository _subscriptions;
  final MembershipService _memberService;
  final MembershipRepository _memberships;
  final ProvidersRepository _providers;
  final ProviderAuthRepository _providerAuth;
  final DateTime Function() _now;

  /// Seats per tier — the ONE place tier entitlements live server-side
  /// (display copy/prices stay client-side + « à confirmer »).
  static const Map<String, int> tierSeats = {
    'pro': 5,
    'business': 15,
    'reseau': 15, // per salon; the multi-salon surface itself is R6
  };

  static const Duration trialLength = Duration(days: kProTrialDays);
  static const Duration graceLength = Duration(days: 7);

  /// The derived state for [providerId], or null when no offer was ever
  /// chosen (the free setup state).
  Future<Map<String, dynamic>?> stateFor(String providerId) async {
    final row = await _subscriptions.byProvider(providerId);
    if (row == null) return null;
    return _derive(row);
  }

  /// True when the salon may operate (publish, receive bookings, invite):
  /// `trial`, `paid` or still in `grace`.
  Future<bool> hasLiveOffer(String providerId) async {
    final state = await stateFor(providerId);
    if (state == null) return false;
    final status = state['status'] as String;
    return status == 'trial' || status == 'paid' || status == 'grace';
  }

  /// Owner-only (`subscription.manage`): pick or switch the offer. The FIRST
  /// choice starts the salon's ONE trial; switches keep the clock; once
  /// `expired`, choosing again does not restart it (409 `trial_used` —
  /// payment goes through « Nous contacter »).
  Future<({bool ok, String? error, Map<String, dynamic>? data})> chooseOffer(
    String accountId,
    String providerId,
    Object? tier,
  ) async {
    if (!await _memberService.can(
      accountId,
      providerId,
      Cap.subscriptionManage,
    )) {
      return (ok: false, error: 'forbidden', data: null);
    }
    if (tier is! String || !tierSeats.containsKey(tier)) {
      return (ok: false, error: 'invalid_tier', data: null);
    }
    final existing = await _subscriptions.byProvider(providerId);
    if (existing == null) {
      final row = await _subscriptions.create(
        providerId: providerId,
        tier: tier,
        trialEndsAt: _now().add(trialLength),
      );
      return (ok: true, error: null, data: await _derive(row));
    }
    // An expired salon can't mint a new trial by re-choosing.
    if (_statusOf(existing) == 'expired') {
      return (ok: false, error: 'trial_used', data: null);
    }
    final row = await _subscriptions.update(providerId, tier: tier);
    return (ok: true, error: null, data: await _derive(row!));
  }

  /// Admin-only path (the route/service layer enforces the admin role and
  /// audits): record a manual payment of [months] months. Reopens the
  /// notice cycle and republishes a billing-unpublished salon when the
  /// publish gate passes.
  Future<({bool ok, String? error, Map<String, dynamic>? data})> markPaid(
    String providerId, {
    required int months,
  }) async {
    if (months < 1 || months > 24) {
      return (ok: false, error: 'invalid_input', data: null);
    }
    final row = await _subscriptions.byProvider(providerId);
    if (row == null) return (ok: false, error: 'not_found', data: null);

    final now = _now();
    final base = (row.paidUntil != null && row.paidUntil!.isAfter(now))
        ? row.paidUntil!
        : now;
    var updated = await _subscriptions.update(
      providerId,
      paidUntil: base.add(Duration(days: 30 * months)),
    );
    await _subscriptions.clearNotices(providerId);

    if (updated!.unpublishedAt != null) {
      final provider = await _providers.byId(providerId);
      if (provider != null &&
          SalonProvisioningService.publishGate(provider).isEmpty) {
        await _providers.setStatus(providerId, 'active');
        updated = await _subscriptions.update(
          providerId,
          clearUnpublished: true,
        );
      }
    }
    return (ok: true, error: null, data: await _derive(updated!));
  }

  /// The legacy `/me/subscription` bridge — keeps the app/web/e2e-stub
  /// contract (`tier: free|pro`) intact while the real model lives on the
  /// salon. Falls back to the old account-age derivation when the account
  /// has no salon or the salon has no offer yet.
  Future<Subscription> legacySubscriptionFor(String accountId) async {
    final providerId = await _memberService.activeSalonFor(accountId);
    if (providerId != null) {
      final row = await _subscriptions.byProvider(providerId);
      if (row != null) {
        final status = _statusOf(row);
        final now = _now();
        final live = status == 'trial' || status == 'paid' || status == 'grace';
        final daysLeft = status == 'trial'
            ? (row.trialEndsAt.difference(now).inSeconds /
                      Duration.secondsPerDay)
                  .ceil()
            : 0;
        return Subscription(
          tier: live ? 'pro' : 'free',
          status: status == 'trial' ? 'trial' : 'free',
          trialEndsAt: row.trialEndsAt,
          trialDaysLeft: daysLeft < 0 ? 0 : daysLeft,
        );
      }
    }
    final account = await _providerAuth.accountById(accountId);
    return computeSubscription(
      accountCreatedAt: account?.createdAt ?? _now(),
      now: _now(),
    );
  }

  String _statusOf(SalonSubscriptionRow row) {
    final now = _now();
    if (row.paidUntil != null && now.isBefore(row.paidUntil!)) return 'paid';
    if (now.isBefore(row.trialEndsAt)) return 'trial';
    final anchor = _latest(row.trialEndsAt, row.paidUntil);
    if (now.isBefore(anchor.add(graceLength))) return 'grace';
    return 'expired';
  }

  DateTime _latest(DateTime a, DateTime? b) =>
      b != null && b.isAfter(a) ? b : a;

  Future<Map<String, dynamic>> _derive(SalonSubscriptionRow row) async {
    final status = _statusOf(row);
    final members = await _memberships.listForProvider(row.providerId);
    final used = members
        .where((m) => m.status == 'active' || m.status == 'invited')
        .length;
    return {
      'tier': row.tier,
      'status': status,
      'trialEndsAt': row.trialEndsAt.toIso8601String(),
      'paidUntil': row.paidUntil?.toIso8601String(),
      'graceEndsAt': _latest(
        row.trialEndsAt,
        row.paidUntil,
      ).add(graceLength).toIso8601String(),
      'unpublishedForBilling': row.unpublishedAt != null,
      'seats': {'cap': tierSeats[row.tier], 'used': used},
    };
  }
}
