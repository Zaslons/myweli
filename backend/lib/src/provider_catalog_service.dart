import 'access/capabilities.dart';
import 'access/membership_service.dart';
import 'auth/provider_auth_repository.dart';
import 'localities/localities_repository.dart';
import 'localities/localities_service.dart';
import 'providers_repository.dart';
import 'validators.dart';

/// Outcome of a catalogue operation. [data] is the affected resource (a service,
/// a service list, or an availability map) on success.
typedef CatalogResult = ({bool ok, String? error, Object? data});

/// Pro-side management of a salon's **services** and **availability**
/// (docs/design/provider-services-availability-backend.md). A provider edits
/// only the Provider its account is linked to: the access token's `sub`
/// resolves to a provider account whose `providerId` must match the path
/// (→ `forbidden` otherwise). The server validates every input and is the
/// authority on ids; the provider is the price authority for its own salon.
class ProviderCatalogService {
  ProviderCatalogService(
    this._providers,
    this._providerAuth,
    this._members, {
    List<String> allowedImageOrigins = const [],
    LocalitiesService? localities,
  }) : _allowedImageOrigins = allowedImageOrigins,
       _localities = localities;

  final ProvidersRepository _providers;
  final ProviderAuthRepository _providerAuth;
  final MembershipService _members;

  /// Multi-pays MP1: locality resolution for `areaId` profile writes + the
  /// per-country deposit-operator catalog. Nullable only for legacy unit
  /// tests (falls back to the seed-list matcher / the Wave-0 operator set).
  final LocalitiesService? _localities;

  /// Gallery URL origins accepted on write. Empty → accept any (dev). When set
  /// (prod), each gallery URL must start with one of these (anti-SSRF/hotlink).
  final List<String> _allowedImageOrigins;

  Future<CatalogResult> listServices(
    String accountId,
    String providerId,
  ) async {
    if (!await _can(accountId, providerId, Cap.catalogueManage)) {
      return _forbidden;
    }
    final provider = await _providers.byId(providerId);
    if (provider == null) return _notFound;
    return (
      ok: true,
      error: null,
      data: provider['services'] ?? const <Map<String, dynamic>>[],
    );
  }

  Future<CatalogResult> createService(
    String accountId,
    String providerId,
    Map<String, dynamic> body,
  ) async {
    if (!await _can(accountId, providerId, Cap.catalogueManage)) {
      return _forbidden;
    }
    final error = _validateService(body, partial: false);
    if (error != null) return (ok: false, error: error, data: null);

    final service = {
      'id': _newId('service'),
      'name': (body['name'] as String).trim(),
      'description': (body['description'] as String?)?.trim() ?? '',
      'price': (body['price'] as num).toDouble(),
      'priceMax': (body['priceMax'] as num?)?.toDouble(),
      'durationMinutes': (body['durationMinutes'] as num).toInt(),
      'durationVariants': body['durationVariants'] ?? const <String, dynamic>{},
      'providerId': providerId,
      'artistIds': body['artistIds'] ?? const <String>[],
      'active': body['active'] as bool? ?? true,
    };
    final created = await _providers.addService(providerId, service);
    if (created == null) return _notFound;
    return (ok: true, error: null, data: created);
  }

  Future<CatalogResult> updateService(
    String accountId,
    String providerId,
    String serviceId,
    Map<String, dynamic> body,
  ) async {
    if (!await _can(accountId, providerId, Cap.catalogueManage)) {
      return _forbidden;
    }
    final error = _validateService(body, partial: true);
    if (error != null) return (ok: false, error: error, data: null);

    const editable = [
      'name',
      'description',
      'price',
      'priceMax',
      'durationMinutes',
      'durationVariants',
      'artistIds',
      'active',
    ];
    final changes = {
      for (final k in editable)
        if (body.containsKey(k)) k: body[k],
    };
    final updated = await _providers.updateService(
      providerId,
      serviceId,
      changes,
    );
    if (updated == null) return _notFound;
    return (ok: true, error: null, data: updated);
  }

