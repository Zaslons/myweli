import 'favorites_repository.dart';
import 'providers_repository.dart';
import 'salon_visibility.dart';

/// Outcome of a favorites operation. [providerIds] is the list on a read, and
/// [providers] the hydrated documents behind it.
typedef FavoritesResult = ({
  bool ok,
  String? error,
  List<String>? providerIds,
  List<Map<String, dynamic>>? providers,
});

/// Consumer favorites (design: docs/design/consumer-favorites.md). Always
/// scoped to the caller's own user id (the route passes the token's `sub`), so
/// there is no cross-user surface.
///
/// **The read hydrates, and deliberately does NOT filter on salon status**
/// (`salon-state-and-refusals.md` §5, Decision C). A favourite is a
/// relationship the client already has, so it keeps resolving after the salon
/// leaves the public listing — carrying its `status`, so the surface can say
/// « ce salon ne prend plus de rendez-vous » instead of quietly losing a row.
/// Before this, web fanned out one public `GET /providers/{id}` per favourite
/// and dropped the ones that failed: closing that read would have made the
/// favourite vanish from the list AND from the RGPD export, on a page whose
/// own copy promises « profil, rendez-vous et favoris ».
///
/// **The write does filter.** An existing favourite is a relationship; a new
/// one would be a way to name a salon the public read hides.
class FavoritesService {
  FavoritesService(this._favorites, this._providers);

  final FavoritesRepository _favorites;
  final ProvidersRepository _providers;

  Future<FavoritesResult> list(String userId) async {
    final ids = await _favorites.listForUser(userId);
    // ONE round trip, not one per favourite — the N+1 the clients are shedding
    // must not reappear here (BACKEND.md §4).
    final found = {
      for (final p in await _providers.byIds(ids)) p['id'] as String: p,
    };
    return (
      ok: true,
      error: null,
      // Retained: shipped app builds parse `providerIds`, and the envelope
      // rule says no existing field changes meaning.
      providerIds: ids,
      // Newest-first, following the id order the repository already sorts. A
      // salon that no longer EXISTS drops out — unlike a hidden one, which
      // still has a document to hydrate.
      providers: [
        for (final id in ids)
          if (found[id] case final Map<String, dynamic> p) p,
      ],
    );
  }

  Future<FavoritesResult> add(String userId, String providerId) async {
    if (!isPublicSalon(await _providers.byId(providerId))) {
      // Hidden and nonexistent answer identically, as everywhere else — a
      // distinguishable refusal here would be the enumeration oracle T51
      // exists to prevent, reachable by any signed-in consumer.
      return (
        ok: false,
        error: 'not_found',
        providerIds: null,
        providers: null,
      );
    }
    await _favorites.add(userId, providerId);
    return (ok: true, error: null, providerIds: null, providers: null);
  }

  Future<FavoritesResult> remove(String userId, String providerId) async {
    await _favorites.remove(userId, providerId);
    return (ok: true, error: null, providerIds: null, providers: null);
  }
}
