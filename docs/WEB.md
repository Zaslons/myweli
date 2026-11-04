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
  build-time fetches below used an **empty-result fallback**, and the ISR pages
  call them during `next build`. A production deploy missing the variable
  therefore published **a marketplace with no salons in it and no error
  anywhere**. Set it per Vercel environment — Production → production API,
  Preview → staging ([LAUNCH.md](LAUNCH.md) §5.4). Design:
  [design/infra-staging.md](design/infra-staging.md) §1.3.
- **A public page does not publish what it could not read** (B9.11, decision
  Q6). `lib/api/providers.ts` and `lib/api/localities.ts` go through
  `lib/api/public-read.ts`: where the build fails closed — production, local,
  CI (`lib/build-posture.ts`) — a refusal, no answer, or a 200 without its list
  **throws**. At ISR regeneration Next keeps the last good page and tries again;
  at build time the build fails and the previous deployment stays up. They used
  to return `[]` (or `null` → a 404 for a live salon). A **Vercel preview**,
  whose staging API sleeps, still degrades to empty. A real empty list, and a
  real 404, are still that.
- **A list read requires its list** (B9.11). The authed wrappers in
  `lib/api/*.ts` read a 200 without its array as a failed read (status 0 — the
  page's error state with its retry), never as « nothing here ».
- **Every environment variable an operator sets for the web is listed in
  `web/.env.example`** — the platform- and build-set ones (`VERCEL_ENV`,
  `VERCEL_GIT_COMMIT_SHA`, `SENTRY_AUTH_TOKEN`) appear there commented (copy
  it to `.env.local`; production values live in Vercel —
  [DEPLOYMENT.md](DEPLOYMENT.md) Phase D). A `NEXT_PUBLIC_*` value is inlined
  into the bundle at build time: public by construction, never a secret.
- **The basemap is built in one place** — `lib/basemap.ts` (`cartoStyleUrl`,
  `cartoTransformRequest`), exported as `MAP_STYLE` and
  `MAP_TRANSFORM_REQUEST` by `components/map/salon-pin.tsx`; **every `<Map>`
  gets both**: `mapStyle={MAP_STYLE}` and
  `transformRequest={MAP_TRANSFORM_REQUEST}`. When
  `NEXT_PUBLIC_CARTO_BASEMAPS_KEY` (the **web** CARTO key, restricted to the
  myweli.com hosts) is set, the style and every CARTO request the map makes
  carry it; unset, everything is keyless. No other file may name the CARTO
  host, and a `<Map>` without both props fails `tests/basemap.test.ts`.
  **Production leaves the variable unset, by decision**, until CARTO requires
  keys on vector — the shared free tier is not spent on tiles that are free
  keyless; `production-checks.yml` (`basemap`) goes red that day. Design:
  [design/map-basemap-key.md](design/map-basemap-key.md) §5.5, §7, §9.
- **A browser → BFF wrapper never throws** (`lib/api/pro.ts`, through the
  shared `send()` / `readJson()` of `lib/api/network.ts`). A request that
  got no usable answer — no network, a connection cut mid-body, a 2xx whose
  body is not JSON — is **status 0** (`ok: false` for a write; a write whose
  2xx body is lost stays `ok`, without its payload), so the « not 200 » branch
  every page already has is its error state with « Réessayer ». A read never
  turns an unreadable body into an empty list. Before this rule, a dropped
  connection rejected into a load effect nothing caught — an async rejection
  that no error boundary sees — and 15 Pro pages stayed on their skeleton for
  ever. Every export is held by `tests/pro-api-network.test.ts` (a new wrapper
  must join its table). Design:
  [design/web-pro-network-failure.md](design/web-pro-network-failure.md).
  **And the error state says why**: a page keeps its load failure as
  `LoadFailure | false` (`lib/pro/load-failure.ts`), never a boolean, so
  status 0 reads « Pas de connexion. Réessayez. » (the app's sentence) while a
  5xx keeps the page's own sentence or `ErrorState`'s default, which does not
  change. Design:
  [design/web-pro-no-connection-copy.md](design/web-pro-no-connection-copy.md).
- Reads for public pages run server-side (RSC/route handlers); writes
  (booking/auth) call the existing hardened API endpoints — reuse their
  validation/authz/notifications; never reimplement business logic on web.
- **A browser → BFF wrapper never throws — consumer side too**
  (`lib/api/account.ts`, `lib/auth/client.ts`, `lib/booking/client.ts`,
  `lib/booking/deposit.ts`, `lib/account/review-photos.ts`). They call
  `send()` / `readJson()` from **`lib/api/network.ts`**, never a bare
  `fetch`: a request that got no usable answer — no network, a connection
  cut mid-body, a 2xx whose body is not JSON — is **status 0** (`ok: false`
  for a write; a write whose 2xx body is lost stays `ok`, without its
  payload), so the « not 200 » branch every page already has is its error
  state with « Réessayer ». A read never turns an unreadable body into an
  empty list. **A caller that branches on « not 200 » must name the statuses
  that mean something** (404/403 = « introuvable », 401 = « not signed in »)
  and send every other one, 0 included, to its error state — the detail page
  told a client offline that their booking did not exist, the booking funnel
  showed them the login form, « Mes données » exported « 0 rendez-vous ».
  Copy that judges the person's input (« Code incorrect », « Vérifiez
  l'image ») is never shown for status 0: say `NO_CONNECTION_MESSAGE`
  (« Pas de connexion. Réessayez. », the app's sentence). A logout leaves the
  page on `'ok'` alone — its httpOnly cookies are cleared only by the BFF's
  response. **A write never fails in silence**: what it changed at once goes
  back — the one item it touched, never a snapshot (SYSTEM §15) — and a
  `role="alert"` under the gesture says why, through
  `writeFailureMessage(status, …)` (`NO_CONNECTION_MESSAGE` for status 0, the
  screen's own sentence otherwise); a button the call unmounted or disabled
  gets focus back if it fell to `<body>`
  ([design/web-consumer-optimistic-revert.md](design/web-consumer-optimistic-revert.md)).
  Every export is held by `tests/consumer-api-network.test.ts` (a
  new wrapper must join its table). The Pro twin is `lib/api/pro.ts`
  ([design/web-pro-network-failure.md](design/web-pro-network-failure.md)).
  Design: [design/web-consumer-network-failure.md](design/web-consumer-network-failure.md).
- Lists use the API's `{items,page,pageSize,total}` pagination.
- **Market data & salon time (multi-pays MP3 — live)** — geography, operator
  catalogs, currency and timezone are **DATA from `GET /localities`**:
  server components read `lib/api/localities.ts` (module-cached, empty-tree
  fallback), client components the `/api/localities` BFF via
  `lib/use-localities.ts`. The taxonomy libs (`lib/landing.ts` /
  `lib/service-landing.ts` / `lib/discovery.ts` / `lib/taxonomy.ts`) stay
  pure and take geography as parameters; Mobile-Money labels/deep links go
  through `lib/mobile-money.ts` (closed `deepLinkKind` vocabulary — T56).
  Phone numbers go through `lib/phone.ts` (`phoneFieldError` /
  `normalizePhone`): the national length of a market (+225 → 10) is **read
  from libphonenumber's metadata**, and the markets are `PHONE_MARKETS` —
  pinned equal to the backend's table by `tests/phone-numbering-pin.test.ts`
  ([design/phone-national-length.md](design/phone-national-length.md)).
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

**CLOSED 2026-08-21, and by a different fix than the two that failed.**
Reserving the button's height did nothing — shipped, deployed, CLS unchanged at
0.131. Attribution with a throttled browser and a `layout-shift` observer
(Lighthouse attributes nothing here) showed the shifts were `div#contenu`,
`header` and `footer` moving as the page frame grew during hydration, not one
late element.

What actually closed it was **removing the late element entirely**: the Google
button is no longer rendered by Google's script at mount. `GoogleSignInButton`
paints our own facade at first paint and only fetches GSI when the visitor taps
it, so the reservation holds a real control instead of a hole. That change was
made for a privacy reason — the script was setting a third-party cookie before
any consent — and closing this was a side effect.

Measured on production after it deployed, mobile emulation with the same 3G-ish
throttling: `/` **CLS 0.049**, `/connexion` **CLS 0.046**, against a 0.1 budget.
The first scheduled run of `production-checks.yml` (2026-08-21, the first time
that workflow ever executed) asserted 3 URLs × 3 runs against the real domain
and passed every budget.

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

**The font, and what paid for it, measured 2026-11-02** (`/`, five runs each, these throttling settings, on a Mac):

| Build | LCP median | First paint | Scripts |
|---|---|---|---|
| No font | 2314 ms | 757 ms | 203 KB |
| Full font file (35 KB), preloaded | **2607 ms, over budget** | 757 ms | 203 KB |
| Full font, not preloaded | 2472 ms | **1060 ms** | 203 KB |
| Trimmed font (19 KB), preloaded | 2457 ms; `/suppression-compte` **2505 ms in CI, over budget** | 757 ms | 203 KB |
| **Shipped: trimmed font, Sentry's tracing code removed** | **2110 ms**; `/suppression-compte` 2109 ms | **757 ms** | **158 KB** |

**Two lessons, both paid for here.**
- **One run is not a measurement.** `lhci` uploads a single representative run, and this metric sits in two modes (1830 ms and 2470 ms appeared in the same five runs of one build). A 1815 ms sample looked like 685 ms of room; five runs showed about 190. A gate that passes on a median of three this close to its limit will fail at random.
- **Measure every budgeted page, not the one you are thinking about.** Trimming was judged on `/`; CI's gate then failed on `/suppression-compte`, by 5 ms.

**Script size now has its own ceiling** (`resource-summary:script:size`, 175 KB on `/` and `/suppression-compte`): measured to pass at 158 KB and to fail at 201 KB with the tracing code back. LCP is an estimate that moves. Bytes do not.

**The same build on `myweli.com` after the merge, 2026-11-02** (five runs per page, these throttling settings, from the same Mac):

| Page | LCP median (range) | First paint | CLS | Scripts | Total |
|---|---|---|---|---|---|
| `/` | 1263 ms (1158–1890) | 1107 ms | 0 | 152–153 KB | 214–215 KB |
| `/connexion` | 1274 ms (951–2412) | 1011 ms | 0–0.006 | 220–222 KB | 291–293 KB |
| `/suppression-compte` | 1480 ms (1200–1921) | 1050 ms | 0 | 152–153 KB | 199 KB |

All within budget, and the check failed as it should with the LCP budget set to 1000 ms. Don't compare these with the table above: that one is a local server. This is a simulated slow phone on a Mac, not a real phone in Abidjan.

**The new look's home page, header and footer (#727), five runs each, on the local build as in the first table:** `/` 2113 ms, `/connexion` 2713 ms (`main` 2712), `/suppression-compte` 2109 ms. First paint and scripts did not move. The hero's type, the pattern and the wordmark cost `/` 3 ms, all inline SVG and text.

**The same on `myweli.com` after the merge, five runs each:** `/` 1487 ms, `/connexion` 1323 ms, `/suppression-compte` 1607 ms, all within budget. `/` read 1263 ms before the new look (1158–1890) and 1487 ms after it (1170–1912). The ranges overlap, and five runs can't say whether that is a real cost, so the next daily runs are the thing to watch.

**The same again after square fields and buttons (#728), five runs each:** `/` 1907 ms (1158–1916), `/connexion` 1456 ms (1156–2207), `/suppression-compte` 1158 ms (1155–1604), CLS 0. The home page has now read 1263, 1487 and 1907 ms across three sets, drawing on the same range of values, while `/suppression-compte` went from 1607 to 1158 ms. That looks like which of two modes a run lands in. It is within budget, but not proved to be noise, and it is worth another look if it stays high.

**`/professionnels` and the 404 (#730), five runs each on a local build:** `/` 2115 ms, `/connexion` 2713 ms, `/suppression-compte` 2109 ms, all where they were, and `/professionnels`, which has no budget, 2148 ms. `/connexion` read 2754 ms in the run before this, on code that didn't touch it, so a 40 ms move there says little.

**The same on `myweli.com` after the merge, 2026-11-04, five runs each, 14:46–14:51 UTC:** `/` 1906 ms (1304–1920), `/connexion` 2207 ms (1914–2218), `/suppression-compte` 1309 ms (1163–1615), all within budget, and `/professionnels`, which has no budget, 1160 ms (1152–1461). CLS at most 0.064, on `/suppression-compte` in one run of five; TBT at most 53 ms. From this Mac on the live CDN, so not comparable with the local numbers above. There is no like-for-like before, so no regression is claimed, and none is ruled out. `/connexion` moved most against the set after #728 (1456 ms), but that set predates #729, #731 and #732, and the daily check's one representative run read it at 2144 ms about ten minutes before this deploy (`/` 1844 ms, `/suppression-compte` 1391 ms, on CI's machine). Why it sits that high is not established (BACKLOG B11.5).

**A font swap can move text.** `/suppression-compte` read a CLS of 0.064 in some live runs, and 0 in others. A `layout-shift` observer named it: when the font arrives after first paint, a paragraph re-wraps by one line. `adjustFontFallback` keeps each line's height, not its width. It comes from the font (#724), not the new look, and it is under the 0.1 budget. Lighthouse's own explanation errored here too.

**Ask which element it is, not only what number it is.** With the wordmark as an `<img>`, `/connexion` read the same 2712 ms, but its Largest Contentful Paint had become the footer's logo. Nothing failed, and Lighthouse's own element audit errored, so it took a `PerformanceObserver` to see. It is inline now, with a test on short pages. That audit does not only error on this machine: on 2026-11-04 it errored in 20 of 20 live runs here (Chromium 149) and in all three reports of that day's scheduled real-domain run (Chrome 156), with « Dependency "RootCauses" failed », and that run still passed. So in those runs Lighthouse names no element. The PR gate's reports were not read.

**The daily check's rules on the policy are also read at merge time.** `tool/csp-promises.ts` holds them. `tool/check-privacy-promise.spec.ts` reads them against the header `myweli.com` sends, and `tests/csp.test.ts` against the policy a PR is about to ship. The daily check needs the deployed site, so nothing runs it on a PR: a correct change to `worker-src` turned it red from 2026-10-21 to 2026-11-02 on text that was no longer there, and its next line never ran. **What this cannot see:** the daily check no longer calling the rule, and its other header assertions, which still only run daily.

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
