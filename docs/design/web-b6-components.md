# web-b6-components — Loading/Skeleton, EmptyState/ErrorState, Icon, Rating, Chip (B6)

**Status:** Built (2026-07-21). **Surface:** `web/` · every async state, every
icon, every pill.
**Design system:** [WEB-SYSTEM.md §3, §10](WEB-SYSTEM.md#10-components) ·
[SYSTEM.md §3.5, §7, §11–§12, §16](SYSTEM.md#11-components). **Roadmap:**
design-system programme, slice B6 (register rows 16 · 7i).

## Goal & the debt

The library grew (Button, TextField, PhoneField, Toast, Modal) but the four
states never got their primitives, measured:

- **Loading**: the register's « 35 » was the raw `Chargement` grep; the real
  ledger (review-corrected): **18 byte-identical** full-page `<p>`s, 5 section
  loaders + 1 main-wrapped, 3 map placeholders, 3 `<option>`s (4 grep hits were
  « Chargement impossible. » error alerts, not loaders) — plus **7 hand-rolled
  label swaps** (« Envoi… », mostly non-`Chargement` strings) bypassing the
  `Button isLoading` B4 shipped. ONE skeleton exists (ProSidebar, static grey, no pulse);
  `animate-pulse` = 0 product-wide — §12's "skeleton when the shape is known"
  was satisfied nowhere.
- **Empty**: ~20 sites, **zero icons product-wide**, mostly bare dead-end
  sentences. Mobile's `EmptyState` (icon `iconXL` → title → why → action) is
  the anatomy the web never mirrored.
- **Error**: 12 bare `role="alert"` dead ends whose copy says « Réessayez. »
  **and ships no retry control** (11 byte-identical) — §12 calls that "a crash
  with better manners" — plus the ~15 h1-less pro error states B5 recorded
  against this slice. 7 sites hand-rolled message + « Réessayer » correctly:
  the reference tier the component generalizes.
- **Icons (row 7i)**: sizing in 4 channels — 5 inline svgs (2 Tailwind-sized,
  3 attr-sized), 10 font-size glyphs, 2 globals.css boxes — with the Material
  paths already copy-pasted inline twice (`salon-pin` ICON_PATHS,
  `NotificationsClient` TYPE_PATHS).
- **Rating**: every site renders `★ {x.toFixed(1)}` — the **anglophone
  decimal point** on a French product (AppRating's spec is « ★ 4,8 (32 avis) »);
  AvisClient's ★★★★☆ bar carries its numeral only in the aria-label (§3.5 says
  glyph + numeral, ALWAYS).
- **Chips**: ~24 hand-rolled pills in 3 families + `TeamRoleChip` — whose own
  `ds-ignore` promised itself to « B6's shared `<Chip>` ». **None** uses
  `borderStrong` on the outlined variant (§16: mandatory on every interactive
  control boundary, "outlined chips" named explicitly).
- `OtpLoginForm`: zero callers, zero tests (row 16 recorded the keep-or-delete
  as B6's call — **deleted**).

## The contracts

### `<Icon name size label?>` (row 7i)

One svg component over a named path registry (24×24 viewBox, Material-outlined
paths — consolidating the two inline registries + the handful EmptyState
needs). Sized by the §7 token name (`iconXS…iconXL` → the `icon` export's px);
`fill="currentColor"`; `aria-hidden` unless `label` (then `role="img"`).

**The honest channel recount** (row 7i closes on this, not on "one component
governs everything"): the svg channels unify under `<Icon>`. The font-size
glyph channel (✕ ★ ♥ ⋯) is **correct by WEB-SYSTEM §3's own doctrine** — a
text character's size IS a font-size; B2c governs it. The two globals.css
sizes are **not icon sizes**: the 44px `.myweli-pin` is marker/tap geometry
that HOSTS an on-scale 20px `<Icon>`; the 22px user dot is a dot. The
hamburger stays a stroke svg in place — the one stroke icon; converting it to
a filled path would change its look for zero doctrine gain.

### `<Loading label?>` + `<Skeleton>` (§12 loading)

`Loading`: the Button-idiom spinner (`animate-spin rounded-pill border-2
border-current border-t-transparent`) + a visible label (default
« Chargement… »; contextual copy passes through). Deliberately NOT a live
region — B5's doctrine: regions pre-exist their text; a loading state is
removed, not announced.

`Skeleton`: `animate-pulse` `bg-surfaceVariant` blocks, `aria-hidden`, with
`Rows` (the ProSidebar shape, generalized) and `Grid` presets. Applied per
§12's rule using the census's shape classification: **list pages → Rows,
card grids → Grid, shape-unknown (forms · single-record detail · maps ·
slot loads) → `Loading`** with their contextual labels kept. **6** of the 7
label swaps route through `Button isLoading` — the 7th is MediasClient's
file-pick `<label>` (« Téléversement… »), which cannot be a Button; its swap
stays, recorded. The 3 `<option>` loaders stay (a select's option IS its
loading idiom).

### `<EmptyState icon? title description? action?>` (§12 empty)

Mobile's anatomy, mirrored: `<Icon>` at `iconXL`/`textTertiary` → title
(`titleLarge`/`textSecondary`) → description (`bodyMedium`/`textTertiary`) →
`action` as a **ReactNode** (server-safe — TaxonomyLandingView is a server
component; a `<Link>` or `<Button>` passes through, never a callback prop).

**The emptiness line** (the judgment call, drawn once): PAGE- or PANEL-level
emptiness gets the full anatomy with an action wherever one can fix it
(favoris → « Découvrir des salons », a filtered list → clear the filter).
SUB-SECTION emptiness — a slot grid's « Aucun créneau disponible », a field's
« Aucune date bloquée » — stays an inline one-liner: a 64px icon between a
date picker and its slot grid would be noise, not guidance.

### `<ErrorState title? message? onRetry?>` (§12 error)

`title` renders the **page h1** — the 15 h1-less pro error states pass their
page title, closing B5's leftover. `message` (default « Une erreur est
survenue. Réessayez. ») renders `role="alert"`. `onRetry` → « Réessayer »
secondary Button — every dead-end site already owns a `load()`, so the retry
is real, not decorative. The 7 hand-rolled retry sites re-base onto it.

### `<Rating value count?>` (§3.5)

« ★ 4,8 (32 avis) » — the glyph `aria-hidden` (decoration; the numeral is the
information), the value in **French decimal comma** via
`toLocaleString('fr-FR')` — fixing the anglophone `toFixed(1)` dots at every
site. AvisClient's per-review ★★★★☆ bar keeps its glyphs and gains the
visible numeral (owner decision). The ♥ favorite toggles are §16-correct
already (filled/outline glyph swap) and stay put.

### `<Chip variant>` (§11.3 / §16)

`filled` (selected: `bg-primary text-secondary`) · `outlined`
(**`border-borderStrong`** — closing the §16 violation at every selection
chip; a visible, doctrine-mandated change) · `tinted(kind)` (status:
`bg-{kind}/10 text-{kind}` — the no-show idiom generalized) · plus the `gold`
owner treatment (TeamRoleChip's privileged tint). Interactive chips carry
`min-h-12` (§13.2); static badges stay compact — a fake tap target on a
non-control is its own lie. `rounded-pill`, `text-labelMedium`. TeamRoleChip
becomes a `<Chip>` caller and its `py-[2px]` ds-ignore **dies**.
`StatusChip.forStatus` (the kind→French-label mapping API) stays B7 with the
density work.

## Testing plan

Unit per component: Icon (registry, sizing from the token, aria-hidden vs
role=img), Loading (label + spinner presence), Skeleton (pulse + aria-hidden +
presets), EmptyState (anatomy, server-safe action), ErrorState (h1-when-title,
role=alert, retry wiring), Rating (comma formatting, count form), Chip
(variants, borderStrong, interactive floor). Lockstep: none expected — the
census proved 'Chargement'/'Aucun'/error copy is unpinned by tests
(`pro-team.test.ts` pins the `teamErrorMessage()` helper only — untouched).
E2e: the full suite + axe; a skeleton state is never crawled by the route scans
(the stub resolves before networkidle) — recorded honestly rather than
pretended.

## What the adversarial review corrected (recorded, per the register's own rule)

Twelve findings total — 7 confirmed by live execution, 5 whose verifiers died
on session limits and were **verified by hand instead** (an unverified finding
is not a rejected one). The classes:

**(1) Retry that lies.** ClientsClient's retry re-armed the init effect —
which reloads UNFILTERED — while the search box and tag chip kept showing the
old filter as active (and « Charger plus » would append a filtered page 2 onto
the unfiltered list); the retry now clears the filter state to match. Revenus'
`onRetry={init}` hard-coded the 'all' period under a still-selected « Semaine »
chip; it now retries the picked period. **(2) A 5xx is not a 404.**
ProAppointmentDetail collapsed every non-200 into the terminal « Rendez-vous
introuvable » — a stub restart told the pro their appointment didn't exist;
the API wrapper distinguishes, and now only the true 404 is terminal (5xx →
ErrorState with retry). **(3) Sweep completeness.** NotificationsClient's
prefs-failure section said « Rechargez la page » with no control — the exact
shape the sweep existed to kill, missed because its copy lacked the census's
grep markers; now a section-level ErrorState. **(4) A new action's own state
bug.** « Effacer la recherche » flashed the base « no clients yet » onboarding
card for the whole clearing reload (no `setLoading(true)`) and could be
overwritten by a still-pending debounced search — fixed (the skeleton shows;
`load()` now supersedes any pending debounce). **(5) The spec's own rule,
broken once.** BookingFlow's session probe got list-shaped SkeletonRows for a
bimodal (login-prompt-or-form) resolve — swapped to `Loading` per the
shape-unknown rule. **(6) Hand-verified leftovers:** two dead `Button` imports
removed; the spec's loading-census arithmetic and « 7 label swaps » claim
corrected (6 + the file-pick label); TeamRoleChip's role→variant mapping and
the gold/filled/neutral variants now carry their own assertions.

## Not in scope

`StatusChip.forStatus` mapping · `Card` · `DataTable` (B7's density work) ·
the Toast action row (still zero callers — ErrorState's retry is an inline
button; recorded again) · the JournalGrid `rounded-md` status blocks (not
pills) · a web `ConfirmDialog` wrapper (Modal + initialFocusRef already covers
the pattern; mobile's A6 will decide the shared shape).

## Definition of done

Rows 16 and 7i → 0 with the corrected counts · every owed item from the docs
ledger closed or re-recorded with a reason · full battery green (vitest, e2e,
axe, Lighthouse, theme-pin/mirror/contrast) · emitted-CSS diff deliberate ·
French copy (the Rating comma included) · adversarial review passed · ROADMAP +
WEB-SYSTEM refreshed in the same PR.
