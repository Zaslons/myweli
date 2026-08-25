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

**In scope:** an outbound POST to a Vercel Deploy Hook on ~~the three events~~
the **five status transitions** that change the listable set (§2, corrected
2026-08-25). **Out of scope:** per-page on-demand revalidation
(`revalidatePath` cannot add params to a closed set), and any read path.

## 2. The events — corrected 2026-08-25

~~`/sitemap/providers` returns `query()`, which lists non-suspended providers.
So the set changes on exactly three transitions, and all three are already
single choke points: salon created, salon suspended, salon restored.~~

**That premise was the root error of this spec.** `query()` excludes
**drafts too** (`status NOT IN ('suspended', 'draft')` —
`salon_visibility.dart` is the canonical statement), and every salon is
CREATED `'draft'`. Two consequences, both real in production until
2026-08-25:

- the "salon created" fires built **nothing** — the new row was not in the
  set — while consuming the cooldown window, where they could swallow a real
  publish's fire seconds later;
- the transition that actually grows the set, **publish** (`draft → active`),
  fired nothing at all, so a salon that published got a public page that
  404s until an unrelated deploy — while `/recherche` (force-dynamic) linked
  to it and the sitemap advertised it to Google.

The set changes on exactly **five** transitions, each fired inside the
service that writes the status (the `BudgetedEmailProvider` placement — no
caller can route around it), once per logical operation:

| transition | seam | reason string |
|---|---|---|
| publish (`draft → active`) | `SalonProvisioningService.publish` | `salon.published` |
| admin suspend | `AdminProviderService._setStatus` | `provider.suspend` |
| admin restore | `AdminProviderService._setStatus` | `provider.restore` |
| republish on payment (`draft → active`) | `SalonSubscriptionService.markPaid` | `salon.republished` |
| billing unpublish (`active → draft`) | `SubscriptionScheduler.tick` — **once per tick**, however many salons expired | `salon.unpublished` |
| account erasure (`active → draft` per owned salon) | `ProviderAccountService.deleteAccount` — **once per account**, guarded on a prior `'active'` | `account.erased` |

(Six rows because suspend/restore share a seam.) Salon **creation** is
deliberately not an event: `SalonDirectoryService` no longer takes a notifier
at all, so a creation fire is uncompilable rather than merely absent, and
`salon_lifecycle_test.dart` pins that `ensureSalon` fires nothing.

KYC approval deliberately does **not** fire: `query()` does not filter on
verification, so approving a salon does not change the listable set.

**The wiring is guarded**: `SalonProvisioningService` was constructed in
`dependencies.dart` WITHOUT the notifier from the day the seam was written
until 2026-08-25 — an optional param whose omission compiles clean and logs
nothing, so its fire had never once run in production.
`test/site/site_rebuild_wiring_test.dart` now greps the composition root
(comments stripped) for `rebuild: siteRebuildNotifier` on all five
constructions, and for its absence on `SalonDirectoryService`.

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
  `kRebuildCooldown` (60s) per process. ~~Further events inside the window are
  dropped, not queued. A dropped event is safe: the next build picks up the
  current state, since the slug set is read fresh at build.~~ **Corrected
  2026-08-25: there is no "next build".** Every trigger IS a set change, so a
  dropped last-event-in-a-burst never gets picked up — two salons publishing
  <60s apart would leave the second 404ing indefinitely. In-window events are
  now **coalesced into one trailing fire** at window expiry (a `Timer`
  carrying the last deferred reason). The bound is unchanged: at most one
  build per window per process; the `skipped` log token is kept because the
  alert filter and both runbooks grep it. Residual: an instance dying with a
  pending timer loses the fire — the same outcome the drop guaranteed, so
  strictly no worse.
- Threat model **T68**.

## 6. Failure behaviour

**Fails open, loudly.** A failed hook must never fail the admin action or the
salon registration that triggered it: the write already succeeded, and a 500 on
"we could not ask Vercel to rebuild" would be a self-inflicted outage on a
correct operation. It is caught, logged at WARNING with the reason, and dropped.

The residual is honest and written down: if the hook fails, the new salon's page
404s until the next deploy. That is strictly better than today, where it always
would.

## 7. Testing plan — revised 2026-08-25

- fires on publish, republish-on-payment, billing unpublish (once per tick,
  proven with a two-salon fixture), erasure (once per account, guarded on a
  prior `'active'`), suspend, restore
- does **not** fire on: creation (`ensureSalon`), a gate-blocked publish, an
  idempotent re-publish, a markPaid whose gate fails (stays draft), an
  enforcement-off tick, an all-draft erasure, KYC approval
- an exception from the hook does not propagate to the caller (posture pinned
  for both `AdminProviderService` and `publish`)
- in-window events coalesce into ONE trailing fire carrying the last reason
  (short real cooldowns — a `Timer` cannot be driven by the injected clock)
- with the env unset, the no-op is wired and nothing is attempted
- the composition root passes the notifier to all five services, and NOT to
  `SalonDirectoryService` (source-level, comments stripped first)

Each watched red — sixteen mutations on 2026-08-25, one of which SURVIVED the
first pass (the markPaid fire hoisted out of the gate branch; no test covered
"unpublished but incomplete", so that test now exists) and one of which was
correctly survived (`??=` → `=` on the trailing timer: the stacked timers all
find the pending reason already consumed — the consumption holds the bound,
not the `??=`).

## 7.1 What is proven, and what is not (2026-08-21)

| link | evidence |
|---|---|
| the secret exists, right shape, no trailing newline | checked; a newline would make `Uri.tryParse` fail and silently wire the no-op |
| mounted on the serving revision | `myweli-api-00028-zhs` |
| the HTTP notifier is wired, not the no-op | no `WEB_DEPLOY_HOOK_URL` warning in the boot log |
| the hook URL triggers a real build | `HTTP 201` + a `PENDING` job + a Vercel deployment |
| **Cloud Run reaching Vercel on a salon change** | **not exercised** |

The last row cannot be closed until a real salon exists — production holds zero,
so nothing can be created, suspended or restored. *(2026-08-25: the transition
that will actually close it is the first salon's PUBLISH — creation no longer
fires at all, per §2.)* Two things cover it:

- the **alert** `infra/gcp/96-rebuild-hook-alert.sh`, which fires on
  `site_rebuild FAILED`. The notifier fails open, so a failure is otherwise
  invisible: the operator sees a salon created, the public page 404s, and
  nothing connects the two.
- **LAUNCH.md §6.4**, the checklist for the day the first salon appears.

The alert covers the failure; the checklist covers the confirmation. Neither
alone is enough — an alert that never fires is indistinguishable from a healthy
system, and a checklist nobody re-reads is a wish.

## 8. Open questions

- **Build cost at scale.** One rebuild per approval is fine at tens-to-hundreds
  of salons, where approvals are manual and rare. If salon signup ever becomes
  self-serve and high-volume, this needs batching (a debounce window measured in
  minutes) or a move to on-demand ISR with an open param set.
