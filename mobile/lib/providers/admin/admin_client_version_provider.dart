import 'package:flutter/foundation.dart';

import '../../services/admin/admin_service.dart';

/// The client version floors, for the admin console
/// (docs/design/client-version-gate.md §14).
class AdminClientVersionProvider extends ChangeNotifier {
  AdminClientVersionProvider({AdminService? service})
    : _service = service ?? adminService;

  final AdminService _service;

  bool _isLoading = false;
  String? _error;
  List<Map<String, dynamic>> _floors = [];
  bool _saving = false;
  String? _actionError;

  /// The machine code of the last failed save, so the screen can route a
  /// field-shaped fault to its field rather than to a snackbar
  /// (SYSTEM.md §830). `actionError` stays the human sentence.
  String? _actionCode;

  bool get isLoading => _isLoading;
  String? get error => _error;
  List<Map<String, dynamic>> get floors => List.unmodifiable(_floors);
  bool get isSaving => _saving;
  String? get actionError => _actionError;
  String? get actionCode => _actionCode;

  Future<void> load() async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    final res = await _service.clientVersionFloors();
    if (res.success && res.data != null) {
      _floors = (res.data!['items'] as List? ?? const [])
          .cast<Map<String, dynamic>>();
    } else {
      _error = res.error ?? 'Erreur lors du chargement';
    }
    _isLoading = false;
    notifyListeners();
  }

  Future<bool> setFloor({
    required String appId,
    required String platform,
    required int minimumBuild,
    required int recommendedBuild,
    required String? updateUrl,
  }) async {
    _saving = true;
    _actionError = null;
    _actionCode = null;
    notifyListeners();
    try {
      final res = await _service.setClientVersionFloor(
        appId: appId,
        platform: platform,
        minimumBuild: minimumBuild,
        recommendedBuild: recommendedBuild,
        updateUrl: updateUrl,
      );
      if (!res.success) {
        _actionError = res.error ?? 'Action impossible';
        _actionCode = res.code;
        return false;
      }
      // Patch the row in place rather than re-fetching. The server returns the
      // updated row, so a reload would be a second round trip to learn what we
      // already know — and on a four-row table the flicker is the only visible
      // difference.
      final updated = res.data;
      if (updated != null) {
        final i = _floors.indexWhere(
          (f) => f['appId'] == appId && f['platform'] == platform,
        );
        if (i >= 0) _floors[i] = updated;
      }
      return true;
    } finally {
      _saving = false;
      notifyListeners();
    }
  }
}
