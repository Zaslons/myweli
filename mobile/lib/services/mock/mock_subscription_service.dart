import '../../core/constants/app_constants.dart';
import '../../models/api_response.dart';
import '../../models/subscription.dart';
import '../interfaces/subscription_service_interface.dart';

/// Demo subscription: a provider partway through the 3-month Pro trial.
class MockSubscriptionService implements SubscriptionServiceInterface {
  @override
  Future<ApiResponse<Subscription>> getSubscription() async {
    await Future.delayed(AppConstants.mockDelay);
    return ApiResponse.success(
      Subscription(
        tier: SubscriptionTier.pro,
        status: SubscriptionStatus.trial,
        trialEndsAt: DateTime.now().add(const Duration(days: 62)),
        trialDaysLeft: 62,
      ),
    );
  }
}
