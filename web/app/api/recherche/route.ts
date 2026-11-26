import { type NextRequest, NextResponse } from 'next/server';
import { lostBodyIsBadGateway } from '../../../lib/bff';
import { RECHERCHE_PAGE_SIZE } from '../../../lib/discovery/search-pages';
import { apiBase } from '../../../lib/server-api';

/// BFF: one more page of `/recherche` for « Afficher plus de salons »
/// (docs/design/consumer-search.md §3.3, A4w) — a same-origin proxy of the public
/// `GET /providers`, because the browser never calls the API host (lib/api/client.ts).
///
/// It forwards the search's own fields and nothing else, and fixes the page size itself:
/// a caller asking for 50, or for a salon's owner, gets the 24 the page shows. The API
/// validates the text (A4-api) and answers 400 to what it refuses.
const FIELDS = ['q', 'category', 'commune', 'sort', 'availableToday'] as const;

export async function GET(req: NextRequest) {
  const src = req.nextUrl.searchParams;
  const qs = new URLSearchParams();
  for (const key of FIELDS) {
    const v = src.get(key);
    if (v) qs.set(key, v);
  }
  const page = src.get('page') ?? '';
  qs.set('page', /^[1-9][0-9]*$/.test(page) ? page : '1');
  qs.set('pageSize', String(RECHERCHE_PAGE_SIZE));

  const r = await fetch(`${apiBase}/providers?${qs.toString()}`, { cache: 'no-store' });
  const body: unknown = await r.json().catch(() => undefined);
  if (body === undefined) {
    // A lost 2xx body is « we could not ask » (502), never a 200 `{}` that would read as a
    // page of nothing (docs/design/export-unreadable-200.md §7).
    if (lostBodyIsBadGateway(r, {})) {
      return NextResponse.json({ error: 'bad_gateway' }, { status: 502 });
    }
    return NextResponse.json({}, { status: r.status });
  }
  return NextResponse.json(body, { status: r.status });
}
