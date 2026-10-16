import { type NextRequest, NextResponse } from 'next/server';
import { lostBodyIsBadGateway } from '../../../lib/bff';
import { apiBase } from '../../../lib/server-api';

/// BFF: public slot lookup (same-origin proxy of GET /availability).
export async function GET(req: NextRequest) {
  const src = req.nextUrl.searchParams;
  const qs = new URLSearchParams();
  for (const key of ['providerId', 'date', 'serviceIds', 'durationMinutes', 'artistId']) {
    const v = src.get(key);
    if (v) qs.set(key, v);
  }
  const r = await fetch(`${apiBase}/availability?${qs.toString()}`);
  const body: unknown = await r.json().catch(() => undefined);
  if (body === undefined) {
    // A lost 2xx body is « we could not ask » (502), never a 200 `{}` that
    // reads as « no opening that day »; an error keeps its status — 404 is
    // « gone » for the booking flow (docs/design/export-unreadable-200.md §7).
    if (lostBodyIsBadGateway(r, {})) {
      return NextResponse.json({ error: 'bad_gateway' }, { status: 502 });
    }
    return NextResponse.json({}, { status: r.status });
  }
  return NextResponse.json(body, { status: r.status });
}
