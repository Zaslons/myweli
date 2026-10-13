import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/constants/app_constants.dart';
import '../core/di/dependency_injection.dart';
import '../core/utils/salon_figures.dart';
import '../models/provider.dart';
import '../models/review.dart';
import '../services/interfaces/image_upload_service_interface.dart';
import '../services/interfaces/provider_service_interface.dart';
import '../services/interfaces/review_service_interface.dart';

/// Where else copies of a salon are held, told its new figures.
///
/// [ProviderProvider] keeps three copies of a salon — the page's, the list's
/// and the featured list's — and moves them itself. The favourites are a
/// FOURTH, in another notifier it cannot reach and must not read: the Pro
/// app's « Aperçu » runs the salon page with [ProviderProvider] alone. So the
/// caller that has both in hand — the review sheet — passes
/// `FavoritesProvider.patchSalonFigures` here.
typedef SalonFiguresSink =
    void Function(
      String providerId, {
      required double rating,
      required int reviewCount,
    });

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

  /// The stars each visit was last given from this device, by appointment id
  /// — what [addReviewLocally] falls back on to tell a visit reviewed AGAIN
  /// from a first review when no copy at hand lists the earlier one: the list
  /// rows carry no reviews, and the page embeds the ten newest only.
  final Map<String, int> _starsByVisit = {};

  /// How many reviews of each salon [addReviewLocally] has applied — the
  /// stale-answer guard of [rereadSalonAfterReview].
  final Map<String, int> _reviewsApplied = {};

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

  /// Shows a just-published review without a reload, on EVERY copy of its
  /// salon held here — docs/design/amounts-that-fit.md §5 « Reviews ».
  ///
  /// **It replaces or adds, keyed on the appointment.** The server keeps one
  /// review per visit; a visit reviewed again used to count twice here and
  /// show both tiles. The review `id` cannot be the key: the 201 of a resubmit
  /// carries a freshly minted one while the stored row keeps its own. An
  /// EMPTY `appointmentId` (seed data, old payloads) is not a key either —
  /// such reviews only ever add.
  ///
  /// **Newest first**, as the server sends them: the page renders
  /// `reviews.take(5)`, so a review appended last was invisible on a salon
  /// that already showed five.
  ///
  /// **The same figures on every copy**: the page's when the slot is this
  /// salon's, and — whoever holds the slot, or nobody — the list's, the
  /// featured list's and, through [alsoPatch], the favourites'. Only the open
  /// page used to move, so the map sheet, the home cards and the favourites
  /// kept « Nouveau » until a reload.
  ///
  /// The figures are [figuresAfterReview]'s estimate; it reads nothing.
  /// [rereadSalonAfterReview] is what fetches the server's.
  void addReviewLocally(Review review, {SalonFiguresSink? alsoPatch}) {
    final id = review.providerId;
    final visit = review.appointmentId;
    _reviewsApplied[id] = (_reviewsApplied[id] ?? 0) + 1;

    final open = _selectedProvider;
    final page = open != null && open.id == id ? open : null;
    // What to count from: the page's copy — the only one that lists reviews
    // — else the list's, else the featured list's.
    final base =
        page ??
        _providers.where((p) => p.id == id).firstOrNull ??
        _featuredProviders.where((p) => p.id == id).firstOrNull;

    final int? replacedStars = visit.isEmpty
        ? null
        : base?.reviews
                  .where((r) => r.appointmentId == visit)
                  .firstOrNull
                  ?.rating ??
              _starsByVisit[visit];
    if (visit.isNotEmpty) _starsByVisit[visit] = review.rating;
    // No copy of this salon here: nothing to show it on.
    if (base == null) return;

    final figures = figuresAfterReview(
      rating: base.rating,
      reviewCount: base.reviewCount,
      stars: review.rating,
      replacedStars: replacedStars,
    );
    if (page != null) {
      _selectedProvider = page.copyWith(
        reviews: [
          review,
          for (final r in page.reviews)
            if (visit.isEmpty || r.appointmentId != visit) r,
        ],
        rating: figures.rating,
        reviewCount: figures.reviewCount,
      );
    }
    _patchFigures(id, figures.rating, figures.reviewCount, alsoPatch);
    notifyListeners();
  }

  /// [rating] and [reviewCount] onto the copies of salon [id] outside the
  /// slot: the list (the map's markers and [providerForMap] read it first),
  /// the featured list, and whatever [alsoPatch] holds.
  void _patchFigures(
    String id,
    double rating,
    int reviewCount,
    SalonFiguresSink? alsoPatch,
  ) {
    _providers = withSalonFigures(
      _providers,
      id,
      rating: rating,
      reviewCount: reviewCount,
    );
    _featuredProviders = withSalonFigures(
      _featuredProviders,
      id,
      rating: rating,
      reviewCount: reviewCount,
    );
    alsoPatch?.call(id, rating: rating, reviewCount: reviewCount);
  }

  /// One read of the salon after a review of it was published, for the
  /// SERVER's figures: [addReviewLocally] can only estimate them, cannot see
  /// a review older than the ten the page embeds, and holds the 201's id
  /// where « Signaler » needs the stored one.
  ///
  /// **It only ever improves what is shown.** Not [loadProviderById], which
  /// blanks the page when its read fails — and this one fails for ordinary
  /// reasons: offline right after the POST, or a salon that stopped (the
  /// appointment screen keeps « Donner mon avis » for it, and the public
  /// route answers 404). So, on anything but an answer inside
  /// [AppConstants.reviewRereadTimeout]: no change, no error, no loader.
  ///
  /// Two answers are stale, and dropped whole:
  ///  * another salon holds the slot now — [loadProviderById]'s own guard. A
  ///    page of THIS salon may be covered beneath it, holding the figures of
  ///    [addReviewLocally]; moving the lists alone would make them disagree.
  ///  * a later review of this salon was applied while the read was out:
  ///    this answer is older than what is shown, and that review's own
  ///    re-read is the one that knows both.
  ///
  /// With the slot free (no salon page was opened), the lists and
  /// [alsoPatch] take the figures and the slot stays free.
  Future<void> rereadSalonAfterReview(
    String providerId, {
    SalonFiguresSink? alsoPatch,
  }) async {
    final applied = _reviewsApplied[providerId];
    Provider? salon;
    try {
      final response = await _providerService
          .getProviderById(providerId)
          .timeout(AppConstants.reviewRereadTimeout);
      if (response.success) salon = response.data;
    } catch (_) {
      // No connection, a 5xx, the time limit: one and the same « no answer ».
    }
    if (salon == null) return;
    if (_reviewsApplied[providerId] != applied) return;
    final holder = _selectedProviderId;
    if (holder != null && holder != providerId) return;

    if (_selectedProvider?.id == providerId) _selectedProvider = salon;
    _patchFigures(providerId, salon.rating, salon.reviewCount, alsoPatch);
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

  /// Submits a review through the service, then shows it
  /// ([addReviewLocally]) and STARTS the re-read of its salon
  /// ([rereadSalonAfterReview]) — started, not awaited: « Publier » ends on
  /// the 201, not on a second round trip nothing bounds but that read's own
  /// time limit. [alsoPatch] goes to both.
  Future<bool> submitReview(
    Review review, {
    SalonFiguresSink? alsoPatch,
  }) async {
    _isSubmittingReview = true;
    _error = null;
    notifyListeners();
    try {
      final res = await _reviewService.submitReview(review);
      final posted = res.data;
      if (res.success && posted != null) {
        addReviewLocally(posted, alsoPatch: alsoPatch);
        unawaited(
          rereadSalonAfterReview(posted.providerId, alsoPatch: alsoPatch),
        );
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
