---
name: myweli-web-guardrails
description: >-
  Web guardrails and a pre-flight / post-flight checklist for the Myweli **web
  surface** (the Next.js / React / TypeScript app in `web/` — public SEO pages,
  consumer web, and the provider dashboard, all on the shared `dart_frog` API).
  Use this skill WHENEVER doing any development work under `web/` — adding or
  editing a page/route, component, API client call, auth/session code, styling,
  metadata/SEO/structured data, or web tests/CI — even if the user does not
  explicitly ask to "check the rules." It enforces the web architecture +
  conventions (docs/WEB.md), the web design system (docs/design/WEB-SYSTEM.md + docs/design/SYSTEM.md),
  the per-page spec + UX-first rule, the SEO/AEO/GEO requirements, **feature
  parity with the mobile apps**, the **install-the-app push**, security
  (httpOnly-cookie auth, CORS, server authority, public-field allowlist),
  Core-Web-Vitals performance budgets, the testing strategy, and the web PR
  Definition of Done. The app-side skill `myweli-dev-guardrails` still governs
  the cross-cutting rules (V1 scope, git/PR workflow, no-Claude-attribution);
  this is its web companion.
---

# Myweli Web Guardrails

The always-on checklist for `web/` (the Next.js web surface). It makes sure the
rules in **[docs/WEB.md](../../../docs/WEB.md)** (architecture, conventions,
security, performance, testing, DoD) and **[docs/design/WEB-SYSTEM.md](../../../docs/design/WEB-SYSTEM.md)**
(the web design system — shared tokens/rules in **[docs/design/SYSTEM.md](../../../docs/design/SYSTEM.md)**) are actually consulted and applied on every web change —
the web mirror of `myweli-dev-guardrails` / `myweli-backend-guardrails`.

> **Source of truth:** [docs/WEB.md](../../../docs/WEB.md) +
> [docs/design/WEB-SYSTEM.md](../../../docs/design/WEB-SYSTEM.md) + [docs/design/SYSTEM.md](../../../docs/design/SYSTEM.md) +
> the part's [docs/design/web-*.md](../../../docs/design/) spec +
> [docs/api/openapi.yaml](../../../docs/api/openapi.yaml) (the contract) +
> the umbrella [docs/design/public-web.md](../../../docs/design/public-web.md).
> If a rule is ambiguous, read those; if they don't answer it, ask the user and
> propose updating them. Keep them honest — a rule change lands in the docs in
> the same PR.

## Two product rules that never lapse on web
- **Feature parity with the mobile apps.** The web is **not** a cut-down version:
  the consumer web reaches parity with the consumer app (discovery/search/map,
  booking, account/my-bookings, reviews, favorites, notifications, profile), and
  the provider dashboard reaches parity with the pro app — adapted to web/desktop.
  If a slice would ship less than the app's equivalent, flag it.
- **Push the mobile app.** Every appropriate surface nudges **download/use the
  mobile app** (smart banner / "Télécharger l'app" / deferred deep link) — web
  converts, the app deepens. Use the standard install component (WEB-SYSTEM §13).

## Before writing code
0. **Write the design spec first.** Before any non-trivial page/slice, **invoke
   this skill, re-confirm it fits public-web.md / WEB.md / WEB-SYSTEM + SYSTEM /
   the security model / the architecture, then write a detailed
   `docs/design/web-<part>.md` spec _before_ code** (goal & scope, UX/flows, all
   states, the API/DTO slice, the **page's SEO/AEO/GEO schema**, copy, perf,
   tests, rollout, open questions). **Align first, then build;** cross-link it
   from the ROADMAP + the code it governs. (Memory: `design-spec-per-part`.)
1. **UX first + check the design system (Step 0).** Re-read **WEB-SYSTEM** (Tailwind
   token mapping, the closed theme, semantic HTML, **focus & keyboard**, **forms +
   ARIA**, live regions, dialogs, responsive/desktop, SEO, the install push) **and**
   **SYSTEM.md** (the shared tokens, four states, a11y, forms, feedback, microcopy)
   **and** the part spec; design *to* the system — never invent a color/size/one-off;
   if the system lacks it, **add it to the system first**. Produce
   a short UX plan (goal, flow, all states, edge cases, copy) and **get sign-off**
   before building user-facing work.
2. **Locate it in the plan.** Which FR + milestone (public-web.md §11)? Stay in
   **V1 scope**; confirm V2 items (PP-006, MP-003) with the user before building.
