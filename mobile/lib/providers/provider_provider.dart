import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/access/account_scope.dart';
import '../core/constants/app_constants.dart';
import '../core/constants/failure_messages.dart';
import '../core/di/dependency_injection.dart';
import '../core/utils/salon_figures.dart';
import '../core/utils/salon_id.dart';
import '../models/provider.dart';
import '../models/provider_page.dart';
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
      SalonId providerId, {
      required double rating,
      required int reviewCount,
    });

/// A screen's own copies of salons, which [ProviderProvider] cannot hold
/// itself: an open salon search (docs/design/consumer-search.md §2.7). It is
/// attached while it lives, so [ProviderProvider.providerForMap] finds a
/// salon in it and a review's new figures reach its card.
abstract interface class SalonCopyHolder {
  /// The copy of salon [id] this holder shows, if any.
  Provider? heldSalon(SalonId id);

  /// Show [rating] and [reviewCount] on this holder's copy of salon [id].
  void patchSalonFigures(
    SalonId id, {
    required double rating,
    required int reviewCount,
  });
}

class ProviderProvider extends ChangeNotifier implements AccountScoped {
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
  SalonId? _selectedProviderId;
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

  /// The home's « Près de vous » read (B9.8) — [providers]. [isLoading] and
  /// [error] are the salon page's alone (docs/design/consumer-search.md
  /// §2.7): a list read used to write them, so a list ending during a salon
  /// read could show that salon page the list's error.
  bool _listLoading = false;
  String? _listError;

  /// The request number of « Près de vous »: a commune changed twice while a
  /// read was out must end on the last commune's salons (the slot picker's
  /// `_reqId` pattern).
  int _listReq = 0;

  /// The featured carousel's own read, for the same reason.
  bool _featuredLoading = false;

  /// The featured read has ANSWERED (not failed). It is the one unfiltered
  /// read: answered with nothing, no salon is public at all (§2.10).
  bool _featuredAnswered = false;
  String? _selectedCommune;

  /// The salon list's sort and « Disponible aujourd’hui », kept for the
  /// session (decision 236) — on the list only: the home and the map never
  /// read them. The list's controller writes them back as they change.
  ProviderSort _listSort = ProviderSort.relevance;
  bool _listAvailableToday = false;

  /// The map's salons (§2.8): the chosen commune only, up to
  /// [kMapSalonPageSize], in a list of their own.
  List<Provider>? _mapSalons;
  int _mapTotal = 0;
  String? _mapCommune;
  bool _mapLoading = false;

  /// The commune of the map read that is out, while [_mapLoading].
  String? _mapAsking;
  String? _mapError;
  int _mapReq = 0;

  /// The open searches (§2.7): [providerForMap] and a review's figures reach
  /// their copies too.
  final Set<SalonCopyHolder> _holders = {};

  /// The stars each visit was last given from this device, by appointment id
  /// — what [addReviewLocally] falls back on to tell a visit reviewed AGAIN
  /// from a first review when no copy at hand lists the earlier one: the list
  /// rows carry no reviews, and the page embeds the ten newest only.
  final Map<String, int> _starsByVisit = {};

  /// How many reviews of each salon [addReviewLocally] has applied — the
  /// stale-answer guard of [rereadSalonAfterReview].
  final Map<String, int> _reviewsApplied = {};

  /// The account changed (B9.13): only the stars it gave are its own.
  ///
  /// Everything else here — the salons, the open page, the commune, the sort
  /// — is public, and emptying it would blank the home under the person.
  /// No notification: nothing on screen reads these stars, and a rebuild of
  /// every salon list for nothing is a cost on a low-end phone. No account
  /// number either: the map is keyed by the previous account's visits, which
  /// the next account can never review (docs/design/consumer-account-scope.md
  /// §2.1).
  @override
  void resetForAccountChange() => _starsByVisit.clear();

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
  bool get listLoading => _listLoading;
  String? get listError => _listError;
  bool get featuredLoading => _featuredLoading;
  String? get selectedCommune => _selectedCommune;
  ProviderSort get listSort => _listSort;
  bool get listAvailableToday => _listAvailableToday;

