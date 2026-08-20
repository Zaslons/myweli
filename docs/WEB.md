# Myweli Web — architecture, conventions & Definition of Done

The rulebook for the **Next.js web surface** (`web/`) — the web mirror of
[BACKEND.md](BACKEND.md). Read this + [WEB-SYSTEM.md](design/WEB-SYSTEM.md) (the
web design system; shared rules in [SYSTEM.md](design/SYSTEM.md))
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
- **Public, SEO pages** (provider `/<slug>`, the nested landing tree
  `/<racine>` → `/<racine>/<ville>` → `/<racine>/<ville>/<commune>` —
  categories AND services, multi-pays MP3 — home) → **SSG + ISR** (revalidate
  on profile edit) — instant, crawlable, cheap. Legacy flat slugs
  (`/coiffure-cocody`) **permanently redirect (308 ≡ 301)** to their nested
  home — never re-emit them in links or the sitemap.
- **Authed, app-like surfaces** (consumer account, booking funnel, pro dashboard)
  → **SSR shell + client components**; code-split per route.
- Never client-render content that must be crawlable.

## 3. Data & contract
- **All API access via the generated typed client** (`lib/api/`, generated from
  [docs/api/openapi.yaml](api/openapi.yaml)) — regenerated in CI; **no drift**, no
  hand-written DTO shapes.
- **The API base URL is resolved in exactly one place** — `lib/api-base.ts` —
  and it **refuses to resolve in production** when neither `API_BASE_URL` nor
  `NEXT_PUBLIC_API_BASE_URL` is set. The localhost fallback it replaced looked
  harmless (a wrong URL fails loudly with connection errors) and was not: the
  build-time fetches below use an **empty-result fallback**, and the ISR pages
  call them during `next build`. A production deploy missing the variable
  therefore published **a marketplace with no salons in it and no error
  anywhere**. Set it per Vercel environment — Production → production API,
  Preview → staging ([LAUNCH.md](LAUNCH.md) §5.4). Design:
  [design/infra-staging.md](design/infra-staging.md) §1.3.
- Reads for public pages run server-side (RSC/route handlers); writes
  (booking/auth) call the existing hardened API endpoints — reuse their
  validation/authz/notifications; never reimplement business logic on web.
- Lists use the API's `{items,page,pageSize,total}` pagination.
- **Market data & salon time (multi-pays MP3 — live)** — geography, operator
  catalogs, currency and timezone are **DATA from `GET /localities`**:
  server components read `lib/api/localities.ts` (module-cached, empty-tree
  fallback), client components the `/api/localities` BFF via
  `lib/use-localities.ts`. The taxonomy libs (`lib/landing.ts` /
  `lib/service-landing.ts` / `lib/discovery.ts` / `lib/taxonomy.ts`) stay
  pure and take geography as parameters; Mobile-Money labels/deep links go
  through `lib/mobile-money.ts` (closed `deepLinkKind` vocabulary — T56).
  Displayed times and day boundaries are **salon time** — thread the salon's
  `timezone`/`currency` (provider payload, appointment carriers,
  `getMyProvider`) into the already-parameterized `lib/time.ts` /
  `lib/format.ts` / `lib/pro/*` helpers; build wall-clock instants ONLY via
  `salonWallClockToUtc` ([modules/multi-pays.md](modules/multi-pays.md)
  §3/§9). Hardcoding a market fact elsewhere fails review (grep-pinned),
  even when it works for CI.

## 4. Auth & session (web) — BFF + httpOnly cookies
- **BFF pattern (M5):** the browser only talks to **Next route handlers**
  (`app/api/*`, same-origin → no CORS, **no tokens in JS**); the handlers call the
  `dart_frog` API server-side with the bearer. Phone/OTP via the existing
  `/auth/otp/*`; on verify the BFF stores the **access + refresh tokens in
  `httpOnly`, `Secure`, `SameSite=Lax` cookies** (`myweli_web_at`/`_rt`). No
  backend change.
- **Silent refresh (M6):** the shared `callApi` (`lib/bff.ts`) attaches the access
  cookie; on 401 it uses the refresh cookie → `POST /auth/refresh` → rotates →
  re-cookies → retries once (refresh fail → 401 → the page routes to `/connexion`).
  Long-lived web sessions. Logout (`/api/auth/logout`) clears the cookies. CSRF:
  `SameSite=Lax` + same-origin. Account reads/writes are **self-scoped** server-side
  (the principal), never a client-supplied id.
