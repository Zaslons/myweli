import '../../models/api_response.dart';
import '../../models/review.dart';

abstract class ReviewServiceInterface {
  /// Submits a review for a completed booking. The server re-validates that the
  /// booking is completed and owns the `verified` flag; returns the stored
  /// review.
  Future<ApiResponse<Review>> submitReview(Review review);
}
