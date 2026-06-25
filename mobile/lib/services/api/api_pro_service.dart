import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/config/app_config.dart';
import '../../models/api_response.dart';
import '../../models/appointment.dart';
import '../../models/availability.dart';
import '../../models/payment.dart';
import '../../models/provider_session.dart';
import '../../models/service.dart';
import '../interfaces/pro_service_interface.dart';
import '../interfaces/session_store.dart';
import '../mock/mock_pro_service.dart';
import 'refreshing_http_client.dart';

/// Real HTTP implementation of [ProServiceInterface] for the slices the backend
/// supports today: the **provider appointment surface** (list + accept / reject
/// / complete / no-show) and the **catalogue** — services CRUD + enable/disable
/// and availability read/replace (design:
/// docs/design/pro-catalogue-app-wiring.md).
///
/// Authenticated calls go through [RefreshingHttpClient] pointed at the
/// **provider** session (its own secure key) and `/auth/provider/refresh`, so a
/// pro acting after the ~15-min access token expires is silently
/// re-authenticated instead of bounced to sign-in. Appointment lists are scoped
/// by the token; catalogue endpoints are `/providers/{id}/…` (the salon id is an
/// argument, or — for the serviceId-only edits — read from the session), with
/// ownership re-checked server-side.
///
/// Everything still without a backend (dashboard, gallery, earnings, deposit
/// policy, manual booking, pro-side reschedule) delegates to an embedded
/// [MockProService], so the pro app keeps working. Wired in by DI only when
/// `AppConfig.useApiBackend` is true.
class ApiProService implements ProServiceInterface {
  ApiProService({
    http.Client? client,
    String? baseUrl,
    SessionStore? providerSessionStore,
    ProServiceInterface? fallback,
  })  : _client = client ?? http.Client(),
        _baseUrl = baseUrl ?? AppConfig.apiBaseUrl,
        _providerSessionStore = providerSessionStore ?? InMemorySessionStore(),
        _fallback = fallback ?? MockProService() {
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
  final ProServiceInterface _fallback;
  late final RefreshingHttpClient _authed;

  /// The salon id this account manages, read from the persisted provider
  /// session — used for the `serviceId`-only edit/delete/active paths. Null if
  /// not signed in or the account isn't linked to a Provider.
  Future<String?> _providerId() async {
    final raw = await _providerSessionStore.read();
    if (raw == null) return null;
    try {
      return ProviderSession.fromJson(jsonDecode(raw) as Map<String, dynamic>)
          .provider
          .providerId;
    } catch (_) {
      return null;
    }
  }

  // ---- Appointments (real backend) -----------------------------------------

  @override
  Future<ApiResponse<List<Appointment>>> getProviderAppointments(
    String providerId, {
    AppointmentStatus? status,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    if (await _authed.accessToken() == null) {
      return ApiResponse.error('Non connecté');
    }
    final uri = _uri('/appointments').replace(
      queryParameters: {if (status != null) 'status': status.name},
    );
    final res = await _authed.send(
      (token) => _client.get(uri, headers: _bearer(token)),
    );
    if (res == null) return _networkError();
    if (res.statusCode != 200) return _errorFrom(res);
    var items = (_decode(res.body)['items'] as List)
        .map((e) => Appointment.fromJson(e as Map<String, dynamic>))
        .toList();
    // The backend has no date-range filter yet; honour it client-side.
    if (startDate != null) {
      items =
          items.where((a) => !a.appointmentDate.isBefore(startDate)).toList();
    }
    if (endDate != null) {
      items = items.where((a) => !a.appointmentDate.isAfter(endDate)).toList();
    }
    return ApiResponse.success(items);
  }

  @override
  Future<ApiResponse<bool>> acceptAppointment(String appointmentId) =>
      _transition(appointmentId, 'accept', 'Rendez-vous confirmé');

  @override
  Future<ApiResponse<bool>> rejectAppointment(
    String appointmentId,
    String? reason,
  ) =>
      _transition(appointmentId, 'reject', 'Rendez-vous refusé');

  @override
  Future<ApiResponse<bool>> markAppointmentComplete(String appointmentId) =>
      _transition(appointmentId, 'complete', 'Rendez-vous terminé');

  @override
  Future<ApiResponse<bool>> markNoShow(String appointmentId) =>
      _transition(appointmentId, 'no-show', 'Client absent enregistré');

  /// POSTs a pro lifecycle transition; the backend enforces provider-role +
  /// salon ownership + the state machine.
  Future<ApiResponse<bool>> _transition(
    String id,
    String action,
    String okMessage,
  ) async {
    if (await _authed.accessToken() == null) {
      return ApiResponse.error('Non connecté');
    }
    final res = await _authed.send((token) => _client.post(
          _uri('/appointments/$id/$action'),
          headers: _bearer(token),
        ));
    if (res == null) return _networkError();
    if (res.statusCode != 200) return _errorFrom(res);
    return ApiResponse.success(true, message: okMessage);
  }

  // ---- Not yet backed by an endpoint → delegate to the mock ----------------

  @override
  Future<ApiResponse<DashboardStats>> getDashboardStats(String providerId) =>
      _fallback.getDashboardStats(providerId);

  @override
  Future<ApiResponse<bool>> rescheduleAppointment(
    String appointmentId,
    DateTime newDateTime,
  ) =>
      _fallback.rescheduleAppointment(appointmentId, newDateTime);

  @override
  Future<ApiResponse<Appointment>> createManualBooking({
    required String providerId,
    required List<String> serviceIds,
    required DateTime appointmentDateTime,
    String? clientName,
    String? clientPhone,
    String? notes,
    bool sendSmsInvite = false,
  }) =>
      _fallback.createManualBooking(
        providerId: providerId,
        serviceIds: serviceIds,
        appointmentDateTime: appointmentDateTime,
        clientName: clientName,
        clientPhone: clientPhone,
        notes: notes,
        sendSmsInvite: sendSmsInvite,
      );

  @override
  Future<ApiResponse<List<Service>>> getProviderServices(
    String providerId,
  ) async {
    if (await _authed.accessToken() == null) {
      return ApiResponse.error('Non connecté');
    }
    final res = await _authed.send(
      (t) => _client.get(
        _uri('/providers/$providerId/services'),
        headers: _bearer(t),
      ),
    );
    if (res == null) return _networkError();
    if (res.statusCode != 200) return _errorFrom(res);
    final items = (_decode(res.body)['items'] as List)
        .map((e) => Service.fromJson(e as Map<String, dynamic>))
        .toList();
    return ApiResponse.success(items);
  }

  @override
  Future<ApiResponse<Service>> createService(
    String providerId,
    Map<String, dynamic> serviceData,
  ) async {
    if (await _authed.accessToken() == null) {
      return ApiResponse.error('Non connecté');
    }
    final res = await _authed.send(
      (t) => _client.post(
        _uri('/providers/$providerId/services'),
        headers: _bearer(t),
        body: jsonEncode(serviceData),
      ),
    );
    if (res == null) return _networkError();
    if (res.statusCode != 201) return _errorFrom(res);
    return ApiResponse.success(Service.fromJson(_decode(res.body)));
  }

  @override
  Future<ApiResponse<Service>> updateService(
    String serviceId,
    Map<String, dynamic> serviceData,
  ) async {
    final pid = await _providerId();
    if (pid == null) return ApiResponse.error('Compte non lié à un salon');
    final res = await _authed.send(
      (t) => _client.patch(
        _uri('/providers/$pid/services/$serviceId'),
        headers: _bearer(t),
        body: jsonEncode(serviceData),
      ),
    );
    if (res == null) return _networkError();
    if (res.statusCode != 200) return _errorFrom(res);
    return ApiResponse.success(Service.fromJson(_decode(res.body)));
  }

  @override
  Future<ApiResponse<bool>> deleteService(String serviceId) async {
    final pid = await _providerId();
    if (pid == null) return ApiResponse.error('Compte non lié à un salon');
    final res = await _authed.send(
      (t) => _client.delete(
        _uri('/providers/$pid/services/$serviceId'),
        headers: _bearer(t),
      ),
    );
    if (res == null) return _networkError();
    if (res.statusCode != 204) return _errorFrom(res);
    return ApiResponse.success(true, message: 'Service supprimé');
  }

  @override
  Future<ApiResponse<bool>> setServiceActive(
    String serviceId,
    bool active,
  ) async {
    final pid = await _providerId();
    if (pid == null) return ApiResponse.error('Compte non lié à un salon');
    final res = await _authed.send(
      (t) => _client.patch(
        _uri('/providers/$pid/services/$serviceId'),
        headers: _bearer(t),
        body: jsonEncode({'active': active}),
      ),
    );
    if (res == null) return _networkError();
    if (res.statusCode != 200) return _errorFrom(res);
    return ApiResponse.success(true);
  }

  @override
  Future<ApiResponse<List<String>>> getGalleryPhotos(String providerId) =>
      _fallback.getGalleryPhotos(providerId);

  @override
  Future<ApiResponse<List<String>>> updateGalleryPhotos(
    String providerId,
    List<String> imageUrls,
  ) =>
      _fallback.updateGalleryPhotos(providerId, imageUrls);

  @override
  Future<ApiResponse<Availability>> getProviderAvailability(
    String providerId,
  ) async {
    if (await _authed.accessToken() == null) {
      return ApiResponse.error('Non connecté');
    }
    final res = await _authed.send(
      (t) => _client.get(
        _uri('/providers/$providerId/availability'),
        headers: _bearer(t),
      ),
    );
    if (res == null) return _networkError();
    if (res.statusCode != 200) return _errorFrom(res);
    return ApiResponse.success(Availability.fromJson(_decode(res.body)));
  }

  @override
  Future<ApiResponse<Availability>> updateAvailability(
    String providerId,
    Availability availability,
  ) async {
    if (await _authed.accessToken() == null) {
      return ApiResponse.error('Non connecté');
    }
    final res = await _authed.send(
      (t) => _client.put(
        _uri('/providers/$providerId/availability'),
        headers: _bearer(t),
        body: jsonEncode(availability.toJson()),
      ),
    );
    if (res == null) return _networkError();
    if (res.statusCode != 200) return _errorFrom(res);
    return ApiResponse.success(Availability.fromJson(_decode(res.body)));
  }

  @override
  Future<ApiResponse<EarningsData>> getEarnings(
    String providerId, {
    DateTime? startDate,
    DateTime? endDate,
  }) =>
      _fallback.getEarnings(
        providerId,
        startDate: startDate,
        endDate: endDate,
      );

  @override
  Future<ApiResponse<DepositPolicy>> getDepositPolicy(String providerId) =>
      _fallback.getDepositPolicy(providerId);

  @override
  Future<ApiResponse<DepositPolicy>> updateDepositPolicy(
    String providerId, {
    required bool depositRequired,
    required double depositPercentage,
    required int cancellationWindowHours,
    MobileMoneyOperator? mobileMoneyOperator,
    String? mobileMoneyNumber,
  }) =>
      _fallback.updateDepositPolicy(
        providerId,
        depositRequired: depositRequired,
        depositPercentage: depositPercentage,
        cancellationWindowHours: cancellationWindowHours,
        mobileMoneyOperator: mobileMoneyOperator,
        mobileMoneyNumber: mobileMoneyNumber,
      );

  // ---- helpers --------------------------------------------------------------

  Uri _uri(String path) => Uri.parse('$_baseUrl$path');

  Map<String, String> _bearer(String token) => {
        'content-type': 'application/json',
        'Authorization': 'Bearer $token',
      };

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
      case 'forbidden':
        return 'Action non autorisée pour ce salon.';
      case 'not_found':
        return 'Introuvable.';
      case 'invalid_input':
        return 'Informations invalides.';
      case 'invalid_state':
        return 'Cette action n’est plus possible.';
      case 'unauthorized':
        return 'Veuillez vous reconnecter.';
      default:
        return 'Une erreur est survenue.';
    }
  }
}