  Future<CatalogResult> deleteService(
    String accountId,
    String providerId,
    String serviceId,
  ) async {
    if (!await _can(accountId, providerId, Cap.catalogueManage)) {
      return _forbidden;
    }
    final removed = await _providers.deleteService(providerId, serviceId);
    return removed ? (ok: true, error: null, data: null) : _notFound;
  }

  /// Update the salon's editable public profile (name/description/address/
  /// city/commune/phoneNumber/whatsapp). Protected fields (slug, rating,
  /// status, services, …) are ignored — they have their own endpoints.
  Future<CatalogResult> updateProfile(
    String accountId,
    String providerId,
    Map<String, dynamic> body,
  ) async {
    if (!await _can(accountId, providerId, Cap.profileManage)) {
      return _forbidden;
    }
    final error = _validateProfile(body);
    if (error != null) return (ok: false, error: error, data: null);

    const editable = [
      'name',
      'description',
      'address',
      'city',
      'commune',
      'phoneNumber',
      'whatsapp',
      // The map pin + listing category (docs/design/pro-salon-lifecycle.md
      // L1 — salons place themselves on the discovery map).
      'latitude',
      'longitude',
      'category',
    ];
    final changes = {
      for (final k in editable)
        if (body.containsKey(k))
          k: body[k] is String ? (body[k] as String).trim() : body[k],
    };

    // Multi-pays MP1 (threat T57): an explicit `areaId` pick is validated
    // against the locality tree and the market facts (commune/city/timezone/
    // currency) DERIVE from it — overriding any client-sent display names; a
    // legacy commune display name without areaId self-heals on slug match.
    // Direct client writes of timezone/currency/countryCode/citySlug/areaId
    // are never in the editable list.
    final areaIdRaw = body['areaId'];
    if (body.containsKey('areaId')) {
      if (areaIdRaw is! String || areaIdRaw.trim().isEmpty) {
        return (ok: false, error: 'invalid_area', data: null);
      }
      final market = _localities != null
          ? await _localities.resolveArea(areaIdRaw.trim())
          : null;
      final changesForArea =
          market?.providerChanges ?? _seedMarketForAreaId(areaIdRaw.trim());
      if (changesForArea == null) {
        return (ok: false, error: 'invalid_area', data: null);
      }
      changes.addAll(changesForArea);
    } else if (changes['commune'] is String) {
      final area = seedAreaForCommuneName(changes['commune'] as String);
      if (area != null) changes.addAll(marketChangesForArea(area));
    }

    if (changes.isEmpty) {
      return (ok: false, error: 'invalid_input', data: null);
    }
    final updated = await _providers.updateProfile(providerId, changes);
    if (updated == null) return _notFound;
    return (ok: true, error: null, data: updated);
  }

  /// Seed-list fallback for legacy test wiring without a LocalitiesService.
  Map<String, dynamic>? _seedMarketForAreaId(String areaId) {
    for (final a in seedAreas) {
      if (a.id == areaId) return marketChangesForArea(a);
    }
    return null;
  }

  String? _validateProfile(Map<String, dynamic> body) {
    if (body.containsKey('name')) {
      final n = body['name'];
      if (n is! String || n.trim().isEmpty) return 'invalid_input';
    }
    for (final k in ['description', 'address', 'city', 'commune']) {
      final v = body[k];
      if (body.containsKey(k) && v != null && v is! String) {
        return 'invalid_input';
      }
    }
    if (body.containsKey('phoneNumber')) {
      final p = body['phoneNumber'];
      if (p is! String || !isValidE164(p.trim())) return 'invalid_input';
    }
    final wa = body['whatsapp'];
    if (body.containsKey('whatsapp') && wa != null) {
      if (wa is! String) return 'invalid_input';
      if (wa.trim().isNotEmpty && !isValidE164(wa.trim())) {
        return 'invalid_input';
      }
    }
    // The map pin comes as a PAIR of sane coordinates (L1).
    final hasLat = body.containsKey('latitude');
    final hasLng = body.containsKey('longitude');
    if (hasLat != hasLng) return 'invalid_input';
    if (hasLat) {
      final lat = body['latitude'];
      final lng = body['longitude'];
      if (lat is! num || lng is! num) return 'invalid_input';
      if (lat < -90 || lat > 90 || lng < -180 || lng > 180) {
        return 'invalid_input';
      }
    }
    if (body.containsKey('category')) {
      const categories = {'salon', 'barber', 'spa', 'nails', 'massage'};
      if (!categories.contains(body['category'])) return 'invalid_input';
    }
    return null;
  }

