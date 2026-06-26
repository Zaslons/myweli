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
}
