# Web surface — Next.js (SEO + AEO + GEO), shared backend (FR-WEB-PP/MP)

| | |
|---|---|
| **Requirements** | FR-WEB-PP-001..005, FR-WEB-MP-001..003 + provider-dashboard web. (Scope pulled up — see §2.) |
| **Phase** | V1 web surface (the last V1 feature area). |
| **Stack (OQ-8 — re-resolved 2026-06-28)** | **Next.js (React, TypeScript) for ALL web**; **Flutter** stays for mobile; **one shared `dart_frog` REST API**. Supersedes the earlier "dart_frog SSR" note — chosen on **UX** (best first-paint/SEO for cold mobile-web; desktop-grade pro tool) now that the owner is building the web in Next.js. |
| **Status** | Plan / spec — **awaiting sign-off**. Large multi-PR epic; nothing built yet. |

## 1. Architecture
```
                ┌───────────────────────────────┐
                │  dart_frog REST API + Postgres │  ← the one backend (unchanged)
                └───────────────▲───────────────┘
         Flutter (mobile)       │        Next.js (all web)
   consumer app · pro app       │   public SEO · consumer web · pro web
        (native UX)             │        (web-native UX, SSR/SSG)
                          admin = Flutter Web (already built)
```
- **New top-level `web/`** Next.js app (App Router, **TypeScript**) alongside `mobile/` + `backend/`.
- **Typed API client generated from `docs/api/openapi.yaml`** (e.g. `openapi-typescript`) → no hand-duplicated DTOs; the contract can't drift.
- **Design tokens shared:** export the monochrome palette/spacing/type to a tokens JSON consumed by **Tailwind** (web) and the Flutter theme (one source of truth) so web ≈ app visually.
- **Rendering per surface:** provider/landing pages = **SSG + ISR** (instant, cheap, fresh on edit); discovery/account/pro dashboard = SSR + client components behind auth.
- **Hosting** (accounts phase): Vercel/Cloudflare/Netlify; the API on its own host. Buildable + CI-tested in-repo now.

## 2. Surfaces & scope
> **Feature parity with the mobile apps is a requirement** (not a cut-down web):
> the **consumer web** matches the consumer app (discovery/search/map · booking ·
> account/my-bookings · reviews · favorites · notifications · profile) and the
> **provider dashboard** matches the pro app, each adapted to web/desktop. Plus a
> first-class **install-the-app push** on every appropriate surface. Conventions:
> [WEB.md](../WEB.md) + [WEB-DESIGN-STANDARDS.md](WEB-DESIGN-STANDARDS.md);
> enforced by the **`myweli-web-guardrails`** skill.
1. **Public SEO pages** (FR-WEB-PP-001/002, FR-WEB-MP-001): `myweli.ci/<slug>` provider pages + `/<categorie>-<commune>` landings + home. SSG/ISR, full SEO/AEO/GEO (§4).
2. **Consumer web app** (FR-WEB-MP-002): login (phone/OTP), discovery (search/filter/map), booking, account/my-bookings.
3. **Pro web dashboard** (provider on PC — Planity-style): login, agenda/day view, manage bookings, services/staff/availability, etc. **Desktop-optimized.**
4. **Install push** everywhere: "Télécharger l'app" / smart banner (FR-WEB-PP-005) — web converts, app deepens.
- **Deferred V2:** per-provider custom branding (PP-006), web group/packages/promos parity (MP-003).

## 3. No-custody on web (correction kept)
Web deposit = the **no-custody facilitated flow** (Wave link / copy number), mirroring the app — **not** an aggregator (FR-WEB-PP-004 corrected; OQ-1/OQ-4).

## 4. SEO + AEO + GEO — first-class strategy
The web's job is discovery; optimise for **all three** discovery engines.

### 4.1 SEO (classic ranking)
- **SSR/SSG crawlable HTML**, semantic structure, one `<h1>`, clean URLs, `<title>`/meta/canonical, **OpenGraph + Twitter** cards.
- **Core Web Vitals budgets** (ranking factor): LCP < 2.5s, INP < 200ms, CLS < 0.1 on mid-range mobile/3G — `next/image`, font-display, minimal JS on public pages.
- **`sitemap.xml`** (all slugs + landings, auto-generated), **`robots.txt`**, `hreflang` (`fr`/`fr-CI`), internal linking (commune/category hubs ↔ providers), descriptive `alt` text.
- **Schema.org JSON-LD:** `LocalBusiness`/`HairSalon`/`BeautySalon` (name, address, geo, `openingHours`, `priceRange`, `image`, `telephone`, `areaServed`), `AggregateRating` + `Review`, `Service`/`Offer`, `BreadcrumbList`.

