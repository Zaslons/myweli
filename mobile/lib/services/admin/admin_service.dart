import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/config/app_config.dart';
import '../../core/constants/failure_messages.dart';
import '../../core/utils/salon_id.dart';
import '../../core/utils/validation_labels.dart';
import '../../models/admin_salon_validation.dart';
import '../../models/api_response.dart';
import '../../models/salon_validation.dart';
import '../../services/secure_session_store.dart';
import '../api/refreshing_http_client.dart';
import '../interfaces/session_store.dart';
import 'admin_response.dart';

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
      // The one sentence for « nothing answered »
      // (docs/design/app-failure-messages.md §8).
      return ApiResponse.error(kNoConnectionMessage, code: 'network');
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
    // **Without this arm the fall-through below tells an admin their password
    // is wrong during a database incident** — the most confusing possible
    // message at the worst possible moment, and the reason the server answers
    // with a distinct code rather than reusing 429.
    if (res.statusCode == 503) {
      return ApiResponse.error(
        'Service momentanément indisponible. Réessayez dans un instant.',
        code: 'throttle_unavailable',
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
  ) => _post('/admin/kyc/$accountId/reject', body: {'reason': reason});

  // --- review moderation -----------------------------------------------------
  Future<ApiResponse<Map<String, dynamic>>> reportedReviews({int page = 1}) =>
      _get('/admin/reviews/reports?page=$page&pageSize=50');

  Future<ApiResponse<Map<String, dynamic>>> hiddenReviews({int page = 1}) =>
      _get('/admin/reviews/hidden?page=$page&pageSize=50');

  Future<ApiResponse<Map<String, dynamic>>> hideReview(
    String reviewId,
    String reason,
  ) => _post('/admin/reviews/$reviewId/hide', body: {'reason': reason});

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

  Future<ApiResponse<Map<String, dynamic>>> providerDetail(SalonId id) =>
      _get('/admin/providers/$id');

  Future<ApiResponse<Map<String, dynamic>>> suspendProvider(
    SalonId id,
    String reason,
  ) => _post('/admin/providers/$id/suspend', body: {'reason': reason});

  /// « Lever la suspension » — two servers answer it (§9.2, the console goes
  /// live first): the older one with the whole salon, written `active`; B0.18
  /// with `{ status, reason }`, or 409 `not_suspended`. [RestoreOutcome] reads
  /// both, and only its `status` belongs in a row (never the `reason` key).
  ///
  /// The route exists on both servers, so a 404 here is never « a server
  /// from before B0.18 »: a JSON `not_found` is an unknown salon, anything
  /// else the generic sentence.
  Future<AdminResponse<RestoreOutcome>> restoreProvider(SalonId id) async =>
      _typed(
        await _rawPost('/admin/providers/$id/restore'),
        RestoreOutcome.fromJson,
        routeMayBeMissing: false,
      );

  Future<ApiResponse<Map<String, dynamic>>> featureProvider(
    SalonId id,
    bool featured,
  ) => _post('/admin/providers/$id/feature', body: {'featured': featured});

  /// Manual billing (T54): record a payment of [months] months.
  Future<ApiResponse<Map<String, dynamic>>> markSubscriptionPaid(
    SalonId id,
    int months,
  ) =>
      _post('/admin/providers/$id/subscription/paid', body: {'months': months});

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
  ) => _post(
    '/admin/disputes',
    body: {'appointmentId': appointmentId, 'reason': reason},
  );

  Future<ApiResponse<Map<String, dynamic>>> resolveDispute(
    String id,
    String resolution,
  ) => _post('/admin/disputes/$id/resolve', body: {'resolution': resolution});

  // --- audit log -------------------------------------------------------------
  Future<ApiResponse<Map<String, dynamic>>> audit({
    String? action,
    int page = 1,
  }) {
    final params = <String, String>{'page': '$page', 'pageSize': '50'};
    if (action != null && action.isNotEmpty) params['action'] = action;
    return _get('/admin/audit?${_query(params)}');
  }

  // --- salon validation (B0.18, docs/design/salon-go-live-approval.md §4) ----
  //
  // **The console goes live before the backend (§9.2).** On a server from
  // before B0.18 these routes do not exist: each call then answers
  // [kRouteMissingCode], a typed outcome the screens turn into a calm state
  // (the queue) or no badge (the count) — never an error.

  /// One tab of « Salons à valider », [pageSize] per page. `pending` is the
  /// oldest request first and leaves suspended salons out.
  ///
  /// The queue route never answers 404 itself, so ANY 404 here is a missing
  /// route — whatever its body.
  Future<AdminResponse<SalonValidationPage>> salonValidationQueue({
    required SalonValidationState state,
    int page = 1,
    int pageSize = 50,
  }) async {
    assert(state != SalonValidationState.unknown, 'not a tab');
    final params = {
      'state': state.wire,
      'page': '$page',
      'pageSize': '$pageSize',
    };
    return _typed(
      await _rawGet('/admin/salon-validations?${_query(params)}'),
      SalonValidationPage.fromJson,
      anyNotFoundIsRouteMissing: true,
    );
  }

  /// The sidebar's count: the « En attente » tab's `total`, read with one row
  /// (§4.1) — the same number as the overview's `providers.pendingValidation`.
  Future<AdminResponse<int>> pendingSalonValidationCount() async => _typed(
    await _rawGet('/admin/salon-validations?state=pending&pageSize=1'),
    (json) => (json['total'] as num).toInt(),
    anyNotFoundIsRouteMissing: true,
  );

  /// The request's detail: the salon, its offer, the owner, the validation
  /// and its history. A JSON 404 `not_found` is an unknown salon; any other
  /// 404 is a missing route.
  ///
  /// The id comes from a link anyone can craft (the admin e-mail's
  /// `#/admin/salon-validations/{id}`), so it travels as ONE encoded path
  /// segment: a `../` in it never reaches another route.
  Future<AdminResponse<SalonValidationDetail>> salonValidationDetail(
    SalonId id,
  ) async => _typed(
    await _rawGet('/admin/salons/${_segment(id)}/validation'),
    SalonValidationDetail.fromJson,
  );

  /// « Valider la mise en ligne » — [from] is the state the screen READ
  /// (`pending`, `refused`, or `approved` for « Validation à terminer »);
  /// the server's compare-and-set refuses any other (§3.2).
  ///
  /// **A 409 can come after the decision was written** (the going-live
  /// failed): the caller re-reads the detail, the queue and the count.
  Future<AdminResponse<SalonApproval>> approveSalonValidation(
    SalonId id, {
    required SalonValidationState from,
  }) async {
    assert(from != SalonValidationState.unknown, 'not a state to send');
    return _typed(
      await _rawPost(
        '/admin/salons/${_segment(id)}/validation/approve',
        body: {'from': from.wire},
      ),
      SalonApproval.fromJson,
    );
  }

  /// « Refuser » — a code from §4.3's list and, for `other`, a note. The note
  /// is sent trimmed and left out when empty; the server trims and counts it
  /// again (≤ 500 code points) and stays the authority.
  Future<AdminResponse<SalonValidation>> refuseSalonValidation(
    SalonId id, {
    required String code,
    String? note,
  }) async {
    final trimmed = note?.trim() ?? '';
    return _typed(
      await _rawPost(
        '/admin/salons/${_segment(id)}/validation/refuse',
        body: {'code': code, if (trimmed.isNotEmpty) 'note': trimmed},
      ),
      (json) => SalonValidation.fromJson(
        (json['validation'] as Map).cast<String, dynamic>(),
      ),
    );
  }

  // ---- helpers --------------------------------------------------------------

  /// A salon id as one path segment.
  static String _segment(SalonId id) => Uri.encodeComponent(id);

  String _query(Map<String, String> params) => params.entries
      .map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}')
      .join('&');

  Future<ApiResponse<Map<String, dynamic>>> _get(String path) async =>
      _shape(await _rawGet(path));

  Future<http.Response?> _rawGet(String path) => _authed.send(
    (t) => _client.get(
      Uri.parse('$_baseUrl$path'),
      headers: {'Authorization': 'Bearer $t'},
    ),
  );

  // --- client version floors (docs/design/client-version-gate.md §14) -------

  Future<ApiResponse<Map<String, dynamic>>> clientVersionFloors() =>
      _get('/admin/client-version');

  Future<ApiResponse<Map<String, dynamic>>> setClientVersionFloor({
    required String appId,
    required String platform,
    required int minimumBuild,
    required int recommendedBuild,
    required String? updateUrl,
  }) => _put(
    '/admin/client-version',
    body: {
      'appId': appId,
      'platform': platform,
      'minimumBuild': minimumBuild,
      'recommendedBuild': recommendedBuild,
      'updateUrl': updateUrl,
    },
  );

  Future<ApiResponse<Map<String, dynamic>>> _put(
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final res = await _authed.send(
      (t) => _client.put(
        Uri.parse('$_baseUrl$path'),
        headers: {
          'Authorization': 'Bearer $t',
          'content-type': 'application/json',
        },
        body: body == null ? null : jsonEncode(body),
      ),
    );
    return _shape(res);
  }

  Future<ApiResponse<Map<String, dynamic>>> _post(
    String path, {
    Map<String, dynamic>? body,
  }) async => _shape(await _rawPost(path, body: body));

  Future<http.Response?> _rawPost(String path, {Map<String, dynamic>? body}) =>
      _authed.send(
        (t) => _client.post(
          Uri.parse('$_baseUrl$path'),
          headers: {
            'Authorization': 'Bearer $t',
            'content-type': 'application/json',
          },
          body: body == null ? null : jsonEncode(body),
        ),
      );

  ApiResponse<Map<String, dynamic>> _shape(http.Response? res) {
    if (res == null) {
      return ApiResponse.error(
        'Session expirée ou hors ligne',
        code: 'unauthorized',
      );
    }
    if (res.statusCode >= 200 && res.statusCode < 300) {
      final decoded = res.body.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(res.body);
      return ApiResponse.success((decoded as Map).cast<String, dynamic>());
    }
    String? code;
    try {
      code = (jsonDecode(res.body) as Map)['error'] as String?;
    } catch (_) {
      code = null;
    }
    return ApiResponse.error(sentenceFor(code), code: code);
  }

  /// [_shape] for the typed calls: the body parsed into a model, and an error
  /// body's `missing` kept. Every non-2xx keeps its server code and sentence,
  /// except, on a route B0.18 added ([routeMayBeMissing]), a 404 that is
  /// not the server's JSON `not_found` — or any 404, for a route that never
  /// answers one ([anyNotFoundIsRouteMissing]) — which is
  /// [kRouteMissingCode]: a server from before B0.18 (dart_frog's plain-text
  /// `Route not found`). Every caller is a salon route (B0.18), so a code is
  /// worded by [salonSentenceFor].
  AdminResponse<T> _typed<T>(
    http.Response? res,
    T Function(Map<String, dynamic> json) parse, {
    bool routeMayBeMissing = true,
    bool anyNotFoundIsRouteMissing = false,
  }) {
    if (res == null) {
      return AdminResponse.failure(
        'Session expirée ou hors ligne',
        code: 'unauthorized',
      );
    }
    final body = _jsonObject(res.body);
    if (res.statusCode >= 200 && res.statusCode < 300) {
      try {
        return AdminResponse.ok(parse(body ?? const <String, dynamic>{}));
      } catch (_) {
        // A 2xx this build cannot read: not the operator's error to fix,
        // and never a half-parsed model on screen.
        return AdminResponse.failure(sentenceFor(null), code: 'bad_response');
      }
    }
    final error = body?['error'];
    final code = error is String ? error : null;
    if (routeMayBeMissing &&
        res.statusCode == 404 &&
        (anyNotFoundIsRouteMissing || code != 'not_found')) {
      return AdminResponse.failure(
        sentenceFor(kRouteMissingCode),
        code: kRouteMissingCode,
      );
    }
    if (code == 'incomplete') {
      final raw = body?['missing'];
      final missing = [
        if (raw is List)
          for (final k in raw)
            if (k is String) k,
      ];
      return AdminResponse.failure(
        incompleteSentence(missing),
        code: code,
        missing: missing,
      );
    }
    return AdminResponse.failure(salonSentenceFor(code), code: code);
  }

  static Map<String, dynamic>? _jsonObject(String body) {
    try {
      final decoded = jsonDecode(body);
      return decoded is Map ? decoded.cast<String, dynamic>() : null;
    } catch (_) {
      return null; // `Route not found`, an HTML error page, an empty body
    }
  }

  /// A 409 `incomplete`, worded (§4.3): the gate's steps, then — when the
  /// offer is among them — the offer's own sentence. « Le salon n’est plus
  /// complet : photos, horaires. »
  static String incompleteSentence(List<String> missing) {
    final steps = [
      for (final k in missing)
        if (k != 'offer') ValidationLabels.missingStep(k),
    ];
    final parts = [
      if (steps.isNotEmpty)
        'Le salon n’est plus complet : ${steps.join(', ')}.',
      if (missing.contains('offer'))
        'L’offre du salon n’est plus active : marquez-la payée, puis validez.',
    ];
    return parts.isEmpty ? 'Le salon n’est plus complet.' : parts.join(' ');
  }

  /// Server codes → French. **A code with no case here renders « Une erreur est
  /// survenue. »**, which tells the operator nothing they can act on — so every
  /// code an endpoint can emit belongs in this list, and the version-floor ones
  /// were added with the endpoint rather than after someone hit one.
  static String sentenceFor(String? code) => switch (code) {
    'forbidden' => 'Action non autorisée.',
    // Version floors. The four that name a field are ALSO attached to that
    // field by the screen (SYSTEM.md §830 — errors belong to fields, not
    // toasts); these strings are the fallback for anywhere that cannot.
    'invalid_app' => 'Application inconnue.',
    'invalid_platform' => 'Plateforme inconnue.',
    'invalid_minimum_build' => 'Build minimum invalide (0 à 1 000 000).',
    'invalid_recommended_build' => 'Build recommandé invalide (0 à 1 000 000).',
    'recommended_below_minimum' =>
      'Le build recommandé doit être supérieur ou égal au minimum.',
    'invalid_update_url' => 'Lien de mise à jour invalide.',
    'invalid_body' => 'Données invalides.',
    'not_found' => 'Introuvable.',
    // Neutral on purpose: this map serves every admin endpoint. The KYC
    // screen words its own case (AdminKycProvider).
    'invalid_state' => 'Cette action n’est plus possible.',
    'invalid_input' => 'Données invalides.',
    'unauthorized' => 'Veuillez vous reconnecter.',
    // Salon validation (B0.18 §3.8, §4.3) — the four the spec words, verbatim;
    // `incomplete` is worded with its `missing` by [incompleteSentence].
    'validation_not_pending' => 'Cette demande a déjà été traitée.',
    'provider_suspended' => 'Salon suspendu : levez d’abord la suspension.',
    'incomplete' => 'Le salon n’est plus complet.',
    'no_owner' =>
      'Ce salon n’a pas de propriétaire actif : il ne peut pas être mis '
          'en ligne.',
    // `invalid_state` keeps the shared, neutral case above; the salon
    // routes word it for the salon in [salonSentenceFor].
    'not_suspended' => 'Ce salon n’est pas suspendu.',
    'note_required' => 'Une note est obligatoire pour le motif « Autre ».',
    'note_too_long' => 'La note dépasse 500 caractères.',
    // Only the owner's publish answers it; worded here for completeness.
    'validation_refused_final' =>
      'Ce refus est définitif : le salon ne peut pas renvoyer sa demande.',
    kRouteMissingCode =>
      'Le serveur ne gère pas encore la validation des salons.',
    _ => 'Une erreur est survenue.',
  };

  /// [sentenceFor] on the salon routes (restore and validation, B0.18 §4.3):
  /// there `invalid_state` can only mean the salon's state moved under the
  /// decision (it left `draft` before the going-live), so it is worded for
  /// the salon. The shared map keeps it neutral, since it serves every admin
  /// endpoint, the KYC decisions included (admin-kyc-queue-submitted.md
  /// §4.5).
  static String salonSentenceFor(String? code) => switch (code) {
    'invalid_state' =>
      'L’état du salon a changé entre-temps. Rechargez la page, puis '
          'réessayez.',
    _ => sentenceFor(code),
  };
}

/// Process-wide instance for the admin console entrypoint.
final AdminService adminService = AdminService();