  /// No salon is public at all: the unfiltered featured read answered with
  /// nothing (§2.10). False while it has not answered, or failed — the empty
  /// states then say what they say.
  bool get noPublicSalon => _featuredAnswered && _featuredProviders.isEmpty;

  /// The map's salons; null until its first answer.
  List<Provider>? get mapSalons => _mapSalons;

  /// How many salons the map's commune holds, of which [mapSalons] shows up
  /// to [kMapSalonPageSize].
  int get mapTotal => _mapTotal;

  /// The commune [mapSalons] are of (null: every commune).
  String? get mapCommune => _mapCommune;
  bool get mapLoading => _mapLoading;
  String? get mapError => _mapError;

  /// The home's « Près de vous » (§2.7): the chosen commune only, by
  /// relevance, page 1. **It never takes a category, a text, a sort or
  /// « Disponible aujourd’hui »**: those were shared with the salon list, so
  /// a category tapped there came back as the home's « Près de vous » under
  /// its unchanged title. It stays [providers], the list the fallbacks read
  /// (`AppointmentCard`, « Derniers rendez-vous », « Mes rendez-vous »,
  /// decision 199).
  Future<void> loadProviders() async {
    final req = ++_listReq;
    _listLoading = true;
    _listError = null;
    notifyListeners();

    List<Provider>? salons;
    String? error;
    try {
      final response = await _providerService.getProviders(
        commune: _selectedCommune,
      );
      if (response.success && response.data != null) {
        salons = response.data!;
      } else {
        error = response.error ?? kGenericErrorMessage;
      }
    } catch (e) {
      error = kGenericErrorMessage;
    }
    if (req != _listReq) return;
    _providers = salons ?? [];
    _listError = error;
    _listLoading = false;
    notifyListeners();
  }

  /// The map's salons (§2.8): the chosen commune, up to [kMapSalonPageSize],
  /// with the server's `total`. The salons shown stay through the read; a
  /// failed read empties them — the pill names a commune whose salons the
  /// map could not get.
  ///
  /// **A read already out for the same commune is not asked again**: its
  /// answer is this one's. This read notifies, so a listener that reloads
  /// on every notification would otherwise call it from inside itself
  /// without end — the map's own commune check deleted (mutation M20) froze
  /// the test isolate for 20 hours, and would freeze the app.
  Future<void> loadMapSalons() async {
    final commune = _selectedCommune;
    if (_mapLoading && _mapAsking == commune) return;
    final req = ++_mapReq;
    _mapAsking = commune;
    _mapLoading = true;
    _mapError = null;
    notifyListeners();

    ProviderPage? page;
    String? error;
    try {
      final response = await _providerService.searchProviders(
        ProviderQuery(commune: commune, pageSize: kMapSalonPageSize),
      );
      if (response.success && response.data != null) {
        page = response.data;
      } else {
        error = response.error ?? kGenericErrorMessage;
      }
    } catch (e) {
      error = kGenericErrorMessage;
    }
    if (req != _mapReq) return;
    _mapSalons = page?.items ?? const [];
    _mapTotal = page?.total ?? 0;
    _mapCommune = commune;
    _mapError = error;
    _mapLoading = false;
    notifyListeners();
  }

  /// The salon list remembers its sort and filter for the session (decision
  /// 236). No notification: nothing but the list reads them, and it changed
  /// them itself.
  void rememberListFilters({
    required ProviderSort sort,
    required bool availableToday,
  }) {
    _listSort = sort;
    _listAvailableToday = availableToday;
  }

  /// An open search's copies, reached by [providerForMap] and a review's
  /// figures while it lives (§2.7).
  void attachSalonHolder(SalonCopyHolder holder) => _holders.add(holder);
  void detachSalonHolder(SalonCopyHolder holder) => _holders.remove(holder);

