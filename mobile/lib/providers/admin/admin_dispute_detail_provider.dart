import 'package:flutter/foundation.dart';

import '../../services/admin/admin_service.dart';

/// Dispute detail: the dispute + its booking + signed deposit-screenshot URL,
/// plus the resolve action. Design: docs/design/admin-console-ui.md §3.
class AdminDisputeDetailProvider extends ChangeNotifier {
  AdminDisputeDetailProvider({AdminService? service})
    : _service = service ?? adminService;

  final AdminService _service;

  bool _isLoading = false;
  String? _error;
  Map<String, dynamic>? _dispute;
  Map<String, dynamic>? _appointment;
  String? _evidenceUrl;
  bool _acting = false;
  String? _actionError;

  bool get isLoading => _isLoading;
  String? get error => _error;
  Map<String, dynamic>? get dispute => _dispute;
  Map<String, dynamic>? get appointment => _appointment;
  String? get evidenceUrl => _evidenceUrl;
  bool get acting => _acting;
  String? get actionError => _actionError;

  /// Whose entity this is. The provider is app-wide and outlives the screen,
  /// so without it the way to B showed A — A's name, A's status, and an
  /// action bar acting on B's id — until B answered, and for good when B's
  /// read failed (B9.8, docs/design/hygiene-batch9.md §14).
  String? _id;
  String? get id => _id;

  Future<void> load(String id) async {
    if (id != _id) {
      _id = id;
      _dispute = null;
      _appointment = null;
      _evidenceUrl = null;
    }
    _isLoading = true;
    _error = null;
    notifyListeners();
    final res = await _service.disputeDetail(id);
    // Another entity was asked for while this read was out: the answer is
    // no longer anybody's.
    if (id != _id) return;
    if (res.success && res.data != null) {
      final d = res.data!;
      _dispute = (d['dispute'] as Map?)?.cast<String, dynamic>();
      _appointment = (d['appointment'] as Map?)?.cast<String, dynamic>();
      _evidenceUrl = d['depositScreenshotUrl'] as String?;
    } else {
      _error = res.error ?? 'Erreur lors du chargement';
    }
    _isLoading = false;
    notifyListeners();
  }

  Future<bool> resolve(String id, String resolution) async {
    _acting = true;
    _actionError = null;
    notifyListeners();
    try {
      final res = await _service.resolveDispute(id, resolution);
      if (res.success && res.data != null) {
        _dispute = {...?_dispute, ...res.data!};
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
