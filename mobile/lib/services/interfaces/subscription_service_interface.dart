import '../../models/api_response.dart';
import '../../models/salon_subscription.dart';

/// The salon's offer & billing state (pricing pivot, team access R2a/R3).
/// Owner-scoped — the offer hangs on the SALON, not the account.
abstract class SubscriptionServiceInterface {
  /// The current offer state. The SETUP state (no offer chosen yet) is a
  /// 404 server-side → `ApiResponse.error(code: 'no_offer')`.
  Future<ApiResponse<SalonSubscription>> getSalonSubscription(
    String providerId,
  );

  /// Pick or switch the offer. The FIRST choice starts the salon's ONE
  /// 3-month trial; switches keep the clock. After expiry → 409
  /// `trial_used` (payment is manual — « Nous contacter »).
  Future<ApiResponse<SalonSubscription>> chooseOffer(
    String providerId,
    SalonTier tier,
  );
}
