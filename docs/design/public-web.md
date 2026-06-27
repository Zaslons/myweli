# Public web surface — SSR provider pages, SEO & web booking (FR-WEB-PP/MP)

| | |
|---|---|
| **Requirements** | FR-WEB-PP-001..005, FR-WEB-MP-001 [V1] (PP-006 / MP-002/003 = V2). |
| **Phase** | V1 — the last remaining V1 **feature** gap (ROADMAP §1.8). |
| **Stack (OQ-8 resolved 2026-06-28)** | **dart_frog SSR (Dart)** — server-rendered HTML from a dedicated public web app that reuses the backend's data layer. *Not* Flutter Web (no SEO); *not* a separate JS/React stack (avoids a second language/toolchain + duplicated DTOs/tokens for a solo Dart team). The PRD's hard constraint is crawlable SSR HTML (FR-WEB-PP-002) — dart_frog satisfies it. |
| **Status** | Plan / spec — **awaiting sign-off**. Multi-PR; nothing built yet. |

## 1. Goal & scope
Give every provider a fast, shareable, **SEO-ranking** public page
(`myweli.ci/<slug>`) — the "single biggest organic-acquisition channel" — plus
SEO landing pages and a **no-install web booking** funnel. Mobile-web first (most
traffic is mobile browsers).

**In V1:** provider page (PP-001/002), web booking funnel (PP-003), no-custody web
deposit (PP-004 — see §2), "open in app" banner (PP-005), SEO landing /
category·commune pages (MP-001), `sitemap.xml` + `robots.txt` + structured data.
**Deferred (V2):** per-provider custom branding (PP-006), full web marketplace
browse/search/login/my-bookings (MP-002/003).

## 2. Corrections to keep the docs honest
- **FR-WEB-PP-004 (deposit):** the PRD says "aggregator hosted/redirect flow" —
  this **conflicts with the no-custody decision** (OQ-1/OQ-4). The web deposit
  **mirrors the app**: a facilitated **Wave deep link / copyable number + amount**,
  client authorises in their own app; Myweli never holds funds. (PRD updated.)
- **Slug (FR-WEB-PP-001):** no `slug` exists yet → a small backend add (§5, PR1).

## 3. Architecture
- A **new dart_frog application** `web_public/` (its own entrypoint/deploy, e.g.
  `myweli.ci`), **separate from the JSON API** (`api.myweli.ci`) but depending on
  the **`backend` package** so it reuses models, repositories, validators, and the
  DB pool — no duplication. (One language, two small deploys sharing one codebase.)
- **SSR reads go straight to the repositories** (e.g. `ProvidersRepository`) for
  the fastest TTFB — no HTTP hop. **Writes** (create booking, request OTP) call the
  existing **JSON API**/`BookingService` so all the server-authority + validation +
  notification logic is reused, never reimplemented.
- **Rendering:** small pure Dart **HTML view functions** (`String render…(dto)`),
  unit-testable, no template engine. A tiny shared layout (head, meta, JSON-LD,
  "open in app" banner, footer).
- **Interactivity:** progressive enhancement — pages work without JS; the booking
  funnel adds **minimal vanilla-JS islands** (fetch open slots, submit booking).
  No SPA framework.

### Routes (on the web host)
- `/` — marketing/landing home.
- `/<slug>` — provider public page (PP-001/002).
- `/<slug>/reserver` — booking funnel (PP-003).
- `/<categorie>-<commune>` — SEO landing (MP-001), e.g. `/tresses-cocody`.
- `/sitemap.xml`, `/robots.txt`.
Slug/landing patterns are matched explicitly (no greedy catch-all that could mask
real paths); unknown slug → **404** page.

## 4. SEO (FR-WEB-PP-002)
- Server-rendered, crawlable HTML; **mobile-first**, minimal CSS inlined for first
  paint.
- Per page: `<title>`, `<meta name=description>`, **canonical**, **OpenGraph** +
  Twitter card (provider name, commune, hero image).
