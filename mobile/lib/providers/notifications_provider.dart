import 'package:flutter/foundation.dart';

import '../core/di/dependency_injection.dart';
import '../models/app_notification.dart';
import '../services/interfaces/notification_service_interface.dart';

class NotificationsProvider extends ChangeNotifier {
  /// [service] lets the PRO app run the same feed on its own session
  /// (`serviceLocator.proNotificationService`); the consumer app keeps the
  /// default. The feed is ACCOUNT-scoped, not salon-scoped: `/me/notifications`
  /// is keyed by the token's subject, so a multi-salon owner sees one merged
  /// feed and a salon switch must not reset it.
  NotificationsProvider({NotificationServiceInterface? service})
      : _service = service ?? serviceLocator.notificationService;

  final NotificationServiceInterface _service;

  List<AppNotification> _items = [];
  bool _isLoading = false;
  bool _loadFailed = false;
  String? _error;

  List<AppNotification> get notifications => _items;
  bool get isLoading => _isLoading;
  bool get loadFailed => _loadFailed;
  String? get error => _error;
  int get unreadCount => _items.where((n) => !n.read).length;

  Future<void> load() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final response = await _service.getNotifications();
      if (response.success && response.data != null) {
        _items = response.data!;
        _loadFailed = false;
        _error = null;
      } else {
        _loadFailed = true;
        _error = response.error ?? 'Erreur lors du chargement';
        _items = [];
      }
    } catch (e) {
      _loadFailed = true;
      _error = e.toString();
      _items = [];
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Optimistically mark one notification read, then persist.
  Future<void> markRead(String id) async {
    final index = _items.indexWhere((n) => n.id == id);
    if (index == -1 || _items[index].read) return;
    _items[index] = _items[index].copyWith(read: true);
    notifyListeners();
    await _service.markRead(id);
  }

  /// Optimistically mark everything read, then persist.
  Future<void> markAllRead() async {
    if (unreadCount == 0) return;
    _items = _items.map((n) => n.copyWith(read: true)).toList();
    notifyListeners();
    await _service.markAllRead();
  }
}