  Future<CatalogResult> getAvailability(
    String accountId,
    String providerId,
  ) async {
    if (!await _can(accountId, providerId, Cap.availabilityManage)) {
      return _forbidden;
    }
    final provider = await _providers.byId(providerId);
    if (provider == null) return _notFound;
    return (ok: true, error: null, data: provider['availability']);
  }

  Future<CatalogResult> replaceAvailability(
    String accountId,
    String providerId,
    Map<String, dynamic> body,
  ) async {
    if (!await _can(accountId, providerId, Cap.availabilityManage)) {
      return _forbidden;
    }
    final error = _validateAvailability(body);
    if (error != null) return (ok: false, error: error, data: null);

    final availability = {
      'providerId': providerId,
      'weeklySchedule': body['weeklySchedule'] ?? const <String, dynamic>{},
      'breaks': body['breaks'] ?? const <String, dynamic>{},
      'blockedDates': body['blockedDates'] ?? const <String>[],
      'bufferMinutes': (body['bufferMinutes'] as num?)?.toInt() ?? 0,
    };
    final saved = await _providers.replaceAvailability(
      providerId,
      availability,
    );
    if (saved == null) return _notFound;
    return (ok: true, error: null, data: saved);
  }

  /// The salon's gallery (`imageUrls`). Design: docs/design/pro-gallery.md.
  Future<CatalogResult> gallery(String accountId, String providerId) async {
    if (!await _can(accountId, providerId, Cap.catalogueManage)) {
      return _forbidden;
    }
    final provider = await _providers.byId(providerId);
    if (provider == null) return _notFound;
    return (
      ok: true,
      error: null,
      data: {'imageUrls': provider['imageUrls'] ?? const <String>[]},
    );
  }

  /// Replace the gallery wholesale with a validated, bounded list of URLs (the
  /// byte upload happens out of band via the image pipeline; see the spec).
  Future<CatalogResult> updateGallery(
    String accountId,
    String providerId,
    Map<String, dynamic> body,
  ) async {
    if (!await _can(accountId, providerId, Cap.catalogueManage)) {
      return _forbidden;
    }
    final raw = body['imageUrls'];
    if (raw is! List) return (ok: false, error: 'invalid_input', data: null);
    if (raw.length > _maxGalleryPhotos) {
      return (ok: false, error: 'invalid_input', data: null);
    }
    final urls = <String>[];
    for (final e in raw) {
      if (e is! String) return (ok: false, error: 'invalid_input', data: null);
      final url = e.trim();
      if (url.isEmpty || url.length > _maxUrlLength) {
        return (ok: false, error: 'invalid_input', data: null);
      }
      if (_allowedImageOrigins.isNotEmpty &&
          !_allowedImageOrigins.any(url.startsWith)) {
        return (ok: false, error: 'invalid_input', data: null);
      }
      urls.add(url);
    }
    final saved = await _providers.updateGallery(providerId, urls);
    if (saved == null) return _notFound;
    return (ok: true, error: null, data: {'imageUrls': saved});
  }

  static const _maxGalleryPhotos = 20;
  static const _maxUrlLength = 2048;

  // ---- before/after showcase — design: docs/design/provider-before-after.md --
  static const _maxBeforeAfterPairs = 12;
  static const _maxCaptionLength = 120;

  /// The salon's before/after pairs (`beforeAfters`).
  Future<CatalogResult> beforeAfters(
    String accountId,
    String providerId,
  ) async {
    if (!await _can(accountId, providerId, Cap.catalogueManage)) {
      return _forbidden;
    }
    final provider = await _providers.byId(providerId);
    if (provider == null) return _notFound;
    return (
      ok: true,
      error: null,
      data: {
        'beforeAfters':
            provider['beforeAfters'] ?? const <Map<String, dynamic>>[],
      },
    );
  }

