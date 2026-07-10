# Pro salon lifecycle — registration creates the salon; « Mettre en ligne » gates visibility

| | |
|---|---|
| **Module** | `access` / onboarding — the missing piece between registration and a live listing |
| **Status** | **Built — B1 backend + B2 web** (2026-07-10); B3 app goLive wiring next |
| **Trigger** | **Production bug (user, 2026-07-10):** a freshly registered web pro saw « Une erreur est survenue. Réessayez. » on every dashboard page. Root cause: `POST /auth/provider/register` creates the ACCOUNT only — **no code path anywhere created a salon record** (salons existed solely from seed data), so `GET /me/provider` 403'd on `providerId == null` and every page fell into its error state. The app has the same latent hole; the web e2e stub masked it (pre-linked account) |
| **Decisions (user sign-off, 2026-07-10)** | (1) Registration must yield a working dashboard. (2) **A salon is publicly visible only once it is properly set up — photos, location, everything** — via an explicit go-live step |
| **Out of scope** | The web/app go-live UI (B2/B3 — next PRs) · auto-DELISTING when a live salon later breaks completeness (admin `suspend` covers abuse; no flapping) · requiring KYC to list (see §3) |
| **Cross-refs** | PRD FR-PRO-ONB-001 (guided onboarding « … → go live ») · `mobile/lib/core/utils/onboarding.dart` (the checklist + thresholds this mirrors) · [web-pro-registration.md](web-pro-registration.md) · BACKEND.md **T50/T51** |

## 1. The lifecycle

```
register (web/app) ──creates──▶ salon { status: 'draft' } linked to the account
    draft: dashboard fully works · INVISIBLE publicly (discovery, by-slug,
           sitemap) · bookings refused
owner completes setup ──POST /providers/{id}/publish──▶ status: 'active'
    (server re-checks completeness; incomplete → 409 + the missing list)
admin suspend/restore keeps working as today ('suspended' ⇄ 'active')
```

## 2. B1 — backend

- **`ProvidersRepository.createSalon(...)`** (in-memory + Postgres): a
  minimal, seed-shaped provider document — name/category (mapped from
  `businessType`: salon→salon · barber→barber · spa→spa · nailSalon→nails ·
  massage→massage · other→salon), phone, optional address, empty
  services/artists/gallery, empty availability, rating 0, **`status:
  'draft'`**, unique slug (slugified name + numeric suffix on collision).
- **`SalonProvisioningService.ensureSalon(account)`** — the ONE path that
  creates + links (`provider_users.provider_id`), used by BOTH:
  - **`POST /auth/provider/register`** — provisions right after the account
    is created (web AND app registrations get a working dashboard);
  - **`GET /me/provider`** — **self-healing**: an account with
    `providerId == null` (the already-registered stuck accounts, or a
    partial failure at register time) gets its draft salon created on first
    read instead of 403. No manual repair needed.
- **`POST /providers/{id}/publish`** (provider-only, ownership-scoped like
  every `/providers/{id}/*` write): recomputes completeness **server-side**
  from the stored salon and either flips `status → 'active'` (idempotent)
  or returns **409 `incomplete` + `missing: [...]`**. The gate mirrors the
  app's onboarding checklist thresholds (PRD FR-PRO-ONB-001):
  - `profile` — description AND address AND commune present (« location and
    everything »);
  - `services` — ≥ 3 active services (`kMinServices`);
  - `photos` — ≥ 3 gallery images (`kMinPhotos`, « with pictures »);
  - `availability` — at least one open weekday.
- **Draft hiding** (T51): discovery `query()` excludes `draft` alongside
  `suspended` (both impls) → `/providers`, landings and the sitemap never
  see drafts; `GET /providers/by-slug/{slug}` 404s drafts (the public page);
  booking (`book`) refuses drafts like suspended. The pro's own surfaces
  (`/me/provider`, journal, catalogue…) resolve by account → unaffected.
- **Contract**: `/providers/{id}/publish` documented; register/me-provider
  descriptions updated; web types regenerated (no web code change in B1).

## 2b. B4/B5 — « Aperçu de ma page » (user ask, 2026-07-10)

Before publishing, the owner sees their salon **exactly as a client will**
(the checklist verifies quantities; the preview catches quality — photo
order, cut-off description, a wrong commune placing the map pin off).

