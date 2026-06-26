import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:http/http.dart' as http;

import '../../core/config/app_config.dart';
import '../../models/api_response.dart';
import '../../models/appointment.dart';
import '../../models/session.dart';
import '../interfaces/appointment_service_interface.dart';
import '../interfaces/session_store.dart';
import 'refreshing_http_client.dart';

/// Compresses [source] (a local file path) to JPEG bytes. Injected so the
/// deposit-screenshot upload is testable without the native compressor.
typedef ImageCompressor = Future<Uint8List?> Function(String source);

/// Real HTTP implementation of [AppointmentServiceInterface] (backend B-appt).
///
/// Authenticated calls go through [RefreshingHttpClient], which reads the access
/// token from the persisted [Session] (written by the auth service on login)
/// and **silently refreshes** it on a 401 — so a booking mid-session never
/// fails just because the short-lived access token expired. The server is the
/// authority on price **and availability** — booking/reschedule can come back
/// `slot_unavailable`, surfaced as a clear French message. `/availability` is
/// public (browsing before sign-in). Wired in by DI when
/// `AppConfig.useApiBackend` is true; the app is otherwise on the mock.
class ApiAppointmentService implements AppointmentServiceInterface {
  ApiAppointmentService({
    http.Client? client,
    String? baseUrl,
    SessionStore? sessionStore,
    ImageCompressor? compressor,
  })  : _client = client ?? http.Client(),
        _baseUrl = baseUrl ?? AppConfig.apiBaseUrl,
        _sessionStore = sessionStore ?? InMemorySessionStore(),
        _compress = compressor ?? _defaultCompress;

  final http.Client _client;
  final String _baseUrl;
  final SessionStore _sessionStore;
  final ImageCompressor _compress;

  static Future<Uint8List?> _defaultCompress(String source) =>
      FlutterImageCompress.compressWithFile(
        source,
        minWidth: 1600,
        minHeight: 1600,
        quality: 80,
        format: CompressFormat.jpeg,
      );

  late final RefreshingHttpClient _authed = RefreshingHttpClient(
    client: _client,
    baseUrl: _baseUrl,
    store: _sessionStore,
  );

  @override
  Future<ApiResponse<Appointment>> bookAppointment({
    required String providerId,
    required List<String> serviceIds,
    required DateTime appointmentDateTime,
    String? artistId,
    String? notes,
    double depositAmount = 0,
    String? depositScreenshotUrl,
  }) async {
    if (await _authed.accessToken() == null) {
      return ApiResponse.error('Connectez-vous pour réserver');
    }
    // Note: depositAmount is computed server-side from the provider's policy.
    final res = await _authed.send((token) => _client.post(
          _uri('/appointments'),
          headers: _authHeaders(token),
          body: jsonEncode({
            'providerId': providerId,
            'serviceIds': serviceIds,
            'appointmentDateTime':
                appointmentDateTime.toUtc().toIso8601String(),
            if (artistId != null) 'artistId': artistId,
            if (notes != null) 'notes': notes,
            if (depositScreenshotUrl != null)
              'depositScreenshotUrl': depositScreenshotUrl,
          }),
        ));
    if (res == null) return _networkError();
    if (res.statusCode != 201) return _errorFrom(res);
    return ApiResponse.success(Appointment.fromJson(_decode(res.body)));
  }

  @override
  Future<ApiResponse<String>> uploadDepositScreenshot({
    required String source,
  }) async {
    if (await _authed.accessToken() == null) {
      return ApiResponse.error('Connectez-vous pour réserver');
    }
    final Uint8List? bytes;
    try {
      bytes = await _compress(source);
    } catch (_) {
      return ApiResponse.error('Image invalide');
    }
    if (bytes == null || bytes.isEmpty) {
      return ApiResponse.error('Image invalide');
    }

    // 1. Presign a private, single-use upload to the deposit bucket.
    final signRes = await _authed.send((token) => _client.post(
          _uri('/uploads/sign'),
          headers: _authHeaders(token),
          body: jsonEncode({'contentType': 'image/jpeg', 'purpose': 'deposit'}),
        ));
    if (signRes == null) return _networkError();
    if (signRes.statusCode != 200) return _errorFrom(signRes);
    final ticket = _decode(signRes.body);

    // 2. Upload bytes straight to private storage (the presign is the auth).
    final req = http.MultipartRequest(
      'POST',
      Uri.parse(ticket['uploadUrl'] as String),
    );
    (ticket['fields'] as Map).forEach((k, v) {
      req.fields[k as String] = v as String;
    });
    req.files.add(
      http.MultipartFile.fromBytes('file', bytes, filename: 'deposit.jpg'),
    );
    final http.StreamedResponse uploaded;
    try {
      uploaded = await _client.send(req);
      await uploaded.stream.drain<void>();
    } catch (_) {
      return ApiResponse.error('Échec de l’envoi. Réessayez.');
    }
    if (uploaded.statusCode < 200 || uploaded.statusCode >= 300) {
      return ApiResponse.error('Échec de l’envoi. Réessayez.');
    }
    // Only the opaque private key is kept; bytes never went through our API.
    return ApiResponse.success(ticket['key'] as String);
  }

  @override
  Future<ApiResponse<Appointment>> submitDeposit({
    required String appointmentId,
    required String screenshotKey,
  }) async {
    if (await _authed.accessToken() == null) {
      return ApiResponse.error('Non connecté');
    }
    final res = await _authed.send((token) => _client.post(
          _uri('/appointments/$appointmentId/deposit'),
          headers: _authHeaders(token),
          body: jsonEncode({'screenshotKey': screenshotKey}),
        ));
    if (res == null) return _networkError();
    if (res.statusCode != 200) return _errorFrom(res);
    return ApiResponse.success(Appointment.fromJson(_decode(res.body)));
  }

