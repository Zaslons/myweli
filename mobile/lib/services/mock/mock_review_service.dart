import '../../core/constants/app_constants.dart';
import '../../models/api_response.dart';
import '../../models/review.dart';
import '../interfaces/review_service_interface.dart';
import 'mock_data.dart';

class MockReviewService implements ReviewServiceInterface {
  @override
  Future<ApiResponse<Review>> submitReview(Review review) async {
    await Future.delayed(AppConstants.mockDelay);

    if (review.rating < 1 || review.rating > 5) {
      return ApiResponse.error('Note invalide');
    }

    // Persist onto the provider so the review survives + shows on reload.
    final index =
        MockData.providers.indexWhere((p) => p.id == review.providerId);
    if (index != -1) {
      final provider = MockData.providers[index];
      MockData.providers[index] = provider.copyWith(
        reviews: [...provider.reviews, review],
      );
    }
    return ApiResponse.success(review, message: 'Avis publié');
  }
}
