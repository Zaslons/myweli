/// The browser → BFF calls' network layer (docs/design/web-consumer-network-failure.md
/// §2): **no wrapper throws**. A request that got no usable answer is status 0
/// (`ok: false` for a write) — and every page's « not 200 » branch is already
/// its error state with « Réessayer ». Before, a dropped connection rejected
/// through the wrapper into a load that never caught it — an async rejection
/// no error boundary sees — and the page stayed on its skeleton for ever.
///
/// `lib/api/pro.ts` carries its own copy of `send` / `readJson` (the Pro
/// change, docs/design/web-pro-network-failure.md, landed separately).

/// The app's no-network sentence (`_networkError` in every `api_*_service.dart`).
export const NO_CONNECTION_MESSAGE = 'Pas de connexion. Réessayez.';

/// The sentence for a write the BFF refused, when the screen has none of its
/// own: the app's fallback on the ♥ (`provider_card.dart`), `ErrorState`'s
/// default — and `lib/pro/team.ts`'s GENERIC_ERROR_MESSAGE, word for word.
export const GENERIC_ERROR_MESSAGE = 'Une erreur est survenue. Réessayez.';

/// What a failed write says (docs/design/web-consumer-optimistic-revert.md
/// §3.1): `NO_CONNECTION_MESSAGE` when nothing answered (status 0 — `send()`'s
/// network error), the screen's own sentence for any other status.
export function writeFailureMessage(
  status: number,
  otherwise: string = GENERIC_ERROR_MESSAGE,
): string {
  return status === 0 ? NO_CONNECTION_MESSAGE : otherwise;
}

/// `fetch` that never throws. A request that never got an answer (no
/// network, the connection dropped) is `Response.error()` — the Fetch
/// standard's own network error: status 0, `ok` false, an empty body — so each
/// wrapper's `!res.ok` branch reads it as one more non-2xx, with no error code.
export async function send(url: string, init?: RequestInit): Promise<Response> {
  try {
    return await fetch(url, init);
  } catch {
    return Response.error();
  }
}

/// A 2xx body, or `undefined` when it cannot be read (the connection dropped
/// mid-body, or something other than the BFF answered). A read turns that
/// into status 0 — never an empty list nobody sent; a write stays `ok` (the
/// server acted) without its payload.
export async function readJson<T>(res: Response): Promise<T | undefined> {
  try {
    return ((await res.json()) as T | null) ?? undefined;
  } catch {
    return undefined;
  }
}
