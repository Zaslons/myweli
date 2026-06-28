# Web M3 — provider page `myweli.ci/<slug>` (SEO/AEO/GEO)

| | |
|---|---|
| **Requirement** | FR-WEB-PP-001/002 (+ 005). The flagship SEO page. |
| **Milestone** | M3 ([public-web.md](public-web.md) §11). |
| **Surface** | `web/` Next.js — `app/(public)/[slug]/page.tsx`. |
| **Skill** | `myweli-web-guardrails`. |
| **Status** | **Built** — page + sections + JSON-LD/FAQ; 14 web unit/component tests. e2e (Playwright) + Lighthouse CI **deferred to a follow-up** (M3.1). |
| **Data** | `GET /providers/by-slug/{slug}` (M1), via the typed client. |

## 1. Goal
A fast, crawlable, shareable public page per provider — the "single biggest
organic-acquisition channel" — that ranks (SEO), is lifted into AI Overviews
(AEO), and teaches generative engines the salon + Myweli (GEO), then converts to a
booking (or an app install).

## 2. UX plan (sign-off)
- **Entry points:** Google/IG link, share, internal links (landing pages M4), the
  app's "share". **Goal:** see the salon + book in the fewest taps.
- **Layout (mobile-first; widens on desktop):**
  1. **Hero** — name (`<h1>`), commune, **verified badge**, ⭐ rating + « N avis »,
     hero image; sticky **« Réserver »** CTA.
  2. **Answer-first lead** — one concise paragraph (salon + category + commune +
     "réservez en ligne") for snippets/AEO.
  3. **Services** — name · **price range (FCFA)** · duration.
  4. **Équipe** — staff (name, specialty).
  5. **Horaires** — weekly hours (from availability).
  6. **Localisation** — address + commune + an **« Itinéraire »** link (Google/OSM).
  7. **Avis** — rating summary + recent reviews (text + stars + date).
  8. **Avant / Après** — when present.
  9. **Contact** — **Appeler** (`tel:`) + **WhatsApp** (`wa.me`).
  10. **FAQ** — 3–5 Q&A (AEO, see §4).
  - The layout **`AppInstallBanner`** + a "continuer dans l'app" nudge persist.
- **States:** **success** (above); **not-found** (unknown slug → `notFound()` → a
  French 404 with links home); **error** (API unreachable at render → ISR serves
  the last good copy, else a graceful French error); **empty sub-sections** hide
  (no staff/reviews/before-after → omit, never an empty shell).
- **Booking CTA (interim):** the web booking funnel is **M5** — until then
  **« Réserver »** opens the app / install (deep link). M5 swaps it to the on-page
  web funnel. (Flagged as OQ-M3-2.)
- **Copy:** French throughout; FCFA via a shared formatter; dates `fr_FR`.
- **Fit:** tokens only; reuse `Button`/sections; respects commune + WhatsApp + the
  no-custody posture.

## 3. Rendering & data
- **SSG + ISR:** `generateStaticParams()` from `GET /sitemap/providers` (prebuild
  the known slugs); `dynamicParams = true` (new slugs render on-demand then cache);
  `revalidate = 3600`. Build-time/per-request fetch is **guarded** (API down →
  `notFound()` for a missing slug; never crash the build).
- **Data:** server-side typed client `GET /providers/by-slug/{slug}`; `null` →
  `notFound()`. Only already-public fields are rendered (allowlist).

## 4. SEO / AEO / GEO (the point of the page)
- **`generateMetadata`:** title `{name} — {catégorie} à {commune} · Myweli`,
  description (answer-first), **canonical** `/{slug}`, **OpenGraph/Twitter** with
  the hero image.
- **JSON-LD (SEO):** `BeautySalon`/`HairSalon` (a `LocalBusiness`) — `name`,
  `image`, `address` (`PostalAddress`, `addressLocality`=commune,
  `addressCountry`=CI), `geo` (lat/lng), `telephone`, `priceRange`,
  `openingHoursSpecification` (from availability), `aggregateRating`
  (rating+reviewCount), `review[]` (embedded), `url`, `makesOffer` (services) +
  **`BreadcrumbList`**.
- **AEO — `FAQPage`:** 3–5 liftable Q&A, e.g. « Comment réserver chez {name} ? »,
  « Où se trouve {name} ? », « Quels sont les tarifs ? », « Faut-il un acompte ? »
  — concise answers an AI Overview can quote.
- **GEO:** the site-wide brand `Organization` (M2) + this page's unambiguous entity
  (name + commune + CI) + consistent NAP; the page is in `sitemap.xml` + `llms.txt`
  patterns. Stat/specific, citable content.

## 5. Performance (CWV budgets — now enforced)
- `next/image` for hero/gallery (configure `remotePatterns` for the image origin);
  responsive sizes; lazy below the fold. Minimal client JS (the page is mostly
  static; only small islands like the gallery/FAQ toggle if any).
- **Lighthouse CI** budget gate comes online here: LCP < 2.5s, CLS < 0.1, INP <
  200ms, SEO score ≥ 95 on a sample provider page.

## 6. Components (`web/components/provider/`)
`ProviderHero`, `ServiceList`, `StaffList`, `Hours`, `ReviewList`, `ContactRow`,
`Faq`, `BookingCta` — token-styled, four-states-aware, reused by M4 where useful.
JSON-LD builders extend `lib/seo/` (`localBusinessJsonLd`, `faqJsonLd`,
`breadcrumbJsonLd`).

## 7. Testing
- **Unit (Vitest):** the JSON-LD builders (LocalBusiness/FAQ/Breadcrumb valid +
  required fields), `generateMetadata` output, section components (render +
  empty-state hide).
- **e2e (Playwright) + Lighthouse CI — deferred to a follow-up (M3.1).** They
  need a served app + headless browser downloads (heavy/flaky to add inline);
  M3 ships with strong **unit/component** coverage instead (14 web tests:
  JSON-LD builders, formatters, ServiceList/ReviewList/Faq). The Playwright e2e
  (renders hero/services/reviews + valid JSON-LD; unknown slug → 404) + the
  Lighthouse CWV/SEO budget gate are a tracked next step on the `web` CI job.

## 8. Security
Public read of already-public data only (field allowlist; no PII/tokens). No auth
on this page. `tel:`/`wa.me` links are inert. Image origins allowlisted via
`remotePatterns` (no arbitrary remote images).

## 9. Rollout
Additive page; SSG/ISR. Deployed in the accounts phase (needs the API reachable +
the image origin configured). No app/backend change (M1 already shipped the data).

## 10. Open questions (proposed defaults)
- **OQ-M3-1 Map:** interactive (Leaflet) vs a **static address + « Itinéraire »
  link** → **default static link** for M3 (keeps JS/CWV lean); interactive later.
- **OQ-M3-2 Booking CTA interim:** **« Réserver » → open app / install** until M5
  → then the web funnel. (Default as stated.)
- **OQ-M3-3 Test data:** mock the API fetch in unit/Playwright (hermetic) vs spin a
  real backend in CI → **default mock/fixture** for M3.
