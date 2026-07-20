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
| spacing | `p-m` `gap-s` … + **`sm` = 12px** · **`0`** · **`xxxl` = 64px** | `sm` (the §5 half-step) and `xxxl` were in the apps and had silently gone missing from the web mirror — the **second** drift after `gold`, and more evidence for row 19's generator. `0` is not a "spacing value" but `inset-0`/`pb-0` need the key. |
| radius | `rounded-lg` … + **`rounded-pill`** | `pill` = 999px, mirroring `AppTheme.radiusPill`. It replaces `rounded-full`, which was Tailwind's own key and dies with the closed theme. |
| z-index | `z-sticky` `z-modal` … | The layer, **named** — never a number (§9). |
| motion | `duration-base` … | SYSTEM.md §9's scale. `transitionDuration.DEFAULT` **must** stay defined: every bare `transition`/`transition-colors` reads it, so dropping it makes them all instant — silently. |

**A raw hex in `app/` or `components/` is a review failure.** The only literal
allowed is `transparent`. The "3 sanctioned alpha-black scrims" carve-out is gone:
`black` *is* `primary` (both `#000000`), so `bg-black/80` → `bg-primary/80` is
pixel-identical and the Lightbox scrim now matches the dialog scrim family. A
carve-out that was never needed is a carve-out someone else will widen.

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
rule. Most are a token that should exist — add it to the theme instead.

**But not all of them are**, and the rule has to say so or it gets ignored. There is
no token that can hold `h-[calc(100dvh-6.5rem)]`, `grid-cols-[minmax(0,55%)_minmax(0,1fr)]`
or a `repeating-linear-gradient`, and a switch knob's travel is exact geometry
(track 44 − knob 20 − inset 2 = **22**), not spacing. So the escape hatch is a
**declared exception**, mirroring SYSTEM.md §20's `// ds-ignore`:

```tsx
// ds-ignore: <why no token can express this>
// eslint-disable-next-line tailwindcss/no-arbitrary-value
className="h-[calc(100dvh-6.5rem)]"
```

The reason goes **above** the directive (`-next-line` binds to the line that
follows), and `tokens.theme-pin.test.ts` fails an `eslint-disable` that has no
`ds-ignore:` reason within 6 lines. An undocumented disable is not a decision, it is
a silencer. B2a left **17**.

### What is closed, and what is not

`colors` · `borderRadius` · `spacing` · `zIndex` · `screens` · `transitionDuration`
(B2a) · **`fontSize`** — the 15 type roles + §7's 5 icon sizes (B2b, B2c) ·
**`maxWidth`** (B2c). Everything a token *should* govern is closed.

