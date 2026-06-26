import 'package:flutter/foundation.dart';

import '../../services/admin/admin_service.dart';

/// Append-only admin audit log: paginated (newest first), filterable by action.
/// Read-only. Design: docs/design/admin-console-ui.md §3.
class AdminAuditProvider extends ChangeNotifier {
  AdminAuditProvider({AdminService? service})
      : _service = service ?? adminService;

  final AdminService _service;

  static const pageSize = 50;

  bool _isLoading = false;
  String? _error;
  List<Map<String, dynamic>> _items = [];
  int _page = 1;
  int _total = 0;
  String? _action;

  bool get isLoading => _isLoading;
  String? get error => _error;
  List<Map<String, dynamic>> get items => _items;
  int get page => _page;
  int get total => _total;
  String? get action => _action;
  bool get hasPrev => _page > 1;
  bool get hasNext => _page * pageSize < _total;

  Future<void> load() async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    final res = await _service.audit(action: _action, page: _page);
    if (res.success && res.data != null) {
      _items = (res.data!['items'] as List? ?? const [])
          .cast<Map<String, dynamic>>();
      _total = (res.data!['total'] as num?)?.toInt() ?? _items.length;
    } else {
      _error = res.error ?? 'Erreur lors du chargement';
    }
    _isLoading = false;
    notifyListeners();
  }

  void setAction(String? action) {
    if (_action == action) return;
    _action = action;
    _page = 1;
    load();
  }

  void nextPage() {
    if (!hasNext) return;
    _page++;
    load();
  }

  void prevPage() {
    if (!hasPrev) return;
    _page--;
    load();
  }
}
