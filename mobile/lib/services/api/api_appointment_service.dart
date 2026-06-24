import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/config/app_config.dart';
import '../../models/api_response.dart';
import '../../models/appointment.dart';
import '../../models/session.dart';
import '../interfaces/appointment_service_interface.dart';
import '../interfaces/session_store.dart';

/// Real HTTP implementation of [AppointmentServiceInterface] (backend B-appt).
///
/// Authenticated calls carry the access token read from the persisted
/// [Session] (written by the auth service on login). The server is the
/// authority on price **and availability** — booking/reschedule can come back
/// `slot_unavailable`, surfaced as a clear French message. `/availability` is
/// public (browsing before sign-in). Wired in by DI when
/// `AppConfig.useApiBackend` is true; the app is otherwise on the mock.
class ApiAppointmentService implements AppointmentServiceInterface {
  ApiAppointmentService({
    http.Client? client,
    String? baseUrl,
    SessionStore? sessionStore,
  })  : _client = client ?? http.Client(),
        _baseUrl = baseUrl ?? AppConfig.apiBaseUrl,
        _sessionStore = sessionStore ?? InMemorySessionStore();

  final http.Client _client;
  final String _baseUrl;
  final SessionStore _sessionStore;

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
    final token = await _token();
    if (token == null) return ApiResponse.error('Connectez-vous pour réserver');
    // Note: depositAmount is computed server-side from the provider's policy.
    final res = await _send(() => _client.post(
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
  Future<ApiResponse<List<Appointment>>> getUserAppointments({
    AppointmentStatus? status,
  }) async {
    final token = await _token();
    if (token == null) return ApiResponse.error('Non connecté');
    final uri = _uri('/appointments').replace(
      queryParameters: {if (status != null) 'status': status.name},
    );
    final res =
        await _send(() => _client.get(uri, headers: _authHeaders(token)));
    if (res == null) return _networkError();
    if (res.statusCode != 200) return _errorFrom(res);
    final items = (_decode(res.body)['items'] as List)
        .map((e) => Appointment.fromJson(e as Map<String, dynamic>))
        .toList();
    return ApiResponse.success(items);
  }

  @override
  Future<ApiResponse<Appointment>> getAppointmentById(String id) async {
    final token = await _token();
    if (token == null) return ApiResponse.error('Non connecté');
    final res = await _send(
      () =>
          _client.get(_uri('/appointments/$id'), headers: _authHeaders(token)),
    );
    if (res == null) return _networkError();
    if (res.statusCode != 200) return _errorFrom(res);
    return ApiResponse.success(Appointment.fromJson(_decode(res.body)));
  }

  @override
  Future<ApiResponse<void>> cancelAppointment(String id) async {
    final token = await _token();
    if (token == null) return ApiResponse.error('Non connecté');
    final res = await _send(() => _client.post(
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
    final token = await _token();
    if (token == null) return ApiResponse.error('Non connecté');
    final res = await _send(() => _client.post(
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

  Future<String?> _token() async {
    final raw = await _sessionStore.read();
    if (raw == null) return null;
    try {
      return Session.fromJson(jsonDecode(raw) as Map<String, dynamic>).token;
    } catch (_) {
      return null;
    }
  }

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
