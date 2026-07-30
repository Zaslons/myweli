# web-pro-mobile-nav — the pro dashboard's off-canvas nav (B0)

**Status:** Built (2026-07-15). **Surface:** `web/` · authed `/pro/*`.
**Design system:** [WEB-SYSTEM.md §9](WEB-SYSTEM.md#9-responsive--desktop) ·
[SYSTEM.md](SYSTEM.md). **Roadmap:** design-system programme, slice B0.

## Goal & the bug

`ProSidebar` was `w-60 shrink-0` with **no breakpoint**, composed as
`flex min-h-screen` + `<main className="flex-1">`. On a 375px phone the sidebar
took a hard **240px**, leaving ~135px of content **on every `/pro` route, in
production** — the only live layout bug in the design-system programme
(WEB-SYSTEM §15 row 1). WEB-SYSTEM §9 already prescribed the fix: **persistent
sidebar at `lg+`, off-canvas drawer below.**

## Flow parity — a deliberate divergence

The pro *app* is hub-and-spoke: owners navigate from dashboard cards + a Profil
list, and it **withholds** a bottom bar from owners on purpose — the bottom bar
signals "collaborateur" (`staff_home_screen.dart`). The web's nav model is its
**sidebar** (the desktop-grade tool, WEB-SYSTEM §9; memory `web-design-latitude`
grants the web its own responsive design). The honest way a sidebar goes mobile
is an **off-canvas drawer** — the same nav, one tap away — not a bottom bar (which
would misrepresent an owner as staff) and not a third card-grid pattern. So mobile
web keeps the web's persistent-nav affordance; it does not mirror the app's chrome
pixel-for-pixel.

## UX & the four states

- **`lg+` (≥1024px):** unchanged — the persistent sidebar column beside the
  content, no top bar. Byte-for-byte what shipped before, **plus** a new
  active-route highlight.
- **< lg:** a slim sticky top bar (hamburger + « MyWeli Pro » → `/pro`). The
  content is full-width; the sidebar is a drawer that slides in from the left over
  a scrim.
- The nav's own states (loading skeleton, capability-filtered links, the salon
  switcher's states, the member identity block) are unchanged — the drawer
  **reuses the one `<ProSidebar>`**, it does not reimplement it.

## Behaviour (the drawer is a landmark disclosure)

Opened by the hamburger (`aria-expanded` + `aria-controls="pro-sidebar-nav"`). It
is an `<aside aria-label="Navigation du salon">`, **not** `role="dialog"` — one
reused element can't be a dialog at `lg+` and a landmark below it, and a nav
drawer is a disclosure. But on a phone it overlays content, so it behaves modally
**while open**:

- closes on **Escape**, **scrim-click**, the drawer's **✕**, **navigation**
  (a `usePathname` effect — covers link taps and programmatic redirects), and
  **resize past `lg`** (kills the rotate-while-open edge);
- **body scroll locks** while open;
- **focus moves into the drawer** on open and **returns to the hamburger** on
  close;
- the covered `<main>` is **`inert`** while open, so focus can't wander behind the
  scrim; the **closed** drawer is `inert` on a phone so its off-screen links aren't
  tabbable.

## Implementation

- **`components/pro/ProShell.tsx`** (new, client) — the responsive chrome + all
  the drawer state/behaviour above. `main.inert` is set via a **ref** (React 18.3
  doesn't accept `inert` as a JSX prop).
- **`components/pro/ProSidebar.tsx`** — gains `open?`/`onClose?` and responsive
  `<aside>` classes (mobile `fixed … -translate-x-full`, `lg:static
  lg:translate-x-0`), a `lg:hidden` ✕, `aria-current` active links. **One instance
  either way** — the hard constraint, because the RTL/e2e selectors are strict and
  a duplicated nav would break them.
- **`lib/pro/use-is-desktop.ts`** (new) — SSR-safe (`true` until mount, then a
  `matchMedia`-guarded listener). Governs only non-visual focus/`inert`/resize
  behaviour; the column-vs-drawer switch is **pure CSS**, so there's no hydration
  flash, and jsdom (no `matchMedia`) stays on the desktop branch — which is why
  the existing sidebar RTL test is untouched.
- **`app/pro/(dash)/layout.tsx`** — wraps children in `<ProShell>`.

Tokens only: scrim `bg-primary/40`; `z-10` top bar / `z-30` scrim / `z-40` drawer
(the exact numbers B2's named `z-sticky/overlay/modal` scale will rename). No
arbitrary values, no new colour.

## Not in scope

The shared `<Modal>` + real focus-trap primitive is **B5**. This drawer is built
as a disclosure so it can adopt that primitive rather than becoming hand-rolled
modal #7. The A1 token staleness in `web/styles/tokens.ts` is **B1**.

## Tests

- **`tests/pro-mobile-nav.test.tsx`** (RTL) — hamburger disclosure, Escape/✕
  close, scroll-lock, and "the nav renders exactly once". *(Note: `useRouter` must
  be mocked with a **stable** object — a fresh one per call churns the membership
  context's probe callback into an async refetch loop that `findBy`/`waitFor` pumps
  to OOM.)*
- **`tests/e2e/pro-mobile-nav.spec.ts`** — the regression guard that was missing:
  `test.use({ viewport: { width: 375 } })`, content-full-width + drawer off-screen,
  open → navigate → auto-close, Escape/✕. The rest of the pro e2e stay at 1280px.