### 4.2 AEO (Google AI Overviews / answer engines / featured snippets)
- **Answer-first content**: each page leads with a concise, extractable answer, then detail. Headings phrased as real queries (« Combien coûte une pose de tresses à Cocody ? », « Meilleur barbier à Plateau »).
- **`FAQPage` schema** on provider + landing pages (price ranges, hours, "à domicile ?", deposit, cancellation) — directly feeds AI Overviews + snippets.
- **Structured, liftable blocks**: short paragraphs, lists, comparison tables; explicit entities (salon name + commune + service).
- **Authority/freshness signals**: visible ratings/review counts, NAP consistency, `dateModified`.

### 4.3 GEO (get ChatGPT/Perplexity/Gemini to recommend Myweli by name)
- **Strong, unambiguous brand entity**: an `Organization` JSON-LD + a canonical **"À propos / Myweli"** entity page (what it is, where — Côte d'Ivoire, what it does), `sameAs` → social profiles; pursue a **Wikidata** entry (off-site, ops).
- **`llms.txt`** at the web root (emerging convention) describing the site + key pages for LLM ingestion; keep `robots.txt` permissive to reputable AI crawlers (configurable).
- **Citable, factual, well-structured content** with concrete specifics (services, communes, prices, stats) — generative engines favour clear, stat-backed, attributable text.
- **Off-site presence (ops, but the site enables it)**: consistent NAP + brand mentions in directories/press so models repeatedly associate "réservation beauté Abidjan/CI" → **Myweli**.
- **Measurement**: track referrals from AI sources + periodic prompts to the engines ("meilleure app de réservation beauté en Côte d'Ivoire ?") to watch name-recall.

## 5. Auth on web
- Phone/OTP via the existing `/auth/otp/*`. **Refresh token in an `httpOnly`, `Secure`, `SameSite` cookie** (set by the backend / Next route handlers) — safer + better UX than `localStorage`; access token kept in memory. Needs a small **backend web-cookie session path** + **CORS** for the web origin.

## 6. Backend additions (the small "glue" — each its own PR, backend-guardrails)
- **`slug`** on providers (unique, generated/backfilled) + `bySlug`.
- **CORS** middleware allowlisting the web origin(s).
- **Public read DTOs** (only public fields) + a **sitemap source** (slugs/landings).
- **Web-cookie auth** path (httpOnly refresh) + **rate-limit / bot hardening** on public + OTP.
- (Storage **CORS** on R2 for browser uploads, when pro-web media lands.)

## 7. Booking on web
Service → staff → slot (existing `SlotService`) → **OTP at confirm** → **no-custody deposit**. Booking under the verified account ⇒ it also appears in the mobile app (dovetails with **FR-APPT-008** auto-sync).

## 8. Security
Public pages = unauthenticated reads of already-public data (render-time field allowlist; no PII/tokens). Authed surfaces via httpOnly-cookie session over the hardened API (its authz/validation apply). CORS locked to known origins; standard security headers/CSP; rate-limit public + OTP. Threat-model rows (`T27+`) added as routes land.

## 9. Performance
Public pages: SSG/ISR + edge cache, minimal JS, optimised images → fast first paint on low-end mobile/3G (the CI reality + a ranking + conversion factor). Authed app: code-split, lazy routes.

## 10. Testing & CI
- **New CI job** for `web/`: typecheck + lint + `next build` + unit (Vitest/RTL).
- **Playwright e2e** for critical flows (provider page renders + JSON-LD; booking funnel; login).
- **Lighthouse CI** budget gate on public pages (CWV + SEO score). Contract types regenerated from `openapi.yaml` in CI (drift check).

## 11. Rollout — milestones (each spec-linked PR; deploy in the accounts phase)
- **M0 — web foundations (✅ this PR):** [WEB.md](../WEB.md) + [WEB-DESIGN-STANDARDS.md](WEB-DESIGN-STANDARDS.md) + the `myweli-web-guardrails` skill. The rulebook every later milestone references.
- **M1 — backend glue:** slug + `bySlug` + CORS + public DTOs + sitemap source. *(backend)*
- **M2 — `web/` scaffold + SEO foundation:** Next.js app, OpenAPI-typed client, Tailwind+tokens, CI job, base layout + metadata/JSON-LD/robots/sitemap/`llms.txt` helpers.
- **M3 — provider page `/<slug>`:** SSG/ISR + full SEO/AEO/GEO (LocalBusiness+FAQPage+Review schema) + smart banner + booking entry.
- **M4 — SEO landing `/<categorie>-<commune>`** + hubs/internal linking.
- **M5 — web booking funnel** (OTP + no-custody deposit; web-cookie auth).
- **M6 — consumer web account** (my bookings, discovery/search/map).
- **M7 — pro web dashboard** (desktop-optimised; likely several PRs: auth → agenda/day view → manage bookings → catalogue/availability).

## 12. Open questions
- **OQ-WEB-1** Host topology + platform (Vercel/Cloudflare/…); a deploy-phase call.
- **OQ-WEB-2** Slug format + provider-chosen slugs (V2?).
- **OQ-WEB-3** Pro-web dashboard scope/order for V1 (full parity vs. agenda + bookings first).
- **OQ-WEB-4** Token model: httpOnly-cookie session details (rotation reuse of the existing refresh family).
