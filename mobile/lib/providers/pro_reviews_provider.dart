import 'package:flutter/foundation.dart';

import '../core/access/pro_salon_scope.dart';
import '../core/di/dependency_injection.dart';
import '../models/review.dart';
import '../services/interfaces/pro_service_interface.dart';

/// The salon's own « Avis ».
///
/// **It reads by account, not by public id.** This used the CONSUMER review
/// service — `getProviderReviews`, which sends no token and hits the public
/// `GET /providers/{id}/reviews` — so the pro app asked the anonymous door for
/// its own reviews, passing the salon id from the client. PR1b moved four
/// surfaces off that door and its source pin could not see this one: the leak
/// crossed a *service* boundary rather than a directory one, and none of the
/// forbidden tokens appeared here. Decision C closes the public route, and a
/// draft salon can hold reviews (T53, T54).
class ProReviewsProvider extends ChangeNotifier implements SalonScoped {
  final ProServiceInterface _proService = serviceLocator.proService;

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
      // No providerId argument: `/me/provider/reviews` resolves the acting
      // salon from the token, honouring the R6 selection on the way.
      final res = await _proService.getMyReviews();
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
