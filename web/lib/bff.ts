import { type NextRequest, NextResponse } from 'next/server';
import { apiBase } from './server-api';
import { AT_COOKIE, RT_COOKIE, setSessionCookies } from './session';

/// BFF core: call the dart_frog API under the session, with **silent refresh**.
/// Reads the access cookie; on 401 uses the refresh cookie → POST /auth/refresh →
/// rotates → retries once → surfaces new tokens for the handler to re-cookie.
/// Design: docs/design/web-m6-account.md.

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
  const r = await fetch(`${apiBase}/auth/refresh`, {
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

export async function callApi(
  req: NextRequest,
  path: string,
  init: RequestInit = {},
): Promise<ApiResult> {
  const at = req.cookies.get(AT_COOKIE)?.value;
  const rt = req.cookies.get(RT_COOKIE)?.value;
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

/// Build the handler's NextResponse, re-cookie-ing if the session was refreshed.
export function respond(result: ApiResult): NextResponse {
  const res = NextResponse.json(result.body, { status: result.status });
  if (result.tokens) setSessionCookies(res, result.tokens.at, result.tokens.rt);
  return res;
}

// --- appointment enrichment (provider name/slug + service names) -------------

type RawAppt = Record<string, unknown> & {
  providerId?: string;
  serviceIds?: string[];
  userId?: string;
};

type ProviderSummary = {
  name?: string;
  slug?: string;
  services?: { id: string; name: string }[];
};

async function providerSummary(id: string): Promise<ProviderSummary> {
  const r = await fetch(`${apiBase}/providers/${id}`);
  if (!r.ok) return {};
  return (await r.json().catch(() => ({}))) as ProviderSummary;
}

function enrichOneWith(a: RawAppt, p: ProviderSummary) {
  const byId = new Map((p.services ?? []).map((s) => [s.id, s.name]));
  return {
    ...a,
    providerName: p.name,
    providerSlug: p.slug,
    serviceNames: (a.serviceIds ?? [])
      .map((id) => byId.get(id))
      .filter((n): n is string => Boolean(n)),
    salonEntered: a.userId === 'manual',
  };
}

/// Enrich a list response (`{ items: [...] }`), fetching each distinct provider
/// once (server-side, internal — small N per user).
export async function enrichAppointments(body: unknown): Promise<unknown> {
  const b = body as { items?: RawAppt[] };
  const items = b.items ?? [];
  const ids = [...new Set(items.map((a) => a.providerId).filter(Boolean))];
  const summaries = new Map<string, ProviderSummary>(
    await Promise.all(
      ids.map(
        async (id) => [id!, await providerSummary(id!)] as const,
      ),
    ),
  );
  return {
    ...b,
    items: items.map((a) =>
      enrichOneWith(a, summaries.get(a.providerId ?? '') ?? {}),
    ),
  };
}

/// Enrich a single appointment (detail).
export async function enrichAppointment(body: unknown): Promise<unknown> {
  const a = body as RawAppt;
  if (!a.providerId) return a;
  return enrichOneWith(a, await providerSummary(a.providerId));
}
