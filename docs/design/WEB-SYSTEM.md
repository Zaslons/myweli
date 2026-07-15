# Myweli Web — the design system

The canonical design system for `web/` (Next.js, myweli.com). It is the **browser
half of one system**, not a second system.

**This document supersedes `WEB-DESIGN-STANDARDS.md`.**

> **Read [SYSTEM.md](SYSTEM.md) first.** The tokens, the four-states contract, the
> accessibility targets, the forms rules, the feedback rules, the microcopy rules
> and the market-data rule are **defined there and are not restated here**. This
> doc covers only what a browser changes: how the tokens reach Tailwind, semantic
> HTML, focus and keyboard, ARIA, responsive/desktop layout, SEO/AEO/GEO, the
> app-install push, and the web's own violations register.
>
> Deliberate duplication is how two documents drift. If a rule is true on both
> surfaces, it lives in SYSTEM.md and is linked from here.

Enforced by the **`myweli-web-guardrails`** skill.

**Contents** — [1 Tokens → Tailwind](#1-tokens--tailwind) · [2 The closed theme](#2-the-closed-theme)
· [3 Type on the web](#3-type-on-the-web) · [4 Semantic HTML](#4-semantic-html)
· [5 Focus & keyboard](#5-focus--keyboard) · [6 Forms & ARIA](#6-forms--aria)
· [7 Announcements](#7-announcements-live-regions) · [8 Dialogs](#8-dialogs)
· [9 Responsive & desktop](#9-responsive--desktop) · [10 Components](#10-components)
· [11 Rendering & performance](#11-rendering--performance) · [12 SEO / AEO / GEO](#12-seo--aeo--geo)
· [13 The app-install push](#13-the-app-install-push) · [14 Enforcement](#14-enforcement)
· [15 The known-violations register](#15-the-known-violations-register)

---

## 1. Tokens → Tailwind

`web/styles/tokens.ts` mirrors `mobile/lib/core/theme/`. Tailwind consumes it in
`tailwind.config.ts`. **Use the token utility, never a raw hex or px.**

The values, the contrast ratios and the *rules about which token may be used
where* are in [SYSTEM.md §3–§10](SYSTEM.md#3-color). What follows is only the
mapping:

| Token | Tailwind utility | Notes |
|---|---|---|
| `primary` `#000000` | `bg-primary` `text-primary` | Brand fills — **never body text** ([SYSTEM.md §1](SYSTEM.md#the-two-blacks--brand-vs-ink)) |
| `primaryHover` `#333333` | `hover:bg-primaryHover` | Renamed from `primaryLight` (which was `#1A1A1A` — an invisible hover step off black) |
| `textPrimary` `#1A1A1A` | `text-textPrimary` | Ink |
| `textSecondary` `#4A4A4A` | `text-textSecondary` | |
| `textTertiary` `#6E6E6E` | `text-textTertiary` | The lightest legal text (4.76:1) |
| `textDisabled` `#9E9E9E` | `text-textDisabled` | Disabled controls only |
| `divider` `#E0E0E0` | `border-divider` | Decorative rules |
| `border` `#D0D0D0` | `border-border` | Container hairlines |
| **`borderStrong`** `#8A8A8A` | `border-borderStrong` | **Every interactive control's boundary** |
| **`borderFocus`** `#000000` | `outline-borderFocus` | The focus ring (§5) |
| semantic | `text-success` `bg-error` … | Status only |
| **`gold`** `#B8860B` | `border-gold` `bg-gold/15` | Non-text accent. **Was missing from `tokens.ts` entirely**, so `TeamRoleChip` silently substituted `starRating` — a drift bug the closed theme (§2) makes impossible. |
| spacing | `p-m` `gap-s` … + **`sm` = 12px** | |
| radius | `rounded-lg` … + **`rounded-pill`** | |

**A raw hex in `app/` or `components/` is a review failure.** The only literals
allowed are `transparent` and the alpha-black scrims (3 sanctioned uses).

## 2. The closed theme

Tailwind's `theme.extend` **adds to** the default palette; `theme` **replaces**
it. Today we use `extend`, which means `bg-red-500`, `text-gray-400` and
`rounded-2xl` all still work — the token discipline holds only because everyone
has been well-behaved. It is a convention, not a constraint.

**The theme is closed**: colors, radius, spacing, fontSize, screens, zIndex and
duration move into `theme`, so a non-token utility simply does not exist.

This creates one hazard that must be handled in the same change: **Tailwind does
not error on an unknown utility — it emits nothing.** `className="bg-red-500"`
after closing the theme is not a build failure; it is an element with no
background, shipped. Grep can't catch the template-literal cases either. So the
actual gate is lint:

- **`eslint-plugin-tailwindcss`** with `no-custom-classname` and
  `no-arbitrary-value` as **errors**.

Arbitrary values (`z-[1100]`, `py-[2px]`, `w-[380px]`) are banned by the same
rule. Each one is a token that should exist — add it to the theme instead.

## 3. Type on the web

Same scale as the apps ([SYSTEM.md §4](SYSTEM.md#4-type)), mapped to **semantic**
Tailwind names so the class says what the text *is*, not how big it happens to be:

| Utility | Size | Maps to |
|---|---|---|
| `text-labelSmall` | 11px | The floor. Badges, nav labels. |
| `text-bodySmall` / `text-labelMedium` | 12px | Captions, chips |
| `text-bodyMedium` | 14px | Secondary text |
| `text-bodyLarge` | 16px | **Reading text** |
| `text-titleLarge` … `text-headlineLarge` | 22 → 32px | Headings |

⚠️ **The web is systematically one step smaller than the app.** `text-sm` (14px) is
**380 of 554** type usages (69%) and `text-base` (16px) is used **once**. The app's
reading size is 16px; the web's is 14px. This is a real product inconsistency, but
fixing it moves nearly every page — so the **rename is zero-pixel** (the semantic
names above map to today's values) and the 14 → 16 body-text migration is a
separate, deliberate slice (**B8**, not yet committed).

## 4. Semantic HTML

The element *is* the accessibility API. Reach for the native one first — it comes
with focus, keyboard, and screen-reader semantics for free, and every hand-rolled
replacement re-implements them (usually badly).

- `<button>` for actions, `<a>` for navigation. **A clickable `<div>` is a bug.**
- One `<h1>` per page = the page's core entity. **Heading levels never skip** —
  `h1 → h3` is a WCAG failure and a real one on `/recherche` today.
- Landmarks: `<header> <nav> <main> <footer>`. One `<main>`.
- Lists are `<ul>/<li>`; tables are `<table>` with `<th scope>`.
- Every `<img>` has `alt` — descriptive when it carries meaning, `alt=""` when it's
  decoration.

## 5. Focus & keyboard

**Everything reachable by mouse is reachable by keyboard, and you can always see
where you are.**

Today `focus-visible:` and `focus:` appear **zero times** across 178 buttons and 93
form controls. Nobody broke the focus ring (`outline-none` is never used) — it was
simply never designed, so the browser default is doing all the work, unstyled and
unbranded, on top of a black-and-white UI where it is barely visible.

The fix is one base-layer rule, not 271 utilities:

```css
:focus-visible {
  outline: 2px solid theme('colors.borderFocus');
  outline-offset: 2px;
  border-radius: theme('borderRadius.md');
}
```

- `:focus-visible`, **not** `:focus` — a mouse click shouldn't leave a ring.
- Never `outline: none` without an equally visible replacement.
- Tab order follows DOM order; `tabIndex` > 0 is banned.
- A "Skip to content" link is the first focusable element on public pages.
- Hover-only affordances (menus, tooltips) must also open on focus.

## 6. Forms & ARIA

The rules are in [SYSTEM.md §14](SYSTEM.md#14-forms--validation) — errors belong
to fields, not toasts. The web adds the wiring that makes that true for assistive
tech:

```tsx
<label htmlFor={id}>Numéro de téléphone</label>
<input
  id={id}
  aria-invalid={!!error}
  aria-describedby={error ? errorId : hintId}
/>
{error && <p id={errorId} role="alert">{error}</p>}
```

- **Every input has a real `<label htmlFor>`.** A placeholder is **not** a label: it
  vanishes on focus, fails contrast, and is not announced as the field's name.
  There are ≥6 placeholder-only inputs today — **in the login funnels**.
- `aria-invalid` + `aria-describedby` tie the message to the field. Today
  **`aria-invalid` appears zero times**: no error in the entire web app is
  programmatically connected to the input that caused it.
- Autocomplete/inputmode set (`tel`, `email`, `one-time-code`) — it's a keyboard
  and an autofill win on the phones most of our users hold.

All of this lives in **one shared `<TextField>`** (§10). Seven ad-hoc input copies
is how we ended up with zero labels.

## 7. Announcements (live regions)

A visual toast is silent to a screen reader. Anything that appears without a page
navigation must announce itself:

- **Toasts / status messages** → `role="status"` + `aria-live="polite"`.
- **Errors that interrupt** → `role="alert"` (assertive; use sparingly).
- **Async results** ("12 salons trouvés") → a polite live region.
- The region must exist in the DOM **before** the text lands, or nothing is read.

Today: `aria-live` appears **zero times**, and 4 of 5 toasts are silent.

## 8. Dialogs

Six hand-rolled modals, **zero** focus traps. A modal that doesn't trap focus lets
a keyboard user tab out into the page behind it — where they are stuck, invisible,
interacting with content that is visually covered.

One shared `<Modal>`:

- `role="dialog"` `aria-modal="true"` `aria-labelledby` (its own title).
- **Focus moves in on open, is trapped inside, and returns to the trigger on
  close.**
- **Esc closes.** Background scroll locks.
- The overlay is a scrim, not a `<div onClick>` masquerading as a button.

## 9. Responsive & desktop

**Mobile-first** for public + consumer surfaces — most Ivorian traffic is a phone
browser. Single column, thumb-friendly, fast.

**Desktop-grade for the pro dashboard.** A salon runs this on a PC all day; it must
feel like a desktop tool (the Planity bar): multi-pane agenda, dense tables,
persistent nav, keyboard shortcuts, hover affordances. **It is currently a
stretched phone column** — `xl:` and `2xl:` appear zero times.

Breakpoints are Tailwind's `sm 640 · md 768 · lg 1024 · xl 1280 · 2xl 1536`, and
they map onto the same window classes as the apps
([SYSTEM.md §10](SYSTEM.md#10-layout-breakpoints-content-width-z-index)).

**A layout that only exists at one width is a bug at every other width.** The pro
dashboard's nav is the reference: a persistent sidebar at `lg+`, an off-canvas
**drawer** below — one `<ProSidebar>`, repositioned by CSS, opened by a hamburger
in a slim top bar (B0; [web-pro-mobile-nav.md](web-pro-mobile-nav.md)). It used to
be `w-60` with no breakpoint, eating 240px of a 375px phone on every `/pro` route.

### z-index

Arbitrary z-values (`z-[5]`, `z-[6]`, `z-[7]`, `z-[1100]`) are banned. The scale is
the layer, named:

| Token | Value | Layer |
|---|---|---|
| `z-base` | 0 | Content |
| `z-sticky` | 10 | Sticky headers, the map's floating controls |
| `z-dropdown` | 20 | Menus, popovers |
| `z-overlay` | 30 | Scrims |
| `z-modal` | 40 | Dialogs, sheets |
| `z-toast` | 50 | Feedback — always on top |

## 10. Components

Shared components live in `web/components/`. **The library is currently one
component** (`Button`, 108 uses) — which is why there are 35 inline "Chargement…"
strings (17 of them byte-identical), 6 hand-rolled modals, 5 hand-rolled toasts and
7 ad-hoc inputs. A missing primitive doesn't prevent the UI from being built; it
just guarantees it's built inconsistently, N times.

Existing: `Button` · `PhoneField` · `AppInstallBanner` · `OpenInAppButton` ·
`SalonTimeHint` · `LocalityPicker` · `ProviderCard` · `TeamRoleChip` · `JsonLd` ·
`Lightbox` · `SiteChrome` / `Header`.

To build (specified in [SYSTEM.md §11.3](SYSTEM.md#113-to-build-the-gaps-this-system-creates-work-for)
where they have an app twin):

| Component | Why |
|---|---|
| **`TextField`** | §6 — labels, `aria-invalid`, `aria-describedby`. The single highest-value primitive. |
| **`Toast`** | §7 — `aria-live`. |
| **`Modal`** | §8 — focus trap. |
| `Loading` / `Skeleton` | Kills the 35 inline "Chargement…" strings. 1 skeleton exists; `animate-pulse` = 0. |
| `EmptyState` / `ErrorState` | ~15 error paths currently offer **no retry**. |
| `Rating` | Glyph + numeral ([SYSTEM.md §3.5](SYSTEM.md#35-accents)). |
| `Card` · `StatusChip` · `DataTable` | The pro/admin density work. |

`Button` also needs its missing `text` variant and a loading state (the app's
`AppButton` has both — this is parity drift).

## 11. Rendering & performance

Per [WEB.md](../WEB.md): public pages are SSG/ISR (crawlable, fast); authed
surfaces are SSR + client components. All API access goes through the **generated
typed client** — never hand-rolled fetch types. Meet the Core Web Vitals budgets:
minimal public-page JS, `next/image`, code-split authed routes.

## 12. SEO / AEO / GEO

*(Carried forward — presentation conventions for every public page.)*

- One `<h1>` = the page's core entity (salon name + commune; or « Coiffure à
  Cocody »).
- **Answer-first**: a concise, extractable lead paragraph, then the detail.
- **Structured data is part of the design** — every public page ships valid JSON-LD
  (`LocalBusiness` / `Review` / `Service` / `FAQPage` / `Breadcrumb`) as a
  first-class output, not an afterthought.
- Headings phrased as real user questions where natural; FAQ blocks on provider and
  landing pages. The brand `Organization` entity and `llms.txt` stay consistent.

## 13. The app-install push

*(Carried forward.)* A recurring, **non-annoying** nudge to install the mobile app —
web converts, the app deepens:

- **`AppInstallBanner`** — dismissible, on public + consumer pages (« Réservez plus
  vite — téléchargez l'app »), store links + deferred deep link. Remembers
  dismissal; never blocks content; one per session.
- **`OpenInAppButton`** — contextual (« Ouvrir dans l'app ») on a provider/booking.
- After a successful web booking → a « continuez dans l'app » card.
- Always token-styled, French, and **never a modal interstitial** (it would hurt
  both SEO and CWV).

## 14. Enforcement

| Rule | Gate |
|---|---|
| Token contrast (§1) | `tokens.contrast.test.ts` — real WCAG math, same floors as the apps |
| Tokens only (§2) | **Closed Tailwind theme** + `eslint-plugin-tailwindcss` (`no-custom-classname`, `no-arbitrary-value`) as **errors** |
| Semantic HTML, labels, keyboard (§4–§6) | **`eslint-plugin-jsx-a11y` strict** — `label-has-associated-control`, `click-events-have-key-events`, `heading-has-content`, `anchor-is-valid`, … |
| The whole of §4–§8, on real pages | **`@axe-core/playwright`** over ~10 routes, inside the **already-blocking** e2e job |
| Regression | Lighthouse a11y ≥ **0.95**, as an **error** |
| Everything | typecheck · lint · `vitest` · `next build` |

Two of these are the point:

- **`.eslintrc.json` is currently `{"extends": "next/core-web-vitals"}`** — which
  enables **none** of the jsx-a11y rules that would have caught the missing labels,
  the clickable divs or the heading skip. Every defect in §15 was lintable.
- **Lighthouse is `continue-on-error: true`, a11y is `warn`, and it audits exactly
  one URL — the homepage.** A gate that cannot fail and looks at one page is not a
  gate.

## 15. The known-violations register

Counted in the code as of 2026-07-14. Each burn-down PR drives a row to **0**.

| # | Rule | Violations | Worst instance | Slice |
|---|---|---|---|---|
| 1 | Layout works at every width (§9) | ~~1~~ → **0** | the pro sidebar ate 240px of a 375px phone on every `/pro` route; now an off-canvas drawer below `lg`, persistent at `lg+` ([web-pro-mobile-nav.md](web-pro-mobile-nav.md)) | ✅ **B0** |
| 2 | `textTertiary` ≥ 4.5:1 | ~~170~~ → **0** | was 3.22:1; the token is now **4.76:1** (the value alone healed all 170) — and the ink softened to `#1A1A1A` | ✅ **B1** |
| 3 | Control borders ≥ 3:1 | ~~186~~ → the shared Button + the salon-switcher **done**; the ~20 hand-classed form inputs pending | `borderStrong` (3.22:1) is now the token; the central controls use it. The web has **no shared input theme**, so the ad-hoc inputs' outlines land with **B4**'s `<TextField>` (which bakes in `borderStrong`) rather than being hand-edited then rebuilt | **B1 → B4** |
| 4 | Token exists ⇒ no substitution | ~~1~~ → **0** | `gold #B8860B` is exported; `TeamRoleChip` uses it. A test grep-pin fails if any `bg-/border-starRating` returns | ✅ **B1** |
| 5 | Splash matches the app | ~~1~~ → **0** | `manifest.ts` `background_color` → `#F6F7F9` (no more black flash); `theme_color` stays brand black | ✅ **B1** |
| 6 | Closed theme (§2) | open | `rounded-xl` ≡ `rounded-2xl` (both alias `radius`); the whole default palette is reachable | **B2** |
| 7 | No arbitrary values (§2) | `z-[5]` `z-[6]` `z-[7]` `z-[1100]` `py-[2px]` | | **B2** |
| 8 | **Visible focus (§5)** | **`focus-visible:` = 0** across **178 buttons + 93 controls** | | **B4** |
| 9 | Labelled inputs (§6) | `htmlFor` = **0**, `id` = **0** (93 controls) | ≥6 placeholder-only inputs **in the login funnels** | **B4** |
| 10 | Errors tied to fields (§6) | `aria-invalid` = **0**, `aria-describedby` = **0** | no error in the app is announced | **B4** |
| 11 | jsx-a11y strict (§14) | off | `next/core-web-vitals` enables none of it | **B4** |
| 12 | Announcements (§7) | `aria-live` = **0** | 4 of 5 toasts silent | **B5** |
| 13 | Focus-trapped dialogs (§8) | **0 of 6** | | **B5** |
| 14 | Heading order (§4) | 1 | `/recherche` **h1 → h3** (`ProviderCard.tsx:23`) | **B5** |
| 15 | axe on real routes (§14) | none | Lighthouse: 1 URL, `warn`, `continue-on-error` | **B5** |
| 16 | Shared primitives (§10) | library = **1** | 35 inline "Chargement", 6 modals, 5 toasts, 7 inputs | *B6* |
| 17 | Reading text = 16px (§3) | 380 × `text-sm` | `text-base` used **once** | *B8* |
| 18 | Desktop-grade pro dashboard (§9) | `xl:`/`2xl:` = **0** | a stretched phone column | *B7* |
| 19 | Token generator (Flutter → `tokens.ts`) | hand-mirrored | already drifted once (row 4) | *B3* |

**Bold** slices are committed (the a11y tranche). *Italic* are specified and
scheduled for re-evaluation after it.

---

*Supersedes `WEB-DESIGN-STANDARDS.md`. Shared rules: [SYSTEM.md](SYSTEM.md).
Enforced by the `myweli-web-guardrails` skill.*
