# A salon's page works the moment it is public (web « live fallback »)

| | |
|---|---|
| **Module** | web: the public salon page (`app/[slug]`), a new `middleware.ts`, one live-rendered route, the build's salon list; a scheduled production check. No backend change, no contract change. |
| **Status** | **Built 2026-11-25, not merged** (`feat/web-salon-page-live-fallback`, #871; §13). Approved the same day, « Approve as recommended »: decisions 255–258 in BACKLOG, batch 18 (#870). Decision 259 has no recommendation and is asked again. The merge (a production web deploy) and the read after it (§9), each on the owner's word. |
| **Owner** | the project owner: the answers, the build's go, the merge, the read after it |
| **Last updated** | 2026-11-25 |
| **PRD ref / phase** | the public salon page (web M1, [web-m1-backend-glue.md](web-m1-backend-glue.md)) and discovery ([web-discovery-map.md](web-discovery-map.md)) · V1 |
| **ROADMAP entry** | [2026-11-25-salon-page-live-fallback-spec.md](../roadmap/entries/2026-11-25-salon-page-live-fallback-spec.md) |
| **Skills checked** | myweli-web-guardrails · myweli-backend-guardrails (read only: nothing in `backend/` changes) · myweli-verification-guardrails · [WEB.md](../WEB.md) |
| **Related** | [backend-web-rebuild-hook.md](backend-web-rebuild-hook.md) (the rebuild this keeps) · `web/tests/e2e/served-html.spec.ts:107-131` (the real-HTML 404 this keeps) · [hygiene-batch9.md](hygiene-batch9.md) §2.10 (`unreadable`, build posture) · [salon-go-live-approval.md](salon-go-live-approval.md) (B0.18: the validation that makes a salon public) |

---

## 1. Goal & scope

**The defect, as the owner reported it (2026-11-25).** « I published a test salon, when I research it as a client on myweli, I find it, when I click on it it shows page introuvable, and after it if I research it again I don't find unless I fully reload the site. » The salon is « test », Adjamé, slug `test-3`.

**What it costs.** For a few minutes after a salon becomes public (validated, restored, republished; §2.2), myweli.com lists it in search and in `sitemap.xml`, and its page is « Page introuvable ». The first people to look are the ones who care most: the salon owner, right after the « approved » notice, and MyWeli itself, checking a validation. A crawler following our own sitemap gets a 404 in that window too.

**Goal.** A salon that the API serves as public has a working page at `myweli.com/<slug>` from that second on. Everything else keeps today's real-HTML 404 (§2.4). Pages already in the build stay static: no API read per view, only a middleware invocation (§7).

**In scope:**
- one list of salon slugs per build, read once, shared by the page's `generateStaticParams` and the middleware (§3.1);
- `web/middleware.ts`, acting only on a single-segment path that is neither in the build nor a route of the site (§3.2);
- one live-rendered route that draws the same `ProviderView` (§3.3);
- the guards: hermetic e2e and unit tests, red first, and a daily production check (§8).

**Out of scope:**
- the rebuild hook. It stays: it moves a new salon into the static set, the home page and the landings (§3.4);
- the 5-minute lag the other way. A salon suspended while its page is in the build keeps its page until its 300-second ISR window ends (`app/[slug]/page.tsx:21-33`, decision C). Unchanged;
- search, the home page and the landings: they already read the API (search) or rebuild with the hook (home, landings);
- symptom 2 (« not found until I reload »): no web defect was found (§2.3). Decision 259 asks the owner one question about it.

---

## 2. What exists today (OBSERVED unless marked)

**Which code.** The web on myweli.com is `main` (`afd2de97`, Vercel production deployment of 12:19 UTC, then rebuilt by the hook). The backend was `myweli-api-00057-pg2` for the owner's 00:27 and 01:15 events, and is `myweli-api-00059-w28` (= `351568e3`, A4-api, deployed by workflow_dispatch at 11:24 UTC, 100 % of traffic) for the 12:41 one. Read with `gcloud run services describe` and `gh run list`.

### 2.1 The mechanism

- **The salon page's slugs are frozen at build time.** `app/[slug]/page.tsx:46` sets `dynamicParams = false`; `generateStaticParams` (`:53-58`) reads `GET /sitemap/providers` through `getAllProviderSlugs` (`lib/api/providers.ts:51-58`). A slug not in that list never enters the route: Vercel serves the prerendered 404 (`x-matched-path: /404`).
- **Search is live.** `app/recherche/page.tsx:8` is `force-dynamic` and calls `GET /providers` on every request (`:39-49`).
- **`sitemap.xml` is live too.** `app/sitemap.ts:19` revalidates hourly from the same API list. At 12:44 it listed `/test-3` (`lastmod` 12:43:53) while `/test-3` was a 404.
- **The bridge is a rebuild.** On each change to the public set, the backend POSTs a Vercel deploy hook (`backend/lib/src/site/site_rebuild_notifier.dart`, one per 60 s per process, later requests coalesced into one trailing fire). A salon has a page only once that build is live.
- **The API is consistent.** Search and the sitemap list share `status NOT IN ('suspended','draft')` (`backend/lib/src/db/postgres_providers_repository.dart:96`); the slug read uses `isPublicSalon` (`backend/routes/providers/by-slug/[slug].dart:23`). After 12:41, all three answered `test-3`.

### 2.2 The timeline (Cloud Run logs of `myweli-api`, then curl against myweli.com)

| UTC, 2026-11-25 | what happened |
|---|---|
| 00:27:11 | admin validation **approve** → `site_rebuild sent reason=salon.approved status=201` (00:27:19) |
| 00:27:35, 00:28:06 | two `/recherche` renders (`/providers?sort=relevance&pageSize=24`, a call only `/recherche` makes): the salon is listed |
| 00:28:29 | admin **suspend** (admin console, a reason is required: `mobile/lib/services/admin/admin_service.dart:139-142`) |
| 00:28:31 | the approval's build reads `/sitemap/providers`, 2 s after the suspend: **`test-3` not in the build** |
| 00:28:44, 00:28:51 | two `/recherche` renders: the salon is **not** listed (suspended) |
| 01:15:18 | admin **restore** → hook 201 |
| 01:15:28–36 | three `/recherche` renders: listed |
| 01:16:02 | admin **suspend** → hook coalesced, trailing fire at 01:16:26 |
| 01:16:53 | the restore's build reads the list: suspended, **not in the build** |
| 12:41:28 | admin **restore** → hook 201 (12:41:35) |
| 12:41:36, 12:41:59 | `/recherche`: listed |
| 12:43:40 | the restore's build reads the list: active, **in the build** |
| 12:44:10–17 | (this investigation) search lists `/test-3`; `GET /test-3` = **404**, `x-matched-path: /404`, `x-vercel-cache: HIT`; `GET /test-3/reserver` = 200 |
| 12:46:21 | `GET /test-3` = **200**, `x-matched-path: /test-3`, `x-vercel-cache: PRERENDER` |

- **The window:** the build reads the list 72–125 s after the hook (three builds). In the one window measured end to end, the page was still a 404 2 min 42 s after the hook and a 200 at 4 min 46 s. Each of the owner's searches came 8–31 s after a transition, always inside it.
- **The hook worked every time** (five 201s) and the builds converged on the right final state. The two suspends landed before those builds read the list, so the page could only appear after the 12:41 restore, which was left in place.
- **Hook builds are not GitHub deployments:** only git pushes appear in `gh api repos/…/deployments`. Their read time shows in Cloud Run as `GET /sitemap/providers` from user-agent `node`.
- **The « approved » notice has no link to the page** (`backend/lib/src/validation/salon_decision_notifier.dart`), so the window is reached through search, the home page, the landings and the sitemap.

### 2.3 Symptom 2: « search again, not found unless I reload »

- In the logs, the only searches that came back without the salon are 00:28:44 and 00:28:51, 15–22 s after the 00:28:29 suspend. The salon came back only after each restore. **INFERRED:** that is what the owner saw. Decision 259 asks.
- **No client-side cause was found.** `RechercheClient` does not filter its results. A search card is a plain `<a>` (`components/provider/ProviderCard.tsx:208`), so a click on it is a full page load for every salon; the map popup's « Voir le salon » is a `next/link` (`ResultsMap.tsx:144`). Measured on production: a client navigation to an unknown slug (`window.next.router.push`, the call that link makes) also turns into a full page load: Next's `fetch-server-response.js:91` (`doMpaNavigation` on a non-OK answer). Either way the client router cache is thrown away. From that 404, « Découvrir des salons » (client navigation) then an empty home search reach `/recherche` on the server, which listed `test-3`.

### 2.4 Why `dynamicParams = false`, and why it stays

`web/tests/e2e/served-html.spec.ts:107-131` records the 2026-08-21 fix:
- a `notFound()` at request time serves `<html id="__next_error__">` with 44 visible characters: a blank page until about 232 KB of JS lands;
- a prerendered 404 serves the real page (311 characters).

Ruled out by measurement then: a framework upgrade (14.2.35, 15.5.23, 16.3.1), a colocated `not-found.tsx`, `force-dynamic`, a segment layout. **Opening the params brings the blank 404 back.** The fix must keep every unknown slug on the prerendered 404.

### 2.5 Already in the hermetic stub (OBSERVED in code, not run)

`web/tests/e2e/stub-api.mjs:1037-1039` lists `beaute-divine` and the logo salon in `/sitemap/providers`. `:1051` also serves `institut-acompte` by slug. By the code, `/institut-acompte` is today's defect in miniature: public by slug, not in the build. The e2e only ever opens `/institut-acompte/reserver` (`booking.spec.ts:156`, `:201`).

---

## 3. Design

### 3.1 One salon list per build

- A prebuild step (`web/tool/build-salon-slugs.mjs`, after `copy-flags.mjs` in `"prebuild"`) reads `GET /sitemap/providers` once. It writes `web/.generated/salon-slugs.json` (`{ "slugs": [...], "readAt": "<ISO>" }`), gitignored and regenerated on every build, like the flags. It loads the env files the way Next does (`loadEnvConfig` from `@next/env`): a plain `node` script would not see `.env.local`, and a local build would then fail closed for no reason.
- `next.config.mjs` reads that file once and hands the list to the code as `env.MYWELI_BUILT_SALON_SLUGS` (a JSON string). Next inlines `env` into every server and edge bundle at build. A missing file gives `"[]"`. So:
  - `generateStaticParams` and the middleware read **the same inlined list**, and neither calls the API;
  - typecheck and unit tests never need the generated file. CI runs them before the stub and the build (`ci.yml`, the `web` job), so a static `import` of a gitignored JSON would break both;
  - `npm run dev`, which has no prebuild, gets an empty list: every salon is served live in dev, and nothing crashes.
- **Why one list, and not two reads.** The middleware passes a slug it believes is built **without asking the API** (§3.2, step 2). If its list held a slug the page did not build (a salon suspended between two reads), that slug would get today's 404 with no fallback. With one list that cannot happen. *This is not what hit the owner:* both builds read the list after the suspend (00:28:31 after 00:28:29, 01:16:53 after 01:16:02), so a single read would have missed the salon as well. The live fallback is what fixes that case.
- **Failure follows today's build posture** (`lib/api/public-read.ts:20-26`, `lib/build-posture.ts`):
  - production, local and CI: an unreadable list fails the build, and the last deployment stays up;
  - preview (staging): an empty list, so every preview salon is served live (§3.2). That is harmless, and better than today's empty preview.
- **The size is bounded:** about 20 bytes per salon in the middleware bundle, so 200 KB at 10,000 salons, under Vercel's edge-function size limit. INFERRED: the limit is the plan's, and it is visible only in the Vercel console.
- **The site's own top-level routes** are listed by `next.config.mjs` itself, at config load, from `app/` (`topLevelRoutes` in `tool/salon-build-list.mjs`): every folder that is not dynamic (`[…]`), private (`_…`) or a parallel slot (`@…`), a route group (`(…)`) read through. Not in the prebuild, so `next dev` has them too. They reach the code the same way (`env.MYWELI_TOP_LEVEL_ROUTES`). The taxonomy roots come from `lib/taxonomy` (`taxonomyRootSlugs`). The middleware never calls the API for any of them, so adding a page can never silently cost one API call per view. Pinned against Next's own build output, an independent source, in §8.1 case 7.
- **A production build without its prebuild is refused** (`staticSalonSlugs`, `lib/salon-fallback.ts`): no inlined list, `NODE_ENV=production` and a posture that fails closed throw in `generateStaticParams`. A `next build` run on its own would otherwise ship with no salon built and every salon page served live, with nothing in any log. `next dev` (no prebuild) gets an empty list, and the middleware serves every salon live there.
- **The prebuild loads env as Next does**, through `@next/env`'s `loadEnvConfig`. That package is CommonJS: it is imported by default, a named ESM import fails at load (found by the first e2e build).

### 3.2 The middleware

`web/middleware.ts`, with `config.matcher = ['/:slug([a-z0-9-]+)', '/recherche/salon/:path*']`.

**The matcher must carry its own pattern.** Next 14.2.35 appends `(.json)?` straight after each source (`node_modules/next/dist/build/analysis/get-page-static-info.js:297`). path-to-regexp then reads `'/:slug(.json)?'` as a parameter whose pattern is `.json`. Measured in a probe build (2026-11-25, §12): with `['/:slug']` the middleware ran on `/` only, never on `/test-3`. With `'/:slug([a-z0-9-]+)'` it ran, and a dotted file (`/favicon.ico`) never enters it.

So only these requests enter the middleware:
- a one-segment, lowercase, dot-free path;
- the live route's own path.

Assets (`/_next/…`), API routes, landings (`/coiffure/abidjan/…`) and the booking funnel (`/<slug>/reserver`) never enter it. Next applies `redirects()` before middleware (`server/lib/router-utils/resolve-routes.js:47-53`, and the probe: `/coiffure-cocody` kept its 308), so the legacy flat landings (`next.config.mjs:274`) are untouched. The matcher sees the path only, so `_rsc` and prefetch requests for the same path run it too.

For a request to `/<slug>`, in order:
1. not a salon-shaped slug (`^[a-z0-9]+(?:-[a-z0-9]+)*$`, the shape `slugifySalonName` produces, `backend/lib/src/providers_repository.dart:852-868`) → **pass**. This is belt and braces behind the matcher: it rejects a leading, trailing or doubled hyphen;
2. a top-level route of the site, a taxonomy root, or a slug in the build list → **pass**, with no fetch;
3. otherwise **one** read of `GET /providers/by-slug/{slug}`, aborted after 2 seconds:
   - 200 with a salon → **rewrite** to the live route (§3.3), plus the response header `x-myweli-salon-page: live`;
   - 404, any other status, a timeout or a network error → **pass**, so Vercel serves today's prerendered 404.

**A request whose path is the live route itself** (`/recherche/salon/…`, the matcher's second entry) is **rewritten to a path that matches nothing**, so the live route has no address of its own and serves the real 404. The middleware's own rewrite does not run the middleware again (probe: `/live-x` still rendered live). Without that entry, the new static folder would also take `/recherche/salon/<x>` away from `app/[slug]/[city]/[area]`, which 404s on it today. `/recherche/salon/<a public slug>` would become a duplicate salon page, and `/recherche/salon/<unknown>` the blank request-time 404. Both measured in the probe.

**The read uses the shared typed client**, `api` from `lib/api/client.ts`, as `api.GET('/providers/by-slug/{slug}', { params, signal: AbortSignal.timeout(2000) })`. Its `import 'server-only'` is replaced with an empty module in server and edge builds (`node_modules/next/dist/build/create-compiler-aliases.js:133-138`; probe: a middleware importing `server-only` built and ran). It does not call `getProviderBySlug`: that function throws on a non-404 failure (`unreadable`), and the middleware wants a quiet pass.

**It never throws and reports nothing.** Every failure is a pass. `withSentryConfig` wraps the middleware automatically, so the edge Sentry init (`instrumentation.ts:15-17`) runs in production for the first time. Its scrubbing keeps the URL path (`lib/sentry-scrub.ts`), so an error raised in the middleware would carry the typed slug. The build PR reads that config, and a unit test pins « no throw ».

### 3.3 The live route

`app/recherche/salon/[slug]/page.tsx` (decision 256: under `recherche`, already reserved by the backend, `slug.dart:59`, so no backend change and no deploy):
- `dynamic = 'force-dynamic'`; it renders exactly what `app/[slug]/page.tsx:93-103` renders: `getProviderBySlug`, `ProviderView`, the same `generateMetadata` (`providerMetadata`, canonical `/<slug>`, JSON-LD);
- the browser URL stays `/<slug>` (a rewrite, not a redirect). The canonical is right, and the page stays indexable: it is the salon's real page, served a few minutes early;
- the salon page's own links are built from the slug, not the path (`FavoriteButton.tsx:134`), so « Connexion » brings the visitor back to `/<slug>`. Only the chrome reads `usePathname` (`SiteChrome`, `SiteFooter`, `FooterMark`, `FooterGroups`). By the code, the live path takes the same branch as `/<slug>`: it is not `/recherche` (`SiteChrome.tsx:28`), not a pro route (`lib/proRoute.ts:4-6`), not in the pro sign-in set, and `isStoreLinkedPage` matches single segments only (`lib/storeLinkedPages.ts:42-45`). Under `next start`, `usePathname` returns the browser path on the server and the client (probe, §12). On Vercel the server may set the URL differently; that cannot be read from code, so it is checked on the deployed site (§9), and either value takes the same branch;
- if its own read returns 404 (the salon was suspended between the middleware's read and this one, a window of milliseconds), it calls `notFound()`: status 404 with the blank-until-JS body of §2.4. **Accepted residual**, written down.

Once the rebuild is live, the slug is in the build list, the middleware passes it, and the static page serves it with its ISR cache.

### 3.4 What stays exactly as it is

- the rebuild hook and its alert (`infra/gcp/96-rebuild-hook-alert.sh`);
- `dynamicParams = false` and `revalidate = 300` on `app/[slug]`;
- every row of `served-html.spec.ts`'s `NOT_FOUND_PATHS` (unknown slug, suspended salon, unknown city and area, unknown funnel). An unknown slug now costs one API read before the same 404;
- `/[slug]/reserver` (already live, `force-dynamic`).

### 3.5 Rejected

| option | why not |
|---|---|
| open the params (`dynamicParams = true`) | the blank 404 of §2.4 for every typo, removed salon and bot path; measured on three Next majors |
| open the params, and send unknown slugs to a path that 404s (307) | every typo and every removed salon becomes 307 → 404 instead of a direct 404 (SEO); ISR may cache the 307 for 300 s, so a slug visited before it went public stays dead up to 5 minutes |
| show the card but no link until the page is built | the URL itself still 404s (sitemap, shared links, the owner typing it); search would need the build list too |
| hide the salon from search and the sitemap until the web has it | needs a Vercel « deployment ready » webhook into the backend, a new authenticated endpoint and a new column. Much more for the same result |
| accept the window | every validation shows « Page introuvable » to whoever looks first |
| `rewrites().fallback` in `next.config.mjs` | it would catch every unknown slug, so the live route's `notFound()` (the blank 404) would serve all of them. Whether Vercel even applies it to a `dynamicParams = false` route is unmeasured |

---

## 4. UX & states

No visible change. A visitor sees the same salon page whether it is static or live.

| case | today | after |
|---|---|---|
| a salon in the build | static page | unchanged (no fetch in the middleware) |
| a salon public, not yet in the build | **« Page introuvable »** (3–5 min) | the salon page |
| a salon public, its rebuild failed | **« Page introuvable » until the next build** | the salon page; the production check goes red (§8.3) |
| an unknown slug, a draft, a suspended salon not in the build | real 404 | real 404 (one API read first) |
| the API down or slow (> 2 s) for an unknown slug | real 404 | real 404 |
| the API down for a live salon's own read | — | `error.tsx` (« Une erreur est survenue », retry), as any server page |

Copy: none new.

---

## 5. API & contract

No change. The middleware reads `GET /providers/by-slug/{slug}` (public) and the prebuild reads `GET /sitemap/providers` (public). Both exist and are in `openapi.yaml`. `backend/` is untouched.

---

## 6. Security

- **A new unauthenticated amplification.** A request for an unknown salon-shaped slug on myweli.com now costs one public API read, `GET /providers/by-slug/…`. A scanner probing `/wp-admin`, `/phpmyadmin` and the like causes one such read per probe. **No rate limit covers it:** the only Cloudflare rule limits `/auth/*` and `/admin/auth/*` (`infra/cloudflare/96-api-front-door.sh:330-341`). It is the same public read anyone can make directly, so it gives nobody a new capability, but scanner traffic on myweli.com now reaches Cloud Run. **Measured after the deploy:** the count of by-slug 404s per day in the Cloud Run logs. A rate limit at the front door is a separate question if that grows. A threat-model row in [WEB.md](../WEB.md) §5, in the build PR.
- The middleware reads public data only, sends no cookie and no token to the API, never throws, and reports nothing (§3.2).
- The live route has no public address of its own (§3.2), so it cannot become a duplicate of every salon page.
- CSP and the other headers apply by the request's own path before the middleware (`next.config.mjs:247`, `source: '/:path*'`; `resolve-routes.js:47`), so they are unchanged.

---

## 7. Performance

- **A built salon page:** one middleware invocation (two set lookups), no API read. **No CWV check measures a salon page today:** `lighthouserc.json` and `tool/lighthouse-production.json` list `/`, `/connexion` and the two deletion pages. So « no read for a built slug » is proven by the unit test of §8.2, not by Lighthouse. Adding a salon page to the production Lighthouse list is a separate question, not part of this fix.
- **A live salon page:** two API reads (middleware, page), `force-dynamic`, no cache. It happens only inside a build window, or while a build is failing, and §8.3 turns that second case into an alert.
- **Middleware invocations:** every one-segment lowercase request runs it: salon pages, `/cgu`, `/recherche`… and their `_rsc` and prefetch requests. Dotted files and multi-segment paths do not. Invocations count against the Vercel plan's middleware quota. **INFERRED**, not measured: the plan and its quota are visible only in the Vercel console. Read a week after the merge.

---

## 8. Testing plan

Every new check is watched failing before it counts, and the list goes in the commit message.

### 8.1 Hermetic e2e (Playwright, the stub), red on today's `main` first

A new stub salon, `salon-juste-valide`: public by slug, **absent** from `/sitemap/providers`. That is « validated after the last build ». It appears in search **only for `q=juste`**, the way the stub already keys `vide` and `vitrine` (`stub-api.mjs:1060-1061`). Adding it to the unfiltered `/providers` answer would change the home page and `/recherche` for every other spec, and the page Lighthouse measures.
1. `GET /salon-juste-valide` (`maxRedirects: 0`) → 200; its visible text (scripts stripped, the `visibleText` of `served-html.spec.ts`) has the salon's name; `<link rel="canonical">` is `/salon-juste-valide`. **Red today (404).**
2. **a.** On `/recherche?q=juste`, a click on its card (a plain `<a>`, a full page load as for every salon) lands on the salon page: URL `/salon-juste-valide`, its `h1` contains the name (contains: a verified salon's heading also holds « ✔ Vérifié »). **Red before the fix (« Page introuvable »).** **b.** A client navigation to it, the call the map popup's `next/link` makes (driven through Next's router), renders it with **no reload**: a marker set on `window` survives. That is the RSC request going through the middleware's rewrite. **Red before the fix:** the 404 forces a full load (§2.3).
3. **Every salon card on `/recherche?q=juste` answers 200 with `maxRedirects: 0`.** This is the structural invariant: search never lists a page the site cannot serve, whatever the mechanism. Without `maxRedirects: 0` a 307 to a 200 would pass. **Red today.**
4. `GET /recherche/salon/beaute-divine` and `GET /recherche/salon/inconnu` → 404 with the real page (« Page introuvable » in the visible text). **Red against the broken matcher of §3.2:** the probe answered 200.
5. `served-html.spec.ts`: every `NOT_FOUND_PATHS` row still 404 with « Page introuvable » in the visible text, untouched. Each costs one stub read now, and the stub answers 404 for all three slugs.
5b. **A built salon costs no read:** `GET /beaute-divine` → 200 without the live header, and the stub's by-slug count for it does not move. The page is warmed first: ISR revalidation (300 s) in a long run would read it by slug in the background.
6. On the live page: no `pageerror` (a production build reports hydration errors through `reportError`, not the console), and the header's links equal a built salon page's, the salon's own `/<slug>/reserver` normalised. The chrome branches on `usePathname`; this proves the live page takes a salon page's branch under `next start`. On Vercel the read after looks (§9).
7. **The route list against Next's own output.** After the build, for every first segment of `.next/app-path-routes-manifest.json` (Next's own list, an oracle independent of the `app/` scan the middleware's list comes from), `GET /<segment>` makes **no** by-slug read, counted by the stub (`/__stub/by-slug-calls`, added for this). Red when the list misses a route.
8. **The compiled matcher.** `.next/server/middleware-manifest.json` matches `/test-3` and `/recherche/salon/x`, and matches neither `/test-3/reserver` nor `/favicon.ico`. **Red with `['/:slug']`:** measured in the probe.

### 8.2 Unit (Vitest)

- the middleware's decision, with a mocked `api`:
  - no read for a built slug, a taxonomy root, every top-level route, a doubled or edge hyphen;
  - one read for an unknown salon-shaped slug;
  - rewrite on 200;
  - pass on 404, 500, a timeout and a network error, and **no throw** on any of them;
  - the live route's own path rewritten to nothing;
- the matcher, compiled with Next's own `getMiddlewareMatchers` (`next/dist/build/analysis/get-page-static-info`). It answers the same four paths as §8.1 case 8, before any build;
- `generateStaticParams` returns exactly the inlined list plus the taxonomy roots, and makes **no** API call (mocked `api`, call count 0);
- the prebuild step: it fails on an unreadable list (production posture), writes `[]` on a preview, loads `.env.local`, and `next.config.mjs` gives `"[]"` when the file is missing.

**Mutations to watch red:**
- delete the rewrite;
- rewrite on any status;
- read the API for built slugs (call count);
- matcher back to `['/:slug']`;
- drop the matcher's second entry;
- drop a route from the generated list;
- call the API again in `generateStaticParams`;
- let the middleware throw on a network error;
- swallow the prebuild's failure.

### 8.3 Production check (scheduled, `production-checks.yml`)

A new job, `salonpages` (`npm run check:salon-pages`, `web/tool/check-salon-pages.mjs`, plain HTTP, no browser). It runs daily with the others:
- it reads `GET https://api.myweli.com/sitemap/providers`;
- for each slug, `GET https://myweli.com/<slug>` (no redirect) must be **200 without `x-myweli-salon-page: live`**, i.e. served by the build;
- a slug served live or answering 404 is checked again 10 minutes later: a validation just before the run is a build window, not a fault. Still not static → red, naming the slug.
- **The job is added to the `needs` of both `report` and `clear`**, and to the report's status line (`SALONPAGES`). Both lists are written by hand; `backend/test/infra/production_alarm_test.dart` and `web/tests/production-alarm-status.test.ts` derive the job list and hold both to it. The job holds `contents: read` only: it reads two public URLs.
- **Found by its first dry run against production:** a hand-built `file://${argv[1]}` never equals `import.meta.url` in a path with a space (« beauty app »), so the script exited 0 without checking anything. It now compares through `pathToFileURL`. After the fix, the dry run read 1 public salon, `/test-3`: static (2026-11-25).

That catches what nothing catches today: a hook answered 201 and the Vercel build then failed (the alert watches only `site_rebuild FAILED`), or a hook that never fired. Watched red through its decision function on recorded answers (404, live, static); then one dry run against production, read in the run log. The monitor's last run is part of a read-back (verification guardrails §16).

---

## 9. Rollout

1. **One web PR** (`feat/web-salon-page-live-fallback`), on the owner's word: §3 and §8, `WEB.md` (rendering, security row), the comments in `app/[slug]/page.tsx:34-46` and `backend-web-rebuild-hook.md` §7 brought up to date (the « 404s until the next build » residual becomes « served live until the next build »), a roadmap entry.
2. **Its merge is a production web deploy** (Vercel deploys `main`): on the owner's word.
3. **The read after**, read-only:
   - `GET /zz-introuvable` → 404 with the real page, `x-matched-path: /404`;
   - a built salon → 200, no live header;
   - `/recherche/salon/test-3` → 404;
   - the production check's first run, read.
4. **The live path on a real deployment** is exercised by the next salon validation, or earlier on a preview against staging. That needs a staging salon validated, a write to staging, so it is done on the owner's word only, never on production.

---

## 10. Definition of done

- [ ] typecheck, lint, `next build` clean; unit and e2e green; every §8 check watched red, listed in the commit.
- [ ] `served-html.spec.ts` unchanged and green.
- [ ] WEB.md (rendering + security row), `backend-web-rebuild-hook.md` §7, the code comments, this spec's status: updated in the build PR.
- [ ] Feature branch + PR, CI green, merge and deploy on the owner's word, no Claude attribution.
- [ ] Read after the deploy (§9.3), with the production check's first run.

---

## 11. Open questions (decisions 255–259; 255–258 answered 2026-11-25, « Approve as recommended »)

1. **The fix** (decision 255). *Recommended:* « live fallback » (§3). Alternatives: the 307 hand-off, hiding unbuilt cards, accepting the window (§3.5).
2. **Where the live route lives** (decision 256). *Recommended:* `app/recherche/salon/[slug]`, under `recherche`, which the backend already reserves: no backend change, no deploy. Alternatives: a new top-level word (`reservedPublicSlugs` and its route-sync pin in `multi_pays_test.dart` change first, then a backend deploy); a child of `[slug]` (it would shadow `/<taxonomy root>/<that word>`).
3. **The daily production check** (decision 257). *Recommended:* add it (§8.3). Without it, a failed Vercel build after a 201 stays invisible: users would not notice it any more, but the static set would lag forever.
4. **When** (decision 258). *Recommended:* built now as one web PR on your word; its merge is the production web deploy, on your word.
5. **Symptom 2** (decision 259). The salon was suspended from the admin console at 00:28:29 and 01:16:02 and restored at 01:15:18 and 12:41:28, each with a reason typed. Were those yours, for example to retry? If yes, symptom 2 is explained (§2.3) and nothing changes for it. If not, it is a separate problem to chase first.

---

## 12. Independent review (2026-11-25)

One independent reader was told to refute this spec against the code and Next 14.2.35's own source. They also built a throwaway probe app in the scratchpad (`next build` + `next start`, using the repo's `node_modules`; stopped afterwards, nothing in the repo touched). They found six faults in the first draft, all now corrected:

1. **The matcher `['/:slug']` never matched a salon path** (Next appends `(.json)?`, `get-page-static-info.js:297`). Corrected to `'/:slug([a-z0-9-]+)'` (§3.2), with §8.1 case 8 and a compiled-matcher unit test.
2. **The live route had a public address:** a one-segment matcher cannot see `/recherche/salon/x`, which answered 200 in the probe. Second matcher entry added (§3.2), and §8.1 case 4.
3. **The `server-only` reason was false:** Next aliases it to an empty module in server and edge builds. The middleware now reuses the shared `api` client (§3.2).
4. **A static import of the generated JSON would break CI** (typecheck and unit tests run before the build) and `npm run dev`. The list now comes through `next.config` `env`, read from the file with an empty fallback (§3.1). The prebuild loads `.env.local`.
5. **« Its rate limits » was wrong:** no rate limit covers `GET /providers/by-slug` (§6).
6. **§3.1's motivation was wrong by the spec's own timeline:** one read would not have saved the owner's builds. The real reason is the middleware's no-fetch step (§3.1).

Also taken from the review:
- `slugifySalonName` (not `slugify`) is the salon slug's source;
- Sentry's edge init starts running in production with the middleware;
- the alarm jobs' hand-written `needs`;
- case 3 keyed on a query so it does not disturb other specs;
- hydration errors read through `pageerror`;
- the route-list test against Next's own manifest, not the same scan.

Each claim used here was re-read in the code by the author before it was taken. Confirmed by the review: redirects before middleware; `_rsc` and prefetch requests run the middleware; the rewrite works for both the HTML and the RSC request, with the navigation staying client-side; `usePathname` returns the browser path under `next start`; no routing conflict for `app/recherche/salon/[slug]`; every `NOT_FOUND_PATHS` row and the reserver's 307 keep working.

---

## 13. Build record (2026-11-25, `feat/web-salon-page-live-fallback`)

**What was built** is §3 as written, with the details §3.1 and §8 now carry:
- the route list comes from `next.config.mjs`, not the prebuild;
- `staticSalonSlugs` refuses a production build without its prebuild;
- the stub counts by-slug reads for cases 5b and 7;
- case 2 is split, because a search card is a plain `<a>`.

**Red first, on the code before the fix** (a throwaway worktree of the spec branch, with only the new spec and the stub copied in): e2e cases 1, 2a, 2b, 3, 6 and 8 failed for the stated reason. Case 1 answered 404. Cases 2a, 2b and 6 found « Page introuvable » as the heading. Case 3 got a 404 for `/salon-juste-valide`. Case 8 found no middleware in the manifest. Cases 4, 5b and 7 passed there: they guard the new code, and their red is the mutations below.

**Green with the fix:**
- the new spec and `served-html.spec.ts`: 32 passed;
- web unit: 229 files, 3,322 tests;
- lint and typecheck clean;
- `backend/test/infra/production_alarm_test.dart`: 15 passed.

**Mutations watched red** (each applied with an asserted change, on committed work, restored with a clean-tree check):
- **unit:**
  - the rewrite deleted;
  - rewrite on any status;
  - the API asked about built salons;
  - the matcher back to `'/:slug'`;
  - the matcher's second entry dropped;
  - `cgu` dropped from the route list;
  - `generateStaticParams` reading the API again;
  - both catches removed;
  - the prebuild swallowing an unreadable list;
  - a production build without its prebuild accepted;
  - the live route not hidden;
  - the check following redirects;
  - the check counting a live page as static;
  - the check skipping the build window;
- **backend test:** `salonpages` left out of the alarm's `needs`;
- **e2e, on a real build each:**
  - the matcher's second entry dropped → case 4: `/recherche/salon/beaute-divine` answered 200;
  - `cgu` dropped from the route list → case 7: « /cgu made the middleware ask the API », 0 → 1. The unit test for that mutation reads the same `app/` scan; this one reads Next's own manifest.

**Found while building:**
- `@next/env` is CommonJS: a named ESM import fails at load.
- The production check's first dry run against production printed nothing and exited 0. A hand-built `file://${argv[1]}` never equals `import.meta.url` in a path with a space. Fixed with `pathToFileURL`. Then: 1 public salon, `/test-3`, static.
- Two test faults, corrected before counting anything:
  - a verified salon's heading also holds « ✔ Vérifié »;
  - the header carries the salon's own `/<slug>/reserver`.

**Not verified here:** anything on Vercel itself (§9 reads it after the deploy) and the middleware quota (the Vercel console).
