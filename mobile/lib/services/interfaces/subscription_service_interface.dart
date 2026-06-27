import '../../models/api_response.dart';
import '../../models/subscription.dart';

/// Provider subscription read (FR-PRO-SUB-001). Read-only in V1 — no billing.
abstract class SubscriptionServiceInterface {
  Future<ApiResponse<Subscription>> getSubscription();
}