- **B4 web (built)**: `/pro/apercu` — outside the dashboard shell (consumer
  chrome) — renders the REAL consumer page component (`ProviderView`) fed
  from `/me/provider`: owner-scoped by construction, **no new endpoint, no
  T51 change** (drafts stay 404 publicly). `preview` mode = a slim owner
  banner, no JSON-LD, no favorite button, booking CTAs disabled
  (« Disponible après la mise en ligne » — drafts refuse bookings anyway).
  Entry points: « Aperçu de ma page » on the GoLiveCard; once live, the
  banner flips to « Voir la page publique » and the pro home gains the same
  link.
- **B5 app (next)**: same idea — the pro app renders the consumer salon
  screen with its own provider data.

## 2c. L1/L2 — the salon's own map pin (user find, 2026-07-10)

The user's post-launch check surfaced it: **nothing could ever set a salon's
coordinates** — the PATCH allowlist had no latitude/longitude, so no real
salon would appear on the discovery map, and its page's Localisation section
would stay address-only forever. The audit also found: the pro APP has no
profile editing at all (web-only, 7.3e-i), the category is frozen at
registration, and `logoUrl` is displayed (app) but never settable (minor,
parked).

- **L1 (built — backend + web)**: `latitude`/`longitude` join the PATCH
  allowlist (validated: a PAIR, −90..90 / −180..180) and **`category`**
  becomes editable (canonical enum). The **publish gate gains `location`**
  — no pin, no go-live (the user's « location and everything » rule; the
  contract's `missing` enum + web checklist updated). Web Profil gets the
  **pin picker**: the shared MapLibre/Positron map — tap to place, drag to
  adjust, « Utiliser ma position » — plus a category dropdown.
- **L2 (built — app)**: « Profil du salon » — the pro app's first listing
  editor (`/pro/salon-profile`, reachable from Profil and the onboarding
  checklist): every allowlisted field + the category dropdown + the pin map
  (flutter_map on the app's CARTO basemap — tap to place, « Utiliser ma
  position » via geolocator). `updateSalonProfile` through the
  interface/mock/API seam (PATCH `/providers/{id}`). The app onboarding
  checklist is now the **exact server-gate mirror**: `location` added,
  `photos` REQUIRED (the stale « upload pipeline pending » optionality
  removed — the pipeline shipped), `deposit` demoted to recommended
  (the server never required it) — « Mettre mon profil en ligne » can no
  longer disagree with the server.

## 3. Decision notes

- **Explicit publish button** (recommended, adopted): the PRD's own funnel
  ends in a « go live » action and the app's onboarding screen already has
  the (placeholder) button — the owner controls the moment; no surprise
  listing while half-configured, no auto-delist flapping.
- **KYC is NOT required to publish** (recommendation): listing friction
  stays low; trust is signalled by the « Vérifié » badge (KYC-gated, as
  today) and **deposits remain verified-only**. One constant to flip if the
  policy hardens later.
- Suspended salons remain reachable via by-slug today (pre-existing
  behaviour, unchanged here) — drafts are NOT, they were never public.

## 4. Threats

- **T50** — publish is ownership-scoped: A's token on B's salon → 403;
  completeness is computed from server state only (a client cannot publish
  an empty salon by lying).
- **T51** — draft leak: drafts absent from discovery/sitemap, 404 on the
  public slug read, bookings refused. Verified by negative tests.

## 5. Tests (B1)

Register → account linked to a draft salon (Google + email identities) ·
`/me/provider` heals a salon-less account (and is idempotent) · publish:
incomplete → 409 with the exact missing keys; complete → active +
discoverable; re-publish idempotent; cross-tenant → 403 · drafts hidden
from query/by-slug/sitemap · booking a draft → refused · PG sections for
`createSalon`/`linkProvider` round-trips.

## 6. Rollout

| PR | Contents | Gate |
|---|---|---|
| **B1 backend** (this) | createSalon + provisioning/heal + publish + draft gating + contract + T50/T51 + tests | analyze 0 · full backend suite |
| B2 web | dashboard draft banner + onboarding checklist card + « Mettre en ligne » (+ stub/e2e) | web gates |
| B3 app | wire the onboarding screen's `_goLive` to `/publish` + draft banner | mobile suite |