  @override
  Future<ApiResponse<String>> depositScreenshotUrl({
    required String appointmentId,
  }) async {
    if (await _authed.accessToken() == null) {
      return ApiResponse.error('Non connecté');
    }
    final res = await _authed.send((token) => _client.get(
          _uri('/appointments/$appointmentId/deposit-screenshot'),
          headers: _authHeaders(token),
        ));
    if (res == null) return _networkError();
    if (res.statusCode != 200) return _errorFrom(res);
    return ApiResponse.success(_decode(res.body)['url'] as String);
  }

  @override
  Future<ApiResponse<List<Appointment>>> getUserAppointments({
    AppointmentStatus? status,
  }) async {
    if (await _authed.accessToken() == null) {
      return ApiResponse.error('Non connecté');
    }
    final uri = _uri('/appointments').replace(
      queryParameters: {if (status != null) 'status': status.name},
    );
    final res = await _authed
        .send((token) => _client.get(uri, headers: _authHeaders(token)));
    if (res == null) return _networkError();
    if (res.statusCode != 200) return _errorFrom(res);
    final items = (_decode(res.body)['items'] as List)
        .map((e) => Appointment.fromJson(e as Map<String, dynamic>))
        .toList();
    return ApiResponse.success(items);
  }

  @override
  Future<ApiResponse<Appointment>> getAppointmentById(String id) async {
    if (await _authed.accessToken() == null) {
      return ApiResponse.error('Non connecté');
    }
    final res = await _authed.send(
      (token) =>
          _client.get(_uri('/appointments/$id'), headers: _authHeaders(token)),
    );
    if (res == null) return _networkError();
    if (res.statusCode != 200) return _errorFrom(res);
    return ApiResponse.success(Appointment.fromJson(_decode(res.body)));
  }

  @override
  Future<ApiResponse<void>> cancelAppointment(String id) async {
    if (await _authed.accessToken() == null) {
      return ApiResponse.error('Non connecté');
    }
    final res = await _authed.send((token) => _client.post(
          _uri('/appointments/$id/cancel'),
          headers: _authHeaders(token),
        ));
    if (res == null) return _networkError();
    if (res.statusCode != 200) return _errorFrom(res);
    return ApiResponse.success(null, message: 'Rendez-vous annulé');
  }

  @override
  Future<ApiResponse<Appointment>> rescheduleAppointment({
    required String id,
    required DateTime newDateTime,
  }) async {
    if (await _authed.accessToken() == null) {
      return ApiResponse.error('Non connecté');
    }
    final res = await _authed.send((token) => _client.post(
          _uri('/appointments/$id/reschedule'),
          headers: _authHeaders(token),
          body: jsonEncode({
            'newDateTime': newDateTime.toUtc().toIso8601String(),
          }),
        ));
    if (res == null) return _networkError();
    if (res.statusCode != 200) return _errorFrom(res);
    return ApiResponse.success(Appointment.fromJson(_decode(res.body)));
  }

  @override
  Future<ApiResponse<List<DateTime>>> getAvailableTimeSlots({
    required String providerId,
    required DateTime date,
    List<String>? serviceIds,
    String? artistId,
    int? durationMinutes,
  }) async {
    final dateStr = '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
    final uri = _uri('/availability').replace(
      queryParameters: {
        'providerId': providerId,
        'date': dateStr,
        if (serviceIds != null && serviceIds.isNotEmpty)
          'serviceIds': serviceIds.join(','),
        if (durationMinutes != null) 'durationMinutes': '$durationMinutes',
      },
    );
    final res = await _send(() => _client.get(uri)); // public
    if (res == null) return _networkError();
    if (res.statusCode != 200) return _errorFrom(res);
    final slots = (_decode(res.body)['slots'] as List)
        .map((s) => DateTime.parse(s as String))
        .toList();
    return ApiResponse.success(slots);
  }

  // ---- helpers --------------------------------------------------------------

  Uri _uri(String path) => Uri.parse('$_baseUrl$path');

  Map<String, String> _authHeaders(String token) => {
        'content-type': 'application/json',
        'Authorization': 'Bearer $token',
      };

  Future<http.Response?> _send(Future<http.Response> Function() run) async {
    try {
      return await run();
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic> _decode(String body) =>
      jsonDecode(body) as Map<String, dynamic>;

  ApiResponse<T> _networkError<T>() =>
      ApiResponse.error('Connexion au serveur impossible');

  ApiResponse<T> _errorFrom<T>(http.Response res) {
    String? code;
    try {
      code = _decode(res.body)['error'] as String?;
    } catch (_) {
      code = null;
    }
    return ApiResponse.error(_messageFor(code), code: code);
  }

  String _messageFor(String? code) {
    switch (code) {
      case 'slot_unavailable':
        return 'Ce créneau n’est plus disponible. Choisissez un autre horaire.';
      case 'not_found':
        return 'Rendez-vous introuvable.';
      case 'forbidden':
        return 'Action non autorisée.';
      case 'invalid_state':
        return 'Cette action n’est plus possible.';
      case 'unauthorized':
        return 'Veuillez vous reconnecter.';
      case 'invalid_input':
        return 'Informations de réservation invalides.';
      default:
        return 'Une erreur est survenue.';
    }
  }
}
