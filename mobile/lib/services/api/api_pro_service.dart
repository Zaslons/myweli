import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/config/app_config.dart';
import '../../core/utils/salon_time.dart';
import '../../models/api_response.dart';
import '../../models/appointment.dart';
import '../../models/availability.dart';
import '../../models/before_after_pair.dart';
import '../../models/journal_day.dart';
import '../../models/payment.dart';
import '../../models/pro_membership.dart';
import '../../models/provider.dart';
import '../../models/provider_session.dart';
import '../../models/provider_user.dart';
import '../../models/salon_membership_info.dart';
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

  /// The salon id this account ACTS IN, read from the persisted provider
  /// session — the R6 selection first, else the account's linked salon.
  /// Used for the `serviceId`-only edit/delete/active paths. Null if not
  /// signed in or the account isn't linked to a Provider.
  Future<String?> _providerId() async {
    final session = await _session();
    return session?.selectedSalonId ?? session?.provider.providerId;
  }

  /// R6 multi-salons: the persisted salon SELECTION (null = default). The
  /// session-resolved endpoints append it as `?salonId=`; the server
  /// revalidates the membership per request (T55).
  Future<String?> _selectedSalonId() async =>
      (await _session())?.selectedSalonId;

  Future<ProviderSession?> _session() async {
    final raw = await _providerSessionStore.read();
    if (raw == null) return null;
    try {
      return ProviderSession.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  /// Appends the R6 salon selection to a session-resolved path.
  Future<Uri> _salonScopedUri(String path) async {
    final selected = await _selectedSalonId();
    final uri = _uri(path);
    if (selected == null || selected.isEmpty) return uri;
    return uri.replace(
      queryParameters: {...uri.queryParameters, 'salonId': selected},
    );
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
    final selected = await _selectedSalonId();
    final uri = _uri('/appointments').replace(
      queryParameters: {
        if (status != null) 'status': status.name,
        // R6: the token still scopes; the selection picks WHICH salon.
        if (selected != null && selected.isNotEmpty) 'salonId': selected,
      },
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
  Future<ApiResponse<void>> deleteProviderAccount() async {
    if (await _authed.accessToken() == null) {
      return ApiResponse.error('Non connecté');
    }
    final res = await _authed.send(
      (t) => _client.delete(_uri('/me/provider'), headers: _bearer(t)),
    );
    if (res == null) return _networkError();
    if (res.statusCode != 204) return _errorFrom(res);
    return ApiResponse.success(null, message: 'Compte supprimé');
  }

  @override
  Future<ApiResponse<Provider>> updateSalonProfile(
    String providerId,
    Map<String, dynamic> changes,
  ) async {
    if (await _authed.accessToken() == null) {
      return ApiResponse.error('Non connecté');
    }
    final res = await _authed.send(
      (token) => _client.patch(
        _uri('/providers/$providerId'),
        headers: {..._bearer(token), 'Content-Type': 'application/json'},
        body: jsonEncode(changes),
      ),
    );
    if (res == null) return _networkError();
    if (res.statusCode != 200) return _errorFrom(res);
    return ApiResponse.success(
      Provider.fromJson(_decode(res.body)),
      message: 'Profil enregistré',
    );
  }

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
      // The gate's `missing` keys — `offer` (pricing pivot) gets its own
      // code so the screen can CTA to the offer picker.
      List<dynamic> missing = const [];
      try {
        missing = (jsonDecode(res.body) as Map<String, dynamic>)['missing']
                as List<dynamic>? ??
            const [];
      } catch (_) {/* keep the generic message */}
      if (missing.contains('offer')) {
        return ApiResponse.error(
          'Choisissez votre offre avant la mise en ligne.',
          code: 'offer_required',
        );
      }
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
    final day = salonDayKey(date);
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
  Future<ApiResponse<MyProviderInfo>> getMyProvider({String? salonId}) async {
    if (await _authed.accessToken() == null) {
      return ApiResponse.error('Non connecté');
    }
    // An explicit [salonId] (the switch probe) wins over the persisted
    // selection; absent both → the server default.
    final selected = salonId ?? await _selectedSalonId();
    final uri = selected == null || selected.isEmpty
        ? _uri('/me/provider')
        : _uri('/me/provider').replace(queryParameters: {'salonId': selected});
    final res = await _authed.send(
      (t) => _client.get(uri, headers: _bearer(t)),
    );
    if (res == null) return _networkError();
    if (res.statusCode != 200) return _errorFrom(res);
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final salonMap = body['provider'] as Map<String, dynamic>;
    final membership = ProMembership.fromJson({
      ...body['membership'] as Map<String, dynamic>,
      // Folded in so ONE persisted blob shapes the app offline.
      'salonId': salonMap['id'],
      'salonName': salonMap['name'],
    });
    return ApiResponse.success(
      MyProviderInfo(
        salon: Provider.fromJson(salonMap),
        membership: membership,
      ),
    );
  }

  @override
  Future<ApiResponse<MySalonsResult>> getMySalons() async {
    if (await _authed.accessToken() == null) {
      return ApiResponse.error('Non connecté');
    }
    final res = await _authed.send(
      (t) => _client.get(_uri('/me/salons'), headers: _bearer(t)),
    );
    if (res == null) return _networkError();
    if (res.statusCode != 200) return _errorFrom(res);
    return ApiResponse.success(MySalonsResult.fromJson(_decode(res.body)));
  }

  @override
  Future<ApiResponse<SalonMembershipInfo>> addSalon({
    required String businessName,
    required BusinessType businessType,
    String? phoneNumber,
    String? address,
    String? areaId,
  }) async {
    if (await _authed.accessToken() == null) {
      return ApiResponse.error('Non connecté');
    }
    final res = await _authed.send(
      (t) => _client.post(
        _uri('/me/salons'),
        headers: _bearer(t),
        body: jsonEncode({
          'businessName': businessName,
          'businessType': businessType.name,
          if (phoneNumber != null && phoneNumber.isNotEmpty)
            'phoneNumber': phoneNumber,
          if (address != null && address.isNotEmpty) 'address': address,
          if (areaId != null && areaId.isNotEmpty) 'areaId': areaId,
        }),
      ),
    );
    if (res == null) return _networkError();
    if (res.statusCode != 201) return _errorFrom(res);
    return ApiResponse.success(
      SalonMembershipInfo.fromJson(
        _decode(res.body)['salon'] as Map<String, dynamic>,
      ),
      message: 'Salon créé',
    );
  }

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
    // Role-aware on the backend: the provider token reschedules inside its
    // acting salon (R6: the selection scopes it; the lifecycle service
    // cross-checks the appointment). Deposit/balance carry over server-side.
    final rescheduleUri =
        await _salonScopedUri('/appointments/$appointmentId/reschedule');
    final res = await _authed.send((t) => _client.post(
          rescheduleUri,
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
    String? artistId,
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
          if (artistId != null) 'artistId': artistId,
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
    String? mobileMoneyOperator,
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
            'mobileMoneyOperator': mobileMoneyOperator,
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
      case 'not_a_member':
        return 'Votre accès à ce salon a été retiré.';
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
