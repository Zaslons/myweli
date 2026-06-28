import { type NextRequest, NextResponse } from 'next/server';
import { apiBase } from './server-api';
import {
  PRO_AT_COOKIE,
  PRO_RT_COOKIE,
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

export async function callApiPro(
  req: NextRequest,
  path: string,
  init: RequestInit = {},
): Promise<ApiResult> {
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
  const res = NextResponse.json(result.body, { status: result.status });
  if (result.tokens) {
    setProSessionCookies(res, result.tokens.at, result.tokens.rt);
  }
  return res;
}
