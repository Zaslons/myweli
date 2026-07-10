import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/config/app_config.dart';
import '../../models/api_response.dart';
import '../../models/appointment.dart';
import '../../models/availability.dart';
import '../../models/before_after_pair.dart';
import '../../models/journal_day.dart';
import '../../models/payment.dart';
import '../../models/provider_session.dart';
import '../../models/service.dart';
import '../interfaces/pro_service_interface.dart';
import '../interfaces/session_store.dart';
import 'refreshing_http_client.dart';

/// Real HTTP implementation of [ProServiceInterface] for the slices the backend
/// supports today — now the **entire** `ProServiceInterface`: the **provider
/// appointment surface** (list + accept / reject / complete / no-show +
/// **manual booking** + **reschedule**), the **catalogue** (services CRUD +
/// enable/disable, availability read/replace), the **dashboard** stats, the
/// **earnings** ledger, the **gallery** URL list, and the **deposit policy**.
/// Designs: docs/design/pro-catalogue-app-wiring.md,
/// provider-dashboard-stats.md, pro-manual-booking.md, provider-earnings.md,
/// pro-reschedule.md, pro-gallery.md, pro-deposit-policy.md.
///
/// Authenticated calls go through [RefreshingHttpClient] pointed at the
/// **provider** session (its own secure key) and `/auth/provider/refresh`, so a
/// pro acting after the ~15-min access token expires is silently
/// re-authenticated instead of bounced to sign-in. Appointment lists are scoped
/// by the token; `/providers/{id}/…` endpoints take the salon id as an argument
/// (or — for the serviceId-only edits — read it from the session), with
/// ownership re-checked server-side.
///
/// Every method now hits the backend (no mock fallback). Wired in by DI only
/// when `AppConfig.useApiBackend` is true.
class ApiProService implements ProServiceInterface {
  ApiProService({
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

  @override
  Future<ApiResponse<bool>> markArrived(String appointmentId) =>
      _transition(appointmentId, 'arrive', 'Client arrivé');

  @override
  Future<ApiResponse<bool>> publishSalon(String providerId) async {
    if (await _authed.accessToken() == null) {
      return ApiResponse.error('Non connecté');
    }
    final res = await _authed.send((token) => _client.post(
          _uri('/providers/$providerId/publish'),
          headers: _bearer(token),
        ));
    if (res == null) return _networkError();
    if (res.statusCode == 409) {
      return ApiResponse.error(
        'Complétez les étapes requises avant la mise en ligne.',
        code: 'incomplete',
      );
    }
    if (res.statusCode != 200) return _errorFrom(res);
    return ApiResponse.success(true, message: 'Votre salon est en ligne');
  }

  @override
  Future<ApiResponse<JournalDay>> getJournalDay(
    String providerId,
    DateTime date,
  ) async {
    if (await _authed.accessToken() == null) {
      return ApiResponse.error('Non connecté');
    }
    final day = date.toUtc().toIso8601String().substring(0, 10);
    final res = await _authed.send(
      (token) => _client.get(
        _uri('/providers/$providerId/journal').replace(
          queryParameters: {'date': day},
        ),
        headers: _bearer(token),
      ),
    );
    if (res == null) return _networkError();
    if (res.statusCode != 200) return _errorFrom(res);
    return ApiResponse.success(JournalDay.fromJson(_decode(res.body)));
  }

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

  @override
  Future<ApiResponse<String>> depositScreenshotUrl(String appointmentId) async {
    if (await _authed.accessToken() == null) {
      return ApiResponse.error('Non connecté');
    }
    final res = await _authed.send((token) => _client.get(
          _uri('/appointments/$appointmentId/deposit-screenshot'),
          headers: _bearer(token),
        ));
    if (res == null) return _networkError();
    if (res.statusCode != 200) return _errorFrom(res);
    return ApiResponse.success(_decode(res.body)['url'] as String);
  }

  // ---- Not yet backed by an endpoint → delegate to the mock ----------------

  @override
  Future<ApiResponse<DashboardStats>> getDashboardStats(
    String providerId,
  ) async {
    if (await _authed.accessToken() == null) {
      return ApiResponse.error('Non connecté');
    }
    final res = await _authed.send(
      (t) => _client.get(
        _uri('/providers/$providerId/dashboard'),
        headers: _bearer(t),
      ),
    );
    if (res == null) return _networkError();
    if (res.statusCode != 200) return _errorFrom(res);
    return ApiResponse.success(DashboardStats.fromJson(_decode(res.body)));
  }

  @override
  Future<ApiResponse<bool>> rescheduleAppointment(
    String appointmentId,
    DateTime newDateTime,
  ) async {
    if (await _authed.accessToken() == null) {
      return ApiResponse.error('Non connecté');
    }
    // Role-aware on the backend: the provider token reschedules by salon
    // ownership. Deposit/balance carry over server-side.
    final res = await _authed.send((t) => _client.post(
          _uri('/appointments/$appointmentId/reschedule'),
          headers: _bearer(t),
          body: jsonEncode({
            'newDateTime': newDateTime.toUtc().toIso8601String(),
          }),
        ));
    if (res == null) return _networkError();
    if (res.statusCode != 200) return _errorFrom(res);
    return ApiResponse.success(true, message: 'Rendez-vous reporté');
  }

  @override
  Future<ApiResponse<Appointment>> createManualBooking({
    required String providerId,
    required List<String> serviceIds,
    required DateTime appointmentDateTime,
    String? clientName,
    String? clientPhone,
    String? notes,
    bool sendSmsInvite = false,
  }) async {
    if (await _authed.accessToken() == null) {
      return ApiResponse.error('Non connecté');
    }
    final res = await _authed.send(
      (t) => _client.post(
        _uri('/providers/$providerId/appointments'),
        headers: _bearer(t),
        body: jsonEncode({
          'serviceIds': serviceIds,
          'appointmentDateTime': appointmentDateTime.toUtc().toIso8601String(),
          if (clientName != null) 'clientName': clientName,
          if (clientPhone != null) 'clientPhone': clientPhone,
          if (notes != null) 'notes': notes,
          // Honoured by the notifications backend (deferred); ignored for now.
          'sendSmsInvite': sendSmsInvite,
        }),
      ),
    );
    if (res == null) return _networkError();
    if (res.statusCode != 201) return _errorFrom(res);
    return ApiResponse.success(Appointment.fromJson(_decode(res.body)));
  }

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
  Future<ApiResponse<List<String>>> getGalleryPhotos(String providerId) async {
    if (await _authed.accessToken() == null) {
      return ApiResponse.error('Non connecté');
    }
    final res = await _authed.send(
      (t) => _client.get(
        _uri('/providers/$providerId/gallery'),
        headers: _bearer(t),
      ),
    );
    if (res == null) return _networkError();
    if (res.statusCode != 200) return _errorFrom(res);
    return ApiResponse.success(_imageUrlsFrom(res.body));
  }

  @override
  Future<ApiResponse<List<String>>> updateGalleryPhotos(
    String providerId,
    List<String> imageUrls,
  ) async {
    if (await _authed.accessToken() == null) {
      return ApiResponse.error('Non connecté');
    }
    final res = await _authed.send((t) => _client.put(
          _uri('/providers/$providerId/gallery'),
          headers: _bearer(t),
          body: jsonEncode({'imageUrls': imageUrls}),
        ));
    if (res == null) return _networkError();
    if (res.statusCode != 200) return _errorFrom(res);
    return ApiResponse.success(
      _imageUrlsFrom(res.body),
      message: 'Galerie mise à jour',
    );
  }

  List<String> _imageUrlsFrom(String body) =>
      ((_decode(body)['imageUrls'] as List?) ?? const [])
          .map((e) => e as String)
          .toList();

  @override
  Future<ApiResponse<List<BeforeAfterPair>>> getBeforeAfters(
    String providerId,
  ) async {
    if (await _authed.accessToken() == null) {
      return ApiResponse.error('Non connecté');
    }
    final res = await _authed.send(
      (t) => _client.get(
        _uri('/providers/$providerId/before-after'),
        headers: _bearer(t),
      ),
    );
    if (res == null) return _networkError();
    if (res.statusCode != 200) return _errorFrom(res);
    return ApiResponse.success(_beforeAftersFrom(res.body));
  }

  @override
  Future<ApiResponse<List<BeforeAfterPair>>> updateBeforeAfters(
    String providerId,
    List<BeforeAfterPair> pairs,
  ) async {
    if (await _authed.accessToken() == null) {
      return ApiResponse.error('Non connecté');
    }
    final res = await _authed.send(
      (t) => _client.put(
        _uri('/providers/$providerId/before-after'),
        headers: _bearer(t),
        body: jsonEncode({
          'beforeAfters': pairs.map((p) => p.toJson()).toList(),
        }),
      ),
    );
    if (res == null) return _networkError();
    if (res.statusCode != 200) return _errorFrom(res);
    return ApiResponse.success(
      _beforeAftersFrom(res.body),
      message: 'Avant / Après mis à jour',
    );
  }

  List<BeforeAfterPair> _beforeAftersFrom(String body) =>
      ((_decode(body)['beforeAfters'] as List?) ?? const [])
          .map((e) => BeforeAfterPair.fromJson(e as Map<String, dynamic>))
          .toList();

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
  }) async {
    if (await _authed.accessToken() == null) {
      return ApiResponse.error('Non connecté');
    }
    final uri = _uri('/providers/$providerId/earnings').replace(
      queryParameters: {
        if (startDate != null) 'startDate': startDate.toUtc().toIso8601String(),
        if (endDate != null) 'endDate': endDate.toUtc().toIso8601String(),
      },
    );
    final res =
        await _authed.send((t) => _client.get(uri, headers: _bearer(t)));
    if (res == null) return _networkError();
    if (res.statusCode != 200) return _errorFrom(res);
    return ApiResponse.success(EarningsData.fromJson(_decode(res.body)));
  }

