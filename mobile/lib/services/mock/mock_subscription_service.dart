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
class MockSubscriptionService implements SubscriptionServiceInterface {
  MockSubscriptionService({
    SalonSubscription? initial,
    bool trialUsed = false,
  })  : _salon = initial,
        _trialUsed = trialUsed || initial != null;

  SalonSubscription? _salon;

  /// Whether the salon's ONE trial has started (first choice sets it).
  bool _trialUsed;

  @override
  Future<ApiResponse<SalonSubscription>> getSalonSubscription(
    String providerId,
  ) async {
    await Future.delayed(AppConstants.mockDelay);
    final salon = _salon;
    if (salon == null) {
      return ApiResponse.error('', code: 'no_offer');
    }
    return ApiResponse.success(_withSeats(salon));
  }

  @override
  Future<ApiResponse<SalonSubscription>> chooseOffer(
    String providerId,
    SalonTier tier,
  ) async {
    await Future.delayed(AppConstants.mockDelay);
    final current = _salon;
    if (current != null && current.status == SalonOfferStatus.expired) {
      return ApiResponse.error(
        teamErrorMessage('trial_used'),
        code: 'trial_used',
      );
    }
    if (current == null) {
      if (_trialUsed) {
        return ApiResponse.error(
          teamErrorMessage('trial_used'),
          code: 'trial_used',
        );
      }
      // First choice starts the salon's ONE trial.
      _trialUsed = true;
      final trialEnd = DateTime.now().add(const Duration(days: 90));
      _salon = SalonSubscription(
        tier: tier,
        status: SalonOfferStatus.trial,
        trialEndsAt: trialEnd,
        graceEndsAt: trialEnd.add(const Duration(days: 7)),
        seats: const SalonSeats(cap: 0, used: 0),
      );
    } else {
      // Switches keep the clock — only the tier (and its cap) changes.
      _salon = SalonSubscription(
        tier: tier,
        status: current.status,
        trialEndsAt: current.trialEndsAt,
        paidUntil: current.paidUntil,
        graceEndsAt: current.graceEndsAt,
        unpublishedForBilling: current.unpublishedForBilling,
        seats: current.seats,
      );
    }
    return ApiResponse.success(_withSeats(_salon!));
  }

  /// Seats derive live from the mock team (owner + active + invited).
  SalonSubscription _withSeats(SalonSubscription salon) => SalonSubscription(
        tier: salon.tier,
        status: salon.status,
        trialEndsAt: salon.trialEndsAt,
        paidUntil: salon.paidUntil,
        graceEndsAt: salon.graceEndsAt,
        unpublishedForBilling: salon.unpublishedForBilling,
        seats: SalonSeats(
          cap: SubscriptionPlans.seatsFor(salon.tier),
          used: MockData.teamSeatsUsed(),
        ),
      );
}
