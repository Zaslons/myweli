import 'package:flutter/foundation.dart';

import '../../models/api_response.dart';
import '../../services/admin/admin_service.dart';

/// Review-moderation state: the **Signalés** (reported) and **Masqués** (hidden)
/// queues + hide/dismiss/restore actions. Design: docs/design/admin-console-ui.md §3.
class AdminModerationProvider extends ChangeNotifier {
  AdminModerationProvider({AdminService? service})
      : _service = service ?? adminService;

  final AdminService _service;

  bool _reportedLoading = false;
  String? _reportedError;
  List<Map<String, dynamic>> _reported = [];

  bool _hiddenLoading = false;
  String? _hiddenError;
  List<Map<String, dynamic>> _hidden = [];

  bool _acting = false;
  String? _actionError;

  bool get reportedLoading => _reportedLoading;
  String? get reportedError => _reportedError;
  List<Map<String, dynamic>> get reported => _reported;
  bool get hiddenLoading => _hiddenLoading;
  String? get hiddenError => _hiddenError;
  List<Map<String, dynamic>> get hidden => _hidden;
  bool get acting => _acting;
  String? get actionError => _actionError;

  Future<void> loadReported() async {
    _reportedLoading = true;
    _reportedError = null;
    notifyListeners();
    final res = await _service.reportedReviews();
    if (res.success && res.data != null) {
      _reported = (res.data!['items'] as List? ?? const [])
          .cast<Map<String, dynamic>>();
    } else {
      _reportedError = res.error ?? 'Erreur lors du chargement';
    }
    _reportedLoading = false;
    notifyListeners();
  }

  Future<void> loadHidden() async {
    _hiddenLoading = true;
    _hiddenError = null;
    notifyListeners();
    final res = await _service.hiddenReviews();
    if (res.success && res.data != null) {
      _hidden = (res.data!['items'] as List? ?? const [])
          .cast<Map<String, dynamic>>();
    } else {
      _hiddenError = res.error ?? 'Erreur lors du chargement';
    }
    _hiddenLoading = false;
    notifyListeners();
  }

  /// Hide a reported review → drops from Signalés (it's now hidden).
  Future<bool> hide(String reviewId, String reason) =>
      _act(_service.hideReview(reviewId, reason), removeFromReported: reviewId);

  /// Dismiss reports (the review is fine) → drops from Signalés.
  Future<bool> dismiss(String reviewId) =>
      _act(_service.dismissReports(reviewId), removeFromReported: reviewId);

  /// Restore a hidden review → drops from Masqués (back in the feed).
  Future<bool> restore(String reviewId) =>
      _act(_service.restoreReview(reviewId), removeFromHidden: reviewId);

  Future<bool> _act(
    Future<ApiResponse<Map<String, dynamic>>> call, {
    String? removeFromReported,
    String? removeFromHidden,
  }) async {
    _acting = true;
    _actionError = null;
    notifyListeners();
    try {
      final res = await call;
      if (res.success) {
        if (removeFromReported != null) {
          _reported = _reported
              .where((r) => r['reviewId'] != removeFromReported)
              .toList();
        }
        if (removeFromHidden != null) {
          _hidden = _hidden.where((r) => r['id'] != removeFromHidden).toList();
        }
        return true;
      }
      _actionError = res.error ?? 'Action impossible';
      return false;
    } finally {
      _acting = false;
      notifyListeners();
    }
  }
}