**Sizing stays open — and that is the answer, not a deferral (B2c).** B2a carved the
sizing keys out "until the web gets a sizing scale". B2c checked that premise and it
does not hold: **sizing is not a token class in this design system**
([SYSTEM.md §5](SYSTEM.md#what-§5-does-not-govern)). `AppTheme` has 19 constants — 8
spacing, 6 radius, 5 icon. Mobile sizes every box with a raw number, its pin cannot
see them *by construction*, and it calls the firewall complete anyway. A web-only
sizing scale would be the **fourth** mirror divergence after `gold`, `sm`/`xxxl` and
§4's tracking — and the first with no upstream for B3's generator to track. So
`w-60` is not a violation; `p-4` is. Row 6b is closed as **won't do**.

> ⚠️ **If you ever do close them, read this.** Each key's literals — `w-full` (**58
> uses**), `h-auto`, `w-1/2`, `left-1/2`, `-translate-x-1/2`, `h-screen`,
> `min-h-screen` — do **not** come from `spacing`; they live in the key's *own*
> default block. Writing `theme.width = {…}` deletes all of them, silently: **112 of
> the 250 sizing usages (45%)**. Preserve the function form and re-include the
> literals, or watch half the layout vanish with a green build.

> Measuring beats auditing here: padding/margin/gap turned out to be **already 100%
> tokenised** — `p-3` and `gap-2` do not appear anywhere. The debt was never rhythm.

### Two blind spots the lint has, and why the pin test exists

`eslint-plugin-tailwindcss` is the ergonomic gate (it fires in the editor). It is not
the net, because it cannot see:

1. **A bare `const s = 'rounded-full px-l …'`** — it only reads JSX `className`/`class`
   and configured callees. Three such strings exist. B2a's `rounded-full` sweep had to
   be a **text** replace, not an AST codemod, for exactly this reason: a codemod would
   have left `TaxonomyLandingView`'s chip un-pilled and lint would have said green.
2. **A bare `rounded`.** `borderRadius` has no `DEFAULT`, so Tailwind emits **nothing**
   for it — but the plugin recognises `rounded` as a known class name and passes it
   clean. *Verified.* Lint alone would ship it as an unstyled element.

Hence `tests/tokens.theme-pin.test.ts` — a source sweep, the mirror of mobile's
`design_system_pin_test.dart`.

## 3. Type on the web

Same scale as the apps ([SYSTEM.md §4](SYSTEM.md#4-type)), mapped to **semantic**
Tailwind names so the class says what the text *is*, not how big it happens to be:

The whole scale is live (B2b) — `fontSize` is **closed**, so `text-sm` does not
exist. Each token carries **size + line-height + tracking**; the *weight* is the one
thing it does not carry (see below), so it stays on the element as `font-*`.

| Utility | Size / line | Weight to pair | Was |
|---|---|---|---|
| `text-labelSmall` | 11 / 16 | 500 | `text-[10px]` ×4 (**illegal — under the floor**) + `text-[11px]` |
| `text-bodySmall` | 12 / 16 | 400 | `text-xs` ×82 |
| `text-labelMedium` | 12 / 16 | 500 | `text-xs font-medium` ×8 |
| `text-bodyMedium` | 14 / 20 | 400 | `text-sm` ×355 — the workhorse |
| `text-labelLarge` / `text-titleSmall` | 14 / 20 | 500 | `text-sm font-medium` ×25. Pixel-identical to each other; the name is the role |
| `text-bodyLarge` / `text-titleMedium` | 16 / 24 | 400 / 500 | `text-base` ×1 |
| `text-titleLarge` | 22 / 28 | 600 | **`text-lg` ×33 (18px) + `text-xl` ×18 (20px)** |
| `text-headlineSmall` | 24 / 32 | 600 | `text-2xl` ×27 |
| `text-headlineMedium` | 28 / 36 | 600 | `text-3xl` ×5 (30px) |
| `text-headlineLarge` | 32 / 40 | 600 | `text-4xl` ×1 (36px) |

**Not a zero-pixel rename — this is what B2b actually did.** The register said it
would be; measuring said otherwise, and the difference matters because "zero-pixel"
is the sentence a reader uses to skip visual review:

- **498 of 555 (90%) are exact** — 12/16, 14/20, 16/24, 24/32 reproduce size *and*
  line-height.
- **57 move the glyph.** Tailwind's 18/20/30/36 steps have no counterpart in a
  Material 11/12/14/16/22/24/28/32 scale, which is precisely *why* the same role had
  drifted: of 42 `<h2>` on main, **23 were 18px, 15 were 20px and 4 had no size at
  all** — three outcomes for one role. Snapping by §4's own names (`titleLarge` =
  "card/section heading") is what makes that impossible again.
- **Line-heights hold — with exactly 2 carve-outs**, both measured in a browser, both
  caused by the same subtlety: `leading-*` is a **unitless multiplier**, so it does
  not pin a px value, it *transmits* the size change.
  - `ProviderCard`'s ♥ (`leading-none`): 18 → 22px line, +4px box.
  - `ClientCardClient`'s MyWeli badge: it had no line-height of its own (an
    arbitrary `text-[10px]` emits font-size only) and **inherited its `<h1>`'s
    absolute 28px**; `labelSmall` gives it 16px, so the pill shrinks 28 → 16px.
    That is a fix — it was a huge pill around a 10px word — but it is visible.
- **Tracking arrives on 476 of the 560.** The other **84 are the headings**
  (`titleLarge` ×51, `headlineSmall` ×27, `headlineMedium` ×5, `headlineLarge` ×1),
  whose tracking is **0 by design** in §4. The web had none anywhere; the app has had
  it all along.
- **Two sites are a role the scale does not have.** `Lightbox`'s ✕ and
  `ProviderCard`'s ♥ are interactive **icon glyphs**, and they took `titleLarge`
  ("card/section heading") purely because 18px has no token. The web has no icon-size
  scale — SYSTEM.md §7 defines one for the apps, and the web's sizing lands with
  **B2c** (row 6b). Until then the class names those two elements wrongly.

### Icons are text, so their size is a font-size (B2c)

§7's scale ported verbatim from `AppTheme.iconXS…iconXL`, and it lives in `fontSize`
beside the type roles — because **every icon on the web is a text character**
(✕ ♥ ★ ✓ ⋯), so its size *is* a font-size.

| Utility | Size | Use for |
|---|---|---|
| `text-iconXS` | 16 | Inline with `bodySmall`/`labelMedium`; dense chips |
| `text-iconS` | 20 | Inline with text — the leading icon in a button, a row |
| `text-iconM` | 24 | **The default action icon** |
| `text-iconL` | 32 | Feature / avatar-scale glyphs |
| `text-iconXL` | 64 | The empty-state illustration |

**A size, and only a size** — a bare value, not a `[size, {lineHeight}]` tuple like
the type roles. That is what makes it a *port*: `AppTheme.iconXS` is `16.0`, and
Flutter's `Icon(size:)` has no line-height, so baking one would invent a concept the
upstream doesn't have. It is also load-bearing — B2c first shipped `lineHeight: 1`
and the review measured it **shrinking seven controls' boxes by 4–8px**, because
preflight's `html { line-height: 1.5 }` is what gives an inheriting button its height.
§7 says *never grow the glyph to make the target bigger — grow the target*; that cuts
both ways, and a font-size token has no business shrinking one (§15 row 7h).

Before B2c the same `✕` rendered at **12, 14, 22px and three different inherited
sizes**, and two wore `titleLarge` — a class reading "card/section heading" on a close
button. Snapped by §7's own method (nearest; ties round up).

**A glyph *inside a text run* is not an icon.** `★ 4,8 sur 5` and `← Tableau de bord`
are sentences; they track the type scale and were left alone. Only a control whose
entire content is the glyph takes an icon token.

⚠️ **An icon's size and its tap target are different things** ([SYSTEM.md §7](SYSTEM.md#7-icon-size)):
`iconM` is 24px of glyph inside a **≥48px** target (§13.2). Never grow the glyph to
make the target bigger — grow the target. **No web control reaches 48 today** (§15) —
that is not fixable with a font-size.

**Weight is not in the token, deliberately** — the single place the web mirror
diverges from Flutter's atomic `TextStyle`, so B3's generator must encode it. Tailwind
emits fontSize (118) before fontWeight (119), so a baked weight is only a default that
any `font-*` beats — but it would still silently override *inheritance* (the MyWeli
badge inherits 600 from its `<h1 font-semibold>`; a baked 500 would quietly undo it),
and it buys nothing while `fontWeight` itself stays an open key. Omitting it means B2b
changed **zero** weights.

⚠️ **The web is still one step smaller than the app.** `text-bodyMedium` (14px) is
**356 of 555** usages and `bodyLarge` (16px) is used **once**; the app reads at 16px.
That inconsistency survives B2b untouched — the 14 → 16 migration is **B8** (row 17),
still uncommitted.

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

The fix is one base-layer rule, not 271 utilities — **shipped in B4**
(`styles/globals.css`, and `tests/e2e/focus.spec.ts` pins its computed values):

```css
:focus-visible {
  outline: 2px solid theme('colors.borderFocus');
  outline-offset: 2px;
  border-radius: theme('borderRadius.md');
}
```

- `:focus-visible`, **not** `:focus` — a clicked **button** shows no ring. A
  clicked **text field** does, and that is platform-correct (a field you clicked
  is a field you will type in) — don't "fix" it; the e2e asserts on a button.
- Never `outline: none` without an equally visible replacement. One place cannot
  use the global ring at all: the phone widget's country `<select>` is an
  opacity-0 overlay, so its focus is painted on the sibling flag icon in
  `.myweli-phone` CSS — kept hand-written, deliberately.
- Tab order follows DOM order; `tabIndex` > 0 is banned.
- The "Aller au contenu" skip link is the first focusable element on every page
  (`app/layout.tsx` → the `#contenu` wrapper) — and the ring's most visible
  proof: the first Tab on any page shows both.
- Hover-only affordances (menus, tooltips) must also open on focus (the
  `/recherche` result-card ↔ map-pin highlight sync gained `onFocus`/`onBlur`
  in B4 for exactly this).

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

All of this lives in **one shared `<TextField>`** (§10) — shipped in B4
(`components/TextField.tsx`, mirroring the app's `InputDecorationTheme` state
table: `borderStrong` → `borderFocus`+ring on focus → `error`, soft `border`
disabled; `min-h-12`; `useId`). `PhoneField` wears the same shell — the library
forwards `id`/`aria-*` to its inner input. Seven ad-hoc input copies is how we
ended up with zero labels; the copies are gone.

§14's rule 2 has a hook: `lib/forms/useFieldErrors.ts` (validate on submit,
re-validate on change once errored, `set()` for server-side field faults — «
Code incorrect ou expiré » belongs under the code field too). The auth funnels
are the reference implementation, and their old `disabled={!emailValid}` gates
— rule 5's dead-end anti-pattern — are gone with it.

