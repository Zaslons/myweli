import 'package:flutter/foundation.dart';

import '../core/access/pro_salon_scope.dart';
import '../core/constants/failure_messages.dart';
import '../core/di/dependency_injection.dart';
import '../core/utils/salon_id.dart';
import '../models/review.dart';
import '../models/review_summary.dart';
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

  /// The whole salon's card (salon-reviews-summary.md) — null until loaded,
  /// or from a server older than it.
  ReviewSummary? _summary;
  bool _isLoading = false;
  String? _error;
  SalonId? _currentProviderId;

  List<Review> get reviews => _reviews;
  ReviewSummary? get summary => _summary;
  bool get isLoading => _isLoading;
  String? get error => _error;

  /// The load's own failure — today the only one [error] holds here, kept
  /// apart as on the other Pro lists, so a write added later cannot become
  /// the list's load error (B9.8).
  String? get loadError => _loadError;
  String? _loadError;

  /// « Signaler » (B6.6): true once the server took the report.
  Future<bool> reportReview(String reviewId, {String? reason}) async {
    try {
      final res = await _proService.reportSalonReview(reviewId, reason: reason);
      return res.success;
    } catch (_) {
      return false;
    }
  }

  Future<void> loadReviews(SalonId providerId) async {
    final scope = _scope;
    if (_currentProviderId == providerId &&
        _reviews.isNotEmpty &&
        !_isLoading) {
      return;
    }

    _isLoading = true;
    _error = null;
    _loadError = null;
    _currentProviderId = providerId;
    notifyListeners();

    try {
      // No providerId argument: `/me/provider/reviews` resolves the acting
      // salon from the token, honouring the R6 selection on the way.
      final res = await _proService.getMyReviews();
      if (scope != _scope) return;
      if (res.success && res.data != null) {
        _reviews = res.data!.items;
        _summary = res.data!.summary;
        _error = null;
      } else {
        _reviews = [];
        _summary = null;
        _error = res.error ?? 'Erreur lors du chargement des avis';
        _loadError = _error;
      }
    } catch (e) {
      if (scope != _scope) return;
      _error = kGenericErrorMessage;
      _loadError = _error;
      _reviews = [];
      _summary = null;
    } finally {
      if (scope == _scope) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  /// R6 multi-salons: drop the previous salon's data on a switch.
  /// Which salon this state belongs to — moved by [resetForSalonSwitch]
  /// only. A read or a write takes it before it awaits and writes nothing
  /// when it moved meanwhile: its answer is the previous salon's, or the
  /// previous account's (docs/design/pro-account-scope.md §2.2).
  int _scope = 0;

  @override
  void resetForSalonSwitch() {
    _scope++;
    _loadError = null;
    _reviews = [];
    _summary = null;
    _isLoading = false;
    _error = null;
    _currentProviderId = null;
    notifyListeners();
  }
}