  @override
  Future<ApiResponse<DepositPolicy>> getDepositPolicy(
    String providerId,
  ) async {
    if (await _authed.accessToken() == null) {
      return ApiResponse.error('Non connecté');
    }
    final res = await _authed.send(
      (t) => _client.get(
        _uri('/providers/$providerId/deposit-policy'),
        headers: _bearer(t),
      ),
    );
    if (res == null) return _networkError();
    if (res.statusCode != 200) return _errorFrom(res);
    return ApiResponse.success(DepositPolicy.fromJson(_decode(res.body)));
  }

  @override
  Future<ApiResponse<DepositPolicy>> updateDepositPolicy(
    String providerId, {
    required bool depositRequired,
    required double depositPercentage,
    required int cancellationWindowHours,
    MobileMoneyOperator? mobileMoneyOperator,
    String? mobileMoneyNumber,
  }) async {
    if (await _authed.accessToken() == null) {
      return ApiResponse.error('Non connecté');
    }
    final res = await _authed.send((t) => _client.put(
          _uri('/providers/$providerId/deposit-policy'),
          headers: _bearer(t),
          body: jsonEncode({
            'depositRequired': depositRequired,
            'depositPercentage': depositPercentage,
            'cancellationWindowHours': cancellationWindowHours,
            'mobileMoneyOperator': mobileMoneyOperator?.apiName,
            'mobileMoneyNumber': mobileMoneyNumber,
          }),
        ));
    if (res == null) return _networkError();
    if (res.statusCode != 200) return _errorFrom(res);
    return ApiResponse.success(
      DepositPolicy.fromJson(_decode(res.body)),
      message: 'Politique d’acompte enregistrée',
    );
  }

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