3. **Find the pattern to copy.** Match the surrounding `web/` idiom — the
   OpenAPI-typed API client, the data-fetching convention (SSG/ISR/SSR per WEB.md),
   the auth/session pattern, the shared components. Don't invent a new shape.

## While writing code — the patterns that must hold (detail in WEB.md)
- **Rendering:** public pages = SSG/ISR (crawlable, fast); authed surfaces = SSR +
  client components. Pick per the WEB.md rules, not ad hoc.
- **Data:** all API access goes through the **generated typed client**
  (from `openapi.yaml`) — never hand-rolled fetch types; the server is the
  authority on prices/ids/status.
- **Design tokens only** — the shared palette/spacing/type via the **closed** Tailwind
  theme; no literal hex/px, **no arbitrary values** (`z-[1100]`, `py-[2px]`) — a
  missing token gets added to the theme (WEB-SYSTEM §1–§2).
- **Accessibility is not a later pass** (WEB-SYSTEM §4–§8): semantic HTML (`<button>`,
  no clickable `<div>`, no heading skips) · a **visible `:focus-visible` ring** ·
  every input has a real `<label htmlFor>` + `aria-invalid`/`aria-describedby`
  (a placeholder is not a label) · toasts announce (`aria-live`) · dialogs trap focus.
- **Four states on every page/section:** loading · empty · error · success.
- **French copy**; FCFA/phone/date formatting; Ivorian taxonomy.
- **SEO/AEO/GEO inline** (every public page): SSR HTML, `<title>`/meta/canonical/OG,
  **Schema.org JSON-LD** (LocalBusiness/Review/Service/FAQPage), answer-first
  content, the brand `Organization` entity + `llms.txt` upkeep.
- **Security inline:** httpOnly-cookie session (no tokens in JS/localStorage),
  **CORS** locked to known origins, secrets via env (never in the bundle or git),
  render-time **public-field allowlist** (no PII/foreign data), validate inputs,
  assume the server re-validates.
- **Performance inline:** minimal JS on public pages, `next/image`, code-split
  authed routes, edge-cache SSG/ISR — meet the **Core Web Vitals budgets**.

## After writing code — run this every time
Treat any unchecked box as "not done":
- [ ] **Typecheck + lint clean**; `next build` succeeds.
- [ ] Tests green: **unit** (Vitest/RTL), **e2e** (Playwright) for critical flows,
      and the **Lighthouse/CWV budget** gate on public pages. Auth-touching → the
      negative tests (no session, expired, cross-user → denied).
- [ ] **Contract:** types regenerated from `openapi.yaml`; **no drift**.
- [ ] **All four states** present; **French**; formatters; CI locale fit.
- [ ] **Design tokens** only (no literal colors/sizes, **no arbitrary values**); shared components reused.
- [ ] **Accessibility (WEB-SYSTEM §4–§8):** semantic HTML + correct heading order ·
      keyboard-reachable with a **visible focus ring** · every input **labelled**
      (`htmlFor`) with errors tied to it (`aria-invalid`/`aria-describedby`) ·
      toasts announce (`aria-live`) · dialogs trap + restore focus · **axe clean**.
- [ ] **SEO/AEO/GEO:** metadata + JSON-LD present & valid; sitemap/robots updated;
      answer-first content; brand entity intact.
- [ ] **Parity:** the page matches the mobile app's equivalent capability (or the
      gap is called out).
- [ ] **App-install push** present where appropriate.
- [ ] **Security:** httpOnly cookies; CORS; no secrets in the bundle; public-field
      allowlist; server authority.
- [ ] **Performance:** CWV budgets met; minimal public-page JS; images optimised.

## Before a commit / PR (shared with the app + backend skills)
- **Feature-branch + PR**, never push `main`; open a PR and leave merging to the
  user. Conventional commit, **authored as the user — no Claude author /
  `Co-Authored-By`**.
- All CI jobs green (mobile · backend · **web** · security) before requesting merge.
- **Refresh `docs/ROADMAP.md`** (milestone status) so the roadmap stays trustworthy.
- Never commit secrets, `.env`, build artifacts (`.next/`, `node_modules/`).

## Keep the guardrails honest
When a real decision changes a rule (new pattern, revised budget, resolved
question), update **docs/WEB.md** / **WEB-SYSTEM.md** / **SYSTEM.md** (and the contract)
in the same change. Stale rules are worse than no rules.
