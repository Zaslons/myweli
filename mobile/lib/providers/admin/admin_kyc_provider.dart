import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/utils/app_clock.dart';
import '../../models/api_response.dart';
import '../../services/admin/admin_service.dart';

/// KYC approval queue + detail state. Design: docs/design/admin-console-ui.md,
/// docs/design/admin-kyc-queue-submitted.md.
class AdminKycProvider extends ChangeNotifier {
  /// Approve/reject refused with `invalid_state`: the file is no longer
  /// awaiting review — another admin acted, or it was never a submission.
  static const notPendingMessage =
      'Ce dossier n’est plus en attente de vérification.';

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

  /// Whose file [detail] is: the provider outlives the screen, and the first
  /// frame of the next file's screen still holds the last one (B9.8).
  String? _detailId;
  String? get detailId => _detailId;
  Map<String, dynamic>? get detail => _detail;

  /// When [detail] arrived. Its signed document links live 5 minutes from
  /// about then (`_docTtl`, backend `admin_kyc_service.dart`): a PDF is
  /// fetched only when clicked, so its tile needs to know.
  DateTime? _detailLoadedAt;
  DateTime? get detailLoadedAt => _detailLoadedAt;
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
    _detailId = accountId;
    _detailLoading = true;
    _detailError = null;
    _detail = null;
    _detailLoadedAt = null;
    notifyListeners();
    final res = await _service.kycDetail(accountId);
    // Another file was opened while this read was out (B9.8).
    if (accountId != _detailId) return;
    if (res.success && res.data != null) {
      _detail = res.data;
      _detailLoadedAt = AppClock.now();
    } else {
      _detailError = res.error ?? 'Erreur lors du chargement';
    }
    _detailLoading = false;
    notifyListeners();
  }

  /// Approve/reject; returns true on success (the screen then pops + refreshes).
  Future<bool> approve(String accountId) =>
      _act(accountId, _service.approveKyc(accountId));

  Future<bool> reject(String accountId, String reason) =>
      _act(accountId, _service.rejectKyc(accountId, reason));

  Future<bool> _act(
    String accountId,
    Future<ApiResponse<Map<String, dynamic>>> call,
  ) async {
    _acting = true;
    _actionError = null;
    notifyListeners();
    try {
      final res = await call;
      if (res.success) return true;
      if (res.code == 'invalid_state') {
        _actionError = notPendingMessage;
        // The file moved on under the admin: what they are looking at is
        // stale. Reload it, so the buttons give way to « Aucune soumission
        // en attente. ».
        if (_detailId == accountId) unawaited(loadDetail(accountId));
      } else {
        _actionError = res.error ?? 'Action impossible';
      }
      return false;
    } finally {
      _acting = false;
      notifyListeners();
    }
  }
}
