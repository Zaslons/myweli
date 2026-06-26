import 'package:flutter/foundation.dart';

import '../../services/admin/admin_service.dart';

/// Admin session state for the console (login / logout / restore). Drives the
/// router redirect. Design: docs/design/admin-console-ui.md.
class AdminAuthProvider extends ChangeNotifier {
  AdminAuthProvider({AdminService? service})
      : _service = service ?? adminService;

  final AdminService _service;

  bool _isAuthenticated = false;
  bool _isLoading = false;
  bool _restoring = true;
  String? _error;

  bool get isAuthenticated => _isAuthenticated;
  bool get isLoading => _isLoading;
  bool get restoring => _restoring;
  String? get error => _error;

  /// On startup: is there a stored admin session?
  Future<void> restore() async {
    _isAuthenticated = await _service.hasSession();
    _restoring = false;
    notifyListeners();
  }

  Future<bool> login(String email, String password) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      final res = await _service.login(email.trim(), password);
      if (res.success) {
        _isAuthenticated = true;
        return true;
      }
      _error = res.error ?? 'Identifiants invalides';
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> logout() async {
    await _service.logout();
    _isAuthenticated = false;
    notifyListeners();
  }
}
