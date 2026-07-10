import { type NextRequest, NextResponse } from 'next/server';
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
  const body = await r.json().catch(() => ({}));
  return NextResponse.json(body, { status: r.status });
}
