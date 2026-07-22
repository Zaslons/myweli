# web-b7-desktop — the desktop-grade pro dashboard: Card, StatusChip, DataTable, the two-pane Aujourd'hui, contentMaxWidth (B7)

**Status:** Shipped (2026-07-22) — see « As built » for the deltas. **Surface:** `web/` · the pro dashboard's
desktop layouts + the density components + the public reading widths.
**Design system:** [WEB-SYSTEM.md §9, §10](WEB-SYSTEM.md#9-responsive--desktop) ·
[SYSTEM.md §10–§12](SYSTEM.md#10-layout-breakpoints-content-width-z-index) ·
[admin-console-ui.md §2](admin-console-ui.md). **Roadmap:** design-system
programme, slice B7 (register rows 18 · 7j).

## Goal & the debt

§9's mandate: a salon runs `/pro` on a PC all day — it must feel like a desktop
tool ("the Planity bar"): multi-pane agenda, dense tables, persistent nav,
keyboard shortcuts, hover affordances. Measured:

- **`xl:`/`2xl:` = 0** product-wide (row 18's count, accurate). `ProShell`'s
  `<main>` has NO width cap and the sidebar is `w-60` at every width, so the
  ten uncapped list/agenda pages stretch their single-column rows to ~1040px
  @1280 and ~1296px @1536 — the stretched phone column, literally.
- **Keyboard shortcuts: none.** Hover affordances: 26 background hovers, zero
  row affordances beyond them.
- **`max-w-content` (720): defined in B2c, used nowhere** (row 7j). Real >720
  prose exists at exactly four places (the census's list below).
- The §10 to-build remnants: `Card` · `StatusChip.forStatus` · `DataTable`.
- A **parity gap** found by the census: web's « À confirmer » counts TODAY's
  pending only; the app's « Demandes » is `DashboardStats.pendingRequests` —
  pending across ALL dates. A salon with Monday requests saw « 0 à confirmer »
  on Friday's web dashboard.

**Owner decisions:** DataTable converts Clients + Équipe + Revenus + **and**
Catalogue (the inline editors rethread) · Aujourd'hui gets the **full two-pane
redesign** · journal shortcuts now (←/→/T) · **kind-tinted StatusChip
everywhere** (§11.2: "kind, not color, is the API").

## The components

### `<Card>` (§11.3 verbatim)

`bg-secondary` on background · `rounded-xl` · `border border-border` · **`p-m`**
— the spec's spacingM. The pro pages hand-roll this box with `p-l` (24) today;
conversions tighten to 16px, which IS the density work, doctrine-backed and
recorded here as the deliberate visual change.

### `statusChipKind()` + `<StatusChip>` (§11.2, mobile's `AdminChipKind` mirrored)

Kind, not color, is the API: `ok | pending | danger | neutral`, mapped
case/underscore-insensitively over the complete cross-surface inventory —

| Kind | Statuses |
|---|---|
| ok | verified · active · confirmed · resolved · paid · arrived |
| pending | pending · open · trial · invited · grace |
| danger | rejected · suspended · banned · hidden · cancelled · noShow/no_show · expired · revoked |
| neutral | completed · draft · everything else |

Rendered as B6's `<Chip variant="tinted">` (ok→success, pending→warning,
danger→error tints) or neutral. French labels via the existing vocabularies
(`statusLabelFr`, team, KYC); `label` overrides. The tint sweep applies it to
the ~7 previously-neutral pills — the visible §11.2 change the owner approved.
The journal's kind-tinted BLOCKS stay as they are (rounded-md by design).

### `<DataTable>` — the AdminDataTable twin, on the B6 primitives

`columns: {label, flex?, align?}[]` · `rows: {key, cells, onClick?}[]` · four
states: `isLoading` → **4 pulsing 52px skeleton rows** (the web upgrade — the
mobile reference's skeleton is static), `error`+`onRetry` → section-level
ErrorState, empty → EmptyState (icon/title/description), success → rows with
1px dividers, `min-h` 52 (comfortable — admin-console-ui §5), hover
`surfaceVariant`, header `bodySmall`/`textTertiary` (mirroring the CODE —
the admin DOC says labelMedium; the B3 lesson is mirror the code and record
the delta). Row click = a full-row interactive pattern that stays keyboard-
legal and holds the 48px floor. `overflow-x-auto` + a min width below desktop
(the Équipe precedent). **No pagination/sorting in-widget** — the admin spec's
footer was never built in the reference either; callers own paging
(ClientsClient's « Charger plus » stays).

## The layouts (row 18)

| Page | Desktop shape |
|---|---|
| Aujourd'hui | **Two-pane at `xl:`** — main = « Rendez-vous du jour »; right rail (320px) = stat Cards, revenue Cards, invitations, GoLive, links. Below xl: today's vertical flow, ONE DOM tree (grid order, no duplication). Staff view stays single-pane. **Parity**: « Demandes en attente » = `pendingRequests` (all dates) when dashboard stats load; today-only fallback otherwise. |
| Rendez-vous | Full width — the agenda IS the width consumer. Journal columns gain `flex-1` past their 168px min so the grid FILLS 1280/1536. **Shortcuts**: ← / → = jour précédent/suivant, **T** = aujourd'hui — guarded: no modifier keys, never while typing (input/textarea/select/contenteditable), never while a dialog is open. |
| Clients | DataTable (Client · Téléphone · Visites · Dernière visite · Tags), row → the card. `max-w-5xl`. |
| Équipe | The hand-rolled table re-based on DataTable (the reference conversion); `Actions pour {email}` + ⋯ menu untouched; Statut → StatusChip. `max-w-5xl`. |
| Revenus | Ledger → DataTable (Date · Rendez-vous · Montant right-aligned); total stays a Card above. `max-w-content`. |
| Catalogue | Services + Employés rows → DataTable (Nom · Durée · Prix · Statut · Modifier / Nom · Spécialité · Modifier); the inline `ServiceFormCard`/`ArtistFormCard` editors RETHREAD to render below the table when open — same state machine, same « Ajouter » flow. `max-w-5xl`. |
| ClientCard | Keeps `lg:grid-cols-2`, gains `max-w-5xl`. |
| Avis | `max-w-3xl` (reading cards). |
| Médias | Full width, photos gain `2xl:grid-cols-4`. |
| Disponibilités · ProAppointmentDetail | `max-w-content` (form/detail pages — §10: "text and forms never stretch past it"). |
| The shell | `<main>` gains `xl:p-xl`. Sidebar stays `w-60` (persistent at lg+, drawer below — the B0 contract, untouched). |

## contentMaxWidth (row 7j)

Applied where >720px text/forms actually existed: **TaxonomyLandingView** main
(768→720) · **ProviderView**'s description + FAQ sections (caps the 768–1024px
band where prose ran to ~1024; at lg+ the 3-col grid already held ~650) ·
**Revenus** (768→720) · **Disponibilités** + **ProAppointmentDetail** (were
unbounded). Deliberately NOT applied (the exclusion list): maps, the journal,
media grids, calendars, card grids, Abonnement (offer CARDS at `md:grid-cols-3`
need the 3xl), the already-≤720 account/booking/login pages.

## Testing plan

Unit: the kind-mapping table (incl. case/underscore variants), DataTable's four
states, Card's spec classes; lockstep `pro-aujourdhui-roles.test.tsx` (the
parity label). E2e: the full suite (team.spec's `Actions pour`, pro.spec's
headings/tabs/`★ 4,5`/`37 000 FCFA`, the journal positional click at
pro.spec:411 re-verified against the flex-1 stretch) + a new shortcuts
assertion + axe (the tables live on already-scanned routes). Browser
screenshots at 1280 and 1536 for the two-pane dashboard, a DataTable page, the
stretched journal, and a 720-capped prose page.

## As built — the deltas the build forced

- **DataTable navigation rows are LINKS wrapping their cells.** The planned
  pattern (a full-row button UNDER `pointer-events-none` cells) broke real
  hit-testing on row text — Playwright's clients flow refused the click, and
  users couldn't hover/select row text either. Rows gained `href` (a `Link`
  around the cell grid — open-in-new-tab works) next to `onClick` (a button,
  same wrapping). The contract is unchanged: an activatable row carries no
  interactive cells.
- **The grid template is a named token.** `xl:grid-cols-[minmax(0,1fr)_320px]`
  is an arbitrary value and those are banned — the theme gains
  `gridTemplateColumns.desk` (`minmax(0, 1fr) 20rem`), so every two-pane
  surface agrees on the rail width.
- **The width caps live at the PAGE level** (`app/pro/(dash)/*/page.tsx`), not
  inside the clients: skeleton, error and success share the cap, so nothing
  flashes full-bleed and snaps narrow.
- **Catalogue's services table** shows Statut as its own column
  (`StatusChip` — Actif in ok-green, Inactif neutral), matching Équipe.
- **The rail keeps the interrupt order on desktop** (invitations → go-live →
  stats → revenue → links): a draft salon's ONE action stays on top. The
  mobile flow moved the two config links below the stats — numbers first,
  configuration after — the same DOM order at every width, zero `order:`
  utilities.
- **The tint sweep's honest count is 6 pill sites**, not ~7: the four
  appointment pills + Catalogue + Équipe. The « KYC doc rows » candidate does
  not exist as a pill (Vérification uses a tinted *banner* + colored text
  lines, already kind-coloured); Abonnement is a banner too. Excluded,
  recorded here.
- **The Card sweep converted 19 boxes across 12 pro files.** Two survivors,
  both deliberate: ManualBookingDialog's panel (dialog chrome, not a card) and
  ClientCard's « Prochain rendez-vous » link (`<Card>` hosts no interactive
  elements — a hover card-link is its own pattern).
- **Shortcuts carry `title` hints** (« Raccourci : ← / → / T ») on their
  buttons, and the WCAG 2.1.4 single-character concern for **T** is recorded
  in §9 with its mitigation (typing guard + view scope).
- **Emitted CSS**: +13 selectors (the `xl:` two-pane set, `xl:p-xl`,
  `2xl:grid-cols-4`, `max-w-content` — emitted for the FIRST time —,
  DataTable's `py-sm`/`last:border-b-0`), −3 (all died with Équipe's
  hand-rolled `<table>`: `border-collapse`, `-mx-s`, `last:border-0`).

## The adversarial review's corrections

Four confirmed by execution, eight hand-verified after their refuters died on
session limits (an unverified finding is not a rejected one):

- **DataTable is an ARIA table now.** The div grid had traded Équipe's real
  `<table>`/`<th>`/`<td>` for zero column↔cell association (WCAG 1.3.1) — and
  axe cannot flag it, because axe only runs table rules on elements *exposed*
  as tables. Markup: `role="table" → rowgroup → row → columnheader/cell`.
  The row control moved INTO the first cell with a row-wide stretch span
  (the row is the positioning context); the other cells stay outside the
  control so table navigation reads them clean — this also dissolves the
  « aria-label swallows the row content » concern. Tracks are
  `minmax(0, Nfr)`: every row resolves identical column widths (a plain
  `Nfr` let one long unbreakable email widen its own row's column). The
  non-success states render OUTSIDE the `role="table"` element. Contract
  note: a table that can overflow keeps ≥1 focusable control per row (all
  four callers do); a control-less overflowing table adds the
  focusable-region pattern with its first real consumer.
- **The Catalogue editor is keyed by the edited id.** `main` keyed the
  in-place editor per row; the rethread lost that, and `useState(initial)`
  meant « Modifier » A→B kept A's form and **saved A's data onto B** —
  pinned by `tests/catalogue-editor.test.tsx`. The edited row now carries
  `aria-current` + the surfaceVariant tint, « Modifier » carries
  `aria-expanded`, and the editor opens with a **focused heading**
  (« Modifier « {nom} » ») — focusOnMount scrolls to it and announces it
  (the editor used to mount below the fold with zero feedback).
- **JournalPanel is a non-modal `role="dialog"`** (aria-label « Détails du
  rendez-vous », no aria-modal, no trap — it never blocked the page): the
  shortcut guard can now see it (←/→ changed the day under the open panel),
  and the semantics were right anyway. Plus `e.repeat` is ignored and
  `loadJournal` carries the booking hub's request-id dedupe — a held arrow
  fired racing day-fetches and the slowest response won.
- **`statusChipLabel` normalizes like `statusChipKind`** (`NO_SHOW` tinted
  danger but printed the raw enum next to red ink).
- **Revenus' « Rendez-vous » column, resolved honestly**: the payload carries
  only `appointmentId` — no name to print — so the ledger row **links** to
  the appointment (`rowLabel` « Ouvrir le rendez-vous du {date} ») instead
  of faking a column. The spec's column list above is corrected by this
  note.

## Not in scope

Sorting/pagination inside DataTable (callers own paging — recorded) · a global
shortcut system beyond the journal set (recorded in §9) · hover-reveal row
actions (touch/a11y hazard — hover stays an affordance, never the only path) ·
the public/consumer Card sweep (pro pages only this slice) · mobile-side gold
(row 23, A-series).

## Definition of done

Rows 18 + 7j → 0 with honest recounts and the exclusion lists · the first
`xl:`/`2xl:` selectors in the product, every one deliberate (emitted-CSS diff)
· parity gap closed · full battery green · adversarial review passed · ROADMAP
+ WEB-SYSTEM refreshed in the same PR.
