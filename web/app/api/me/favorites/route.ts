import type { NextRequest } from 'next/server';
import { callApi, respond } from '../../../../lib/bff';
import { apiBase } from '../../../../lib/server-api';

/// BFF: the caller's favorites — ids from /me/favorites, enriched server-side to
/// full providers (public reads) for the cards.
export async function GET(req: NextRequest) {
  const result = await callApi(req, '/me/favorites');
  if (result.status === 200) {
    const ids =
      ((result.body as { providerIds?: string[] }).providerIds ?? []).filter(
        Boolean,
      );
    const favorites = (
      await Promise.all(
        ids.map(async (id) => {
          const r = await fetch(`${apiBase}/providers/${id}`);
          return r.ok ? await r.json() : null;
        }),
      )
    ).filter(Boolean);
    result.body = { favorites };
  }
  return respond(result);
}
