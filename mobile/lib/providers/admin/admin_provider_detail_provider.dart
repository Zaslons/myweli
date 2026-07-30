import 'package:flutter/foundation.dart';

import '../../models/api_response.dart';
import '../../services/admin/admin_service.dart';

/// Salon support view: the provider entity + its recent bookings, plus the
/// suspend / restore / feature actions. Design: docs/design/admin-console-ui.md §3.
class AdminProviderDetailProvider extends ChangeNotifier {
  AdminProviderDetailProvider({AdminService? service})
      : _service = service ?? adminService;

  final AdminService _service;

  bool _isLoading = false;
  String? _error;
  Map<String, dynamic>? _provider;
  List<Map<String, dynamic>> _appointments = [];
  bool _acting = false;
  String? _actionError;

  bool get isLoading => _isLoading;
  String? get error => _error;
  Map<String, dynamic>? get provider => _provider;
  List<Map<String, dynamic>> get appointments => _appointments;
  bool get acting => _acting;
  String? get actionError => _actionError;

  Future<void> load(String id) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    final res = await _service.providerDetail(id);
    if (res.success && res.data != null) {
      final d = res.data!;
      _appointments = (d['recentAppointments'] as List? ?? const [])
          .cast<Map<String, dynamic>>();
      _provider = {...d}..remove('recentAppointments');
    } else {
      _error = res.error ?? 'Erreur lors du chargement';
    }
    _isLoading = false;
    notifyListeners();
  }

  Future<bool> suspend(String id, String reason) =>
      _act(_service.suspendProvider(id, reason));

  Future<bool> restore(String id) => _act(_service.restoreProvider(id));

  Future<bool> feature(String id, bool featured) =>
      _act(_service.featureProvider(id, featured));

  Future<bool> markPaid(String id, int months) =>
      _act(_service.markSubscriptionPaid(id, months));

  Future<bool> _act(Future<ApiResponse<Map<String, dynamic>>> call) async {
    _acting = true;
    _actionError = null;
    notifyListeners();
    try {
      final res = await call;
      if (res.success && res.data != null && _provider != null) {
        _provider = {..._provider!, ...res.data!};
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
