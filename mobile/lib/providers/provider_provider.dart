import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/di/dependency_injection.dart';
import '../models/provider.dart';
import '../models/review.dart';
import '../services/interfaces/image_upload_service_interface.dart';
import '../services/interfaces/provider_service_interface.dart';
import '../services/interfaces/review_service_interface.dart';

class ProviderProvider extends ChangeNotifier {
  final ProviderServiceInterface _providerService =
      serviceLocator.providerService;
  // Lazy so constructing ProviderProvider doesn't require these registered.
  ReviewServiceInterface get _reviewService => serviceLocator.reviewService;
  ImageUploadServiceInterface get _uploadService =>
      serviceLocator.reviewImageUploadService;

  List<Provider> _providers = [];
  List<Provider> _featuredProviders = [];
  Provider? _selectedProvider;

  /// WHOSE salon the [selectedProvider] slot holds — or is loading, or failed
  /// to load (docs/design/salon-location-map.md §2.7). The slot is one, shared
  /// by every salon page in the stack; [selectedProvider] alone cannot say
  /// whose it is: during a read it still holds the previous salon, and after
  /// a failed one it is `null` for everybody.
  String? _selectedProviderId;
  bool _isLoading = false;
  bool _isSubmittingReview = false;
  String? _error;

  /// The machine-readable failure code behind [error], mirroring
  /// `AppointmentProvider._errorCode`.
  ///
  /// A screen has to distinguish « this salon is no longer on Myweli » from
  /// « your connection dropped »: the first has no retry that can succeed
  /// (SYSTEM.md §12) and its way out is another salon; the second is exactly
  /// the case where « Réessayer » is the right control. Comparing French
  /// sentences to tell them apart is how `'Salon introuvable'` became dead
  /// code that never rendered.
  String? _errorCode;
  String? _selectedCategory;
  String? _selectedCommune;
  ProviderSort _sort = ProviderSort.relevance;
  bool _availableToday = false;

  static const _communeKey = 'myweli_selected_commune_v1';

  List<Provider> get providers => _providers;
  List<Provider> get featuredProviders => _featuredProviders;
  Provider? get selectedProvider => _selectedProvider;

  /// The id of the last [loadProviderById] — set BEFORE its read —, or of the
  /// last [showPreloaded] / [restoreSalon]. See [_selectedProviderId].
  String? get selectedProviderId => _selectedProviderId;
  bool get isLoading => _isLoading;
  bool get isSubmittingReview => _isSubmittingReview;
  String? get error => _error;
  String? get errorCode => _errorCode;
  String? get selectedCategory => _selectedCategory;
  String? get selectedCommune => _selectedCommune;
  ProviderSort get sort => _sort;
  bool get availableToday => _availableToday;

  Future<void> loadProviders({String? category, String? searchQuery}) async {
    _isLoading = true;
    _error = null;
    _selectedCategory = category;
    notifyListeners();

    try {
      final response = await _providerService.getProviders(
        category: category,
        searchQuery: searchQuery,
        commune: _selectedCommune,
        sort: _sort,
        availableToday: _availableToday,
      );
      if (response.success && response.data != null) {
        _providers = response.data!;
        _error = null;
      } else {
        _error = response.error ?? 'Erreur lors du chargement';
        _providers = [];
      }
    } catch (e) {
      _error = e.toString();
      _providers = [];
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Restore the last selected commune from local storage (call at startup).
  Future<void> restoreSelectedCommune() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_communeKey);
    if (saved != null && saved.isNotEmpty) {
      _selectedCommune = saved;
      notifyListeners();
    }
  }

  /// Set the active commune (null = all communes), persist it, and reload the
  /// provider list for the current category.
  Future<void> setCommune(String? commune) async {
    _selectedCommune = (commune != null && commune.isNotEmpty) ? commune : null;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    if (_selectedCommune == null) {
      await prefs.remove(_communeKey);
    } else {
      await prefs.setString(_communeKey, _selectedCommune!);
    }

    await loadProviders(category: _selectedCategory);
  }

  /// Change the sort (FR-DISC-007) and reload.
  Future<void> setSort(ProviderSort sort) async {
    if (_sort == sort) return;
    _sort = sort;
    notifyListeners();
    await loadProviders(category: _selectedCategory);
  }

  /// Toggle the "available today" filter (FR-DISC-007) and reload.
  Future<void> setAvailableToday(bool value) async {
    if (_availableToday == value) return;
    _availableToday = value;
    notifyListeners();
    await loadProviders(category: _selectedCategory);
  }

