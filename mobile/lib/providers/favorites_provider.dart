import 'package:flutter/foundation.dart';

import '../core/access/account_scope.dart';
import '../core/constants/failure_messages.dart';
import '../core/di/dependency_injection.dart';
import '../core/utils/salon_figures.dart';
import '../core/utils/salon_id.dart';
import '../models/api_response.dart';
import '../models/provider.dart';
import '../services/interfaces/favorites_service_interface.dart';

/// What [FavoritesProvider.addIfMissing] did.
enum FavoriteAddOutcome {
  /// The salon is a favourite now.
  added,

  /// It already was: nothing was sent — a toggle would have removed it.
  alreadyThere,

  /// The read or the add failed; [FavoritesProvider.error] says why.
  failed,
}

class FavoritesProvider extends ChangeNotifier implements AccountScoped {
  final FavoritesServiceInterface _favoritesService =
      serviceLocator.favoritesService;

  /// Whose favourites these are — see [resetForAccountChange]. A read or a
  /// heart sent before the account changed writes nothing when it answers
  /// after (docs/design/consumer-account-scope.md §2.3).
  int _account = 0;

  List<SalonId> _favoriteProviderIds = [];
  List<Provider> _favoriteProviders = [];
  bool _isLoading = false;
  String? _error;
  String? _currentUserId;

  List<String> get favoriteProviderIds => _favoriteProviderIds;

  /// The favourite salons as the SERVER hydrated them — including any that
  /// stopped taking appointments, which the discovery list excludes.
  List<Provider> get favoriteProviders => _favoriteProviders;
  bool get isLoading => _isLoading;
  String? get error => _error;

  /// Load favorites for a user.
  ///
  /// [force] reads even when this user's list is already in memory — the data
  /// export needs the account as it is now, not as it was when the session
  /// first read it (docs/design/consumer-export-completeness.md §1 point 7).
  /// It also resets [error], which the early return below leaves as it was.
  ///
  /// **A read of the same account already under way is shared,** not raced:
  /// the root's reload after a sign-in and a heart applied after that sign-in
  /// both read (consumer-signin-push.md §2.3, §2.8), and whichever answered
  /// last won — an older read landing after the add erased the salon just
  /// added.
  Future<void> loadFavorites(String userId, {bool force = false}) {
    if (!force && _currentUserId == userId && _favoriteProviderIds.isNotEmpty) {
      // Already loaded for this user
      return Future<void>.value();
    }
    // Shared only if no heart was written since it was sent: a read that
    // predates an add would answer without it.
    final running = _inFlight;
    if (running != null &&
        _inFlightUser == userId &&
        _inFlightWrites == _writes) {
      return running;
    }
    final load = _loadFavorites(userId);
    _inFlight = load;
    _inFlightUser = userId;
    _inFlightWrites = _writes;
    return load.whenComplete(() {
      if (identical(_inFlight, load)) {
        _inFlight = null;
        _inFlightUser = null;
      }
    });
  }

  Future<void>? _inFlight;
  String? _inFlightUser;

  /// Hearts written (sent) so far, and how many when [_inFlight] was sent.
  int _writes = 0;
  int _inFlightWrites = 0;

  Future<void> _loadFavorites(String userId) async {
    final account = _account;
    _isLoading = true;
    _error = null;
    _currentUserId = userId;
    notifyListeners();

    ApiResponse<List<Provider>>? response;
    try {
      response = await _favoritesService.getFavoriteProviders(userId);
    } catch (e) {
      response = null;
    }
    if (account != _account) return;
    final loaded = response?.data;
    if (response != null && response.success && loaded != null) {
      _favoriteProviders = loaded;
      _favoriteProviderIds = [for (final p in loaded) p.id];
      _error = null;
    } else {
      _error = response == null
          ? kGenericErrorMessage
          : response.error ?? 'Erreur lors du chargement des favoris';
      _favoriteProviderIds = [];
      _favoriteProviders = [];
    }
    _isLoading = false;
    notifyListeners();
  }