## 7. Announcements (live regions)

A visual toast is silent to a screen reader. Anything that appears without a page
navigation must announce itself:

- **Toasts / status messages** → `role="status"` + `aria-live="polite"`.
- **Errors that interrupt** → `role="alert"` (assertive; use sparingly).
- **Async results** ("12 salons trouvés") → a polite live region.
- The region must exist in the DOM **before** the text lands, or nothing is read.

**Shipped in B5** — `components/Toast.tsx` + `lib/useToast.ts` is the single
transient-feedback entry point (SYSTEM §15's kind/duration table: success/info
3 s, error 6 s; the with-action row is deliberately absent — zero callers
product-wide). The component **always** renders the `role="status"` region and
swaps the pill inside it — the region-before-text rule held structurally; every
pre-B5 toast (including the one that had `role="status"`) mounted the region
together with its text. Beyond the toasts, B5 swept **56 silent error-outcome
sites** onto `role="alert"` (insertion-announced — the alert exception), the
five « Enregistré. » confirmations + the go-live banner onto persistent
`role="status"` regions whose **text** toggles, and the two « Copié ✓ » label
swaps onto sr-only status twins. « Chargement… » strings await B6's `Loading`.

## 8. Dialogs

Six hand-rolled modals, **zero** focus traps. A modal that doesn't trap focus lets
a keyboard user tab out into the page behind it — where they are stuck, invisible,
interacting with content that is visually covered.