  /// Replace the before/after pairs wholesale with a validated, bounded list
  /// (bytes are uploaded out of band via the image pipeline, like the gallery).
  Future<CatalogResult> updateBeforeAfters(
    String accountId,
    String providerId,
    Map<String, dynamic> body,
  ) async {
    if (!await _can(accountId, providerId, Cap.catalogueManage)) {
      return _forbidden;
    }
    final raw = body['beforeAfters'];
    if (raw is! List || raw.length > _maxBeforeAfterPairs) {
      return (ok: false, error: 'invalid_input', data: null);
    }
    final pairs = <Map<String, dynamic>>[];
    for (final e in raw) {
      if (e is! Map) return (ok: false, error: 'invalid_input', data: null);
      final before = _validUrl(e['before']);
      final after = _validUrl(e['after']);
      if (before == null || after == null) {
        return (ok: false, error: 'invalid_input', data: null);
      }
      final captionRaw = e['caption'];
      if (captionRaw != null && captionRaw is! String) {
        return (ok: false, error: 'invalid_input', data: null);
      }
      final caption = (captionRaw as String?)?.trim() ?? '';
      if (caption.length > _maxCaptionLength) {
        return (ok: false, error: 'invalid_input', data: null);
      }
      pairs.add({
        'before': before,
        'after': after,
        if (caption.isNotEmpty) 'caption': caption,
      });
    }
    final saved = await _providers.updateBeforeAfters(providerId, pairs);
    if (saved == null) return _notFound;
    return (ok: true, error: null, data: {'beforeAfters': saved});
  }

  /// A trimmed, bounded, origin-allowlisted URL — or null if invalid (same rule
  /// as the gallery).
  String? _validUrl(Object? value) {
    if (value is! String) return null;
    final url = value.trim();
    if (url.isEmpty || url.length > _maxUrlLength) return null;
    if (_allowedImageOrigins.isNotEmpty &&
        !_allowedImageOrigins.any(url.startsWith)) {
      return null;
    }
    return url;
  }

  // ---- staff (artists) — design: docs/design/pro-artists.md -----------------

  Future<CatalogResult> listArtists(String accountId, String providerId) async {
    if (!await _can(accountId, providerId, Cap.catalogueManage)) {
      return _forbidden;
    }
    final provider = await _providers.byId(providerId);
    if (provider == null) return _notFound;
    return (
      ok: true,
      error: null,
      data: provider['artists'] ?? const <Map<String, dynamic>>[],
    );
  }

  Future<CatalogResult> createArtist(
    String accountId,
    String providerId,
    Map<String, dynamic> body,
  ) async {
    if (!await _can(accountId, providerId, Cap.catalogueManage)) {
      return _forbidden;
    }
    final name = body['name'];
    if (name is! String || name.trim().isEmpty) {
      return (ok: false, error: 'invalid_input', data: null);
    }
    final artist = {
      'id': _newId('artist'),
      'name': name.trim(),
      'specialization': (body['specialization'] as String?)?.trim(),
      'imageUrl': (body['imageUrl'] as String?)?.trim(),
      'providerId': providerId,
      'rating': null, // server-owned; recomputed from reviews
      'reviewCount': null,
      'workingHours': body['workingHours'] ?? const <String, dynamic>{},
    };
    final created = await _providers.addArtist(providerId, artist);
    if (created == null) return _notFound;
    return (ok: true, error: null, data: created);
  }

  Future<CatalogResult> updateArtist(
    String accountId,
    String providerId,
    String artistId,
    Map<String, dynamic> body,
  ) async {
    if (!await _can(accountId, providerId, Cap.catalogueManage)) {
      return _forbidden;
    }
    if (body.containsKey('name')) {
      final name = body['name'];
      if (name is! String || name.trim().isEmpty) {
        return (ok: false, error: 'invalid_input', data: null);
      }
    }
    // `rating`/`reviewCount`/`id`/`providerId` are server-owned — not editable.
    const editable = ['name', 'specialization', 'imageUrl', 'workingHours'];
    final changes = {
      for (final k in editable)
        if (body.containsKey(k))
          k: body[k] is String ? (body[k] as String).trim() : body[k],
    };
    final updated = await _providers.updateArtist(
      providerId,
      artistId,
      changes,
    );
    if (updated == null) return _notFound;
    return (ok: true, error: null, data: updated);
  }

