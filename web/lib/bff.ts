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

/// The answer for a 2xx the BFF cannot hand on as one (502, as
/// `app/api/auth/verify` already answers an OK it cannot use). The rotated
/// tokens ride along: the refresh happened, and dropping them would leave the
/// browser holding a refresh token the server has already spent.
export function badGateway(tokens?: { at: string; rt: string }): ApiResult {
  return { status: 502, body: { error: 'bad_gateway' }, tokens };
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
  let body: unknown;
  try {
    body = await res.json();
  } catch {
    // A 2xx whose body is lost between the server and here (cut off, or a
    // proxy's HTML page) is no success: passed on as a 200 `{}`, it read as
    // « the server said nothing » — an empty list in « Mes données ». The
    // server sends a body with every 2xx but a 204, which has none and
    // stays a 204 (docs/design/export-unreadable-200.md §2.1). An error
    // keeps its status; its unreadable body stays `{}`.
    if (res.ok && res.status !== 204) return badGateway(tokens);
    body = {};
  }
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

/// Enrich a list response (`{ items: [...] }`). The server always sends
/// `items` (`routes/appointments/index.dart`), so a 200 without a list lost
/// it on the way: a 502, never `items: []` — « aucun rendez-vous », and an
/// empty section in « Mes données », for a client who has some
/// (docs/design/export-unreadable-200.md §2.1). Any other status passes as
/// it came.
export function enrichAppointments(result: ApiResult): ApiResult {
  if (result.status !== 200) return result;
  const b = result.body as { items?: unknown } | null;
  const items = b?.items;
  if (!Array.isArray(items)) return badGateway(result.tokens);
  return {
    ...result,
    body: { ...b, items: (items as RawAppt[]).map(withSalonEntered) },
  };
}

/// Enrich a single appointment (detail).
export async function enrichAppointment(body: unknown): Promise<unknown> {
  return withSalonEntered(body as RawAppt);
}
