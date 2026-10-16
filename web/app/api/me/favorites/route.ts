import type { NextRequest } from 'next/server';
import { badGateway, callApi, respond } from '../../../../lib/bff';

/// BFF: the caller's favorite salons, straight through.
///
/// **The fan-out is gone.** This used to fetch the PUBLIC `GET /providers/{id}`
/// once per favorite and `.filter(Boolean)` the failures away — so a favorite
/// whose salon stopped simply vanished from the list AND from the RGPD export,
/// on a page whose own copy promises « profil, rendez-vous et favoris ». With
/// the list empty the account then rendered « Aucun favori », telling a user
/// with favorites that they had none.
///
/// `/me/favorites` hydrates server-side now (Decision C): authenticated, no
/// status filter, each salon carrying its `status` so a stopped one is MARKED
/// rather than lost. `favorites` keeps its name so the client contract does
/// not move.
export async function GET(req: NextRequest) {
  const result = await callApi(req, '/me/favorites');
  if (result.status === 200) {
    const providers = (result.body as { providers?: unknown } | null)
      ?.providers;
    // The server always sends `providers` (`FavoritesService.list`): a 200
    // without the list lost it on the way. `[]` here was « Aucun favori »
    // and an empty section in « Mes données » for someone who has some
    // (docs/design/export-unreadable-200.md §2.1).
    if (!Array.isArray(providers)) return respond(badGateway(result.tokens));
    result.body = { favorites: providers };
  }
  return respond(result);
}
