# Web M1 — backend glue (slug · CORS · public read · sitemap source)

| | |
|---|---|
| **Milestone** | M1 of the web surface ([public-web.md](public-web.md) §11). |
| **Surface** | Backend (`dart_frog`) only — enables the Next.js web (M2+). |
| **Skill** | `myweli-backend-guardrails` (backend slice). |
| **Status** | Spec → building (one PR). |

## 1. Goal & scope
The backend prerequisites the Next.js web needs before any page is built:
1. **`slug`** per provider (`myweli.ci/<slug>`) + a **public read by slug**.
2. **CORS** so a browser app may call the API.
3. A **sitemap source** (provider slugs) for SEO.
No new business logic — provider reads are already public; this adds a slug lookup,
a browser-origin allowlist, and a slugs feed.

## 2. Slug
- Canonical seed (`seedProviders`) gains a stable **`slug`** per provider
  (`beaute-divine`, `elegance-coiffure`, …) — flows into both InMemory and the
  Postgres seed (`data` jsonb + a promoted column).
- **Migration `0021_providers_slug`:** `ALTER TABLE providers ADD COLUMN slug text`
  → backfill `slug = data->>'slug'` for existing rows → **unique index**
  `providers_slug_idx`. Runs **before** `seedProvidersIfEmpty` (boot order:
  migrations → seed), and the seed `INSERT` now sets `slug` too.
- **`slugify(name)`** pure util (lowercase · deaccent · non-alnum→`-` · collapse/
  trim) — used for future create paths + tests + the documented backfill intent.
  (Seed slugs are curated literals for stability; no runtime create-provider path
  exists in V1.)
- **`ProvidersRepository.bySlug(slug)`** (InMemory + Postgres) → same shaped map as
  `byId` (services/availability merged), or null.

## 3. Public read by slug
- `GET /providers/by-slug/{slug}` — **public** (mirrors the already-public
  `GET /providers/{id}`): returns the provider + embedded recent reviews; **404**
  if no such slug; **405** non-GET. Backs the Next.js provider page (M3).
- No new field exposure: returns exactly what `GET /providers/{id}` already does
  (public data). A tighter public field-allowlist is a separate follow-up if ever
  needed — not changed here to avoid app regressions.

## 4. Sitemap source
- `GET /sitemap/providers` — **public**: `{ items: [{ slug }] }` for every
  non-suspended provider (reuses `query()`, which already hides suspended +
  orders). The Next app builds `sitemap.xml` from it. (Distinct `/sitemap/*` path
  → no clash with `/providers/{id}`.)

## 5. CORS
- `corsMiddleware(allowedOrigins)` (`lib/src/cors.dart`, pure/testable): for an
  allowed `Origin`, adds `Access-Control-Allow-Origin` (echoed) + `…-Methods` +
  `…-Headers: Authorization, Content-Type` + `…-Credentials: true` + `Vary:
  Origin`; **preflight `OPTIONS` → 204**; **disallowed origin → no CORS headers**
  (browser blocks). Applied **outermost** in `routes/_middleware.dart`.
- Origins from env **`WEB_ORIGINS`** (comma-separated; `.env.example` documented);
  default dev `http://localhost:3000`. Locked to known origins (no `*` with
  credentials).

## 6. Security (threat model T27)
- **CORS** is allowlisted (never `*` alongside credentials); only the configured
  web origins get headers. CORS is a browser convenience, **not** authz — every
  endpoint keeps its own auth/ownership checks (the server stays authoritative).
- `by-slug` exposes the same public data as `byId` (no auth, no PII). Slug lookup
  is read-only.

## 7. Contract
OpenAPI: add `GET /providers/by-slug/{slug}` + `GET /sitemap/providers`; add
**`slug`** to the `Provider` schema.

## 8. Tests
- `slugify` (accents, spaces, punctuation, collapse/trim, empty).
- `bySlug` (InMemory): hit · miss · suspended still resolvable by slug? (returns
  the row; the *sitemap* excludes suspended, not the direct read).
- Route `by-slug`: 200 shape · 404 unknown · 405 non-GET.
- `corsMiddleware`: allowed origin → headers; `OPTIONS` → 204; disallowed → none.
- `GET /sitemap/providers`: lists active slugs.
- Postgres repo `bySlug` in the DB test (gated like the others).

## 9. Rollout
Additive: one migration (idempotent) + new public GET routes + CORS. No app
change; existing endpoints unaffected. Deployed with the rest in the accounts
phase; `WEB_ORIGINS` set then.
