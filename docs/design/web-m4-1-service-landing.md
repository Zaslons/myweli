# Web M4.1 — service landing pages `/(service)-(commune)`

| | |
|---|---|
| **Requirement** | FR-WEB-MP-001 (the `/tresses-cocody` half — service-level SEO). |
| **Milestone** | M4.1 (extends M4; [public-web.md](public-web.md) §11). |
| **Surface** | `web/` — third arm of the `app/[slug]` dispatcher. |
| **Skill** | `myweli-web-guardrails`. |
| **Status** | **Built** — dispatcher service arm + `ServiceLandingView` + taxonomy/matcher + sitemap; 22 unit + 6 e2e. |

## 1. Goal
Long-tail SEO hubs for high-intent service queries (« tresses cocody »,
« dégradé plateau ») — the PRD's headline example. List salons that **offer that
service** in that commune, link to their provider pages.

## 2. Dispatcher (extends M4)
`app/[slug]` resolves: provider → **category·commune** landing (M4) →
**service·commune** landing (M4.1) → `notFound()`. Category slugs and service
slugs are disjoint; provider/category win first, so no collision.

## 3. Service filtering (decision)
The `/providers` API filters by **category + commune only** (no service param).
So M4.1 filters **client-side**:
- `GET /providers?commune=<Commune>` (all categories) → keep providers whose
  `services[].name` **matches the service** (deaccented, lowercased keyword
  match against a curated taxonomy). No backend change.
- A backend `service` filter/index is a **scale-time** optimisation (noted, not
  now — the catalogue is small).

## 4. Service taxonomy (curated, from PRD Appendix A)
`lib/service-landing.ts` — each: `{ slug, label, keywords[] }`. Launch set:
`tresses` (tresse·natte·vanille·box·braid) · `tissage` · `defrisage`
(defrisage·lissage) · `coupe-homme` (degrade·fade·coupe homme) · `barbe`
(barbe·rasage) · `coupe-femme` (coupe femme·brushing) · `locks` (locks·dread) ·
`coloration` (coloration·couleur) · `manucure` · `pedicure` · `ongles`
(ongle·gel·capsule·vernis·nail) · `massage` · `soin-visage` (soin du visage·
gommage·facial). `matchesService(serviceName, slug)` = any keyword is a substring
of `slugify`-normalised name.

## 5. Routing/data helpers
- `parseServiceLanding(slug)` → `{ serviceSlug, label, commune }` | null (commune
  reuses M4's `communes`; service from the taxonomy).
- `listProvidersByCommune(commune)` (typed client) + client filter by
  `matchesService`.
- `getServiceLandingSlugs()` — combos with ≥1 matching provider (derived from the
  catalogue: each provider's services → service slugs × its commune) for
  `generateStaticParams` + sitemap.

## 6. UX (mirrors M4)
- `<h1>` « {Service} à {Commune} » (e.g. « Tresses à Cocody ») + answer-first lead.
- `ProviderCard` grid (reused) of matching salons (rating, price-from, link).
- Internal-link chips: « {Service} dans d'autres communes » + « Autres prestations
  à {Commune} » (other services).
- FAQ (AEO) + app-install banner.
- **States:** success · empty → render + **`noindex`** + alternatives · invalid
  service/commune → 404.

## 7. SEO / AEO / GEO
`generateMetadata` (title « {Service} à {Commune} — réserver en ligne », desc,
canonical) + **`ItemList`** + **`BreadcrumbList`** + **`FAQPage`** JSON-LD.
Service landings added to `sitemap.xml`. SSG/ISR.

## 8. Tests
- **Unit:** `parseServiceLanding` (valid/invalid), `matchesService` (e.g. "Tresses
  africaines" → `tresses`; "Manucure" → `manucure`; non-match → false),
  `getServiceLandingSlugs` mapping.
- **e2e (Playwright):** `/tresses-cocody` renders the matching salon + valid
  `ItemList`; `/tresses-nowhere` → 404; a non-service single segment → 404.
- Reuse the e2e stub's `/providers?commune=` (already added in M4).

## 9. Rollout
Additive; reuses `/providers` (no backend change). Dispatcher gains one arm.
Deployed with the rest.

## 10. Open questions (proposed defaults)
- **OQ-M4.1-1** Filtering = **client-side keyword match** (no backend) → default.
- **OQ-M4.1-2** Launch taxonomy = the ~13 above → default (extend later).
- **OQ-M4.1-3** Empty → render + `noindex` → default.
