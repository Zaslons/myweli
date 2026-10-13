import '../../core/constants/app_constants.dart';
import '../../core/utils/salon_figures.dart';
import '../../models/api_response.dart';
import '../../models/review.dart';
import '../interfaces/review_service_interface.dart';
import 'mock_data.dart';

class MockReviewService implements ReviewServiceInterface {
  /// Stores the review the way the server does — one per appointment, and
  /// the salon's figures moved with the write
  /// (docs/design/consumer-reviews.md §3).
  ///
  /// It used to append the review to `MockData.providers[i].reviews`, which
  /// nothing reads back: `MockProviderService.getProviderById` rebuilds a
  /// salon's reviews from [MockData.reviews] and returns the salon's own
  /// `rating`/`reviewCount`. So any read after a submit erased the review and
  /// restored the old figures — and the app now re-reads the salon right
  /// after « Publier » (`ProviderProvider.rereadSalonAfterReview`).
  @override
  Future<ApiResponse<Review>> submitReview(Review review) async {
    await Future.delayed(AppConstants.mockDelay);

    if (review.rating < 1 || review.rating > 5) {
      return ApiResponse.error('Note invalide');
    }

    // Upsert on the appointment, like `ON CONFLICT (appointment_id)`. A
    // review that names none (the server refuses those; some fixtures send
    // them) is simply stored.
    final visit = review.appointmentId;
    final stored = visit.isEmpty
        ? -1
        : MockData.reviews.indexWhere((r) => r.appointmentId == visit);
    final replaced = stored == -1 ? null : MockData.reviews.removeAt(stored);
    MockData.reviews.add(review);

    // The seeded figures stand for reviews the mock list does not hold
    // (« 120 avis », three listed), so they are MOVED by this write — one
    // more for a new visit, none for a visit reviewed again — rather than
    // recounted from the list. No seeded figure changes until someone posts.
    final index = MockData.providers.indexWhere(
      (p) => p.id == review.providerId,
    );
    if (index != -1) {
      final provider = MockData.providers[index];
      final figures = figuresAfterReview(
        rating: provider.rating,
        reviewCount: provider.reviewCount,
        stars: review.rating,
        replacedStars: replaced?.rating,
      );
      MockData.providers[index] = provider.copyWith(
        rating: figures.rating,
        reviewCount: figures.reviewCount,
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
    final all =
        MockData.reviews.where((r) => r.providerId == providerId).toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final start = (page - 1) * pageSize;
    final items = start >= all.length
        ? <Review>[]
        : all.sublist(start, (start + pageSize).clamp(0, all.length));
    return ApiResponse.success(items);
  }

  @override
  Future<ApiResponse<void>> reportReview(
    String reviewId, {
    String? reason,
  }) async {
    await Future.delayed(AppConstants.mockDelay);
    return ApiResponse.success(null, message: 'Avis signalé');
  }
}