  Future<CatalogResult> deleteArtist(
    String accountId,
    String providerId,
    String artistId,
  ) async {
    if (!await _can(accountId, providerId, Cap.catalogueManage)) {
      return _forbidden;
    }
    final removed = await _providers.deleteArtist(providerId, artistId);
    return removed ? (ok: true, error: null, data: null) : _notFound;
  }

  /// The salon's deposit policy (design: docs/design/pro-deposit-policy.md).
  /// Maps the provider's stored `depositMobileMoney*` fields to the DTO's
  /// `mobileMoney*` names.
  Future<CatalogResult> depositPolicy(
    String accountId,
    String providerId,
  ) async {
    if (!await _can(accountId, providerId, Cap.depositManage)) {
      return _forbidden;
    }
    final p = await _providers.byId(providerId);
    if (p == null) return _notFound;
    return (ok: true, error: null, data: _policyDto(p));
  }

  /// Replace the deposit policy wholesale. The server is the authority on this
  /// money math — booking derives the deposit from the stored policy.
  Future<CatalogResult> updateDepositPolicy(
    String accountId,
    String providerId,
    Map<String, dynamic> body,
  ) async {
    if (!await _can(accountId, providerId, Cap.depositManage)) {
      return _forbidden;
    }
    // Multi-pays MP1: the operator accept-list is the salon COUNTRY's
    // catalog (identical to the legacy set for CI — threat T57).
    final salon = await _providers.byId(providerId);
    if (salon == null) return _notFound;
    final allowedOperators = _localities != null
        ? await _localities.operatorIdsForCountry(
            (salon['countryCode'] as String?) ?? 'CI',
          )
        : _operators;
    final error = _validateDepositPolicy(body, allowedOperators);
    if (error != null) return (ok: false, error: error, data: null);

    final required = body['depositRequired'] as bool;
    // Deposits are a trust feature: only a KYC-VERIFIED salon may demand
    // them (parity audit 8.1 / threat T52 — the promise both KYC screens
    // make, now enforced).
    if (required) {
      final account = await _providerAuth.accountById(accountId);
      if (account?.verificationStatus != 'verified') {
        return (ok: false, error: 'verification_required', data: null);
      }
    }
    final fields = {
      'depositRequired': required,
      'depositPercentage': (body['depositPercentage'] as num).toDouble(),
      'cancellationWindowHours': (body['cancellationWindowHours'] as num)
          .toInt(),
      'depositMobileMoneyOperator': (body['mobileMoneyOperator'] as String?)
          ?.trim(),
      'depositMobileMoneyNumber': (body['mobileMoneyNumber'] as String?)
          ?.trim(),
    };
    final saved = await _providers.updateDepositPolicy(providerId, fields);
    if (saved == null) return _notFound;
    return (ok: true, error: null, data: _policyDto(saved));
  }

  Map<String, dynamic> _policyDto(Map<String, dynamic> p) => {
    'depositRequired': p['depositRequired'] ?? false,
    'depositPercentage': p['depositPercentage'] ?? 0,
    'cancellationWindowHours': p['cancellationWindowHours'] ?? 24,
    'mobileMoneyOperator': p['depositMobileMoneyOperator'],
    'mobileMoneyNumber': p['depositMobileMoneyNumber'],
  };

  /// Wave-0 fallback only (legacy test wiring without a LocalitiesService) —
  /// production reads the salon country's catalog.
  static const _operators = {'wave', 'orangeMoney', 'mtnMoMo', 'moov'};
  static const _maxCancellationHours = 720; // 30 days

