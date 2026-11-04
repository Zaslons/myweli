import 'package:flutter/foundation.dart';

import '../core/access/account_scope.dart';
import '../core/constants/failure_messages.dart';
import '../core/di/dependency_injection.dart';
import '../models/api_response.dart';
import '../models/notification_preferences.dart';
import '../services/interfaces/notification_service_interface.dart';

/// Drives the notification-preferences screen (FR-NOTIF-004): loads the prefs
/// and toggles them **optimistically, reverting on a failed save**.
class NotificationPreferencesProvider extends ChangeNotifier
    implements AccountScoped {
  final NotificationServiceInterface _service =
      serviceLocator.notificationService;

  /// Whose switches these are — see [resetForAccountChange]. A read or a save
  /// sent before the account changed writes nothing when it answers after:
  /// a refused save's revert would restore the PREVIOUS account's switch
  /// (docs/design/consumer-account-scope.md §2.3).
  int _account = 0;

  /// The account changed (B9.13): back to « not asked yet » — [loadedPrefs]
  /// null, so the screen shows its skeleton, not the defaults as answers.
  @override
  void resetForAccountChange() {
    _account++;
    _prefs = const NotificationPreferences();
    _loaded = false;
    _loadFailed = false;
    _isLoading = false;
    _saving = false;
    _error = null;
    notifyListeners();
  }

  NotificationPreferences _prefs = const NotificationPreferences();
  bool _isLoading = false;
  bool _loadFailed = false;
  bool _saving = false;
  String? _error;

  NotificationPreferences get prefs => _prefs;

  /// The preferences once the server said them — null before: [prefs] holds
  /// defaults until then, and a screen showing them would set switches the
  /// person never set (B9.8).
  NotificationPreferences? get loadedPrefs => _loaded ? _prefs : null;
  bool _loaded = false;
  bool get isLoading => _isLoading;
  bool get loadFailed => _loadFailed;
  bool get saving => _saving;
  String? get error => _error;

  Future<void> load() async {
    final account = _account;
    _isLoading = true;
    _error = null;
    notifyListeners();
    ApiResponse<NotificationPreferences>? res;
    try {
      res = await _service.getPreferences();
    } catch (e) {
      res = null;
    }
    if (account != _account) return;
    final prefs = res?.data;
    if (res != null && res.success && prefs != null) {
      _prefs = prefs;
      _loaded = true;
      _loadFailed = false;
    } else {
      _loadFailed = true;
      _error = res == null
          ? kGenericErrorMessage
          : res.error ?? kGenericErrorMessage;
    }
    _isLoading = false;
    notifyListeners();
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
    final account = _account;
    final previous = _prefs;
    _prefs = optimistic;
    _saving = true;
    _error = null;
    notifyListeners();
    ApiResponse<NotificationPreferences>? res;
    try {
      res = await _service.updatePreferences(
        reminders: reminders,
        marketing: marketing,
        push: push,
      );
    } catch (e) {
      res = null;
    }
    final saved = res?.data;
    final ok = res != null && res.success && saved != null;
    if (account != _account) return ok;
    if (ok) {
      _prefs = saved;
    } else {
      _prefs = previous; // revert
      _error = res?.error ?? 'Impossible d’enregistrer. Réessayez.';
    }
    _saving = false;
    notifyListeners();
    return ok;
  }
}
