# Web M2 — Next.js scaffold + SEO foundation

| | |
|---|---|
| **Milestone** | M2 of the web surface ([public-web.md](public-web.md) §11). |
| **Surface** | New `web/` Next.js app (first web code). |
| **Skill** | `myweli-web-guardrails` (+ WEB.md, WEB-DESIGN-STANDARDS). |
| **Status** | **Built** — Next.js app scaffolded; defaults confirmed (Tailwind v3 · openapi-typescript+openapi-fetch · minimal home). |

## 1. Goal & scope
Stand up the `web/` Next.js app and the **foundations every later page reuses** —
typed API client, shared design tokens, base layout, the SEO/AEO/GEO plumbing, the
app-install components, and an isolated CI job. **No feature pages** (the provider
page is M3, booking M5, etc.); M2 ships only the skeleton + a minimal home so the
app renders and is testable.

**In M2:** project scaffold · Tailwind+tokens · OpenAPI-typed client + drift check
· base `layout` (default metadata + brand `Organization` JSON-LD) · minimal home ·
`robots.txt` · `sitemap.xml` (from `GET /sitemap/providers`) · `llms.txt` ·
`AppInstallBanner`/`OpenInAppButton` + a couple of base components · `web` CI job.
**Not in M2:** provider page, landing pages, booking, auth, account, pro dashboard.

## 2. Stack & dependencies (pinned in `web/package.json`)
- **Next.js (App Router) + React + TypeScript** · **Tailwind CSS v3** (mature) +
  postcss/autoprefixer.
- **API types:** `openapi-typescript` (generate types from `../docs/api/openapi.yaml`)
  + `openapi-fetch` (tiny typed client). Lightweight, no heavy codegen runtime.
- **Test:** `vitest` + `@testing-library/react` + `jsdom`. (Playwright e2e +
  Lighthouse CI arrive in M3 when there are real pages — noted, not in M2.)
- **Lint:** `eslint` (next config) + the design-token sweep.
- Node 22 (matches local + CI `setup-node`).

## 3. Folder structure (per WEB.md §1)
```
web/
  app/
    layout.tsx            # <html lang=fr>, default metadata, Organization JSON-LD, AppInstallBanner
    page.tsx              # minimal home (hero + value prop + install push) — placeholder
    robots.ts            # Next metadata route → robots.txt
    sitemap.ts           # → sitemap.xml (static pages + provider slugs from the API)
  components/
    Button.tsx  AppInstallBanner.tsx  OpenInAppButton.tsx   # design-system seeds
  lib/
    api/schema.ts         # GENERATED (openapi-typescript) — do not hand-edit
    api/client.ts         # openapi-fetch client (baseUrl from env)
    seo/jsonld.ts         # JSON-LD builders (Organization now; LocalBusiness/FAQ in M3)
    seo/metadata.ts       # shared <metadata> builders (title template, OG, canonical)
  styles/
    tokens.ts             # shared design tokens (palette/spacing/radius/type)
    globals.css           # Tailwind layers
  public/
    llms.txt              # GEO: site/brand description for LLMs
  tailwind.config.ts      # theme = tokens (no raw palette in pages)
  package.json  tsconfig.json  .eslintrc  .env.example  README.md
```

## 4. Design tokens (shared, no literals)
`styles/tokens.ts` mirrors the Flutter theme values (monochrome: `primary #000`,
surfaces, text, `border`, semantic `success/successLight #4A7C2A/error/warning
#6B5B00/info #1A1A2E`, category accents; spacing 4/8/16/24/32/48; radius
4/8/12/16/24; the type scale). `tailwind.config.ts` consumes them so pages use
`bg-surface`/`text-primary`/`rounded-lg` etc., never raw hex/px. (Automating the
export Flutter→tokens is a later nicety; M2 hand-mirrors the documented values, one
source in `tokens.ts`.)

## 5. OpenAPI-typed client + drift check
- `npm run gen:api` → `openapi-typescript ../docs/api/openapi.yaml -o lib/api/schema.ts`.
- `lib/api/client.ts` = `openapi-fetch` with `baseUrl = NEXT_PUBLIC_API_BASE_URL`
  (default `http://localhost:8080` for dev). All future API calls go through it.
- **CI drift check:** regenerate `schema.ts` and `git diff --exit-code` → fail if
  the committed types are stale vs `openapi.yaml`.

## 6. SEO / AEO / GEO foundation (the reusable plumbing)
- **`layout.tsx`**: `<html lang="fr">`; default `metadata` (title template
  `%s · Myweli`, description, OpenGraph/Twitter, `metadataBase`); inject the brand
  **`Organization` JSON-LD** site-wide (name, url, logo, `sameAs`, areaServed CI) —
  the GEO entity anchor.
- **`robots.ts`**: allow crawl; link the sitemap; permit reputable AI crawlers
  (configurable).
- **`sitemap.ts`**: static pages + provider URLs from `GET /sitemap/providers`
  (ISR-revalidated).
- **`public/llms.txt`**: concise site/brand summary + key URLs for LLM ingestion
  (GEO).
- **`lib/seo/`**: `jsonLd()` + `buildMetadata()` helpers so every later page emits
  valid structured data + meta consistently.

## 7. App-install push (WEB-DESIGN-STANDARDS §7)
`AppInstallBanner` (dismissible, remembers dismissal, one/session) in the layout +
`OpenInAppButton` — the standard nudge, French, token-styled. Store links + deep
link are config (`NEXT_PUBLIC_*`), filled at the accounts phase.

## 8. CI (isolated `web` job in `.github/workflows/ci.yml`)
A new job, `working-directory: web`: `setup-node@v4` (Node 22) → `npm ci` →
`npm run lint` → `tsc --noEmit` (typecheck) → **api drift check** → `npm run build`
(`next build`) → `npm test` (vitest). Independent of the Flutter/dart_frog jobs
(can't affect them). Lighthouse/Playwright added in M3.

## 9. Security & performance
- No secrets in the bundle (only `NEXT_PUBLIC_*`); `.env.example` documents
  `NEXT_PUBLIC_API_BASE_URL` + the store/deep-link vars. `.gitignore`:
  `web/node_modules`, `web/.next`.
- Minimal JS on the home; tokens/CSS inlined by Tailwind; `next/image` ready.
  Real CWV/Lighthouse budget enforcement starts with M3's real pages.

## 10. Tests (M2)
- Unit (Vitest/RTL): `jsonLd()` Organization output is valid; `buildMetadata()`
  shape; `AppInstallBanner` renders + dismiss behavior; home renders the hero +
  install push.
- `next build` succeeds; typecheck clean; api-types not drifted.

## 11. Rollout
Additive, isolated under `web/`. Nothing deploys yet (accounts phase). Sets the
conventions M3+ build on.

## 12. Open questions (proposed defaults — flag if you disagree)
- **OQ-M2-1** Tailwind **v3** (mature) vs v4 (newer CSS-first) → **default v3**.
- **OQ-M2-2** API client = `openapi-typescript` + `openapi-fetch` → **default yes**
  (lightweight) vs a heavier generator (orval).
- **OQ-M2-3** M2 ships a **minimal home placeholder** (so the app renders/tests) vs
  infra-only → **default minimal home**.