  String? _validateDepositPolicy(
    Map<String, dynamic> body,
    Set<String> allowedOperators,
  ) {
    final required = body['depositRequired'];
    if (required is! bool) return 'invalid_input';

    final pct = body['depositPercentage'];
    if (pct is! num || pct < 0 || pct > 1) return 'invalid_input';
    if (required && pct <= 0) return 'invalid_input';

    final hours = body['cancellationWindowHours'];
    if (hours is! num || hours < 0 || hours > _maxCancellationHours) {
      return 'invalid_input';
    }

    final op = body['mobileMoneyOperator'];
    if (op != null && (op is! String || !allowedOperators.contains(op))) {
      return 'invalid_input';
    }
    final number = body['mobileMoneyNumber'];
    if (number != null && (number is! String || !isValidE164(number.trim()))) {
      return 'invalid_input';
    }

    // A required deposit needs a Mobile Money destination.
    if (required) {
      final hasOp = op is String && op.isNotEmpty;
      final hasNum = number is String && number.trim().isNotEmpty;
      if (!hasOp || !hasNum) return 'invalid_input';
    }
    return null;
  }

  /// Tenant authz (module `access` R1): the caller must hold [capability]
  /// inside [providerId] — resolved per request via the membership layer.
  Future<bool> _can(String accountId, String providerId, String capability) =>
      _members.can(accountId, providerId, capability);

  /// Returns an error code (`invalid_input`) or null. On create everything
  /// required is checked; on a partial update only the provided fields are.
  String? _validateService(Map<String, dynamic> body, {required bool partial}) {
    bool has(String k) => body.containsKey(k);

    if (!partial || has('name')) {
      final name = body['name'];
      if (name is! String || name.trim().isEmpty) return 'invalid_input';
    }
    if (!partial || has('price')) {
      final price = body['price'];
      if (price is! num || price < 0) return 'invalid_input';
    }
    if (has('priceMax') && body['priceMax'] != null) {
      final pm = body['priceMax'];
      final price = (body['price'] as num?) ?? 0;
      if (pm is! num || pm < price) return 'invalid_input';
    }
    if (!partial || has('durationMinutes')) {
      final d = body['durationMinutes'];
      if (d is! num || d <= 0) return 'invalid_input';
    }
    if (has('durationVariants') && body['durationVariants'] != null) {
      final v = body['durationVariants'];
      if (v is! Map) return 'invalid_input';
      for (final val in v.values) {
        if (val != null && (val is! num || val <= 0)) return 'invalid_input';
      }
    }
    if (has('artistIds') &&
        body['artistIds'] != null &&
        body['artistIds'] is! List) {
      return 'invalid_input';
    }
    if (has('active') && body['active'] is! bool) return 'invalid_input';
    return null;
  }

  String? _validateAvailability(Map<String, dynamic> body) {
    final buffer = body['bufferMinutes'];
    if (buffer != null && (buffer is! num || buffer < 0)) {
      return 'invalid_input';
    }

    for (final schedule in [body['weeklySchedule'], body['breaks']]) {
      if (schedule == null) continue;
      if (schedule is! Map) return 'invalid_input';
      for (final entry in schedule.entries) {
        final weekday = int.tryParse(entry.key.toString());
        if (weekday == null || weekday < 0 || weekday > 6) {
          return 'invalid_input';
        }
        final windows = entry.value;
        if (windows is! List) return 'invalid_input';
        for (final slot in windows) {
          if (slot is! Map) return 'invalid_input';
          final start = DateTime.tryParse('${slot['startTime']}');
          final end = DateTime.tryParse('${slot['endTime']}');
          if (start == null || end == null || !start.isBefore(end)) {
            return 'invalid_input';
          }
        }
      }
    }

    final blocked = body['blockedDates'];
    if (blocked != null) {
      if (blocked is! List) return 'invalid_input';
      for (final d in blocked) {
        if (d is! String || DateTime.tryParse(d) == null) {
          return 'invalid_input';
        }
      }
    }
    return null;
  }

  static const CatalogResult _forbidden = (
    ok: false,
    error: 'forbidden',
    data: null,
  );
  static const CatalogResult _notFound = (
    ok: false,
    error: 'not_found',
    data: null,
  );

  String _newId(String prefix) =>
      '${prefix}_${DateTime.now().microsecondsSinceEpoch}';
}
