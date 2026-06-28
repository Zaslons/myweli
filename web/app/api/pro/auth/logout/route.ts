import { NextResponse } from 'next/server';
import { clearProSessionCookies } from '../../../../../lib/session';

/// Pro BFF: end the provider web session.
export async function POST() {
  const res = NextResponse.json({ ok: true });
  clearProSessionCookies(res);
  return res;
}
