# Web M8.1 — consumer discovery home + search (`/` + `/recherche`)

| | |
|---|---|
| **Requirement** | FR-WEB-PP-001/002; closes parity gap **G1** ([web-parity-audit.md](web-parity-audit.md)). |
| **Mirrors (flow)** | the app's `home_screen` (search · categories · featured · "près de vous"). |
| **Design** | **web-own, desktop-creative, responsive** ([[web-design-latitude]]), informed by **Planity**, in Myweli's monochrome identity. |
| **Surface** | `web/` — home + `/recherche` — **no backend change** (reuses `GET /providers`). |
| **Status** | **Built.** |

## 1. What & why
Replace the placeholder home with a real **discovery** surface: search + browse
on-site (the home was the biggest remaining consumer gap). Public, crawlable,
SEO/AEO/GEO-first.

## 2. Layout (desktop-first, responsive) — adapted from Planity
1. **Hero** — headline + subcopy + **service + commune search** (`HomeSearch`),
   over an on-brand **monochrome SVG backdrop** (`HeroBackground`; real photos at
   the content phase). Search stacks on mobile.
2. **Catégories** tiles (categories + popular *Tresses*) → `/recherche?...`.
3. **Salons populaires** — `ProviderCard` grid (`searchProviders`, ISR), 4-up→1-up.
4. **Partout à Abidjan** — commune×category **link matrix → the existing
   `/coiffure-cocody`… landings** (Planity's "Partout en France"; big internal-link/SEO win).
5. **Value props** (réservation en ligne · acompte direct au salon/no-custody · WhatsApp).
6. **App-install** CTA (`OpenInAppButton`).
7. **FAQ** (answer-first) → **FAQPage JSON-LD** (AEO).

## 3. Search routing (`lib/discovery.ts`, pure + tested)
`resolveSearchHref(service, commune)`: category+commune → `/coiffure-cocody`;
service+commune → `/tresses-cocody`; else → `/recherche?q=&commune=`. So search
funnels into our **indexed SEO landings** when it can, the results page otherwise.

## 4. `/recherche` results
SSR/dynamic, **noindex** (thin/duplicate; the landings are the indexed targets).
Reads `q`/`commune`/`category` → `searchProviders` → `ProviderCard` grid + the
search bar (prefilled, to refine) + four states (empty copy).

## 5. SEO/AEO/GEO
Home: **WebSite + SearchAction** (sitelinks search box) + **FAQPage** JSON-LD
(Organization stays site-wide); canonical `/`; ISR. The directory deep-links the
landing graph.

## 6. Rendering / security / perf
Home = SSG/**ISR** (revalidate 1h) — crawlable + fast; `/recherche` = dynamic,
noindex. No tokens/PII (public reads). Minimal JS (search island only); SVG hero
(no image weight) → CWV budget holds.

## 7. Tests
- **Unit:** `resolveSearchHref` (category/service/fallback), `resolveCommune`,
  `resolveCategorySlug`, `serviceSlugForQuery`; `HomeSearch` routing (mocked router).
- **e2e:** home renders (hero/categories/directory/FAQ + WebSite JSON-LD); search
  → existing landing; `/recherche` lists salons.

## 8. Rollout / open questions (resolved)
Additive. Hero = generated SVG now → real photography at the content phase.
Search routing = landing-when-resolvable, else `/recherche`. **Closes G1.**
Next: **M8.2** provider extras (map · Avant/Après · artistes) · **M8.3** account
extras (rebook · avis · favoris).
