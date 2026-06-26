import 'package:flutter/foundation.dart';

import '../../models/api_response.dart';
import '../../services/admin/admin_service.dart';

/// KYC approval queue + detail state. Design: docs/design/admin-console-ui.md.
class AdminKycProvider extends ChangeNotifier {
  AdminKycProvider({AdminService? service})
      : _service = service ?? adminService;

  final AdminService _service;

  bool _isLoading = false;
  String? _error;
  List<Map<String, dynamic>> _queue = [];

  bool _detailLoading = false;
  String? _detailError;
  Map<String, dynamic>? _detail;

  bool _acting = false;
  String? _actionError;

  bool get isLoading => _isLoading;
  String? get error => _error;
  List<Map<String, dynamic>> get queue => _queue;
  bool get detailLoading => _detailLoading;
  String? get detailError => _detailError;
  Map<String, dynamic>? get detail => _detail;
  bool get acting => _acting;
  String? get actionError => _actionError;

  Future<void> loadQueue() async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    final res = await _service.kycQueue();
    if (res.success && res.data != null) {
      _queue = (res.data!['items'] as List? ?? const [])
          .cast<Map<String, dynamic>>();
    } else {
      _error = res.error ?? 'Erreur lors du chargement';
    }
    _isLoading = false;
    notifyListeners();
  }

  Future<void> loadDetail(String accountId) async {
    _detailLoading = true;
    _detailError = null;
    _detail = null;
    notifyListeners();
    final res = await _service.kycDetail(accountId);
    if (res.success && res.data != null) {
      _detail = res.data;
    } else {
      _detailError = res.error ?? 'Erreur lors du chargement';
    }
    _detailLoading = false;
    notifyListeners();
  }

  /// Approve/reject; returns true on success (the screen then pops + refreshes).
  Future<bool> approve(String accountId) =>
      _act(_service.approveKyc(accountId));

  Future<bool> reject(String accountId, String reason) =>
      _act(_service.rejectKyc(accountId, reason));

  Future<bool> _act(Future<ApiResponse<Map<String, dynamic>>> call) async {
    _acting = true;
    _actionError = null;
    notifyListeners();
    try {
      final res = await call;
      if (res.success) return true;
      _actionError = res.error ?? 'Action impossible';
      return false;
    } finally {
      _acting = false;
      notifyListeners();
    }
  }
}
