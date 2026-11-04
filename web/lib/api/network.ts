/// The browser → BFF calls' network layer (docs/design/web-consumer-network-failure.md
/// §2): **no wrapper throws**. A request that got no usable answer is status 0
/// (`ok: false` for a write) — and every page's « not 200 » branch is already
/// its error state with « Réessayer ». Before, a dropped connection rejected
/// through the wrapper into a load that never caught it — an async rejection
/// no error boundary sees — and the page stayed on its skeleton for ever.
///
/// The Pro wrappers (`lib/api/pro.ts`, docs/design/web-pro-network-failure.md)
/// go through the same two functions.

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

// --- a write whose answer is lost (docs/design/write-idempotency.md §4) ------

/// The header the four creating POSTs carry. The BFF hands it to the API on
/// those four routes only (`idempotencyKeyHeader` in `lib/bff.ts`).
export const IDEMPOTENCY_KEY_HEADER = 'Idempotency-Key';

/// How long « already running » (409 `request_in_progress`) is waited for
/// before asking again, and how many times.
export const IN_PROGRESS_WAIT_MS = 800;
export const MAX_IN_PROGRESS_WAITS = 3;

/// One key per SUBMISSION of a form: the same while the form is unchanged —
/// « Réessayer » is the same request, which the server may already have done
/// — a new one as soon as anything in it changed (another slot, another
/// text), and a new one after a success, so that sending the same words
/// again on purpose is a second note, not a replay of the first.
export class SubmissionKey {
  private last?: { form: string; key: string };

  for(form: unknown): string {
    const sig = JSON.stringify(form);
    if (this.last?.form !== sig) {
      this.last = { form: sig, key: crypto.randomUUID() };
    }
    return this.last.key;
  }

  settle(): void {
    this.last = undefined;
  }
}

/// Nothing came back (status 0), or a gateway answered instead of the
/// server: the write may have been done. A 500 is the server's own answer.
function answerLost(status: number): boolean {
  return status === 0 || status === 502 || status === 503 || status === 504;
}

export type IdempotentAnswer<T> = { status: number; body?: T; error?: string };

/// A creating write that can be asked again without risk, because it carries
/// its [key]: the server replays the write it did instead of doing it again.
///
/// - A lost answer — or a 2xx whose body is not [complete] (the deposit block
///   needs the booking's id and amount) — is asked again ONCE, at once, with
///   the same key, without a word: the replay is invisible (owner Q2).
/// - « Already running » waits and asks again, [MAX_IN_PROGRESS_WAITS] times.
/// - Still nothing: status 0 — « nothing answered », and the screen's
///   « Réessayer » sends the same key again.
/// - A refusal is the answer, as it came, with its code.
/// - A 2xx without its body twice is still a success: the write was done.
export async function sendIdempotent<T>(
  url: string,
  init: RequestInit,
  key: string,
  opts: {
    complete: (body: T | undefined) => boolean;
    wait?: (ms: number) => Promise<void>;
  },
): Promise<IdempotentAnswer<T>> {
  const wait = opts.wait ?? ((ms) => new Promise<void>((r) => setTimeout(r, ms)));
  const headers = { ...(init.headers as Record<string, string>), [IDEMPOTENCY_KEY_HEADER]: key };
  let askedAgain = false;
  let waits = 0;
  for (;;) {
    const res = await send(url, { ...init, headers });
    if (res.ok) {
      const body = await readJson<T>(res);
      if (opts.complete(body) || askedAgain) return { status: res.status, body };
      askedAgain = true;
      continue;
    }
    if (answerLost(res.status)) {
      if (askedAgain) return { status: 0 };
      askedAgain = true;
      continue;
    }
    const error = (await readJson<{ error?: string }>(res))?.error;
    if (res.status === 409 && error === 'request_in_progress') {
      if (waits >= MAX_IN_PROGRESS_WAITS) return { status: 0 };
      waits += 1;
      await wait(IN_PROGRESS_WAIT_MS);
      continue;
    }
    return { status: res.status, error };
  }
}
