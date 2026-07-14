import { NextResponse } from 'next/server';
import { apiBase } from '../../../lib/server-api';

// A same-origin proxy, never build-time content (a parameterless GET would
// otherwise be prerendered — and fail builds without a reachable API).
export const dynamic = 'force-dynamic';

/// BFF: same-origin proxy of the public locality tree (GET /localities —
/// multi-pays T56: read-only, zero PII, parameterless). Client components
/// (pickers, operator catalogs, the salon-time hint label) read it via
/// lib/use-localities.ts; the backend's Cache-Control rides through.
export async function GET() {
  const r = await fetch(`${apiBase}/localities`);
  const body = await r.json().catch(() => ({ countries: [] }));
  const res = NextResponse.json(body, { status: r.status });
  const cache = r.headers.get('cache-control');
  if (cache) res.headers.set('cache-control', cache);
  return res;
}
