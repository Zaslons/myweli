import { NextResponse } from 'next/server';
import { clearSessionCookies } from '../../../../lib/session';

/// BFF: end the web session (clear the httpOnly cookies).
export async function POST() {
  const res = NextResponse.json({ ok: true });
  clearSessionCookies(res);
  return res;
}
