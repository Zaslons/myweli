import 'package:flutter/foundation.dart';

import '../core/di/dependency_injection.dart';
import '../models/notification_preferences.dart';
import '../services/interfaces/notification_service_interface.dart';

/// Drives the notification-preferences screen (FR-NOTIF-004): loads the prefs
/// and toggles them **optimistically, reverting on a failed save**.
class NotificationPreferencesProvider extends ChangeNotifier {
  final NotificationServiceInterface _service =
      serviceLocator.notificationService;

  NotificationPreferences _prefs = const NotificationPreferences();
  bool _isLoading = false;
  bool _loadFailed = false;
  bool _saving = false;
  String? _error;

  NotificationPreferences get prefs => _prefs;
  bool get isLoading => _isLoading;
  bool get loadFailed => _loadFailed;
  bool get saving => _saving;
  String? get error => _error;

  Future<void> load() async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      final res = await _service.getPreferences();
      if (res.success && res.data != null) {
        _prefs = res.data!;
        _loadFailed = false;
      } else {
        _loadFailed = true;
        _error = res.error ?? 'Erreur lors du chargement';
      }
    } catch (e) {
      _loadFailed = true;
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> setReminders(bool value) =>
      _apply(_prefs.copyWith(reminders: value), reminders: value);
  Future<bool> setMarketing(bool value) =>
      _apply(_prefs.copyWith(marketing: value), marketing: value);
  Future<bool> setPush(bool value) =>
      _apply(_prefs.copyWith(push: value), push: value);

  /// Flip optimistically, persist the single changed field, **revert on
  /// failure**. Returns whether the save succeeded.
  Future<bool> _apply(
    NotificationPreferences optimistic, {
    bool? reminders,
    bool? marketing,
    bool? push,
  }) async {
    final previous = _prefs;
    _prefs = optimistic;
    _saving = true;
    _error = null;
    notifyListeners();
    try {
      final res = await _service.updatePreferences(
        reminders: reminders,
        marketing: marketing,
        push: push,
      );
      if (res.success && res.data != null) {
        _prefs = res.data!;
        return true;
      }
      _prefs = previous; // revert
      _error = res.error ?? 'Impossible d\'enregistrer. Réessayez.';
      return false;
    } catch (e) {
      _prefs = previous; // revert
      _error = 'Impossible d\'enregistrer. Réessayez.';
      return false;
    } finally {
      _saving = false;
      notifyListeners();
    }
  }
}
