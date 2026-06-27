# Myweli Web — architecture, conventions & Definition of Done

The rulebook for the **Next.js web surface** (`web/`) — the web mirror of
[BACKEND.md](BACKEND.md). Read this + [WEB-DESIGN-STANDARDS.md](design/WEB-DESIGN-STANDARDS.md)
+ the part's `docs/design/web-<part>.md` spec before any web work. Enforced by the
**`myweli-web-guardrails`** skill.

> **Stack (OQ-8):** Next.js (App Router) · React · TypeScript · Tailwind, consuming
> the shared `dart_frog` REST API. **One backend, two frontends** (Flutter mobile,
> Next.js web). Mobile stays Flutter; admin stays Flutter Web.

## 0. Two product rules (never lapse)
1. **Feature parity with the mobile apps** — consumer web ≈ consumer app
   (discovery/search/map · booking · account/my-bookings · reviews · favorites ·
   notifications · profile); provider dashboard ≈ pro app, adapted to web/desktop.
2. **Push the mobile app** — every appropriate surface nudges install/use of the
   mobile app (smart banner / "Télécharger l'app" / deferred deep link).

## 1. Architecture & layering (one direction)
`app/` routes (pages, RSC) → feature **components** → **hooks/data** (the typed
API client + server actions) → the **generated API client**. A page never inlines
fetch-shapes or business rules; the **server is authoritative** (prices, ids,
status, availability) — recompute/verify, never trust the client.

```
web/
  app/                 # Next.js App Router (routes, layouts, metadata)
    (public)/          # SSG/ISR crawlable pages (provider, landing, home)
    (consumer)/        # authed consumer web (discovery, booking, account)
    (pro)/             # authed provider dashboard (desktop-optimised)
    api/               # route handlers (auth cookie exchange, webhooks-to-api)
  components/          # shared UI (design-system components, install banner)
  lib/                 # api client (generated) + wrappers, auth, seo helpers
  lib/api/             # OpenAPI-generated types/client (do not hand-edit)
  styles/              # Tailwind config + tokens (shared design system)
  tests/               # unit (Vitest/RTL) + e2e (Playwright)
```

## 2. Rendering rules (pick deliberately)
- **Public, SEO pages** (provider `/<slug>`, landing `/<categorie>-<commune>`,
  home) → **SSG + ISR** (revalidate on profile edit) — instant, crawlable, cheap.
- **Authed, app-like surfaces** (consumer account, booking funnel, pro dashboard)
  → **SSR shell + client components**; code-split per route.
- Never client-render content that must be crawlable.

## 3. Data & contract
- **All API access via the generated typed client** (`lib/api/`, generated from
  [docs/api/openapi.yaml](api/openapi.yaml)) — regenerated in CI; **no drift**, no
  hand-written DTO shapes.
- Reads for public pages run server-side (RSC/route handlers); writes
  (booking/auth) call the existing hardened API endpoints — reuse their
  validation/authz/notifications; never reimplement business logic on web.
- Lists use the API's `{items,page,pageSize,total}` pagination.

## 4. Auth & session (web)
- Phone/OTP via the existing `/auth/otp/*`. The **refresh token lives in an
  `httpOnly`, `Secure`, `SameSite=Lax` cookie** set by a Next route handler / the
  backend web-session path; the access token is held **in memory** and refreshed
  silently. **No tokens in `localStorage`/JS.**
- Consumer and provider sessions are **separate** (distinct cookie names), mirroring
  the app's split session keys.
- Logout clears the cookie + memory. CSRF: `SameSite` + a token on state-changing
  POSTs.

## 5. Security (first-order)
- **CORS** on the API locked to the known web origin(s); credentials mode for the
  cookie. **No secrets in the bundle** (only `NEXT_PUBLIC_*` is public; everything
  else server-only) — CI secret scanning applies.
- **Public pages render a field allowlist** — only already-public provider data +
  public reviews; never PII, tokens, or another user's data.
- Validate inputs at the boundary; the server re-validates everything.
- Standard security headers / CSP where feasible; **rate-limit** public + OTP
  endpoints (backend) + basic bot hardening. Threat-model rows (`T27+`) added as
  routes land.

## 6. SEO / AEO / GEO (every public page — see public-web.md §4)
- **SEO:** SSR/SSG HTML, one `<h1>`, `<title>`/meta/canonical/OG, **JSON-LD**
  (`LocalBusiness`/`Review`/`Service`/`BreadcrumbList`), `sitemap.xml`, `robots.txt`,
  `hreflang`, image `alt`, internal linking.
- **AEO:** answer-first content, query-shaped headings, **`FAQPage`** schema.
- **GEO:** brand **`Organization`** entity + "À propos" page + `sameAs`, **`llms.txt`**,
  citable stat-backed content, NAP consistency.

## 7. Performance — Core Web Vitals budgets (enforced, Lighthouse CI)
- **LCP < 2.5s · INP < 200ms · CLS < 0.1** on mid-range mobile / 3G.
- Public pages: minimal JS, `next/image`, font-display swap, edge-cached SSG/ISR.
- Authed app: route-level code-splitting, lazy data, optimistic UI where it helps.

## 8. Testing
- **Unit** (Vitest + React Testing Library): components, hooks, SEO/JSON-LD helpers.
- **e2e** (Playwright): provider page renders + valid JSON-LD; booking funnel;
  login; pro dashboard core flows.
- **Lighthouse CI** budget gate on public pages (CWV + SEO score).
- **Contract drift check**: regenerate types from `openapi.yaml`; fail on diff.
- Auth-touching → negative tests (no session / expired / cross-user → denied).

## 9. CI
A dedicated **web** job: `typecheck` + `lint` + `next build` + unit + (e2e +
Lighthouse on the relevant PRs). Joins the existing mobile · backend · security
jobs; **all green before merge**.

## 10. Definition of Done (web PR)
- [ ] Spec (`docs/design/web-<part>.md`) written + UX signed off (user-facing).
- [ ] Typecheck/lint clean; `next build` ok; tests green; **Lighthouse budget met**.
- [ ] Four states; French; tokens only; shared components reused.
- [ ] SEO/AEO/GEO present + valid (metadata, JSON-LD, sitemap/robots) on public pages.
- [ ] **Parity** with the app equivalent (or the gap explicitly noted).
- [ ] **App-install push** present where appropriate.
- [ ] Security: httpOnly cookies; CORS; no bundle secrets; field allowlist; server authority.
- [ ] Contract regenerated (no drift); OpenAPI updated in the same PR if the API changed.
- [ ] Feature branch + PR; conventional commit (no Claude attribution); ROADMAP refreshed.

## 11. Keep it honest
A real decision that changes a rule updates **this doc** / WEB-DESIGN-STANDARDS /
the contract in the same change. Stale rules are worse than no rules.
