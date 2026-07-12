import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/config/app_config.dart';
import '../../core/utils/team_error_messages.dart';
import '../../models/api_response.dart';
import '../../models/team_invitation.dart';
import '../../models/team_member.dart';
import '../interfaces/pro_team_service_interface.dart';
import '../interfaces/session_store.dart';
import 'refreshing_http_client.dart';

/// REST impl of the salon team surface (module `access` R3, consuming the
/// R2b API) — `/me/provider/members*` + `/me/provider/invitations*` on the
/// **provider** session (silent refresh). The acting salon resolves
/// server-side from the caller; no id is ever sent.
class ApiProTeamService implements ProTeamServiceInterface {
  ApiProTeamService({
    http.Client? client,
    String? baseUrl,
    SessionStore? providerSessionStore,
  })  : _client = client ?? http.Client(),
        _baseUrl = baseUrl ?? AppConfig.apiBaseUrl,
        _providerSessionStore = providerSessionStore ?? InMemorySessionStore() {
    _authed = RefreshingHttpClient(
      client: _client,
      baseUrl: _baseUrl,
      store: _providerSessionStore,
      refreshPath: '/auth/provider/refresh',
    );
  }

  final http.Client _client;
  final String _baseUrl;
  final SessionStore _providerSessionStore;
  late final RefreshingHttpClient _authed;

  @override
  Future<ApiResponse<List<TeamMember>>> getMembers() async {
    if (await _authed.accessToken() == null) {
      return ApiResponse.error('Non connecté');
    }
    final res = await _authed.send(
      (t) => _client.get(_uri('/me/provider/members'), headers: _bearer(t)),
    );
    if (res == null) return _networkError();
    if (res.statusCode != 200) return _errorFrom(res);
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final items = (body['items'] as List? ?? const [])
        .cast<Map<String, dynamic>>()
        .map(TeamMember.fromJson)
        .toList();
    return ApiResponse.success(items);
  }

  @override
  Future<ApiResponse<TeamMember>> inviteMember({
    required String email,
    required TeamRole role,
    String? artistId,
  }) async {
    if (await _authed.accessToken() == null) {
      return ApiResponse.error('Non connecté');
    }
    final res = await _authed.send(
      (t) => _client.post(
        _uri('/me/provider/members'),
        headers: _json(t),
        body: jsonEncode({
          'email': email.trim().toLowerCase(),
          'role': role.name,
          if (artistId != null && artistId.isNotEmpty) 'artistId': artistId,
        }),
      ),
    );
    return _memberFrom(res, expected: 201);
  }

  @override
  Future<ApiResponse<TeamMember>> changeRole(
    String memberId, {
    required TeamRole role,
    String? artistId,
  }) async {
    if (await _authed.accessToken() == null) {
      return ApiResponse.error('Non connecté');
    }
    final res = await _authed.send(
      (t) => _client.patch(
        _uri('/me/provider/members/$memberId'),
        headers: _json(t),
        body: jsonEncode({
          'role': role.name,
          if (artistId != null && artistId.isNotEmpty) 'artistId': artistId,
        }),
      ),
    );
    return _memberFrom(res);
  }

  @override
  Future<ApiResponse<TeamMember>> revokeMember(String memberId) =>
      _postMember('/me/provider/members/$memberId/revoke');

  @override
  Future<ApiResponse<TeamMember>> resendInvitation(String memberId) =>
      _postMember(
        '/me/provider/members/$memberId/resend',
        resendBudgetCopy: true,
      );

  @override
  Future<ApiResponse<List<TeamInvitation>>> getMyInvitations() async {
    if (await _authed.accessToken() == null) {
      return ApiResponse.error('Non connecté');
    }
    final res = await _authed.send(
      (t) => _client.get(_uri('/me/provider/invitations'), headers: _bearer(t)),
    );
    if (res == null) return _networkError();
    if (res.statusCode != 200) return _errorFrom(res);
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final cards = (body['invitations'] as List? ?? const [])
        .cast<Map<String, dynamic>>()
        .map(TeamInvitation.fromJson)
        .toList();
    return ApiResponse.success(cards);
  }

  @override
  Future<ApiResponse<TeamMember>> acceptInvitation(String invitationId) =>
      _postMember('/me/provider/invitations/$invitationId/accept');

  @override
  Future<ApiResponse<bool>> declineInvitation(String invitationId) async {
    if (await _authed.accessToken() == null) {
      return ApiResponse.error('Non connecté');
    }
    final res = await _authed.send(
      (t) => _client.post(
        _uri('/me/provider/invitations/$invitationId/decline'),
        headers: _bearer(t),
      ),
    );
    if (res == null) return _networkError();
    if (res.statusCode != 200) return _errorFrom(res);
    return ApiResponse.success(true);
  }

  Future<ApiResponse<TeamMember>> _postMember(
    String path, {
    bool resendBudgetCopy = false,
  }) async {
    if (await _authed.accessToken() == null) {
      return ApiResponse.error('Non connecté');
    }
    final res = await _authed.send(
      (t) => _client.post(_uri(path), headers: _bearer(t)),
    );
    return _memberFrom(res, resendBudgetCopy: resendBudgetCopy);
  }

  Future<ApiResponse<TeamMember>> _memberFrom(
    http.Response? res, {
    int expected = 200,
    bool resendBudgetCopy = false,
  }) async {
    if (res == null) return _networkError();
    if (res.statusCode != expected) {
      return _errorFrom(res, resendBudgetCopy: resendBudgetCopy);
    }
    return ApiResponse.success(
      TeamMember.fromJson(jsonDecode(res.body) as Map<String, dynamic>),
    );
  }

  Uri _uri(String path) => Uri.parse('$_baseUrl$path');
  Map<String, String> _bearer(String t) => {'Authorization': 'Bearer $t'};
  Map<String, String> _json(String t) =>
      {..._bearer(t), 'Content-Type': 'application/json'};
  ApiResponse<T> _networkError<T>() =>
      ApiResponse.error('Pas de connexion. Réessayez.');

  ApiResponse<T> _errorFrom<T>(
    http.Response res, {
    bool resendBudgetCopy = false,
  }) {
    try {
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final code = body['error'] as String?;
      // The resend budget shares invite_rate_limited with the daily cap —
      // the per-invitation message reads better on the resend action.
      final message = resendBudgetCopy && code == 'invite_rate_limited'
          ? resendBudgetExhaustedMessage
          : teamErrorMessage(code);
      return ApiResponse.error(message, code: code);
    } catch (_) {
      return ApiResponse.error('Erreur');
    }
  }
}
