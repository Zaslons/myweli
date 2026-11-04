import 'package:flutter/foundation.dart';

import '../../models/api_response.dart';
import '../../services/admin/admin_service.dart';

/// Client support view: the user entity + their recent bookings, plus the
/// ban / unban actions. Design: docs/design/admin-console-ui.md §3.
class AdminUserDetailProvider extends ChangeNotifier {
  AdminUserDetailProvider({AdminService? service})
    : _service = service ?? adminService;

  final AdminService _service;

  bool _isLoading = false;
  String? _error;
  Map<String, dynamic>? _user;
  List<Map<String, dynamic>> _appointments = [];
  bool _acting = false;
  String? _actionError;

  bool get isLoading => _isLoading;
  String? get error => _error;
  Map<String, dynamic>? get user => _user;
  List<Map<String, dynamic>> get appointments => _appointments;
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
      _user = null;
      _appointments = [];
    }
    _isLoading = true;
    _error = null;
    notifyListeners();
    final res = await _service.userDetail(id);
    // Another entity was asked for while this read was out: the answer is
    // no longer anybody's.
    if (id != _id) return;
    if (res.success && res.data != null) {
      final d = res.data!;
      _appointments = (d['recentAppointments'] as List? ?? const [])
          .cast<Map<String, dynamic>>();
      _user = {...d}..remove('recentAppointments');
    } else {
      _error = res.error ?? 'Erreur lors du chargement';
    }
    _isLoading = false;
    notifyListeners();
  }

  Future<bool> ban(String id, String reason) =>
      _act(_service.banUser(id, reason));

  Future<bool> unban(String id) => _act(_service.unbanUser(id));

  Future<bool> _act(Future<ApiResponse<Map<String, dynamic>>> call) async {
    _acting = true;
    _actionError = null;
    notifyListeners();
    try {
      final res = await call;
      if (res.success && res.data != null && _user != null) {
        _user = {..._user!, ...res.data!};
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
