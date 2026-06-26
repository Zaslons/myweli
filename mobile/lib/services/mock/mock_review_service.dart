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

  @override
  Future<ApiResponse<List<Review>>> getProviderReviews(
    String providerId, {
    int page = 1,
    int pageSize = 20,
  }) async {
    await Future.delayed(AppConstants.mockDelay);
    final all = MockData.reviews
        .where((r) => r.providerId == providerId)
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final start = (page - 1) * pageSize;
    final items = start >= all.length
        ? <Review>[]
        : all.sublist(start, (start + pageSize).clamp(0, all.length));
    return ApiResponse.success(items);
  }
}
