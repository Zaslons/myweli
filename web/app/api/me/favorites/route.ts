import type { NextRequest } from 'next/server';
import { callApi, respond } from '../../../../lib/bff';

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
    const b = result.body as { providers?: unknown[] };
    result.body = { favorites: b.providers ?? [] };
  }
  return respond(result);
}
