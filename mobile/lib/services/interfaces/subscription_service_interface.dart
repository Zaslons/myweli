import '../../models/api_response.dart';
import '../../models/salon_subscription.dart';

/// The salon's offer & billing state (pricing pivot, team access R2a/R3).
/// Owner-scoped — the offer hangs on the SALON, not the account.
///
/// Read-only in the app. Nothing here chooses or switches an offer: the
/// server starts the salon's one trial at its first successful publish, and
/// offers are chosen on the web — the Pro app is a companion app (App Store
/// 3.1.3(f)). Design: docs/design/pro-companion-path.md §3.1.
abstract class SubscriptionServiceInterface {
  /// The current offer state. The SETUP state (no offer row yet) is a 404
  /// server-side → `ApiResponse.error(code: 'no_offer')`.
  Future<ApiResponse<SalonSubscription>> getSalonSubscription(
    String providerId,
  );
}
