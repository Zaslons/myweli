import { type NextRequest, NextResponse } from 'next/server';
import { apiBase } from './server-api';
import {
  PRO_AT_COOKIE,
  PRO_RT_COOKIE,
  PRO_SALON_COOKIE,
  setProSessionCookies,
} from './session';

/// Pro BFF core — mirror of `callApi` (lib/bff.ts) but on the **pro** cookies and
/// refreshing via `POST /auth/provider/refresh`. Keeps the consumer and provider
/// sessions fully separate. Design: docs/design/web-m7-pro-dashboard.md.

export type ApiResult = {
  status: number;
  body: unknown;
  tokens?: { at: string; rt: string };
};

function call(path: string, init: RequestInit, accessToken: string) {
  return fetch(`${apiBase}${path}`, {
    ...init,
    headers: {
      ...(init.headers ?? {}),
      authorization: `Bearer ${accessToken}`,
      ...(init.body ? { 'content-type': 'application/json' } : {}),
    },
  });
}

async function refresh(
  refreshToken: string,
): Promise<{ at: string; rt: string } | null> {
  const r = await fetch(`${apiBase}/auth/provider/refresh`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ refreshToken }),
  });
  if (!r.ok) return null;
  const b = (await r.json().catch(() => ({}))) as {
    accessToken?: string;
    refreshToken?: string;
  };
  return b.accessToken && b.refreshToken
    ? { at: b.accessToken, rt: b.refreshToken }
    : null;
}

/// The backend paths whose acting salon is SESSION-resolved (family B) —
/// the R6 salon selection threads onto exactly these; `/providers/{id}/*`
/// already carries its salon explicitly.
const SALON_SCOPED_PREFIXES = ['/me/provider', '/appointments', '/uploads/sign'];

/// R6: append the selected salon (the httpOnly cookie) as `?salonId=` on
/// the session-resolved paths. The server revalidates the membership on
/// every request (T55) — this only picks WHICH salon the session acts in.
function withSalonSelection(req: NextRequest, path: string): string {
  const selected = req.cookies.get(PRO_SALON_COOKIE)?.value;
  if (!selected) return path;
  if (!SALON_SCOPED_PREFIXES.some((p) => path.startsWith(p))) return path;
  if (path.includes('salonId=')) return path; // an explicit choice wins
  const sep = path.includes('?') ? '&' : '?';
  return `${path}${sep}salonId=${encodeURIComponent(selected)}`;
}

export async function callApiPro(
  req: NextRequest,
  rawPath: string,
  init: RequestInit = {},
): Promise<ApiResult> {
  const path = withSalonSelection(req, rawPath);
  const at = req.cookies.get(PRO_AT_COOKIE)?.value;
  const rt = req.cookies.get(PRO_RT_COOKIE)?.value;
  if (!at && !rt) return { status: 401, body: { error: 'not_authenticated' } };

  let res = at
    ? await call(path, init, at)
    : new Response(null, { status: 401 });
  let tokens: { at: string; rt: string } | undefined;

  if (res.status === 401 && rt) {
    const refreshed = await refresh(rt);
    if (!refreshed) return { status: 401, body: { error: 'session_expired' } };
    tokens = refreshed;
    res = await call(path, init, refreshed.at);
  }
  const body = await res.json().catch(() => ({}));
  return { status: res.status, body, tokens };
}

export function respondPro(result: ApiResult): NextResponse {
  // 204 carries no body (e.g. service delete).
  const res =
    result.status === 204
      ? new NextResponse(null, { status: 204 })
      : NextResponse.json(result.body, { status: result.status });
  if (result.tokens) {
    setProSessionCookies(res, result.tokens.at, result.tokens.rt);
  }
  return res;
}
