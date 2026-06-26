import 'favorites_repository.dart';
import 'providers_repository.dart';

/// Outcome of a favorites operation; [providerIds] is the list on a read.
typedef FavoritesResult = ({bool ok, String? error, List<String>? providerIds});

/// Consumer favorites (design: docs/design/consumer-favorites.md). Always
/// scoped to the caller's own user id (the route passes the token's `sub`), so
/// there is no cross-user surface. Adding validates the provider exists.
class FavoritesService {
  FavoritesService(this._favorites, this._providers);

  final FavoritesRepository _favorites;
  final ProvidersRepository _providers;

  Future<FavoritesResult> list(String userId) async {
    final ids = await _favorites.listForUser(userId);
    return (ok: true, error: null, providerIds: ids);
  }

  Future<FavoritesResult> add(String userId, String providerId) async {
    if (await _providers.byId(providerId) == null) {
      return (ok: false, error: 'not_found', providerIds: null);
    }
    await _favorites.add(userId, providerId);
    return (ok: true, error: null, providerIds: null);
  }

  Future<FavoritesResult> remove(String userId, String providerId) async {
    await _favorites.remove(userId, providerId);
    return (ok: true, error: null, providerIds: null);
  }
}
