import '../../core/config/subscription_plans.dart';
import '../../core/constants/app_constants.dart';
import '../../core/utils/app_clock.dart';
import '../../core/utils/salon_id.dart';
import '../../models/api_response.dart';
import '../../models/salon_subscription.dart';
import '../interfaces/subscription_service_interface.dart';
import 'mock_data.dart';

/// Demo offer state (pricing pivot). Defaults to the SETUP state (no offer
/// row) so the full arc — onboarding → the request → MyWeli validates and
/// the trial starts → team invites — is demo-able offline. The `initial`
/// knob reaches the trial/paid/grace/expired scenarios for tests and manual
/// QA.
///
/// R6 multi-salons: state is keyed PER SALON (each salon has its own offer
/// and its own single trial). The `initial` seed lands on the FIRST salon
/// touched — exactly the pre-R6 single-salon behavior every existing test
/// drives.
///
/// Nothing here chooses an offer: the app never does (App Store 3.1.1).
/// The one write is [startTrialIfAbsent], the server's trial start at
/// MyWeli's validation (B0.18 — salon-go-live-approval §3.6), mirrored for
/// `MockProService.validateSalonForTests`. The publish starts none.
/// Design: docs/design/pro-companion-path.md §3.1 / §5.
class MockSubscriptionService implements SubscriptionServiceInterface {
  MockSubscriptionService({SalonSubscription? initial}) : _seed = initial;

  final SalonSubscription? _seed;
  bool _seedApplied = false;

  final Map<String, SalonSubscription> _byId = {};

  /// Test hook: back to the pristine per-salon SETUP world (the service
  /// locator is late-final, so tests reset the singleton instead).
  void resetForTests() {
    _byId.clear();
    _seedApplied = false;
  }

  void _applySeed(SalonId providerId) {
    if (_seedApplied) return;
    _seedApplied = true;
    final seed = _seed;
    if (seed != null) _byId[providerId] = seed;
  }

  /// The server's trial start at validation (`startDefaultTrial`, §3.6 —
  /// it was the publish's before B0.18): **insert-if-absent**. A salon with
  /// no offer row gets its one 90-day trial on [tier]; a salon that already
  /// has a row — a choice made on the web, a running trial, an expired offer
  /// — is left exactly as it is, so a trial is never granted twice and a web
  /// choice is never overwritten.
  /// True when it created the row.
  ///
  /// The caller picks the default tier the way the server does: `reseau`
  /// when the owner already owns another salon on a live Réseau offer, else
  /// `pro` (`MockProService.validateSalonForTests`).
  bool startTrialIfAbsent(
    SalonId providerId, {
    SalonTier tier = SalonTier.pro,
  }) {
    _applySeed(providerId);
    if (_byId.containsKey(providerId)) return false;
    final trialEnd = AppClock.now().add(const Duration(days: 90));
    _byId[providerId] = SalonSubscription(
      tier: tier,
      status: SalonOfferStatus.trial,
      trialEndsAt: trialEnd,
      graceEndsAt: trialEnd.add(const Duration(days: 7)),
      seats: const SalonSeats(cap: 0, used: 0),
    );
    return true;
  }

  /// R6: the « Ajouter un salon » gate — any of [ownedIds] on a LIVE
  /// (trial/paid/grace) Réseau offer. Mock-only (the backend computes it).
  bool hasLiveReseauAmong(Iterable<String> ownedIds) {
    for (final id in ownedIds) {
      final salon = _byId[id];
      if (salon == null) continue;
      if (salon.tier == SalonTier.reseau &&
          salon.status != SalonOfferStatus.expired) {
        return true;
      }
    }
    return false;
  }

  @override
  Future<ApiResponse<SalonSubscription>> getSalonSubscription(
    SalonId providerId,
  ) async {
    await Future.delayed(AppConstants.mockDelay);
    _applySeed(providerId);
    final salon = _byId[providerId];
    if (salon == null) {
      return ApiResponse.error('', code: 'no_offer');
    }
    return ApiResponse.success(_withSeats(salon, providerId));
  }

  /// Seats derive live from the mock team (owner + active + invited),
  /// PER SALON (R6).
  SalonSubscription _withSeats(SalonSubscription salon, SalonId providerId) =>
      SalonSubscription(
        tier: salon.tier,
        status: salon.status,
        trialEndsAt: salon.trialEndsAt,
        paidUntil: salon.paidUntil,
        graceEndsAt: salon.graceEndsAt,
        unpublishedForBilling: salon.unpublishedForBilling,
        seats: SalonSeats(
          cap: SubscriptionPlans.seatsFor(salon.tier),
          used: MockData.teamSeatsUsed(providerId: providerId),
        ),
      );
}
