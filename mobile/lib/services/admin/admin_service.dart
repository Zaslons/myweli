import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/config/app_config.dart';
import '../../models/api_response.dart';
import '../../services/secure_session_store.dart';
import '../api/refreshing_http_client.dart';
import '../interfaces/session_store.dart';

/// The admin/ops console's single backend client (design:
/// docs/design/admin-console-ui.md). Auth + data in one place since the console
/// is small. The admin session lives under its **own** secure key, never mixed
/// with the consumer/provider sessions; data calls carry the admin bearer via
/// [RefreshingHttpClient] (silent refresh on 401 at `/admin/auth/refresh`).
class AdminService {
  AdminService({http.Client? client, String? baseUrl, SessionStore? store})
      : _client = client ?? http.Client(),
        _baseUrl = baseUrl ?? AppConfig.apiBaseUrl,
        _store = store ?? SecureSessionStore(key: 'myweli_admin_session') {
    _authed = RefreshingHttpClient(
      client: _client,
      baseUrl: _baseUrl,
      store: _store,
      refreshPath: '/admin/auth/refresh',
    );
  }

  final http.Client _client;
  final String _baseUrl;
  final SessionStore _store;
  late final RefreshingHttpClient _authed;

  Future<bool> hasSession() async => (await _store.read()) != null;

  Future<ApiResponse<bool>> login(String email, String password) async {
    final http.Response res;
    try {
      res = await _client.post(
        Uri.parse('$_baseUrl/admin/auth/login'),
        headers: const {'content-type': 'application/json'},
        body: jsonEncode({'email': email, 'password': password}),
      );
    } catch (_) {
      return ApiResponse.error('Connexion au serveur impossible');
    }
    if (res.statusCode == 200) {
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      await _store.save(
        jsonEncode({
          'token': body['accessToken'],
          'refreshToken': body['refreshToken'],
        }),
      );
      return ApiResponse.success(true);
    }
    if (res.statusCode == 429) {
      return ApiResponse.error(
        'Trop de tentatives. Réessayez plus tard.',
        code: 'locked_out',
      );
    }
    return ApiResponse.error(
      'Identifiants invalides',
      code: 'invalid_credentials',
    );
  }

  Future<void> logout() => _store.clear();

  Future<ApiResponse<Map<String, dynamic>>> overview() =>
      _get('/admin/analytics/overview');

  Future<ApiResponse<Map<String, dynamic>>> kycQueue({int page = 1}) =>
      _get('/admin/kyc?page=$page&pageSize=50');

  Future<ApiResponse<Map<String, dynamic>>> kycDetail(String accountId) =>
      _get('/admin/kyc/$accountId');

  Future<ApiResponse<Map<String, dynamic>>> approveKyc(String accountId) =>
      _post('/admin/kyc/$accountId/approve');

  Future<ApiResponse<Map<String, dynamic>>> rejectKyc(
    String accountId,
    String reason,
  ) =>
      _post('/admin/kyc/$accountId/reject', body: {'reason': reason});

  // --- review moderation -----------------------------------------------------
  Future<ApiResponse<Map<String, dynamic>>> reportedReviews({int page = 1}) =>
      _get('/admin/reviews/reports?page=$page&pageSize=50');

  Future<ApiResponse<Map<String, dynamic>>> hiddenReviews({int page = 1}) =>
      _get('/admin/reviews/hidden?page=$page&pageSize=50');

  Future<ApiResponse<Map<String, dynamic>>> hideReview(
    String reviewId,
    String reason,
  ) =>
      _post('/admin/reviews/$reviewId/hide', body: {'reason': reason});

  Future<ApiResponse<Map<String, dynamic>>> dismissReports(String reviewId) =>
      _post('/admin/reviews/$reviewId/dismiss');

  Future<ApiResponse<Map<String, dynamic>>> restoreReview(String reviewId) =>
      _post('/admin/reviews/$reviewId/restore');

  // --- provider management ---------------------------------------------------
  Future<ApiResponse<Map<String, dynamic>>> providers({
    String? status,
    String? q,
    int page = 1,
  }) {
    final params = <String, String>{'page': '$page', 'pageSize': '50'};
    if (status != null && status.isNotEmpty) params['status'] = status;
    if (q != null && q.trim().isNotEmpty) params['q'] = q.trim();
    return _get('/admin/providers?${_query(params)}');
  }

