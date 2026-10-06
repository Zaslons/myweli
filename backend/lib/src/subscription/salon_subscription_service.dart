import '../access/capabilities.dart';
import '../access/membership_repository.dart';
import '../access/membership_service.dart';
import '../auth/demo_seam.dart';
import '../auth/provider_auth_repository.dart';
import '../providers_repository.dart';
import '../salon_provisioning_service.dart';
import '../site/site_rebuild_notifier.dart';
import 'salon_subscription_repository.dart';
import 'subscription.dart';

/// The pricing pivot's server core (docs/design/team-access-r2a-offers.md):
/// offers hang on the SALON — Pro/Business/Réseau, ONE 3-month trial per
/// salon starting at the first offer choice or, when none was made, at the
/// first successful publish (docs/design/pro-companion-path.md §3.1), then
/// manual billing (« Nous contacter », admin-confirmed), a 7-day grace
/// window, and unpublish-not-lockout on expiry (threat T54).
class SalonSubscriptionService {
  SalonSubscriptionService(
    this._subscriptions,
    this._memberService,
    this._memberships,
    this._providers,
    this._providerAuth, {
    DateTime Function()? clock,
    SiteRebuildNotifier? rebuild,
  }) : _now = clock ?? (() => DateTime.now().toUtc()),
       _rebuild = rebuild ?? NoopSiteRebuildNotifier();

  final SalonSubscriptionRepository _subscriptions;
  final MembershipService _memberService;
  final MembershipRepository _memberships;
  final ProvidersRepository _providers;
  final ProviderAuthRepository _providerAuth;
  final DateTime Function() _now;

  /// Optional so the existing test constructions keep compiling — but wired
  /// in `dependencies.dart`, and `site_rebuild_wiring_test.dart` fails if it
  /// is not (the omission compiles clean and logs nothing, which is exactly
  /// how the provisioning service ran with the Noop for a week).
  final SiteRebuildNotifier _rebuild;

  /// Seats per tier — the ONE place tier entitlements live server-side
  /// (display copy/prices stay client-side + « à confirmer »).
  static const Map<String, int> tierSeats = {
    'pro': 5,
    'business': 15,
    'reseau': 15, // per salon; the multi-salon surface itself is R6
  };

  static const Duration trialLength = Duration(days: kProTrialDays);
  static const Duration graceLength = Duration(days: 7);

  /// The derived state for [providerId], or null while the salon has no
  /// offer row (the free setup state — until the first choice or the first
  /// publish).
  Future<Map<String, dynamic>?> stateFor(String providerId) async {
    final row = await _subscriptions.byProvider(providerId);
    if (row == null) return null;
    return _derive(row);
  }

  /// True when the salon may operate (publish, receive bookings, invite):
  /// `trial`, `paid` or still in `grace`.
  Future<bool> hasLiveOffer(String providerId) async =>
      isLiveState(await stateFor(providerId));

  /// The one spelling of « live » over a derived [state] (null = setup).
  static bool isLiveState(Map<String, dynamic>? state) =>
      state != null && _isLiveStatus(state['status'] as String);

  static bool _isLiveStatus(String status) =>
      status == 'trial' || status == 'paid' || status == 'grace';

  /// The companion path (docs/design/pro-companion-path.md §3.1): the Pro
  /// app no longer offers a choice (App Store 3.1.3(f)), so a salon that
  /// never chose gets its ONE trial at its first successful publish. Called
  /// only by `SalonProvisioningService.publish`, after the full publish gate
  /// and the demo lock — minting a trial still takes a complete salon.
  ///
  /// Insert-if-absent: a web choice that landed first keeps its tier and its
  /// clock, and an existing row (even an expired one) is never replaced —
  /// one trial per salon, as `trial_used` says. Returns the derived state of
  /// whichever row now exists, so the caller re-checks rather than assumes.
  Future<Map<String, dynamic>> startDefaultTrial(String providerId) async {
    final row = await _subscriptions.createIfAbsent(
      providerId: providerId,
      tier: await _defaultTierFor(providerId),
      trialEndsAt: _now().add(trialLength),
    );
    return _derive(row);
  }

  /// `reseau` when the salon's OWNER already owns ANOTHER salon on a live
  /// Réseau offer — the only way to add a salon is under Réseau, so the new
  /// one joins the network's tier — else `pro`. Owned = the scalar link ∪
  /// active owner rows, the same set `SalonDirectoryService` gates on.
  Future<String> _defaultTierFor(String providerId) async {
    final members = await _memberships.listForProvider(providerId);
    final ownerId = members
        .where((m) => m.role == 'owner' && m.status == 'active')
        .map((m) => m.accountId)
        .nonNulls
        .firstOrNull;
    if (ownerId == null) return 'pro';
    final owned = <String>{};
    final account = await _providerAuth.accountById(ownerId);
    if (account?.providerId != null) owned.add(account!.providerId!);
    for (final m in await _memberships.listForAccount(ownerId)) {
      if (m.role == 'owner' && m.status == 'active') owned.add(m.providerId);
    }
    owned.remove(providerId);
    for (final id in owned) {
      final row = await _subscriptions.byProvider(id);
      if (row != null &&
          row.tier == 'reseau' &&
          _isLiveStatus(_statusOf(row))) {
        return 'reseau';
      }
    }
    return 'pro';
  }

  /// Owner-only (`subscription.manage`): pick or switch the offer. The FIRST
  /// choice starts the salon's ONE trial (unless a publish already did —
  /// then it is a switch); switches keep the clock; once `expired`, choosing
  /// again does not restart it (409 `trial_used` — payment goes through
  /// « Nous contacter »).
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
    // The demo review account (T69): its credential is public and the web
    // dashboard accepts it, so a tier switch made with it is made by anyone
    // — and it would hand the shared demo a Réseau offer (and its « Ajouter
    // un salon » door) until the weekly reset. Keyed on the owner membership,
    // same constant, same reasoning as the publish and invite refusals.
    // Design: docs/design/pro-companion-path.md §3.2.
    final members = await _memberships.listForProvider(providerId);
    if (members.any((m) => m.role == 'owner' && isDemoIdentity(m.email))) {
      return (ok: false, error: 'demo_account_locked', data: null);
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
        // The slug just re-entered the prebuilt set. Here rather than in the
        // admin route that happens to be today's only caller, so a future
        // payments webhook calling markPaid inherits the fire.
        await _rebuild.requestRebuild('salon.republished');
      }
    }
    return (ok: true, error: null, data: await _derive(updated!));
  }

  /// The legacy `/me/subscription` bridge — keeps the app/web/e2e-stub
  /// contract (`tier: free|pro`) intact while the real model lives on the
  /// salon. Falls back to the old account-age derivation when the account
  /// has no salon or the salon has no offer yet. R6: an explicit [salonId]
  /// must match an ACTIVE membership — invalid → null (the route 403s).
  Future<Subscription?> legacySubscriptionFor(
    String accountId, {
    String? salonId,
  }) async {
    final providerId = await _memberService.salonForRequest(
      accountId,
      salonId: salonId,
    );
    if (providerId == null && (salonId?.isNotEmpty ?? false)) return null;
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
