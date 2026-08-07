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
  const res =
    result.status === 204
      ? new NextResponse(null, { status: 204 })
      : NextResponse.json(result.body, { status: result.status });
  if (result.tokens) setSessionCookies(res, result.tokens.at, result.tokens.rt);
  return res;
}

// --- appointment enrichment ---------------------------------------------------
//
// **The fetching is gone, and that is the change.** This block used to call
// the PUBLIC `GET /providers/{id}` once per distinct salon just to print a
// name, and returned `{}` when that failed — so a client looking at their own
// booking silently lost the salon's name, the « Voir le salon » link, the
// contact buttons, the service list and the Mobile Money handle they owed a
// deposit to. Decision C closes that route for a salon that is `draft` or
// `suspended`, which would have made the silent version the normal one.
//
// The server enriches now (`withProviderFacts`): `/appointments` is
// authenticated and scoped to the caller, so it is the endpoint that owns the
// relationship and the only one that may serve a hidden salon's facts without
// giving an anonymous caller an enumeration oracle. What is left here is the
// one fact the server does not send.

type RawAppt = Record<string, unknown> & { userId?: string };

/// `salonEntered` — was this booking typed by the SALON rather than made by
/// the client? The backend marks it with a sentinel `userId`.
///
/// Mobile derives the same fact from `clientName != null`. One product fact,
/// two client derivations: a candidate for the backend to own, recorded in
/// `salon-state-and-refusals.md` §9 rather than fixed here.
function withSalonEntered(a: RawAppt) {
  return { ...a, salonEntered: a.userId === 'manual' };
}

/// Enrich a list response (`{ items: [...] }`).
export async function enrichAppointments(body: unknown): Promise<unknown> {
  const b = body as { items?: RawAppt[] };
  return { ...b, items: (b.items ?? []).map(withSalonEntered) };
}

/// Enrich a single appointment (detail).
export async function enrichAppointment(body: unknown): Promise<unknown> {
  return withSalonEntered(body as RawAppt);
}