One shared `<Modal>` — **shipped in B5** (`components/Modal.tsx`), all six
dialogs converted:

- `role="dialog"` `aria-modal="true"` `aria-labelledby` (Modal renders its own
  `<h2>` title; `label` replaces it for the title-less Lightbox).
- **Focus moves in on open** (`initialFocusRef` ?? first focusable — the
  EquipeClient revoke confirm points it at **Annuler**, SYSTEM §15's
  cancel-gets-focus), **is trapped inside** (Tab/Shift+Tab cycle), **and
  returns to the opener on close** (guarded — the opener may have unmounted).
- **Esc closes** (capture + stopPropagation, so a modal above the pro drawer
  closes alone). Background scroll locks.
- The overlay is an `aria-hidden` scrim sibling carrying the dismiss click —
  never a `<div onClick>` masquerading as a button. Deliberately hand-rolled,
  not native `<dialog>`: jsdom has no `showModal()` and `z-layers.spec.ts`
  asserts the token stack.

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
| `z-auto` | `auto` | The escape from the scale. Load-bearing at one site: at `lg:` the pro sidebar is a **flex item**, and z-index applies to flex items whatever their `position` — `z-base` (0) is *not* a substitute, because `0` creates a stacking context on a flex item and would trap the salon-switcher dropdown inside the aside; `auto` does not. |

**Ties are resolved by DOM order — so if two things at the same layer can coexist,
one of them is at the wrong layer.** That is not pedantry: `JournalPanel` and the
mobile drawer were both `z-40`, and the panel renders later, so it painted above the
drawer's `z-30` scrim and stayed **bright while the whole page dimmed** (B2a). A
number carries no intent, so nobody could see the collision; `dropdown` vs `modal`
states it. Note what could *not* catch it — the two sit on opposite edges and never
overlap, and `<main>` is `inert` while the drawer is open, so a hit-test returns the
scrim regardless. Only comparing the computed layers sees it
(`tests/e2e/z-layers.spec.ts`).

## 10. Components

Shared components live in `web/components/`. **The library is currently one
component** (`Button`, 108 uses) — which is why there are 35 inline "Chargement…"
strings (17 of them byte-identical), 6 hand-rolled modals, 5 hand-rolled toasts and
7 ad-hoc inputs. A missing primitive doesn't prevent the UI from being built; it
just guarantees it's built inconsistently, N times.

Existing: `Button` (48-floor, `text` variant, `isLoading` — parity complete, B4)
· **`TextField`** (B4) · `PhoneField` (label/error shell, B4) · `AppInstallBanner`
· `OpenInAppButton` · `SalonTimeHint` · `LocalityPicker` · `ProviderCard` ·
`TeamRoleChip` · `JsonLd` · `Lightbox` · `SiteChrome` / `Header`.