- **Schema.org JSON-LD** `BeautySalon`/`LocalBusiness` (name, address, commune,
  geo, hours, `aggregateRating`, price range, photos, `telephone`).
- `sitemap.xml` enumerates provider slugs + landing pages; `robots.txt` allows
  crawl + points to the sitemap.
- FR copy; FCFA/hours via the same formatting rules.

## 5. Data / backend (PR1)
- Add **`slug`** to providers: unique, generated from name (kebab, deaccented,
  collision-suffixed), backfilled for existing rows; immutable once set (or
  redirect on change — V2). Migration + `ProvidersRepository.bySlug(slug)`.
- Public read DTO = only **public** fields (no deposit-handle internals beyond
  what booking needs, no other users' data). Reviews are already public.

## 6. Web booking funnel (PP-003) + deposit (PP-004)
- Steps: **service(s) → staff (optional) → slot → confirm**. Slots come from the
  existing `SlotService` (same availability rules as the app).
- **Auth at confirm** (mirrors the app's gate): phone + **OTP** via the existing
  `/auth/otp/*`. Creating the booking under the verified account means it also
  shows up in their app (dovetails with **FR-APPT-008** auto-sync). No separate
  guest-booking path in V1.
- **Deposit:** if the salon requires one, show the **no-custody** facilitated step
  (Wave link / copy number + amount + "j'ai payé" → attach screenshot later in the
  app), identical posture to the consumer app. Booking stays **pending** until the
  salon confirms.

## 7. "Open in app" smart banner + attribution (PP-005)
- A dismissible banner / `Réserver dans l'app` deep link (store links + a deferred
  deep link to the provider). Attribution params recorded on the click-through.

## 8. Security
- Public pages are **unauthenticated reads of already-public data** — no PII, no
  tokens, no other users' data; only the provider's public profile + public
  reviews. Render-time allowlist of fields.
- **Rate-limit** public endpoints (esp. the OTP request reused by the funnel) and
  add basic bot hardening; no secrets in HTML; standard headers (CSP where
  feasible). Booking/OTP go through the existing hardened API (its authz/validation
  apply). Threat-model rows added when the routes land (`T27+`).

## 9. Performance
- SSR string render → low TTFB; **cache** provider pages (short TTL, CDN-friendly
  `Cache-Control`) with invalidation on profile edit. Responsive/lazy images from
  the existing CDN; minimal/inlined critical CSS; tiny JS. Target fast first paint
  on 3G mobile.

## 10. Testing
- Handler/unit tests: provider page renders the right HTML + **JSON-LD** + meta;
  unknown slug → 404; landing page lists matching providers; `sitemap.xml`
  well-formed. Slug generation (collisions, accents). Booking funnel handlers
  (slot fetch, OTP-gated create, no-custody deposit). No PII in output.

## 11. Rollout — PR breakdown (each spec-linked, own PR)
1. **PR1 — slug + public read:** migration + slug gen/backfill + `bySlug`; tests.
2. **PR2 — `web_public/` app + provider page:** scaffold the SSR app, the layout,
   the `/<slug>` page (PP-001/002) + JSON-LD/meta + smart banner (PP-005) +
   `robots.txt`/`sitemap.xml`. CI builds it.
3. **PR3 — SEO landing pages (MP-001):** `/<categorie>-<commune>` + internal
   linking + sitemap entries.
4. **PR4 — web booking funnel (PP-003 + PP-004):** service→staff→slot→confirm,
   OTP at confirm, no-custody deposit; reuses `SlotService`/`BookingService`.
- Built + CI-green in-repo now; **deployed in the accounts/hosting phase** (host +
  `myweli.ci` DNS + TLS are yours-at-the-end, like the rest of activation).

## 12. Open questions
- **OQ-WEB-1** Host topology: `myweli.ci` (web) + `api.myweli.ci` (API) vs a path
  split — a deploy-phase detail; doesn't block building.
- **OQ-WEB-2** Exact slug format + whether to allow provider-chosen slugs (V2).
- **OQ-WEB-3** How much funnel interactivity is "minimal JS" vs a small island —
  settle in PR4's spec pass.
