import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/config/app_config.dart';
import '../../models/api_response.dart';
import '../../models/app_notification.dart';
import '../../models/notification_preferences.dart';
import '../interfaces/notification_service_interface.dart';
import '../interfaces/session_store.dart';
import 'refreshing_http_client.dart';

/// Real HTTP implementation of [NotificationServiceInterface] (backend
/// FR-NOTIF-002). The feed is per-account + server-scoped (the user is the
/// token's `sub`), so calls just go through a [RefreshingHttpClient] (silent
/// refresh on a 401). Wired in by DI when `AppConfig.useApiBackend` is true.
///
/// The endpoints are role-agnostic, so the PRO app runs the same service on
/// its own session ([sessionStore] = the provider store, [refreshPath] =
/// `/auth/provider/refresh`) and reads the salon-team feed
/// (docs/design/push-notifications-fcm.md §10).
/// Design: docs/design/notification-center.md.
class ApiNotificationService implements NotificationServiceInterface {
  ApiNotificationService({
    http.Client? client,
    String? baseUrl,
    SessionStore? sessionStore,
    String refreshPath = '/auth/refresh',
  })  : _client = client ?? http.Client(),
        _baseUrl = baseUrl ?? AppConfig.apiBaseUrl,
        _sessionStore = sessionStore ?? InMemorySessionStore(),
        _refreshPath = refreshPath;

  final http.Client _client;
  final String _baseUrl;
  final SessionStore _sessionStore;
  final String _refreshPath;

  late final RefreshingHttpClient _authed = RefreshingHttpClient(
    client: _client,
    baseUrl: _baseUrl,
    store: _sessionStore,
    refreshPath: _refreshPath,
  );

  @override
  Future<ApiResponse<List<AppNotification>>> getNotifications() async {
    if (await _authed.accessToken() == null) {
      return ApiResponse.error('Non connecté');
    }
    final res = await _authed.send(
      (t) => _client.get(_uri('/me/notifications'), headers: _bearer(t)),
    );
    if (res == null) return _networkError();
    if (res.statusCode != 200) return _errorFrom(res);
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final items = ((body['items'] as List?) ?? const [])
        .map((e) => AppNotification.fromJson(e as Map<String, dynamic>))
        .toList();
    return ApiResponse.success(items);
  }

  @override
  Future<ApiResponse<bool>> markRead(String id) =>
      _post('/me/notifications/$id/read');

  @override
  Future<ApiResponse<bool>> markAllRead() =>
      _post('/me/notifications/read-all');

  @override
  Future<ApiResponse<NotificationPreferences>> getPreferences() async {
    if (await _authed.accessToken() == null) {
      return ApiResponse.error('Non connecté');
    }
    final res = await _authed.send(
      (t) => _client.get(_uri('/me/notification-preferences'),
          headers: _bearer(t)),
    );
    if (res == null) return _networkError();
    if (res.statusCode != 200) return _errorFrom(res);
    return ApiResponse.success(
      NotificationPreferences.fromJson(
        jsonDecode(res.body) as Map<String, dynamic>,
      ),
    );
  }

  @override
  Future<ApiResponse<NotificationPreferences>> updatePreferences({
    bool? reminders,
    bool? marketing,
    bool? push,
  }) async {
    if (await _authed.accessToken() == null) {
      return ApiResponse.error('Non connecté');
    }
    final body = jsonEncode({
      if (reminders != null) 'reminders': reminders,
      if (marketing != null) 'marketing': marketing,
      if (push != null) 'push': push,
    });
    final res = await _authed.send(
      (t) => _client.put(
        _uri('/me/notification-preferences'),
        headers: {..._bearer(t), 'Content-Type': 'application/json'},
        body: body,
      ),
    );
    if (res == null) return _networkError();
    if (res.statusCode != 200) return _errorFrom(res);
    return ApiResponse.success(
      NotificationPreferences.fromJson(
        jsonDecode(res.body) as Map<String, dynamic>,
      ),
    );
  }

  Future<ApiResponse<bool>> _post(String path) async {
    if (await _authed.accessToken() == null) {
      return ApiResponse.error('Non connecté');
    }
    final res = await _authed.send(
      (t) => _client.post(_uri(path), headers: _bearer(t)),
    );
    if (res == null) return _networkError();
    if (res.statusCode != 200) return _errorFrom(res);
    return ApiResponse.success(true);
  }

  Uri _uri(String path) => Uri.parse('$_baseUrl$path');
  Map<String, String> _bearer(String token) =>
      {'Authorization': 'Bearer $token'};
  ApiResponse<T> _networkError<T>() =>
      ApiResponse.error('Pas de connexion. Réessayez.');

  ApiResponse<T> _errorFrom<T>(http.Response res) {
    try {
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      return ApiResponse.error(
        body['message'] as String? ?? 'Erreur',
        code: body['error'] as String?,
      );
    } catch (_) {
      return ApiResponse.error('Erreur');
    }
  }
}
