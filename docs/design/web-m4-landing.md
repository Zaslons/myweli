# Web M4 — SEO landing pages `/(categorie)-(commune)`

| | |
|---|---|
| **Requirement** | FR-WEB-MP-001 (SEO landing / category·commune pages). |
| **Milestone** | M4 ([public-web.md](public-web.md) §11). |
| **Surface** | `web/` — handled inside `app/[slug]` (dispatcher). |
| **Skill** | `myweli-web-guardrails`. |
| **Status** | **Built** — `app/[slug]` dispatcher + landing page + `ProviderCard` + ItemList/Breadcrumb/FAQ JSON-LD + sitemap; 18 unit + 4 e2e. (Category×commune; service landings = M4.1.) |
| **Data** | `GET /providers?category=&commune=&sort=rating` (existing, public). |

## 1. Goal
Crawlable "hub" pages that rank for high-intent queries (« coiffure Cocody »,
« barbier Plateau ») and funnel organic traffic into the provider pages (M3) →
booking. Drives the search-demand half of acquisition.

## 2. Routing & disambiguation (decision)
URLs are flat (`/coiffure-cocody`) per the PRD, so they share the single-segment
space with provider slugs (`/beaute-divine`). **`app/[slug]` becomes a
dispatcher:**
1. `getProviderBySlug(slug)` → if found, render the **provider page** (M3).
2. else parse `slug` as `<catSlug>-<communeSlug>` against the known vocab → if
   valid, render the **landing page**.
3. else `notFound()`.
The M3 provider rendering is factored into a `ProviderView`; this PR adds a
`LandingView`. `generateMetadata` branches the same way.

## 3. Scope (decision)
- **M4 = category × commune** landings: `coiffure`(salon) · `barbier`(barber) ·
  `onglerie`(nail) · `spa` · `massage`, × the communes present in the data
  (Cocody, Plateau, Yopougon, Marcory, Treichville, Adjamé, Abobo, Koumassi…).
- **Service-level** landings (`/tresses-cocody`) are **deferred to M4.1** — they
  need a curated service-taxonomy list and are long-tail; category·commune is the
  bounded, high-value set first.

## 4. Vocab & params
- **Category slugs (FR) → API key:** `coiffure→salon`, `barbier→barber`,
  `onglerie→nail`, `spa→spa`, `massage→massage`.
- **Commune slug** = `slugify(commune)` (e.g. `cocody`); reverse-mapped to the
  display name for the API `commune` param + the `<h1>`.
- Landing fetch: `GET /providers?category=<key>&commune=<Display>&sort=rating`.

## 5. UX
- **`<h1>`** « {Catégorie} à {Commune} » (e.g. « Coiffure à Cocody »).
- **Answer-first lead** (« Les meilleurs salons de coiffure à Cocody, réservables
  en ligne… »).
- **Provider cards** (`ProviderCard`, reusable): name, ⭐ rating + avis, commune,
  « à partir de {min prix} », link → `/<slug>`. Sorted by rating/featured.
- **Internal linking** (SEO): « {Catégorie} dans d'autres communes » +
  « Autres prestations à {Commune} » — link chips to sibling landings.
- **FAQ** (AEO): « Où trouver {cat} à {commune} ? », « Combien coûte… ? »,
  « Comment réserver ? ».
- **App-install** banner (layout) persists.
- **States:** success (N salons); **empty** (0 results → render but **`noindex`**
  to avoid thin content, show "Bientôt des salons…" + links to communes/categories
  that have salons); 404 (slug is neither a provider nor a valid combo).
- Tokens only; French; FCFA; mobile-first.

## 6. SEO / AEO / GEO
- `generateMetadata`: title « {Catégorie} à {Commune} — réserver en ligne · Myweli »,
  description, **canonical** `/{slug}`, OG.
- **JSON-LD:** `ItemList` (the listed providers, with `url` + position) +
  `BreadcrumbList` (Accueil → {Catégorie} à {Commune}) + `FAQPage`.
- **`sitemap.ts`**: add the landing URLs (the in-data combos) alongside providers.
- Brand `Organization` stays site-wide (M2).

## 7. Performance
SSG + ISR (`generateStaticParams` = the (category,commune) combos present in
`GET /providers`); `dynamicParams = true` (other combos on-demand, often empty→
noindex). Provider cards are static markup; minimal JS. CWV budgets apply.

## 8. Components
`ProviderCard` (`components/provider/ProviderCard.tsx`, reusable) + `LandingView`
(sections) + `lib/landing.ts` (vocab + parse/build slug helpers, pure + tested) +
`lib/seo/jsonld.ts` `itemListJsonLd()`.

## 9. Tests
- **Unit:** `parseLandingSlug`/`buildLandingSlug` (valid combos, unknown cat/commune
  → null), `itemListJsonLd`, `ProviderCard` render (price-from + link).
- **e2e (Playwright):** a landing renders provider cards + a valid `ItemList`
  JSON-LD; an invalid combo → 404. (Extend the stub API with
  `GET /providers?category&commune`.)
- Lighthouse budget already gates the public pages.

## 10. Security
Public reads of public list data only (allowlist; no PII). No auth. Same CORS.

## 11. Rollout
Additive; reuses the existing `/providers` query (no backend change). `app/[slug]`
refactor is internal (provider behaviour unchanged). Deployed with the rest.

## 12. Open questions (proposed defaults)
- **OQ-M4-1 Dispatcher** in `app/[slug]` (provider-first → landing → 404) → default yes.
- **OQ-M4-2 Scope** category×commune now, service landings M4.1 → default.
- **OQ-M4-3 Empty landing** → render + `noindex` + alternatives → default.
