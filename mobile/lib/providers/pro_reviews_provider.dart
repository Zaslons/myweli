import 'package:flutter/foundation.dart';

import '../core/access/pro_salon_scope.dart';
import '../core/di/dependency_injection.dart';
import '../models/review.dart';
import '../services/interfaces/review_service_interface.dart';

class ProReviewsProvider extends ChangeNotifier implements SalonScoped {
  final ReviewServiceInterface _reviewService = serviceLocator.reviewService;

  List<Review> _reviews = [];
  bool _isLoading = false;
  String? _error;
  String? _currentProviderId;

  List<Review> get reviews => _reviews;
  bool get isLoading => _isLoading;
  String? get error => _error;

  Future<void> loadReviews(String providerId) async {
    if (_currentProviderId == providerId &&
        _reviews.isNotEmpty &&
        !_isLoading) {
      return;
    }

    _isLoading = true;
    _error = null;
    _currentProviderId = providerId;
    notifyListeners();

    try {
      final res = await _reviewService.getProviderReviews(providerId);
      if (res.success && res.data != null) {
        _reviews = res.data!;
        _error = null;
      } else {
        _reviews = [];
        _error = res.error ?? 'Erreur lors du chargement des avis';
      }
    } catch (e) {
      _error = e.toString();
      _reviews = [];
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// R6 multi-salons: drop the previous salon's data on a switch.
  @override
  void resetForSalonSwitch() {
    _reviews = [];
    _isLoading = false;
    _error = null;
    _currentProviderId = null;
    notifyListeners();
  }
}
