import '../../core/config/subscription_plans.dart';
import '../../core/constants/app_constants.dart';
import '../../core/utils/team_error_messages.dart';
import '../../models/api_response.dart';
import '../../models/salon_subscription.dart';
import '../interfaces/subscription_service_interface.dart';
import 'mock_data.dart';

/// Demo offer state (pricing pivot). Defaults to the SETUP state (no offer)
/// so the full arc — picker → « 3 mois offerts » trial → team invites — is
/// demo-able offline. Constructor knobs reach the trial/grace/expired
/// scenarios for tests and manual QA.
///
/// R6 multi-salons: state is keyed PER SALON (each salon has its own offer
/// and its own single trial). The legacy constructor knobs seed the FIRST
/// salon touched — exactly the pre-R6 single-salon behavior every existing
/// test drives.
class MockSubscriptionService implements SubscriptionServiceInterface {
  MockSubscriptionService({
    SalonSubscription? initial,
    bool trialUsed = false,
  })  : _seed = initial,
        _seedTrialUsed = trialUsed || initial != null;

  final SalonSubscription? _seed;
  final bool _seedTrialUsed;
  bool _seedApplied = false;

  final Map<String, SalonSubscription> _byId = {};
  final Set<String> _trialUsed = {};

  /// Test hook: back to the pristine per-salon SETUP world (the service
  /// locator is late-final, so tests reset the singleton instead).
  void resetForTests() {
    _byId.clear();
    _trialUsed.clear();
    _seedApplied = false;
  }

  void _applySeed(String providerId) {
    if (_seedApplied) return;
    _seedApplied = true;
    final seed = _seed;
    if (seed != null) _byId[providerId] = seed;
    if (_seedTrialUsed) _trialUsed.add(providerId);
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
    String providerId,
  ) async {
    await Future.delayed(AppConstants.mockDelay);
    _applySeed(providerId);
    final salon = _byId[providerId];
    if (salon == null) {
      return ApiResponse.error('', code: 'no_offer');
    }
    return ApiResponse.success(_withSeats(salon, providerId));
  }

  @override
  Future<ApiResponse<SalonSubscription>> chooseOffer(
    String providerId,
    SalonTier tier,
  ) async {
    await Future.delayed(AppConstants.mockDelay);
    _applySeed(providerId);
    final current = _byId[providerId];
    if (current != null && current.status == SalonOfferStatus.expired) {
      return ApiResponse.error(
        teamErrorMessage('trial_used'),
        code: 'trial_used',
      );
    }
    if (current == null) {
      if (_trialUsed.contains(providerId)) {
        return ApiResponse.error(
          teamErrorMessage('trial_used'),
          code: 'trial_used',
        );
      }
      // First choice starts THIS salon's ONE trial.
      _trialUsed.add(providerId);
      final trialEnd = DateTime.now().add(const Duration(days: 90));
      _byId[providerId] = SalonSubscription(
        tier: tier,
        status: SalonOfferStatus.trial,
        trialEndsAt: trialEnd,
        graceEndsAt: trialEnd.add(const Duration(days: 7)),
        seats: const SalonSeats(cap: 0, used: 0),
      );
    } else {
      // Switches keep the clock — only the tier (and its cap) changes.
      _byId[providerId] = SalonSubscription(
        tier: tier,
        status: current.status,
        trialEndsAt: current.trialEndsAt,
        paidUntil: current.paidUntil,
        graceEndsAt: current.graceEndsAt,
        unpublishedForBilling: current.unpublishedForBilling,
        seats: current.seats,
      );
    }
    return ApiResponse.success(_withSeats(_byId[providerId]!, providerId));
  }

  /// Seats derive live from the mock team (owner + active + invited),
  /// PER SALON (R6).
  SalonSubscription _withSeats(SalonSubscription salon, String providerId) =>
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
