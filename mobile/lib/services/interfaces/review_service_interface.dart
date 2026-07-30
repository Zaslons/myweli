import '../../models/api_response.dart';
import '../../models/review.dart';

abstract class ReviewServiceInterface {
  /// Submit a review of a completed appointment ([Review.appointmentId]). The
  /// server derives provider/artist/service/reviewer/verified from the
  /// appointment; only rating/text/photos are taken from the client.
  Future<ApiResponse<Review>> submitReview(Review review);

  /// A provider's reviews, newest first (paginated).
  Future<ApiResponse<List<Review>>> getProviderReviews(
    String providerId, {
    int page,
    int pageSize,
  });

  /// Flag a review for moderation (FR-REV-005). Consumer-only; idempotent
  /// per (review, reporter); [reason] is optional (≤500 chars server-side).
  Future<ApiResponse<void>> reportReview(String reviewId, {String? reason});
}