  Future<void> loadFeaturedProviders() async {
    _isLoading = true;
    notifyListeners();

    try {
      final response = await _providerService.getFeaturedProviders();
      if (response.success && response.data != null) {
        _featuredProviders = response.data!;
      }
    } catch (e) {
      // Silent fail for featured providers
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Frame 1.
  ///
  /// The screens whose whole subject is one salon schedule their fetch in a
  /// post-frame callback — they must, because [loadProviderById] notifies
  /// before its first await and notifying during build throws — so the FIRST
  /// build saw `isLoading == false, selectedProvider == null` and rendered the
  /// ERROR state for one frame. `null` meant both « not asked » and « asked and
  /// failed »; this is the missing third value.
  ///
  /// Called from `initState`, before this screen's first build and before any
  /// `Consumer` of it has subscribed — so it must **not** notify. It touches
  /// `_isLoading` and nothing else on purpose: another mounted listener may
  /// still be rendering `_selectedProvider`, and clearing that here would go
  /// stale silently.
  void beginProviderLoad() => _isLoading = true;

  Future<void> loadProviderById(String id) async {
    _selectedProviderId = id;
    _isLoading = true;
    _error = null;
    _errorCode = null;
    notifyListeners();

    Provider? salon;
    String? error;
    String? code;
    try {
      final response = await _providerService.getProviderById(id);
      if (response.success && response.data != null) {
        salon = response.data;
      } else {
        error = response.error ?? 'Ce salon n’est plus disponible sur MyWeli.';
        code = response.code;
      }
    } catch (e) {
      error = e.toString();
      code = 'network';
    }
    // Another salon was asked for while this read was out — a later load, or
    // a page taking the slot back ([restoreSalon], §2.7). This answer is no
    // longer anybody's: written, it would put salon B under page A's id.
    if (_selectedProviderId != id) return;
    _selectedProvider = salon;
    _error = error;
    _errorCode = code;
    _isLoading = false;
    notifyListeners();
  }

  /// Show a salon the caller ALREADY has, without a network read.
  ///
  /// The owner preview (`/pro/apercu`) renders this consumer screen against
  /// the salon it just fetched from `GET /me/provider` — authenticated, and
  /// resolved from the token rather than from a public id. Seeding is the
  /// mobile equivalent of what web does by passing the object down as a prop
  /// (`SalonPreviewClient` → `ProviderView`): the screen reads a notifier
  /// rather than a parameter, so the notifier is what gets handed the payload.
  ///
  /// With [restoreSalon], the only way `_selectedProvider` is set without
  /// [loadProviderById]; this one exists so a pro surface never has to knock
  /// on the anonymous door for its own salon (T51 — « Pro-own surfaces resolve
  /// by account »). `salon_preview_test.dart` fails the test if the public
  /// service is called at all.
  void showPreloaded(Provider provider) => _show(provider);

  /// Give the slot back to a salon page that already shows its salon
  /// (docs/design/salon-location-map.md §2.7): another salon page, pushed
  /// above it — the map's « Voir le salon » —, took the slot while it was
  /// covered. No network and no loader: the page was already rendering this
  /// very copy.
  void restoreSalon(Provider salon) => _show(salon);

  /// The slot is [salon]'s, settled. `_isLoading` goes false with it: a read
  /// this supersedes drops its answer and would never reset it.
  void _show(Provider salon) {
    _selectedProvider = salon;
    _selectedProviderId = salon.id;
    _error = null;
    _errorCode = null;
    _isLoading = false;
    notifyListeners();
  }

  /// The salon `/carte?providerId=` should centre
  /// (docs/design/salon-location-map.md §2.3): the loaded list first, then
  /// the salon page's own [selectedProvider] — the « Voir sur la carte » case,
  /// which therefore needs no network — else one public read.
  ///
  /// **It writes nothing.** The salon page is still mounted under the map and
  /// reads [selectedProvider], [isLoading] and [error]; a lookup that set any
  /// of them would repaint that page behind the user's back. `null` = not
  /// found, gone, or unreachable — the caller says so.
  Future<Provider?> providerForMap(String id) async {
    for (final p in _providers) {
      if (p.id == id) return p;
    }
    final selected = _selectedProvider;
    if (selected != null && selected.id == id) return selected;
    try {
      final response = await _providerService.getProviderById(id);
      return response.success ? response.data : null;
    } catch (_) {
      return null;
    }
  }

  void clearSelectedProvider() {
    _selectedProvider = null;
    _selectedProviderId = null;
    notifyListeners();
  }

  /// Shows a just-submitted review without a reload — and moves the
  /// denormalized `rating`/`reviewCount` with it, as the backend's
  /// `recomputeRatings` does on the same write. It used to append the review
  /// alone, so a salon's FIRST reviewer saw « Nouveau » and « Pas encore
  /// d’avis. » directly above their own review until the page reloaded
  /// (docs/design/salon-rating-new-and-visits-card.md §2.2). The average is
  /// rounded to one decimal like the backend's `_round1`; the next load
  /// replaces it with the server's figure either way.
  void addReviewLocally(Review review) {
    final salon = _selectedProvider;
    if (salon == null || salon.id != review.providerId) return;
    final count = salon.reviewCount + 1;
    final average = (salon.rating * salon.reviewCount + review.rating) / count;
    _selectedProvider = salon.copyWith(
      reviews: [...salon.reviews, review],
      reviewCount: count,
      rating: (average * 10).round() / 10,
    );
    notifyListeners();
  }

  /// Uploads a review photo through the image pipeline; returns the URL.
  Future<String?> uploadReviewPhoto(String source) async {
    final res = await _uploadService.uploadImage(source: source);
    return res.success ? res.data : null;
  }

  /// Reports a review for moderation (FR-REV-005 — parity 2.14).
  Future<bool> reportReview(String reviewId, {String? reason}) async {
    final res = await _reviewService.reportReview(reviewId, reason: reason);
    return res.success;
  }

  /// Submits a review through the service, then reflects it locally.
  Future<bool> submitReview(Review review) async {
    _isSubmittingReview = true;
    _error = null;
    notifyListeners();
    try {
      final res = await _reviewService.submitReview(review);
      if (res.success && res.data != null) {
        addReviewLocally(res.data!);
        return true;
      }
      _error = res.error ?? 'Erreur lors de la publication';
      return false;
    } catch (e) {
      _error = e.toString();
      return false;
    } finally {
      _isSubmittingReview = false;
      notifyListeners();
    }
  }
}