  /// Restore the last selected commune from local storage (call at startup).
  Future<void> restoreSelectedCommune() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_communeKey);
    if (saved != null && saved.isNotEmpty) {
      _selectedCommune = saved;
      notifyListeners();
    }
  }

  /// Set the active commune (null = all communes), persist it, and reload
  /// the home's « Près de vous ». The commune is one shared, saved choice
  /// (§2.7): an open salon list and the map see it change and reload
  /// themselves — each only when it actually changed.
  Future<void> setCommune(String? commune) async {
    _selectedCommune = (commune != null && commune.isNotEmpty) ? commune : null;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    if (_selectedCommune == null) {
      await prefs.remove(_communeKey);
    } else {
      await prefs.setString(_communeKey, _selectedCommune!);
    }

    await loadProviders();
  }

  Future<void> loadFeaturedProviders() async {
    _featuredLoading = true;
    notifyListeners();

    try {
      final response = await _providerService.getFeaturedProviders();
      if (response.success && response.data != null) {
        _featuredProviders = response.data!;
        _featuredAnswered = true;
      }
    } catch (e) {
      // Silent fail for featured providers
    } finally {
      _featuredLoading = false;
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

  Future<void> loadProviderById(SalonId id) async {
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
      error = kGenericErrorMessage;
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
  /// (docs/design/salon-location-map.md §2.3): a copy already held — the
  /// home's list, the map's, an open search (consumer-search.md §2.7) —
  /// then the salon page's own [selectedProvider] — the « Voir sur la
  /// carte » case, which therefore needs no network — else one public read.
  ///
  /// **It writes nothing.** The salon page is still mounted under the map and
  /// reads [selectedProvider], [isLoading] and [error]; a lookup that set any
  /// of them would repaint that page behind the user's back. `null` = not
  /// found, gone, or unreachable — the caller says so.
  Future<Provider?> providerForMap(SalonId id) async {
    final held = _heldCopy(id);
    if (held != null) return held;
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
    // — else a list's, else the featured list's.
    final base =
        page ??
        _heldCopy(id) ??
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

  /// The copy of salon [id] in a list held here or in an open search — the
  /// home's, the map's, then the searches' — or null.
  Provider? _heldCopy(SalonId id) {
    for (final p in _providers) {
      if (p.id == id) return p;
    }
    for (final p in _mapSalons ?? const <Provider>[]) {
      if (p.id == id) return p;
    }
    for (final holder in _holders) {
      final p = holder.heldSalon(id);
      if (p != null) return p;
    }
    return null;
  }

  /// [rating] and [reviewCount] onto the copies of salon [id] outside the
  /// slot: the home's list, the map's, every open search, the featured
  /// list, and whatever [alsoPatch] holds.
  void _patchFigures(
    SalonId id,
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
    final map = _mapSalons;
    if (map != null) {
      _mapSalons = withSalonFigures(
        map,
        id,
        rating: rating,
        reviewCount: reviewCount,
      );
    }
    for (final holder in _holders) {
      holder.patchSalonFigures(id, rating: rating, reviewCount: reviewCount);
    }
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
  /// One answer is stale, and dropped whole: a later review of this salon
  /// was applied while the read was out. It is older than what is shown, and
  /// that review's own re-read is the one that knows both.
  ///
  /// **The slot takes the answer only while it HOLDS this salon** — never on
  /// the slot's id alone, which also names a salon whose read is out or
  /// failed. **The lists and [alsoPatch] take it whoever holds the slot**:
  /// their rows of this salon are nobody else's. They used to be skipped
  /// whenever another salon held the slot — and the slot outlives its page:
  /// no screen calls [clearSelectedProvider], so the last salon page,
  /// booking hub or booking confirmation opened holds it for the rest of
  /// the session. A review published from « Mes rendez-vous » after any of
  /// them lost its answer, and a favourite held in no list kept « Nouveau »
  /// until the app restarted.
  ///
  /// Not reached: a page of this salon COVERED by another salon's page. It
  /// renders its own copy and hands that back when uncovered
  /// ([restoreSalon]) — without this answer, and without a review applied
  /// while it was covered —, so it can disagree with the lists until its
  /// next read.
  Future<void> rereadSalonAfterReview(
    SalonId providerId, {
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
      _error = kGenericErrorMessage;
      return false;
    } finally {
      _isSubmittingReview = false;
      notifyListeners();
    }
  }
}
