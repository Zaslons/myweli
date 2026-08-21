# Web rebuild on salon visibility change — design spec

> **Module:** M-web-glue · **Surface:** `backend/` → Vercel
> **Status:** Built · **Threat model:** [BACKEND.md](../BACKEND.md) §7 T68
> **Related:** [web-m1-backend-glue.md](web-m1-backend-glue.md)

## 0. Why this exists

The web's `/[slug]` route now sets `dynamicParams = false`. That is the **only**
mechanism that makes Next 14 serve a real 404 in the HTML: `notFound()` produces
a 44-character `__next_error__` shell at request time *and* when prerendered
from a page, so the fix is to make an unknown slug never enter the route at all
(measured — see `web/tests/e2e/served-html.spec.ts`).

The cost is that the slug set is fixed at **build** time. A salon that becomes
publicly listable after the last build would 404 until the next one. This closes
that gap: the backend asks Vercel to rebuild whenever the listable set changes.

## 1. Goal & scope

**Goal.** `GET /sitemap/providers` and the web's prebuilt slug set stay in
agreement without anyone remembering to deploy.

**In scope:** an outbound POST to a Vercel Deploy Hook on the three events that
change the listable set. **Out of scope:** per-page on-demand revalidation
(`revalidatePath` cannot add params to a closed set), and any read path.

## 2. The events

`/sitemap/providers` returns `query()`, which lists non-suspended providers. So
the set changes on exactly three transitions, and all three are already single
choke points:

| event | seam |
|---|---|
| salon created | `SalonDirectoryService` · `SalonProvisioningService` |
| salon suspended | `AdminProviderService._setStatus` |
| salon restored | `AdminProviderService._setStatus` |

KYC approval deliberately does **not** fire: `query()` does not filter on
verification, so approving a salon does not change the listable set.

## 3. Contract

No API change. One outbound `POST` with an empty body to the hook URL — Vercel's
Deploy Hooks take no payload.

## 4. Architecture

`SiteRebuildNotifier` (interface) in `lib/src/site/`, mirroring
`MessagingProvider`: an HTTP implementation and a no-op. Services depend on the
interface; `dependencies.dart` picks the implementation from the environment.

**Absent configuration is the default and is not an error.** With
`WEB_DEPLOY_HOOK_URL` unset the no-op is wired, so dev, CI and any self-hosted
run behave exactly as before.

## 5. Security & authz

- The hook URL **is a secret** — anyone holding it can trigger unlimited builds.
  Secret Manager, never a manifest literal, never logged. The notifier logs the
  *reason* and the *outcome*, never the URL.
- No user input reaches the request: the body is empty and the URL comes from
  the environment, so there is nothing to inject.
- **Denial of wallet** is the real risk: builds cost money and a suspend/restore
  loop could be driven by an admin. Bounded by a **cooldown** — one build per
  `kRebuildCooldown` (60s) per process; further events inside the window are
  dropped, not queued. A dropped event is safe: the next build picks up the
  current state, since the slug set is read fresh at build.
- Threat model **T68**.

## 6. Failure behaviour

**Fails open, loudly.** A failed hook must never fail the admin action or the
salon registration that triggered it: the write already succeeded, and a 500 on
"we could not ask Vercel to rebuild" would be a self-inflicted outage on a
correct operation. It is caught, logged at WARNING with the reason, and dropped.

The residual is honest and written down: if the hook fails, the new salon's page
404s until the next deploy. That is strictly better than today, where it always
would.

## 7. Testing plan

- fires on create, on suspend, on restore
- does **not** fire on KYC approval (the set did not change)
- an exception from the hook does not propagate to the caller
- the cooldown drops a second event inside the window and allows one after it
- with the env unset, the no-op is wired and nothing is attempted

Each watched red.

## 8. Open questions

- **Build cost at scale.** One rebuild per approval is fine at tens-to-hundreds
  of salons, where approvals are manual and rare. If salon signup ever becomes
  self-serve and high-volume, this needs batching (a debounce window measured in
  minutes) or a move to on-demand ISR with an open param set.
