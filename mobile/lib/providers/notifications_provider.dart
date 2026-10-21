import 'package:flutter/foundation.dart';

import '../core/constants/failure_messages.dart';
import '../core/di/dependency_injection.dart';
import '../models/api_response.dart';
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

  /// The notifications with a « lu » write still out
  /// (docs/design/app-failure-messages.md §2.3). A reload while one is out
  /// would bring the server's list — which has not written it yet — and turn
  /// the row the person just opened back to unread; so they stay read until
  /// their write answers.
  final Set<String> _writing = {};

  /// The notifications whose « lu » the server confirmed WHILE a reload was
  /// out. That reload's list was taken before the write landed, so it is the
  /// older of the two: it must not turn them back to unread. Emptied once no
  /// reload is out — from then on the server's list rules.
  final Set<String> _confirmedDuringLoad = {};
  int _loadsOut = 0;
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
    _loadsOut++;
    notifyListeners();

    try {
      final response = await _service.getNotifications();
      if (response.success && response.data != null) {
        _items = [
          for (final n in response.data!)
            _writing.contains(n.id) || _confirmedDuringLoad.contains(n.id)
                ? n.copyWith(read: true)
                : n,
        ];
        _loadFailed = false;
        _error = null;
      } else {
        _loadFailed = true;
        _error = response.error ?? 'Erreur lors du chargement';
        _items = [];
      }
    } catch (e) {
      _loadFailed = true;
      _error = kGenericErrorMessage;
      _items = [];
    } finally {
      _loadsOut--;
      if (_loadsOut == 0) _confirmedDuringLoad.clear();
      _isLoading = false;
      notifyListeners();
    }
  }

  /// What a refused write says when the service has nothing better — the
  /// app's fallback on the favourite heart. The server's own sentence is never
  /// shown: these routes send none, and `_errorFrom` turns that into « Erreur ».
  static const writeFailedMessage = kGenericErrorMessage;

  /// Mark one notification read at once, then persist.
  ///
  /// Returns `null` when the server took it (or there was nothing to do);
  /// otherwise THIS notification is unread again — only it, in the current
  /// list — and the result is the sentence to show.
  /// Design: docs/design/app-notifications-read-revert.md §3.
  Future<String?> markRead(String id) async {
    final index = _items.indexWhere((n) => n.id == id);
    if (index == -1 || _items[index].read) return null;
    final marked = {id};
    return _markAndPersist(marked, () => _service.markRead(id));
  }

  /// Mark everything read at once, then persist.
  ///
  /// On a failure only the notifications that were unread when the gesture
  /// started go back to unread: one read before stays read, one tapped
  /// meanwhile keeps its own outcome, one a reload brought in is left alone
  /// (SYSTEM.md §15 — undo undoes ONE action, never a snapshot).
  Future<String?> markAllRead() async {
    final marked = {
      for (final n in _items)
        if (!n.read) n.id,
    };
    if (marked.isEmpty) return null;
    return _markAndPersist(marked, _service.markAllRead);
  }

  /// Read at once; kept read across a reload while [write] is out; then the
  /// server's answer decides — only for [marked], never a snapshot.
  Future<String?> _markAndPersist(
    Set<String> marked,
    Future<ApiResponse<bool>> Function() write,
  ) async {
    _setRead(marked, true);
    _writing.addAll(marked);
    final failure = await _persist(write);
    _writing.removeAll(marked);
    if (failure != null) {
      _setRead(marked, false);
    } else if (_loadsOut > 0) {
      // A reload still out took its list before this write: keep them read
      // when it answers.
      _confirmedDuringLoad.addAll(marked);
    }
    return failure;
  }

  void _setRead(Set<String> ids, bool read) {
    _items = [
      for (final n in _items) ids.contains(n.id) ? n.copyWith(read: read) : n,
    ];
    notifyListeners();
  }

  /// `null` when [write] went through, else the sentence: the service's own
  /// when there was no answer (« Pas de connexion. Réessayez. »), the generic
  /// one for anything else — a refusal, no session, an exception.
  Future<String?> _persist(Future<ApiResponse<bool>> Function() write) async {
    try {
      var response = await write();
      // A lost answer is asked again ONCE, at once, without a word (owner
      // decision 12): the write is safe to repeat — the server sets
      // `read = true` and answers 200 every time.
      if (!response.success && response.code == 'network') {
        response = await write();
      }
      if (response.success) return null;
      if (response.code == 'network') {
        return response.error ?? writeFailedMessage;
      }
      return writeFailedMessage;
    } catch (_) {
      return writeFailedMessage;
    }
  }
}
