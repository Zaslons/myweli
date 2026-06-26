import 'package:flutter/foundation.dart';

import '../../models/api_response.dart';
import '../../services/admin/admin_service.dart';

/// Consumer (user) management state: filterable/searchable list + ban / unban.
/// Design: docs/design/admin-console-ui.md §3.
class AdminUsersProvider extends ChangeNotifier {
  AdminUsersProvider({AdminService? service})
      : _service = service ?? adminService;

  final AdminService _service;

  static const _statuses = [null, 'active', 'banned']; // Tous/Actifs/Bannis

  bool _isLoading = false;
  String? _error;
  List<Map<String, dynamic>> _items = [];
  int _filter = 0;
  String _query = '';
  bool _acting = false;
  String? _actionError;

  bool get isLoading => _isLoading;
  String? get error => _error;
  List<Map<String, dynamic>> get items => _items;
  int get filter => _filter;
  bool get acting => _acting;
  String? get actionError => _actionError;

  Future<void> load() async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    final res = await _service.users(status: _statuses[_filter], q: _query);
    if (res.success && res.data != null) {
      _items = (res.data!['items'] as List? ?? const [])
          .cast<Map<String, dynamic>>();
    } else {
      _error = res.error ?? 'Erreur lors du chargement';
    }
    _isLoading = false;
    notifyListeners();
  }

  void setFilter(int i) {
    if (_filter == i) return;
    _filter = i;
    load();
  }

  void search(String q) {
    _query = q;
    load();
  }

  Future<bool> ban(String id, String reason) =>
      _act(_service.banUser(id, reason), id);

  Future<bool> unban(String id) => _act(_service.unbanUser(id), id);

  Future<bool> _act(
    Future<ApiResponse<Map<String, dynamic>>> call,
    String id,
  ) async {
    _acting = true;
    _actionError = null;
    notifyListeners();
    try {
      final res = await call;
      if (res.success && res.data != null) {
        final updated = res.data!;
        final keep = _statuses[_filter] == null ||
            updated['status'] == _statuses[_filter];
        final next = <Map<String, dynamic>>[];
        for (final r in _items) {
          if (r['id'] != id) {
            next.add(r);
          } else if (keep) {
            next.add({...r, ...updated});
          }
        }
        _items = next;
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