To build (specified in [SYSTEM.md §11.3](SYSTEM.md#113-to-build-the-gaps-this-system-creates-work-for)
where they have an app twin):

| Component | Why |
|---|---|
| ~~**`Toast`**~~ | §7 — `aria-live`. **Shipped in B5** (+ `useToast`, §15 durations). |
| ~~**`Modal`**~~ | §8 — focus trap. **Shipped in B5** — all 6 dialogs converted. |
| `Loading` / `Skeleton` | Kills the 35 inline "Chargement…" strings. 1 skeleton exists; `animate-pulse` = 0. |
| `EmptyState` / `ErrorState` | ~15 error paths currently offer **no retry**. |
| `Rating` | Glyph + numeral ([SYSTEM.md §3.5](SYSTEM.md#35-accents)). |
| `Card` · `StatusChip` · `DataTable` | The pro/admin density work. |

(`TextField` and Button's `text`/`isLoading` parity landed in B4. The switch
remains hand-rolled in NotificationsClient — §10 specs no Switch primitive; its
48px target and row-label association were fixed in place.)

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
| Tokens only (§2) | **Closed Tailwind theme** (B2a) + `eslint-plugin-tailwindcss` (`no-custom-classname`, `no-arbitrary-value`) as **errors** — **and** `tokens.theme-pin.test.ts`, because the lint has two blind spots (bare `const` class strings; a bare `rounded`, which it passes clean while Tailwind emits nothing). Config lives in **`.eslintrc.js`**, not `.json`: the plugin resolves `tailwindcss` relative to `dirname(settings.tailwindcss.config)`, so a *relative* config path makes it look in `.` and throw — JSON cannot compute an absolute path |
| Layering (§9) | `tests/e2e/z-layers.spec.ts` — the drawer/scrim/panel stack and the map control, asserted on **computed layers** (a hit-test can't see it: `<main>` is `inert` while the drawer is open, and inert content isn't hit-tested) |
| Semantic HTML, labels, keyboard (§4–§6) | **`eslint-plugin-jsx-a11y` strict** — `label-has-associated-control`, `click-events-have-key-events`, `heading-has-content`, `anchor-is-valid`, … |
| The whole of §4–§8, on real pages | **`@axe-core/playwright`** over **13 routes + 2 stateful scans** (an open Modal, a visible toast) inside the **already-blocking** e2e job (`tests/e2e/axe.spec.ts`, B5; proof-red at base: 11 violations / 5 rules / 8 routes — 3 rules were new finds) |
| Regression | Lighthouse a11y ≥ **0.95** as an **error** on `/` + `/connexion` (B5; SEO ≥ 0.9 errors on `/` — `/connexion` is deliberately noindex, so its SEO score gates nothing) |
| Everything | typecheck · lint · `vitest` · `next build` |

Two of these are the point:

- **`.eslintrc.js`** (not `.json` — stale since B2a) now extends
  **`plugin:jsx-a11y/strict`** (B4): the four rules named above plus ~20 more, as
  errors, with one calibration — `label-has-associated-control: {depth: 25}`
  (the default depth-2 walk false-positived on label text three levels deep).
  At B4's branch base the strict set measured **16 errors across 5 rules**; all
  16 were fixed for real — **zero disables** — and the theme-pin now rejects any
  `eslint-disable jsx-a11y/*` that lacks `ds-ignore:` prose. Trivia with a moral:
  three of the 16 were `img-redundant-alt` catching the **French** word « Photo »
  — the rule's banned-word list is language-blind, the alts were reworded to say
  what the image shows.
- **Lighthouse was `continue-on-error: true`, a11y `warn`, one URL** — a gate
  that cannot fail, looking at one page. B5 promoted it: the job blocks, a11y
  0.95 + SEO 0.9 are errors (perf/best-practices stay `warn` — the flake-prone
  pair), and `/connexion` joined via `assertMatrix` (a11y only — it is noindex
  by design).

## 15. The known-violations register

Counted in the code as of 2026-07-14. Each burn-down PR drives a row to **0**.

| # | Rule | Violations | Worst instance | Slice |
|---|---|---|---|---|
| 1 | Layout works at every width (§9) | ~~1~~ → **0** | the pro sidebar ate 240px of a 375px phone on every `/pro` route; now an off-canvas drawer below `lg`, persistent at `lg+` ([web-pro-mobile-nav.md](web-pro-mobile-nav.md)) | ✅ **B0** |
| 2 | `textTertiary` ≥ 4.5:1 | ~~170~~ → **0** | was 3.22:1; the token is now **4.76:1** (the value alone healed all 170) — and the ink softened to `#1A1A1A` | ✅ **B1** |
| 3 | Control borders ≥ 3:1 | ~~186~~ → **0** | `borderStrong` on every control boundary: `<TextField>` bakes it in; the 6 copy-pasted `const input` strings and every remaining hand-classed control were upgraded in place, **including the phone widgets the original count never saw** (react-phone-number-input renders an input + a country select the grep missed — `.myweli-phone` now draws borderStrong too). "~20 hand-classed" was really 93 literal controls + ~12 phone-widget internals | ✅ **B1 → B4** |
| 4 | Token exists ⇒ no substitution | ~~1~~ → **0** | `gold #B8860B` is exported; `TeamRoleChip` uses it. A test grep-pin fails if any `bg-/border-starRating` returns | ✅ **B1** |
| 5 | Splash matches the app | ~~1~~ → **0** | `manifest.ts` `background_color` → `#F6F7F9` (no more black flash); `theme_color` stays brand black | ✅ **B1** |
| 6 | Closed theme (§2) | open → **closed, except sizing** | `colors` · `borderRadius` · `spacing`(rhythm) · `zIndex` · `screens` · `transitionDuration` are now `theme`, not `theme.extend`: a non-token utility **does not exist**. Held by `no-custom-classname` (**0**) + `tokens.theme-pin.test.ts`, because Tailwind emits *nothing* for an unknown utility — a dead class ships as an unstyled element and no build, typecheck or test can see it. Proven by diffing the emitted CSS: 298 → 287 selectors, every one of the 11 deliberate. **`fontSize` closed in B2b** — the 15-style scale now lives in `tokens.ts`, mirrored from `text_styles.dart` (the code) rather than §4's table (the doc, which omitted tracking). **`maxWidth` closed in B2c**, which also fixed a live leak (row 7g). **Sizing is deliberately NOT closed** — it is not a token class (row 6b) | ✅ **B2a + B2b + B2c** |
| 6b | A sizing scale (§2, §9) | **won't do** | B2c checked the premise and it is wrong: **sizing is not a token class** ([§5](SYSTEM.md#what-§5-does-not-govern)). `AppTheme` has 19 constants (8 spacing · 6 radius · 5 icon); mobile sizes every box with a raw number; its pin cannot see them *by construction* (the regex needs `)` right after the number, so a sized container never matches) and calls the firewall **complete** anyway. A web-only scale would be the **fourth** mirror divergence — and the first with no upstream for B3. What B2c did instead: ported §7's icons, closed `maxWidth`, and put the doctrine in §5 where a reader will find it. ⚠️ And recorded the trap: closing these keys would silently delete `w-full` (**58 uses**) and 111 other literals — they come from each key's own block, not from `spacing` | ✅ **B2c** |
| 7 | No arbitrary values (§2) | ~~`z-[5]` `z-[6]` `z-[7]` `z-[1100]` `py-[2px]`~~ → **0 undeclared** | `no-arbitrary-value` is an **error**. Every arbitrary `z-` is gone: `z-[5/6/7]` were never isolated (no stacking context in the chain) so the JournalGrid column is now ordered bottom-to-top in the **DOM** and needs no z at all; `z-[1100]` was cargo cult (maplibre's own vocabulary is 1/2) → `z-sticky`. **14 declared exceptions** remain (B2a left 18; B2b cleared the 4 type ones — `JournalGrid`'s survives for its `py-[2px]`), each with a `ds-ignore:` reason the pin test enforces: a `calc()`, two grid templates, a gradient, the switch's exact 44−20−2 travel, the 2px chip paddings… | ✅ **B2a** |
| 7b | Type below the §3 floor | ~~4~~ → **0** | the 4 `text-[10px]` are `text-labelSmall` (11px). Not a rename — §4 is explicit ("there is no 10px token and there will not be one"), so this is a redesign: +1px, and the badges gain the line-height an arbitrary size never emitted. `ClientCardClient`'s inherited its `<h1>`'s 28px line and is now a 16px box — smaller, and correct | ✅ **B2b** |
| 7c | **The pin was blind** | ~~2 files~~ → **0** | B2a's `stripComments` read the `/*` in `accept="image/*"` as a block comment with no close, so the pin saw **nothing** from that line to EOF in `MediasClient` + `DepositProof` — hiding 6 real type usages. It shipped that way. Replaced with a **TypeScript AST walk**: comment-immune by construction rather than by regex, and it reaches the 4 bare-`const`/default-param strings ESLint cannot see | ✅ **B2b** |
| 7d | **The pin had no positive rule** | ~~1~~ → **0** | every rule was a prohibition, and during B2b's own migration window — classes renamed, config not yet wired — all 555 emitted **nothing**, the site rendered at browser-default 16px, and the pin passed **green**, because the old tokens it bans were gone. "No forbidden classes" ≠ "the classes we use exist". A `resolveConfig` assertion now makes the second claim | ✅ **B2b** |
| 8 | **Visible focus (§5)** | ~~0~~ → **shipped** | §5's base rule verbatim (2px `borderFocus`, offset 2, radius md) + the "Aller au contenu" skip link as the first focusable on every page. Counts corrected: **180** buttons (109 `<Button>` + 71 raw), not 178. Keyboard-only trigger **measured** in `focus.spec.ts` (proven red first): ring on Tab, none on a clicked button — and a clicked *text field* legitimately shows it (platform behaviour, recorded not fought). The one place the global ring cannot work — the phone country select, an invisible overlay — keeps a hand-written ring on its sibling icon, fixed from its pre-§5 form (`:focus` → `:focus-visible`, `primary` → `borderFocus`, offset 1 → 2) | ✅ **B4** |
| 9 | Labelled inputs (§6) | ~~0~~ → **every control associated** | `<TextField>` (label + `useId`) across the funnels, account, booking, clients, dialogs; label-*wrapped* forms (ProfilClient's `Field`, the label-wrapped dialogs) kept their working implicit association — the metric that matters is *associated*, not *htmlFor specifically*. The funnels' 8 placeholder-only inputs have real labels ("Votre e-mail" replaced its placeholder; "Code à 6 chiffres" became one; "07 00 00 00 00" survives as a format example, the one legitimate placeholder role). Optional fields say « (optionnelle) » in the label (§14 rule 6) | ✅ **B4** |
| 10 | Errors tied to fields (§6) | ~~0~~ → **wired** | `<TextField>`/`PhoneField` render `aria-invalid` + `aria-describedby` (error id first, hint id second) + `<p role="alert">`; `useFieldErrors` implements §14 rule 2 (validate on submit, re-validate on change once errored, `set()` for server faults — « Code incorrect ou expiré » now renders under the code field). The funnels' `disabled={!emailValid}` gates — rule 5's dead-end anti-pattern — are gone; an invalid submit answers with a field error. E2e-proven: the describedby chain resolves id-by-id. **The first `validate()` replaced the whole error map** — a step-2 submit wiped a still-unfixed step-1 error and the submit fired with the empty value (the review proved it on ProRegister's businessName); it now **merges**, touching only the keys it validated, and ProRegister validates each path's full field subset | ✅ **B4** |
| 11 | jsx-a11y strict (§14) | ~~off~~ → **on, 0 errors, 0 disables** | branch-base proof-red = **16 errors / 5 rules** (3 were `label-has-associated-control` depth-2 false positives → `{depth: 25}`; 3 were `img-redundant-alt` catching the **French** « Photo » — reworded to say what the image shows; the rest: the 2 raw PhoneInput labels, the dialog backdrops restructured to ProShell's aria-hidden-scrim precedent, the `/recherche` hover-sync wrapper gaining focus parity). The theme-pin rejects an undocumented `eslint-disable jsx-a11y/*` | ✅ **B4** |
| 12 | Announcements (§7) | ~~0~~ → **wired product-wide** | the count was low three ways: 5 toasts (1 announced — unreliably: its region mounted WITH the text, against §7's own rule — and it was the one toast missing `z-toast`), **plus ~63 silent outcome sites nobody had counted**. Shipped: `<Toast>`/`useToast` (§15 durations; the region always exists, text swaps inside) over the 4 fixed toasts + the map note in place; `role="alert"` on **56** error-outcome sites; persistent `role="status"` on the 5 « Enregistré. » confirmations + the go-live banner; sr-only status twins for the 2 « Copié ✓ » swaps. « Chargement… » → B6's `Loading` | ✅ **B5** |
| 13 | Focus-trapped dialogs (§8) | ~~0 of 6~~ → **6 of 6** | the debt was wider than the trap: focus-in/restore **0/6**, scroll lock **0/6**, Escape **2/6**, three scrim patterns. One `<Modal>` (trap · Escape · restore guarded on `isConnected` · scroll lock · aria-labelledby'd h2) converted all six; the revoke confirm focuses **Annuler** (SYSTEM §15). `Button` gained `forwardRef` for exactly that | ✅ **B5** |
| 14 | Heading order (§4) | ~~1~~ → **0** | the count was 1 of **2**: `/recherche`'s h1→h3 (fixed by promoting the tertiary count `<p>` to the visible « N salons » h2 — the card was already correct on home/landing under their h2 sections) — and `/mon-compte/[id]` had **no h1 at all** (the salon-name h2 is promoted; it is the page's only heading). Row 7f's 4 token-less h2s joined `text-titleLarge` here | ✅ **B5** |
| 15 | axe on real routes (§14) | ~~none~~ → **13 routes + 2 stateful scans, blocking** | proof-red at base (measured in a worktree, `axe-base.json`): **11 violations / 13 nodes / 5 rules / 8 of 12 routes** — and 3 of the 5 rules were violations **nothing in this register knew**: `region` ×7 routes (the home hero — h1 + search — sat OUTSIDE `<main>`; the install banner was landmark-less chrome everywhere), `nested-interactive` (maplibre stamps `role=button` on its marker wrapper around our named pin — the child now claims the wrapper as presentation before `addTo`), `aria-prohibited-attr` (MapEmbed's aria-label on a role-less div), `empty-table-header` (Équipe's actions column). The row-21 radiogroup never fired at base because the stars' route wasn't in the first matrix — it is now (13th route). Lighthouse promoted to blocking (a11y 0.95 + SEO 0.9 as errors; `/connexion` a11y-only — noindex by design) | ✅ **B5** |
| 16 | Shared primitives (§10) | library = **1** → growing | 35 inline "Chargement", 6 modals, 5 toasts, 7 inputs. B4 added `TextField`/`Button`/`PhoneField` — and found `OtpLoginForm` has **zero callers** (both funnels inline their own OTP steps): a "shared" component nothing shares. Keep-or-delete is B6's call | *B6* |
| 7e | Icons borrow a type role | ~~2~~ → **0** | the count was the *tokenised* ones. Measured, the same `✕` rendered at **12, 14, 22px and three inherited sizes** — the drift was in the 24 nobody counted. §7's scale is ported (`text-iconXS…XL`, **a bare size** — see §3) and 10 standalone glyph controls snapped to it by §7's own method. The inheriting ✕s sat at the 16px body default → `iconXS` is **zero-pixel, box included** (measured: font 16 · line 24 · box 24 on both sides); the rest move by the snap and every one **grows** (♡ 22→24, box 26→28), which is the right direction for row 7h. **The first attempt did not**: baking `lineHeight: 1` shrank 7 boxes by 4–8px, and the review measured it — a font-size token quietly regressing the tap-target metric this very slice added. A glyph *inside a sentence* (`★ 4,8 sur 5`, `← Tableau de bord`) is text, not an icon, and was left alone | ✅ **B2c** |
| 7g | **The `maxWidth` leak** | ~~5~~ → **0** | `maxWidth` spread `spacing` **first**, so `max-w-s`=8px · `max-w-m`=16px · `max-w-l`=24px · `max-w-xxl`=48px · `max-w-xxxl`=64px — rhythm tokens acting as max-widths — while `max-w-sm`=24rem and `max-w-xl`=36rem, because Tailwind's names win where they collide. `max-w-l` (24px) and `max-w-xl` (576px) sat adjacent in one scheme, **24× apart**. Closed to the named steps; the 7 in use are byte-identical | ✅ **B2c** |
| 7h | **Tap targets ≥ 48 (§13.2)** | ~~0 of ~10~~ → **0 remaining** | the count was wrong **three** times over: the glyph floor was **16px** (not 18); the census missed HeaderBell (20×20) and the phone country selects; and the first "0 remaining" claim here was **false** — the adversarial review measured a long tail the sweep never reached (the header logo 70×28 and « MyWeli Pro » 112×28 wordmark links, sidebar nav links 207×36 at a 4px stride, the salon switcher ~30, ManualBookingDialog's checkbox/client rows 28 and « Changer » 57×20, ClientCardClient's tag pills + tel links + « Supprimer », DayHoursEditor's « Travaille » rows) — **and** four adjacency violations the sweep itself had *created* with two-sided negative margins (banner ✕/bell/hamburger abutting neighbours at 0–4px; fixed one-sided), plus MediasClient's 3×48 IconBtn row overflowing its 155px grid-cols-2 card at 375 (fixed: 1-col base / `sm:2` / `lg:3` + a wrapping footer). Fixed by A4a's two patterns, ported: bordered boxes/pills grow visibly (`Button` 36→48 = mobile A3's `Size(0, 48)`; chips 28→48; IconBtn; the Lightbox ✕ pill; ReviewForm's stars 24→48 each **+ `gap-s` fixing their 4px adjacency violation**); tight-layout glyphs grow invisibly (padding + **one-sided** negative margin where a neighbour exists, glyph unmoved); the switch keeps its 44×24 track inside a 48 target, labelled by its row title; the photo-✕ badges got 48 wrappers at compensated offsets; text-links became `<Button variant="text">` or floored in place. MonthCalendar cells: **height floored at 48, width grid-bound (~43 at 375px)** — recorded, not hidden. Pinned by `tap-targets.spec.ts` (boundingBox ≥ 48 over the control table, incl. the review's finds; EquipeClient's ⋯ is floored in code but **not pinnable** — the stub seeds no second member, and the first draft's guard passed vacuously). B5 found one more in passing — the map's « Autour de moi » at 40px — floored + `borderStrong` | ✅ **B4** (+B5) |
| 7i | No `<Icon>` component | **4 channels** | icon size lives in Tailwind classes (2 of 5 svgs), raw SVG `width`/`height` attrs (3), `globals.css` (the 44px map pin, a 22px dot), and font-size (10 glyphs). B2c governs the last; a real `<Icon>` would govern all four | *B6* |
| 7j | `contentMaxWidth` unapplied | **1** | §10's `contentMaxWidth = 720` is the only non-icon dimension the system names, and it had never existed in code on either surface. B2c makes it a token (`max-w-content`); **applying** it to the pages that need it is a layout decision | *B7* |
| 7f | `<h2>` with no type token | ~~4~~ → **0** | all four (`ClientCardClient` ×2, `JournalPanel`, `ProRegisterClient`) joined their 38 peers on `text-titleLarge` (ProRegister's also traded `font-medium` for the peers' `font-semibold`) | ✅ **B5** |
| 17 | Reading text = 16px (§3) | **356 × `text-bodyMedium`** | `bodyLarge` (16px) used **once**. B2b renamed the workhorse but did not resize it — the web still reads one step smaller than the app | *B8* |
| 18 | Desktop-grade pro dashboard (§9) | `xl:`/`2xl:` = **0** | a stretched phone column | *B7* |
| 19 | Token generator (Flutter → `tokens.ts`) | hand-mirrored | drifted **six times** now (row 4; B4 found `borderFocus` missing — §5's own snippet would not have built — and `warningLight`/`infoLight` still exist on mobile only) | *B3* |
| 20 | Role pickers announce selection | ~~visual-only~~ → **`aria-pressed`** | ChangeRoleDialog/InviteMemberDialog's role rows showed the chosen role by border colour alone — a screen reader heard four identical buttons. Two lines each | ✅ **B4** |
| 21 | ReviewForm stars: toggle semantics | ~~5 × `aria-pressed`~~ → **a real radio group** | worse than "loose": `aria-pressed` buttons are **invalid children** of `role="radiogroup"` (axe `aria-required-children`). Now `role="radio"` + `aria-checked` on the chosen value, one roving tab stop, arrows move-and-select **wrapping at the edges** (APG); the ≥48px targets and `rating >= n` fill are untouched. Pinned by the axe matrix's 13th route | ✅ **B5** |
| 22 | FilePick is keyboard-inaccessible | ~~3~~ → **0** | the count was wrong twice: **5** hidden file inputs exist, but 3 (Verification, Catalogue, ReviewForm) already had focusable proxy `<Button>`s — only **MediasClient's two** label-wrapped pickers were keyboard-dead. Both: `hidden` → `sr-only` (a real tab stop) + §5's ring projected onto the label via `focus-within:outline-*`. DepositProof's sixth input was always visible | ✅ **B5** |

**Bold** slices are committed (the a11y tranche). *Italic* are specified and
scheduled for re-evaluation after it.

---

*Supersedes `WEB-DESIGN-STANDARDS.md`. Shared rules: [SYSTEM.md](SYSTEM.md).
Enforced by the `myweli-web-guardrails` skill.*