- **The BFF does NOT enrich (PR1c).** `lib/bff.ts` used to fetch the public
  `GET /providers/{id}` once per distinct salon to put a name on a booking
  card, and `/api/me/favorites` fetched one per favorite. Both dropped what
  failed, silently. The **API** enriches now: a consumer appointment carries
  the salon's identity, contact, deposit coordinates, booking window and
  `providerStatus`, and `/me/favorites` returns hydrated salons — because those
  endpoints are authenticated and own the relationship, and the public read is
  closing to salons that are `draft` or `suspended`
  (docs/design/salon-state-and-refusals.md Decision C). **Rule: a BFF route
  shapes and forwards; it does not go and get data the API should have sent.**
  Held by `tests/no-public-provider-read.test.ts`.
- **Pro session (M7.0):** the provider dashboard uses a **separate** cookie pair
  (`myweli_pro_at`/`_rt`) + its own pro BFF (`app/api/pro/*`, `callApiPro` in
  `lib/bff-pro.ts`) refreshing via `/auth/provider/refresh` — consumer and provider
  sessions never collide. `/pro/*` is `noindex`; consumer chrome is hidden there.

## 4.1 Error boundaries & reporting

- **`app/error.tsx`** catches any unhandled render or data error in a route
  segment; **`app/global-error.tsx`** catches a failure in the root layout
  itself, which `error.tsx` cannot — it renders *inside* that layout. Neither
  existed before: a thrown error showed Next's default page, in English, with no
  way out and nothing reported.
- `error.tsx` **reuses `ErrorState`** rather than restating the shape. §12/B6
  already settled that an error state is "a human French message + a RETRY
  control", and Next's `reset` *is* that retry. It passes `title`, because §4
  requires one h1 per page in **every** state.
- **The raw exception is never rendered.** It goes to Sentry and the server log;
  the user sees our sentence.
- **Reporting is inert without a DSN** (`NEXT_PUBLIC_SENTRY_DSN`), and
  `withSentryConfig` + `instrumentation.ts` are what make it live at all — the
  SDK config files alone are dead weight, and a build stays green while nothing
  is reported. Everything sent is scrubbed by `lib/sentry-scrub.ts`, **cookies
  above all**: the session is httpOnly precisely so JavaScript cannot read it.
  Design: [design/observability-error-reporting.md](design/observability-error-reporting.md).

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

**What "enforced" means, as of 2026-08-20 — because it did not mean this
before.** The gate ran a **desktop** preset against a build pointed at a backend
that does not exist in CI, so it scored an **empty site**; it asserted only
Lighthouse *category scores*, never the three numbers above; and performance was
`warn`, so it could not fail the build. None of LCP, INP or CLS was checked
anywhere.

It now runs mobile emulation with 3G-ish throttling against a **stub-backed**
build, three runs, and asserts **LCP**, **CLS** and **TBT** — the lab proxy for
INP, which is a field metric Lighthouse cannot measure and which no lab tool can
honestly report.

**Measured medians on that setup:**

| page | LCP | CLS | TBT |
|---|---|---|---|
| `/` | 2309 ms | 0.049 | 0 ms |
| `/suppression-compte` | 2307 ms | 0.049 | 0 ms |
| `/connexion` | **2774 ms** | 0.038 | 8 ms |

**On the real domain** (`npm run check:cwv`, same settings, against
`myweli.com`): `/` **2030 ms · CLS 0.000**, `/suppression-compte` **1873 ms ·
0.000**, `/connexion` **1457 ms · CLS 0.131**. Production is *faster* than the
local build on LCP — CDN and edge caching — but `/connexion` **breaches CLS**
there, caused by Google's asynchronously-rendered sign-in button landing late
and pushing the page down. Unthrottled it measures 0.000, which is why no local
check saw it.

**Reserving that button's height did NOT fix it** — shipped, deployed, and CLS
unchanged at 0.131. Attributed with a throttled browser and a `layout-shift`
observer (Lighthouse attributes nothing here): the shifts are `div#contenu`,
`header` and `footer` moving as the page frame grows during hydration, not one
late element. The fix is to make the auth card's server-rendered height match
its hydrated height — a layout change, not a reservation. Open.

**A gate can flatter as easily as it can fail.** The first production run
reported green while two of three runs were over budget: `lhci`'s default
aggregation is *optimistic*, taking the best run. Both configs now set
`aggregationMethod: median` inside each `assertMatrix` block — lhci rejects it at
the top level.

**`/connexion` does not meet the local budget**, and the gate says so rather than
hiding it: it carries **253 KB of JS across 18 files** against the home page's
192 KB in 11 — the auth and phone-input components. Its ceiling is set to
**2900 ms**, above today's number and below the target, so the page cannot get
slower while the gap stays visible. Lower it as the page is split; delete the
per-URL block when it reaches 2500.
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
A real decision that changes a rule updates **this doc** / [WEB-SYSTEM.md](design/WEB-SYSTEM.md) /
the contract in the same change. Stale rules are worse than no rules.
