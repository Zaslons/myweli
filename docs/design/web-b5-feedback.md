# web-b5-feedback — live regions, the focus-trapped `<Modal>`, honest headings, and axe as a gate (B5)

**Status:** Built (2026-07-20). **Surface:** `web/` · every transient message, every
dialog, the heading skeleton, and the CI gates.
**Design system:** [WEB-SYSTEM.md §4, §7–§8, §10, §14](WEB-SYSTEM.md#7-announcements-live-regions) ·
[SYSTEM.md §15](SYSTEM.md#15-feedback--destructive-actions). **Roadmap:** design-system
programme, slice B5 (register rows 12 · 13 · 14 · 15 · 7f · 21 · 22).

## Goal & the debt

Every number is measured, and the register's counts were wrong again — corrected
here as the point, not hidden:

- **Row 12** — `aria-live` = **0** product-wide. Five hand-rolled toasts;
  exactly one (`EquipeClient`) carries `role="status"` — and even that one mounts
  the region *together with* the text, which §7's own rule says is unreliable
  ("the region must exist in the DOM **before** the text lands"). It is also the
  only toast **missing `z-toast`** (it paints on DOM-order luck). Beyond the
  toasts: **~63 silent outcome sites** across ~35 files — panel load failures,
  form-level outcome errors, and « Enregistré. » confirmations — none announced.
  (Field-level errors already announce: B4's `TextField` `role="alert"`.)
- **Row 13** — dialogs: **focus traps 0/6, focus-in/restore 0/6, scroll lock 0/6**,
  Escape on 2/6 (InviteMember, ChangeRole), three different scrim patterns.
- **Row 14** — `/recherche` skips h1 → h3 (`ProviderCard`). The card itself is
  correct on home and the landings (it sits under h2 sections there) — the miss
  is `/recherche`'s missing intermediate h2. **And an unregistered find:
  `/mon-compte/[id]` has no h1 at all** (it opens at the salon-name h2).
- **Row 15** — no axe anywhere; Lighthouse audits one URL with a11y as `warn`
  inside a `continue-on-error` job. A gate that cannot fail, looking at one page.
- **Row 7f** — the 4 token-less `<h2>`s (`ProRegisterClient:224`,
  `ClientCardClient:276+368`, `JournalPanel:96`) inherit their size while 38
  peers are `text-titleLarge`.
- **Row 21** — `ReviewForm`'s stars: a `role="radiogroup"` whose children are
  `aria-pressed` **buttons** — invalid ARIA children (`aria-required-children`),
  and toggle semantics for what is a pick-one-of-five.
- **Row 22** — the count was 3; measured, it is **5** hidden file inputs
  (`MediasClient` ×2, `VerificationClient`, `CatalogueClient`, `ReviewForm`) —
  `className="hidden"` is `display:none`, unfocusable, so keyboard users cannot
  upload at all. `DepositProof`'s sixth input is visible and fine.

## UX & contracts

### `<Toast>` + `useToast` (§7, SYSTEM §15)

One transient-feedback entry point, mirroring mobile's `AppSnackBar` **spec**
(SYSTEM §15's table — mobile's own implementation is still A6, so the table is
the source and nothing is invented):

| Kind | Fill | Duration |
|---|---|---|
| `success` / `info` | `bg-primary` (the existing pill idiom) | **3 s** |
| `error` | `bg-error` (#8B0000 — ~10:1 under white text) | **6 s** (an error needs time to read) |

The §15 "with action → 10 s" row is **deliberately omitted**: zero callers exist
product-wide (mobile has exactly one in 118 calls); A6/B6 adds it when a caller
does. Recorded here so the omission is a decision, not a gap.

**The live-region contract:** the component ALWAYS renders
`<div role="status" aria-live="polite">` (fixed, bottom-center, `z-toast`) and the
pill swaps **inside** it — the region pre-exists every message, structurally.
`useToast()` owns the state + timer (kind-based duration, re-show resets, cleanup
on unmount). No entrance animation — the pre-B5 pills had none, and inventing
motion is exactly what B2c banned; if one is ever added it must be a token
duration + `motion-reduce`.

Converted: the 4 fixed-position toasts (Verification, RendezVous ± ManualBooking's
`onToast`, ClientCard, Equipe). `ResultsMap`'s locate note stays **map-local**
(it belongs to the map box, not the viewport) but gains the same always-mounted
`role="status"` wrapper in place.

### The §7 sweep — classification per site

| Shape | Treatment |
|---|---|
| Field-level error under an input | already announced (B4 `TextField`) — untouched |
| Outcome / panel-load error `<p>` | `role="alert"` — insertion-announced (the alert exception; B4-proven mechanism) |
| Transient confirmation (was a hand-rolled toast) | `<Toast>` |
| Persistent « Enregistré. » confirmation | always-mounted `<p role="status">` whose **text** toggles (status is not insertion-announced — the region persists) |
| « Chargement… » strings | B6's `Loading` — out of scope, recorded |

### `<Modal>` (§8)

Hand-rolled, **not** native `<dialog>` — jsdom has no `showModal()` (unit tests
render dialogs directly), and the z-layer stack is token-asserted by
`z-layers.spec.ts`. Structure is B4's blessed pattern: `fixed inset-0 z-modal`
wrapper · **aria-hidden scrim sibling** carrying `onClick={onClose}` · relative
panel (`w-full max-w-md rounded-xl border border-border bg-secondary p-l`).

- `role="dialog"` `aria-modal="true"` `aria-labelledby={titleId}` — Modal renders
  its own `<h2>` title (killing 5 hand-rolled ones); `label` replaces it for the
  title-less Lightbox.
- **Behavior** (ProShell's drawer idioms, generalized): Escape closes · body
  scroll locks · on mount capture `document.activeElement`, focus
  `initialFocusRef ?? the first focusable` · **Tab/Shift+Tab cycle inside the
  panel** (keydown trap — inert-siblings can't work for an in-tree modal) ·
  restore on unmount (guarded on `isConnected`).
- Props: `title | label` · `onClose` · `initialFocusRef?` · `panelClassName?`
  (ManualBooking's `max-h-[90vh]` ds-ignore stays at *its* call site) ·
  `scrimClassName?` (Lightbox's `bg-primary/80`).
- All 6 dialogs convert. EquipeClient's revoke confirm sets `initialFocusRef` to
  **Annuler** — SYSTEM §15: the cancel path is the safe default and gets focus.

### Headings (§4)

- `/recherche`: a **visible** `<h2>` « {n} salon{s} » above the results (French
  plural; only when n > 0 — the empty state owns 0). Fixes h1→h3, shows the count
  (the Planity-style answer-first win), and gives SEO an extractable result line.
- `/mon-compte/[id]`: the salon-name h2 becomes the page's **h1** (its only
  heading; the core entity).
- Row 7f: the 4 h2s gain `text-titleLarge`.

### Stars → a real radio group (row 21)

`role="radio"` + `aria-checked={rating === n}` + roving tabIndex (the selected
star is the tab stop; the first when unrated) + Arrow keys move **and** select,
**wrapping at the edges** (APG). `aria-pressed` dies. Visuals unchanged (fill is
still `rating >= n`).

### FilePick (row 22)

As-built correction: of the 5 hidden inputs, **3 already had focusable proxy
`<Button>`s** (Verification, Catalogue, ReviewForm — keyboard-fine); only
**MediasClient's two** label-wrapped pickers were keyboard-dead. Both → `sr-only`
(a real tab stop), labels gain `focus-within:outline focus-within:outline-2
focus-within:outline-offset-2 focus-within:outline-borderFocus` — §5's ring,
projected onto the visible label while the (invisible) input holds focus.
Enter/Space on a focused file input opens the picker natively; nothing else to
wire.

## The gates (§14)

- **`tests/e2e/axe.spec.ts`** — `@axe-core/playwright` over **13 routes**
  (`/`, `/recherche?commune=Cocody`, `/beaute-divine`, `/beaute-divine/reserver`,
  `/connexion`, `/mon-compte`, `/mon-compte/notifications`, `/mon-compte/appt2`
  — the stars' page, added when the base census proved the first matrix never
  reached row 21 — `/pro/connexion`, `/pro`, `/pro/rendez-vous`, `/pro/equipe`,
  `/pro/clients`) **plus two stateful scans**: an open Modal and a visible Toast
  (triggered by the manual-booking past-date error — deterministic, no stub-data
  dependency). Runs inside the already-blocking e2e job. **Proof-red at base
  479e092, measured in a worktree: 11 violations / 13 nodes / 5 rules / 8 of 12
  routes — and 3 of the 5 rules were unregistered finds** (`region` ×7: the home
  hero outside `<main>` + the landmark-less install banner; `nested-interactive`:
  maplibre's role=button marker wrapper; `aria-prohibited-attr`: MapEmbed;
  `empty-table-header`: Équipe). Any genuinely unfixable rule (third-party
  internals) gets a per-rule exclusion with ds-ignore-style prose — fix first,
  exclude last. Today: **zero exclusions**.
- **Lighthouse promoted to blocking**: a11y `["error", {minScore: 0.95}]`
  (§14's own prescription), SEO stays `error` 0.9, performance/best-practices
  stay `warn` (the flake-prone pair); URLs `/` + `/connexion`; the job loses
  `continue-on-error` and its "(report-only)" name.

## Testing plan

Unit: `tests/toast.test.tsx` (region persists across show/hide, kind durations
via fake timers, re-show resets, z-toast) · `tests/modal.test.tsx` (labelledby
resolution, Escape, focus-in incl. `initialFocusRef`, Tab cycling both directions
at both edges, restore-on-close, scroll lock, scrim click) · star radio-group
keyboard test. Lockstep: `account.spec.ts:85` star selector → `getByRole('radio')`;
`equipe-invite.test.tsx` if dialog structure shifts selectors. E2e: full suite +
the axe spec, zero skips.

## Not in scope

`Loading`/`Skeleton`, `EmptyState`/`ErrorState`, `ConfirmDialog`-as-component and
the Toast action row (B6/A6) · the desktop-grade pro dashboard (B7) · the 14→16px
reading size (B8).

## Definition of done

Rows 12, 13, 14, 15, 7f, 21, 22 → 0 with measured counts and corrections · axe
green over the matrix with zero undocumented exclusions · Lighthouse blocking ·
every dialog flow still completes (vitest + e2e green) · French copy · ROADMAP +
WEB-SYSTEM refreshed in the same PR · adversarial review passed.
