# Team access R2a — salon offers & billing states (module `access`/`finance`)

**Status:** Built (PR feat/team-access-r2a-offers) · **Module doc:**
[modules/access.md](../modules/access.md) (pricing-pivot sign-off block) ·
**Backend + contract + one admin-console button.** UIs (offer picker,
banners) land in R3/R5.

## Goal & scope

The pricing pivot's server side: offers hang on the SALON (Pro 5 places ·
Business 15 · Réseau 15/salon, custom pricing) — a free, time-unlimited
setup state, **3 mois offerts** starting when the salon picks its offer
(one trial per salon), expiry → J-14/J-7/J-1 warnings → **7 jours de
grâce** → **unpublish** (draft + T51 — the journal, existing bookings and
data stay fully usable; never a lockout) → the admin marks the manual
payment → republish. Enforcement is **config-driven**
(`SUBSCRIPTION_ENFORCEMENT`, default off — cold-start leniency).

## Data (migration `0028_salon_subscriptions`)

- `provider_subscriptions(provider_id PK→providers, tier, trial_ends_at,
  paid_until, unpublished_at, chosen_at, updated_at)` — a SEPARATE table:
  the public provider payload serializes the whole `data` blob, so
  subscription state must never live there (leak-proof by construction).
- `subscription_notices(provider_id, kind, sent_at, PK(provider_id, kind))`
  — the idempotency log for warnings (the `appointment_reminders` pattern).
- **Backfill:** every ACTIVE salon → `('pro', now() + 90 jours)` — the
  user-confirmed grandfather (existing salons are test data).

## Derived state (`SalonSubscriptionService`)

`status = trial` (now < trialEndsAt) · `paid` (paidUntil > now) · `grace`
(past both, ≤ +7 j) · `expired`. Payload adds `graceEndsAt` and
`seats {cap, used}` (used = `provider_members` invited+active, owner
included). `chooseOffer` (owner, `Cap.subscriptionManage`): first choice
starts the ONE trial; tier switches keep the clock; an expired salon's
re-choice → 409 `trial_used` (payment goes through « Nous contacter »).
`markPaid(adminId, providerId, months)`: `paid_until = max(now, current) +
months`, republishes a billing-unpublished salon when the publish gate
passes; admin-audited (`subscription.paid`).

## Enforcement & warnings

`SubscriptionScheduler.tick(now)` behind
`POST /internal/cron/subscriptions` (same `CRON_SECRET` gate as the
reminders cron): J-14/J-7/J-1/grâce/unpublished notices — branded email
(the OTP template family) + best-effort push to the owner — each
once-per-kind via `subscription_notices`. Unpublish flips `status→draft`
ONLY when enforcement is on and grace has ended.

## Gates

- **Publish** now requires a live offer: no row or `expired` → the 409
  `incomplete` payload gains the `offer` missing-key (clients map it to
  « Choisissez une offre » in R3/R5).
- `/me/subscription` (legacy, consumed verbatim by the app/web/e2e-stub)
  keeps its `{tier: free|pro, status, trialEndsAt, trialDaysLeft}` shape —
  now derived from the salon row (`pro|business|reseau → 'pro'`); accounts
  without a salon/row fall back to the old account-age derivation.

## Contract

`GET/PUT /providers/{id}/subscription` (owner) · `POST
/admin/providers/{id}/subscription/paid` (admin, audited) · the
`SalonSubscription` schema · error codes `invalid_tier`, `trial_used`.

## Threat model — T54

Subscription state is server-owned: the owner sets only `tier` (pre-expiry),
`paid_until` flips only through the audited admin action, enforcement only
through the secret-gated cron, and the state never enters a public payload
(separate table, never merged into `data`).

## Tests

State-boundary unit suite (trial/paid/grace/expired edges, one-trial rule,
clock-keeping switches, seat counting) · route handlers success + 4xx + 405
· scheduler idempotency + enforcement-gating + republish · `/me/subscription`
compat (grandfathered owner + fallback) · security negatives (cross-salon
403, consumer 403, cron secret).