  Future<ApiResponse<Map<String, dynamic>>> providerDetail(String id) =>
      _get('/admin/providers/$id');

  Future<ApiResponse<Map<String, dynamic>>> suspendProvider(
    String id,
    String reason,
  ) =>
      _post('/admin/providers/$id/suspend', body: {'reason': reason});

  Future<ApiResponse<Map<String, dynamic>>> restoreProvider(String id) =>
      _post('/admin/providers/$id/restore');

  Future<ApiResponse<Map<String, dynamic>>> featureProvider(
    String id,
    bool featured,
  ) =>
      _post('/admin/providers/$id/feature', body: {'featured': featured});

  // --- consumer management ---------------------------------------------------
  Future<ApiResponse<Map<String, dynamic>>> users({
    String? status,
    String? q,
    int page = 1,
  }) {
    final params = <String, String>{'page': '$page', 'pageSize': '50'};
    if (status != null && status.isNotEmpty) params['status'] = status;
    if (q != null && q.trim().isNotEmpty) params['q'] = q.trim();
    return _get('/admin/users?${_query(params)}');
  }

  Future<ApiResponse<Map<String, dynamic>>> userDetail(String id) =>
      _get('/admin/users/$id');

  Future<ApiResponse<Map<String, dynamic>>> banUser(String id, String reason) =>
      _post('/admin/users/$id/ban', body: {'reason': reason});

  Future<ApiResponse<Map<String, dynamic>>> unbanUser(String id) =>
      _post('/admin/users/$id/unban');

  // --- disputes --------------------------------------------------------------
  Future<ApiResponse<Map<String, dynamic>>> disputes({
    String? status,
    int page = 1,
  }) {
    final params = <String, String>{'page': '$page', 'pageSize': '50'};
    if (status != null && status.isNotEmpty) params['status'] = status;
    return _get('/admin/disputes?${_query(params)}');
  }

  Future<ApiResponse<Map<String, dynamic>>> disputeDetail(String id) =>
      _get('/admin/disputes/$id');

  Future<ApiResponse<Map<String, dynamic>>> openDispute(
    String appointmentId,
    String reason,
  ) =>
      _post('/admin/disputes',
          body: {'appointmentId': appointmentId, 'reason': reason});

  Future<ApiResponse<Map<String, dynamic>>> resolveDispute(
    String id,
    String resolution,
  ) =>
      _post('/admin/disputes/$id/resolve', body: {'resolution': resolution});

  // ---- helpers --------------------------------------------------------------

  String _query(Map<String, String> params) => params.entries
      .map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}')
      .join('&');

  Future<ApiResponse<Map<String, dynamic>>> _get(String path) async {
    final res = await _authed.send(
      (t) => _client.get(
        Uri.parse('$_baseUrl$path'),
        headers: {'Authorization': 'Bearer $t'},
      ),
    );
    return _shape(res);
  }

  Future<ApiResponse<Map<String, dynamic>>> _post(
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final res = await _authed.send(
      (t) => _client.post(
        Uri.parse('$_baseUrl$path'),
        headers: {
          'Authorization': 'Bearer $t',
          'content-type': 'application/json'
        },
        body: body == null ? null : jsonEncode(body),
      ),
    );
    return _shape(res);
  }

  ApiResponse<Map<String, dynamic>> _shape(http.Response? res) {
    if (res == null) {
      return ApiResponse.error('Session expirée ou hors ligne',
          code: 'unauthorized');
    }
    if (res.statusCode >= 200 && res.statusCode < 300) {
      final decoded =
          res.body.isEmpty ? <String, dynamic>{} : jsonDecode(res.body);
      return ApiResponse.success((decoded as Map).cast<String, dynamic>());
    }
    String? code;
    try {
      code = (jsonDecode(res.body) as Map)['error'] as String?;
    } catch (_) {
      code = null;
    }
    return ApiResponse.error(_messageFor(code), code: code);
  }

  String _messageFor(String? code) => switch (code) {
        'forbidden' => 'Action non autorisée.',
        'not_found' => 'Introuvable.',
        'invalid_input' => 'Données invalides.',
        'unauthorized' => 'Veuillez vous reconnecter.',
        _ => 'Une erreur est survenue.',
      };
}

/// Process-wide instance for the admin console entrypoint.
final AdminService adminService = AdminService();
