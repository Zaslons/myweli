# Session refresh — one exchange per session, the right endpoint per principal

| | |
|---|---|
| **Status** | Built (2026-10-11) |
| **Owner** | mobile |
| **Last updated** | 2026-10-11 |
| **PRD ref / phase** | Auth & session (BACKEND.md §3 — rotating refresh, reuse → revoke) · V1 |
| **ROADMAP entry** | [2026-10-11-session-refresh](../roadmap/entries/2026-10-11-session-refresh.md) |
| **Skills checked** | myweli-dev-guardrails · myweli-verification-guardrails |

## 1. Goal & scope

A salon owner who allows notifications was **signed out of the Pro app on
every cold start** once the 15-minute access token had expired. This part makes
a silent refresh unable to end a live session by accident. In scope: the app's
`RefreshingHttpClient`, the Pro push-registration wiring, and guards for both.
Out of scope: the backend (§7).

## 2. What production showed (2026-10-11, Pro build 555, iOS)

Cloud Run request log, Dart user agent, one cold start of the owner's demo
session at 10:47:56 UTC:

| t (ms) | request | status |
|---|---|---|
| 289 | `GET /me/provider` | 401 — access token expired |
| 315 | `POST /me/devices` | 401 — same, in parallel (push registration) |
| 394 | `POST /auth/provider/refresh` | 200 — the pro service refreshes correctly |
| 412 | `POST /auth/refresh` | **401** — push registration refreshes the PROVIDER session on the CONSUMER endpoint |
| 533 | `GET /me/provider` | 200 — retried with the new token |
| +38 s | `POST /auth/provider/email/otp/request` → `verify` | the owner had to sign in again |

A refused refresh means "this session is dead", so the client cleared the
provider store — signing the owner out a few milliseconds after a successful
refresh.

The same log holds **pairs of `/auth/refresh` within 12 ms** (2026-09-12,
10-07, 10-10): two services refreshing one session concurrently with the same
single-use token. They both got 200 only because the server's check-then-mark
is not atomic (§7); with the server's documented reuse detection
(`refresh_reused` → revoke the family) the second one signs the user out.

## 3. Root causes

1. **Wrong endpoint.** `proDeviceRegistrationService` (DI) rode the provider
   session store with `ApiDeviceRegistrationService`'s only refresh path, the
   consumer `/auth/refresh`.
2. **No single flight.** Every `Api*Service` builds its own
   `RefreshingHttpClient` over the same stored session, and nothing stopped two
   of them exchanging the same refresh token at once. A cold start fires
   several authenticated requests together (membership, push registration,
   salons).

## 4. The fix

- `ApiDeviceRegistrationService` takes `refreshPath` (as
  `ApiNotificationService` already did); DI passes `/auth/provider/refresh`
  for the Pro instance. The two provider image-upload slots now name it
  explicitly too, so one rule covers every provider-session wiring.
- `SessionStore.identity` names the persisted session across instances
  (`SecureSessionStore` → its storage key; `InMemorySessionStore` → itself).
- `RefreshingHttpClient` keeps one in-flight exchange per
  `(store identity, base URL + refresh path)`, shared by all instances:
  concurrent 401s join it and retry with its token.
- After a 401, if the stored access token is no longer the one the request
  used, another request already rotated the session: retry with the stored
  token instead of exchanging again.

Unchanged on purpose: a transport failure still keeps the session; a genuine
rejection still ends it.

## 5. Tests (all watched failing — see the commit body)

- `test/unit/refreshing_http_client_test.dart` — against a mock server with
  single-use refresh tokens and reuse detection: two clients on one session,
  two concurrent 401s → exactly one exchange, both retried, still signed in;
  different sessions never share; equal `SecureSessionStore` keys share an
  identity; a late 401 after a rotation retries with the stored token.
- `test/unit/api_device_registration_service_test.dart` — on the provider
  session an expired token refreshes on `/auth/provider/refresh` only.
- `test/unit/di_refresh_path_pin_test.dart` — DI builds the real services only
  with `USE_API_BACKEND`, which no test sets, so it reads the wiring (comments
  stripped): every service on the provider store names the provider path, no
  consumer-store service does, and every `RefreshingHttpClient` over a
  `_providerSessionStore` names it.

## 6. Rollout

App-only, ships in the next build of both apps (Pro build 556). No backend or
contract change. Verify on the device: sign in, wait > 15 min, kill and reopen
the app → still signed in; the request log shows one refresh, on the provider
endpoint, per cold start.

## 7. Follow-ups

- **Backend — make rotation atomic.** Two concurrent refreshes with one token
  both succeeded (§2): the reuse check can be raced, which weakens theft
  detection. Fix with a conditional update (`… WHERE rotated = false
  RETURNING`). Ship it **after** this client is out: before, it would turn
  today's lucky double refreshes into sign-outs.
- The Pro splash calls `loadCurrentProvider()` while the constructor's call is
  still running (pro-open-animation.md); harmless with single flight, but the
  duplicate requests should be de-duplicated there.
