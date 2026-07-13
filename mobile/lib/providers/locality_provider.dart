import 'package:flutter/foundation.dart';

import '../core/di/dependency_injection.dart';
import '../models/locality.dart';
import '../services/interfaces/locality_service_interface.dart';

/// State for the locality reference tree (multi-pays MP2 —
/// docs/design/multi-pays-end-version.md §2/§6): lazy-fetched once, cached
/// for the session, with loading/error/retry for the pickers. Reference data
/// only — no per-user variance.
class LocalityProvider extends ChangeNotifier {
  LocalityServiceInterface get _service => serviceLocator.localityService;

  List<LocalityCountry> _countries = const [];
  List<LocalityCountry> get countries => _countries;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  String? _error;
  String? get error => _error;

  bool get isLoaded => _countries.isNotEmpty;

  Future<void>? _inFlight;

  /// Lazy fetch, deduped: every picker calls this; only the first hits the
  /// service, the rest await the same future or return the cache.
  Future<void> ensureLoaded() {
    if (isLoaded) return Future.value();
    return _inFlight ??= _load().whenComplete(() => _inFlight = null);
  }

  Future<void> retry() {
    _countries = const [];
    return ensureLoaded();
  }

  Future<void> _load() async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    final res = await _service.getLocalities();
    _isLoading = false;
    if (res.success && (res.data?.isNotEmpty ?? false)) {
      _countries = res.data!;
      _error = null;
    } else {
      _error = res.error ?? 'Impossible de charger les communes.';
    }
    notifyListeners();
  }

  // ---- Convenience reads (null/empty-safe before load) ---------------------

  LocalityCountry? countryOf(String? code) {
    for (final c in _countries) {
      if (c.code == (code ?? 'CI')) return c;
    }
    return _countries.isEmpty ? null : _countries.first;
  }

  /// The country's display name — the hint label (« heure du salon (X) »).
  String? countryName(String? code) => countryOf(code)?.name;

  /// The Mobile-Money catalog for a salon's country.
  List<MomoOperatorInfo> operatorsFor(String? countryCode) =>
      countryOf(countryCode)?.operators ?? const [];

  MomoOperatorInfo? operatorInfo(String? id, {String? countryCode}) {
    if (id == null) return null;
    for (final o in operatorsFor(countryCode)) {
      if (o.id == id) return o;
    }
    return null;
  }

  /// Every pickable area (Wave 0: Abidjan's communes), city order preserved.
  List<LocalityArea> areasOf({String? countryCode, String? citySlug}) {
    final country = countryOf(countryCode);
    if (country == null) return const [];
    final cities = citySlug == null
        ? country.cities
        : country.cities.where((c) => c.slug == citySlug);
    return [for (final city in cities) ...city.areas];
  }

  /// « Près de moi »: the nearest area by squared-degree distance to the
  /// device position (the historical nearestCommune behavior, now on data).
  LocalityArea? nearestArea(double lat, double lng, {String? countryCode}) {
    LocalityArea? best;
    double bestD = double.infinity;
    for (final a in areasOf(countryCode: countryCode)) {
      final aLat = a.lat;
      final aLng = a.lng;
      if (aLat == null || aLng == null) continue;
      final d = (aLat - lat) * (aLat - lat) + (aLng - lng) * (aLng - lng);
      if (d < bestD) {
        bestD = d;
        best = a;
      }
    }
    return best;
  }
}