  /// Toggle favorite status for a provider
  Future<bool> toggleFavorite(String userId, SalonId providerId) async {
    if (userId.isEmpty) {
      _error = 'Utilisateur non connecté';
      notifyListeners();
      return false;
    }

    final account = _account;
    // Ensure favorites are loaded
    if (_currentUserId != userId || _favoriteProviderIds.isEmpty) {
      await loadFavorites(userId);
    }
    if (account != _account) return false;

    final isCurrentlyFavorite = _favoriteProviderIds.contains(providerId);

    _isLoading = true;
    notifyListeners();

    ApiResponse<bool>? response;
    try {
      _writes++;
      if (isCurrentlyFavorite) {
        response = await _favoritesService.removeFavorite(userId, providerId);
      } else {
        response = await _favoritesService.addFavorite(userId, providerId);
      }
    } catch (e) {
      response = null;
    }
    final done = response != null && response.success;
    // Done on the previous account's favourites — not on the next one's.
    if (account != _account) return done;
    if (done) {
      if (isCurrentlyFavorite) {
        _favoriteProviderIds.remove(providerId);
      } else if (!_favoriteProviderIds.contains(providerId)) {
        _favoriteProviderIds.add(providerId);
      }
      _error = null;
    } else {
      _error = response == null
          ? kGenericErrorMessage
          : response.error ?? 'Erreur lors de la modification des favoris';
    }
    _isLoading = false;
    notifyListeners();
    return done;
  }

  /// Adds [providerId] unless it already is a favourite — for a heart tapped
  /// before signing in, applied after (consumer-signin-push.md §2.8,
  /// decision 205). The favourites are read fresh first: signing in may bring
  /// ones saved on another phone or on the website, and a toggle there would
  /// have REMOVED the salon the person asked to add.
  Future<FavoriteAddOutcome> addIfMissing(
    String userId,
    SalonId providerId,
  ) async {
    if (userId.isEmpty) return FavoriteAddOutcome.failed;
    final account = _account;
    await loadFavorites(userId, force: true);
    if (account != _account) return FavoriteAddOutcome.failed;
    if (_error != null) return FavoriteAddOutcome.failed;
    if (_favoriteProviderIds.contains(providerId)) {
      return FavoriteAddOutcome.alreadyThere;
    }

    _isLoading = true;
    notifyListeners();
    ApiResponse<bool>? response;
    try {
      _writes++;
      response = await _favoritesService.addFavorite(userId, providerId);
    } catch (e) {
      response = null;
    }
    final done = response != null && response.success;
    if (account != _account) return FavoriteAddOutcome.failed;
    if (done) {
      if (!_favoriteProviderIds.contains(providerId)) {
        _favoriteProviderIds.add(providerId);
      }
      _error = null;
    } else {
      _error = response == null
          ? kGenericErrorMessage
          : response.error ?? 'Erreur lors de la modification des favoris';
    }
    _isLoading = false;
    notifyListeners();
    return done ? FavoriteAddOutcome.added : FavoriteAddOutcome.failed;
  }

  /// Check if a provider is favorited
  bool isFavorite(SalonId providerId) {
    return _favoriteProviderIds.contains(providerId);
  }

  /// The favourite salons.
  ///
  /// **[allProviders] is a fallback, not the source.** This used to intersect
  /// the ids with the discovery list, which excludes salons that are `draft`
  /// or `suspended` — so a favourite whose salon stopped simply disappeared,
  /// and the screen said « Aucun favori » to someone who had one. The server
  /// hydrates the list now (Decision C); the intersection remains only for a
  /// caller that loaded ids without documents.
  List<Provider> getFavoriteProviders(List<Provider> allProviders) {
    if (_favoriteProviders.isNotEmpty) return _favoriteProviders;
    return allProviders
        .where((provider) => _favoriteProviderIds.contains(provider.id))
        .toList();
  }

  /// A salon's rating and review count just changed — a review of it was
  /// published (docs/design/amounts-that-fit.md §5 « Reviews »): carry them
  /// onto its hydrated copy, if it is a favourite.
  ///
  /// These copies are loaded once per user per session ([loadFavorites]
  /// returns early afterwards, and the home's pull-to-refresh does not reload
  /// them), so without this the « Mes favoris » cards kept the old figures —
  /// « Nouveau », for a salon's first review — until the app restarted.
  ///
  /// The signature is `SalonFiguresSink`'s (provider_provider.dart): the
  /// review sheet hands this method to `ProviderProvider.submitReview`.
  void patchSalonFigures(
    SalonId providerId, {
    required double rating,
    required int reviewCount,
  }) {
    final patched = withSalonFigures(
      _favoriteProviders,
      providerId,
      rating: rating,
      reviewCount: reviewCount,
    );
    if (identical(patched, _favoriteProviders)) return;
    _favoriteProviders = patched;
    notifyListeners();
  }

  /// The account changed (B9.13). It replaces `clearFavorites`, which the
  /// profile screen called by hand — before the sign-out, so a sign-out that
  /// failed emptied the hearts of an account still signed in.
  @override
  void resetForAccountChange() {
    _account++;
    _inFlight = null;
    _inFlightUser = null;
    _favoriteProviderIds = [];
    _favoriteProviders = [];
    _currentUserId = null;
    _isLoading = false;
    _error = null;
    notifyListeners();
  }
}
