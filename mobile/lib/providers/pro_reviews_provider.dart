import 'package:flutter/foundation.dart';
import '../models/review.dart';
import '../services/mock/mock_data.dart';
import '../core/constants/app_constants.dart';

class ProReviewsProvider extends ChangeNotifier {
  List<Review> _reviews = [];
  bool _isLoading = false;
  String? _error;
  String? _currentProviderId;

  List<Review> get reviews => _reviews;
  bool get isLoading => _isLoading;
  String? get error => _error;

  Future<void> loadReviews(String providerId) async {
    if (_currentProviderId == providerId && _reviews.isNotEmpty && !_isLoading) {
      return;
    }

    _isLoading = true;
    _error = null;
    _currentProviderId = providerId;
    notifyListeners();

    try {
      // For now, use mock data directly.
      // TODO(reviews): inject ProServiceInterface and call getProviderReviews(providerId).
      await Future.delayed(AppConstants.mockDelay);
      _reviews = MockData.reviews.where((r) => r.providerId == providerId).toList();
      _reviews.sort((a, b) => b.createdAt.compareTo(a.createdAt)); // Most recent first
      _error = null;
    } catch (e) {
      _error = e.toString();
      _reviews = [];
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
