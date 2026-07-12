import { type NextRequest, NextResponse } from 'next/server';
import { callApiPro } from '../../../../../lib/bff-pro';
import {
  clearProSalonCookie,
  setProSalonCookie,
  setProSessionCookies,
} from '../../../../../lib/session';

/// Pro BFF: switch the acting salon (module `access` R6). The selection is
/// VALIDATED against the backend BEFORE the httpOnly cookie is set — a
/// forged/revoked salon id never poisons the cookie (T55; the uniform 403
/// flows back). `{salonId: null}` clears the selection (back to the default
/// salon). A 200 returns the SELECTED salon's /me/provider payload so the
/// client reshapes without an extra probe.
export async function POST(req: NextRequest) {
  const { salonId } = await req.json().catch(() => ({}));

  if (salonId === null || salonId === undefined || salonId === '') {
    const res = NextResponse.json({ ok: true });
    clearProSalonCookie(res);
    return res;
  }
  if (typeof salonId !== 'string') {
    return NextResponse.json({ error: 'invalid_input' }, { status: 400 });
  }

  const probe = await callApiPro(
    req,
    `/me/provider?salonId=${encodeURIComponent(salonId)}`,
  );
  if (probe.status !== 200) {
    const res = NextResponse.json(probe.body, { status: probe.status });
    if (probe.tokens) {
      setProSessionCookies(res, probe.tokens.at, probe.tokens.rt);
    }
    return res;
  }
  const res = NextResponse.json(probe.body, { status: 200 });
  if (probe.tokens) {
    setProSessionCookies(res, probe.tokens.at, probe.tokens.rt);
  }
  setProSalonCookie(res, salonId);
  return res;
}
