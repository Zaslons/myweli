# The « Signaler » forms at doubled text

| | |
|---|---|
| **Status** | Built (2026-11-27), mutation pass done, not merged (§8) |
| **Approved** | by the owner, 2026-11-27, on §4: « Approve as recommended » (all three decisions as recommended) |
| **Owner** | Sadreddine Daher |
| **Last updated** | 2026-11-27 |
| **Register row** | [WEB-SYSTEM.md](WEB-SYSTEM.md) §15 row 41 (new) |
| **Rule** | [WEB-SYSTEM.md](WEB-SYSTEM.md) §9 « Text scale & reflow » (rule 1, a row that cannot fit must wrap; the doubled-text modes) · the app's rule, [SYSTEM.md](SYSTEM.md) §13.3 |
| **Governs** | `web/components/provider/ReviewList.tsx` (`ReportAction`, the salon page's reviews) · `web/components/pro/AvisClient.tsx` (`SalonReportAction` and the distribution list, `/pro/avis`) |
| **Skills checked** | `myweli-web-guardrails`, `myweli-dev-guardrails` |
| **Follows** | [web-dialogs-toast-doubled-text.md](web-dialogs-toast-doubled-text.md) (#906, not merged) §7, its second follow-up: « two inline reply rows … not dialogs, not measured here » |
| **Not changed by this** | `web/components/Button.tsx`: it is in the five store-linked pages' graph (§13, §15 row 38; traced, §2.4). The fix is in the two rows, not in the button |

---

## 1. Goal & scope

#906 made every dialog's row of buttons wrap. Two rows outside dialogs have
the same shape, `mt-s flex justify-end gap-s`, and nobody had measured them.
They are not reply rows: they are the **« Signaler » forms** (report a
review), opened under a review by tapping « Signaler », with a reason field
and two buttons, « Annuler » and « Signaler ».

- **The salon page** (`/{slug}`, `ReviewList`'s `ReportAction`): any signed-in
  client, or a visitor (who is then asked to sign in).
- **`/pro/avis`** (`AvisClient`'s `SalonReportAction`): the Propriétaire and
  the Gérant (`profile.manage`).

Measuring `/pro/avis` found a third failure on the same page, in the same
mode, before anything is opened (§2.2). It is in scope only if decision 3
says so.

**Out of scope:** everything §7 lists.

## 2. Measured before building

`main` at `b097e330`, the e2e stub, Chromium (Playwright 1.61.1) at 320×568.
The three modes of `type-overflow.spec.ts`: normal text, the Android mode
(`text-size-adjust: 200%` on a touch phone) and the browser font at 200 %
(a 32 px root: px text stays, rem boxes grow). Each form opened from the
keyboard (focus « Signaler », Enter), then read. Raw readings and the two
throwaway specs: the session notes' `report-rows-doubled-text/` folder.

### 2.1 The salon page (`ReviewList`)

The form opens inside the date's row, `flex items-center justify-between
gap-m`, beside « 1 juin 2026 ». The row is 256 px wide at 320 (x 32–288).

| | Normal | Android 200 % | 32 px root |
|---|---|---|---|
| Layout viewport, form closed | 320×568 | 320×568 | 320×568 |
| **Layout viewport, form open** | 320×568 | **428×760** | 320×568 |
| The open form | x 76.5–300.3 (224 px): **12 px past the card's content edge** (288), into its padding | x 103–427.5 (324 px): **past the card (304) and the screen** | as normal |
| « Annuler » · « Signaler » | 84.5–184.6 · 192.6–292.3 | 111–261 · 269–419.5 (28 px) | as normal, 96 px tall |
| The date beside it | **28.5 px wide, 3 lines** (« 1 » / « juin » / « 2026 ») | 55 px wide, 3 lines | 28.5 px wide, 3 lines |

The button row cannot wrap, so the form cannot be narrower than its two
buttons (308 px at 28 px text, plus its 16 px padding). The row it sits in
cannot wrap either, so in the Android mode the form pushes the layout
viewport to 428 px: the « Réserver » bar and any toast are then placed off
the screen (§9). At normal text nothing leaves the screen, but the form
takes all but 28.5 px of the row and the date is squeezed to three lines.

### 2.2 `/pro/avis` (`AvisClient`)

The form opens in the review's text column, beside the avatar: 182 px wide at
320 (x 97–279), its button row 166 px (x 105–271).

| | Normal | Android 200 % | 32 px root |
|---|---|---|---|
| Layout viewport, form closed | 320×568 | 320×568 | 320×568, **the document 489 px wide** |
| The form's panel | x 97–279 | x 97–279 | x 137–279 (the avatar is 80 px) |
| **« Annuler »** | **x 63–163: 34 px left of its panel** | **x −37–112: starts 37 px off the screen** | **x 63–163: 74 px left of its panel** |
| « Signaler » | 171–271 | 120–271 (28 px) | 171–271 |

The row is `justify-end` and does not wrap, so two buttons wider than it run
out at its **start**, to the left. A page cannot be scrolled to the left of
0, so in the Android mode the viewport does not grow and nothing reports it:
« Annuler » simply starts off the screen. At normal text it is the same
fault, smaller: « Annuler » is drawn outside its grey panel, over the
avatar's column. At 360 it is 2 px into the panel's padding (x 103, the row
at 105); from 375 it fits.

**The third failure, found by measuring:** with the 32 px root, `/pro/avis`
scrolls sideways before anything is opened. The origin is the distribution
list, `<dl class="min-w-56 flex-1">`: `min-w-56` is 14 rem, so 448 px at a
32 px root (x 41–489). The comment on this page's row in
`type-overflow.spec.ts`'s matrix (« 224 fits the ~240 a 320 viewport
leaves ») holds at a 16 px root only; that matrix runs normal text.

### 2.3 Elsewhere on the two pages

Nothing else crosses the screen on either page in any mode (an origin walk
over every element; on the salon page at the 32 px root, a gallery `li` is
inside its own scroller). Closed, the salon page is already gated in both
doubled modes (« the salon page at doubled text »).

### 2.4 The frozen graph

The salon page is not one of the five store-linked pages, and neither file
is in their graph: an esbuild trace of the five pages, `app/layout.tsx` and
`app/not-found.tsx` reaches 39 modules, `Button.tsx` among them, and neither
`ReviewList`, `ProviderView` nor `AvisClient`.

## 3. The shape

**The fix is room, never a smaller font** (SYSTEM.md §13.3). DOM order, copy,
focus order and every state stay as they are.

### 3.1 Both forms: the button row wraps

`mt-s flex justify-end gap-s` → `mt-s flex flex-wrap justify-end gap-s`, as
#906 did for every dialog footer. When the two buttons do not fit side by
side, « Annuler » keeps the first line and « Signaler » goes under it, both
at the right edge, 8 px apart (`gap-s` on both axes, SYSTEM.md §13.2's
adjacency floor). One button is never wider than its row: 150 px at 28 px
text in a row of at least 166 px; 100 px in a row of 126 px at the 32 px
root.

Expected, to be measured after building:

| | Normal 320 | Normal 360 | Normal 375 + | Android 200 % | 32 px root |
|---|---|---|---|---|---|
| Salon page | one line | one line | one line, as today | two lines | one line |
| `/pro/avis` | **two lines** | **two lines** | one line, as today | two lines | two lines |

### 3.2 The salon page: the form takes its own line when it cannot sit beside the date

The date's row wraps (`flex flex-wrap items-center justify-between gap-x-m
gap-y-xs`), and the report action carries `ml-auto`, so that alone on a line
it keeps to the right, as « Signaler » sits today.

- **Closed** (date and « Signaler »): one line, as today. Measured at 320 in
  the three modes: the date whole on one line (63 px; 121 px in the Android
  mode) and « Signaler » beside it. If they ever do not fit, « Signaler » goes
  under the date, at the right.
- **Open, at 320** (normal text and the 32 px root), expected: the date on
  its line, whole; the form under it at the right, at its own width (224 px),
  its buttons on one line. In the Android mode: the form under the date, as
  wide as the row (256 px), its buttons on two lines; the viewport stays
  320×568.
- **Open, from 375 at normal text, and on a desktop**: beside the date, as
  today. Measured today at 375: the date whole (63 px), the form beside it
  (x 119–343) in a 311 px row; the two need 303 px (63 + 16 + 224), so from a
  367 px screen. At 1280: the form 224 px at the right of a 749 px row.
- **Sent** (« Merci. Notre équipe va examiner cet avis. »): beside the date
  where it fits, under it otherwise.

### 3.3 `/pro/avis`'s distribution list (decision 3)

`min-w-56 flex-1` → `w-56 grow`. At a 16 px root it behaves as today: the
list goes to its own line when less than 224 px is left beside the average,
then fills the line. At a 32 px root its 448 px still sends it to its own
line, where it may now shrink to the card's width, so the page stops
scrolling sideways. It shrinks with no `min-w-0`: a flex item's automatic
minimum is the smaller of its specified width (14 rem) and its min-content
(about 128 px at a 32 px root). The approved shape had `w-56 min-w-0 grow`;
the mutation pass removed `min-w-0` and every check stayed green, so it is
gone (§8). No `basis-*`: `flexBasis` is fed by the closed spacing scale and
has no `56` (`tailwind.config.ts`).

## 4. Decisions (answered 2026-11-27: « Approve as recommended »)

1. **Both button rows wrap** (§3.1). *Recommended*, the rule #906 applied to
   every dialog. *Alternative:* on `/pro/avis`, move the form out of the
   text column to span the whole card (240 px at 320), so its buttons stay on
   one line at normal text; more markup moved, and the form no longer lines
   up with the review it reports.
2. **The salon page's form drops under the date only when it cannot sit
   beside it, at its own width** (§3.2). *Recommended.* *Alternative:* the
   open form always on its own line, full width: at 1280 the reason field
   would be about 733 px wide (the row is 749 px), against 208 today.
3. **Fix `/pro/avis`'s distribution list in this PR** (§3.3). *Recommended*:
   the same page, file and mode, one class, and without it the new e2e case
   cannot hold « no sideways scroll » on `/pro/avis` at the 32 px root.
   *Alternative:* leave it, as an open line of row 41.

## 5. Tests (red first, on the code before the change)

- **Unit** (`web/tests/report-rows-doubled-text.test.tsx`): in both forms,
  opened, the button row carries `flex-wrap`; on the salon page the date's
  row carries `flex-wrap` and the report action `ml-auto`; on `/pro/avis` the
  distribution list carries `w-56` and `grow`, and neither `min-w-56` nor
  `flex-1` (decision 3).
- **e2e** (`type-overflow.spec.ts`, a new block « the « Signaler » forms at
  doubled text »), at 320×568 × the three modes × the two pages, each form
  opened from the keyboard, with the mode's vacuity guard read at the moment
  of measuring (the buttons' text 28 px in the Android mode, the root 32 px
  in the other; §9's autosizer trap):
  - the layout viewport equals the screen, and the page does not scroll
    sideways;
  - each button wholly inside the form's content box and on the screen;
  - on the salon page, the date on one line, and the form ending at its
    card's content edge (it keeps to the right; added by the mutation pass,
    §8);
  - « Annuler » pressed closes the form (it is reachable);
  - the generic checks (`overflowingText`, `overflowingFlexRows`,
    `verticalClipping`, `truncationLosses`);
  - in the Android mode, the two buttons on two lines (the guard that the
    wrap is what is tested).
- **Kept green:** the salon page's doubled-text block, the matrix's
  `/pro/avis` row, `pro-avis-report.test.tsx`, `account.spec.ts`'s signed-in
  « Signaler » and `pro.spec.ts`'s.
- **Mutations, on committed code**, each alone: each of the two button rows
  without `flex-wrap`; the date's row without `flex-wrap`; the report action
  without `ml-auto`; the list's `min-w-56 flex-1` back; the list without
  `min-w-0`. Unit and e2e. Results: §8.

## 6. Rollout

One PR into `main`, authored as the owner. Its merge deploys `myweli.com`,
on the owner's word, then read back there. A roadmap entry in
`docs/roadmap/entries/`, WEB-SYSTEM §15 row 41 and §9's paragraph on doubled
text.

**Two branches touch the same files.** #906 (not merged) adds §15 row 40,
whose « Not covered » points at these rows, and its own block to
`type-overflow.spec.ts`; A5w (approved, not built,
[salon-team-and-reviews.md](salon-team-and-reviews.md) §2.7) edits
`ReviewList`'s review lines. Whichever lands second rebases; row 40's
pointer then names row 41, and A5w keeps both wraps.

## 7. Not covered

- **The Pro sidebar's salon switcher at Android's 200 %**: « Beauté Divine »
  is cut, 156 of 174 px, in its 240 px rail. Found by the new block's
  page-wide truncation check; the site is declared (`ProSidebar.tsx`,
  `// clip-ok:`, the full name in the button's accessible name and on
  `/pro/profil`), so the block excuses it by its text on `/pro/avis` only.

- Real phones: Chromium's mobile emulation only.
- The salon page's other rows at doubled text beyond what its gate already
  holds; `/`, `/recherche`, the 404, the install banner and the store-linked
  pages (§15 row 38).
- The Pro shell at a 32 px root on other `/pro` pages: only `/pro/clients`
  was looked at, as a control (its table scrolls in its own box, the
  declared exception).

## 8. Built (2026-11-27)

On `fix/web-report-rows-doubled-text`, from `main` (`b097e330`).

- **Red first,** on the code before the change (`a8b8de58`): unit **5 of
  5**, e2e **6 of 6**, each on a measured failure: the salon page's form
  past its card's content edge (x 300 against 288) at normal text and the
  32 px root, its layout viewport 428×760 in the Android mode; `/pro/avis`'s
  « Annuler » outside its form (x 63, and −37 in the Android mode), the page
  489 px wide at the 32 px root. One guard of mine was wrong on the first
  run, not the code: the Android mode doubles the root's drawn size too, so
  the root tells the other two modes apart only.
- **On the fixed code, `/pro/avis` in the Android mode** still failed the
  page-wide truncation check, on the sidebar's declared switcher (§7). Excused
  by its text, in its own commit (`fbeaea1a`).
- **Measured after** (§3 said « expected »), 320×568:

  | | Normal | Android 200 % | 32 px root |
  |---|---|---|---|
  | Salon page, viewport | 320×568 | **320×568** (was 428×760) | 320×568 |
  | Salon page, the form | x 64–288, under the date, at the right; buttons on one line | x 32–288; « Annuler » over « Signaler », at the right | as normal, boxes taller |
  | Salon page, the date | 63 px, 1 line (was 3 in 28.5 px) | 121 px, 1 line | 63 px, 1 line |
  | `/pro/avis`, the buttons | stacked, x 171–271, inside the panel (97–279) | stacked, x 120–271 | stacked, x 171–271, inside the panel (137–279) |
  | `/pro/avis`, the document | 320 | 320 | **320** (was 489) |

  `/pro/avis` at 360: stacked (x 211); at 375 and 390: one line, as before.
  The salon page at 375 and 1280, and every closed row: as before.
- **Mutations, on committed code** (`d1e54244`, then `10eba97c`), each
  alone. **Unit: 8, all red** — each button row without `flex-wrap`, the
  date's row without `flex-wrap`, the action without `ml-auto`, the list
  `min-w-56 flex-1` again, `w-56 flex-1`, without `grow`, without `w-56`.
  **e2e: 7, in five rebuilt trees** grouped so that no two land in the same
  test. Red: the salon page's button row (the viewport, Android), `/pro/avis`'s
  (« Annuler » outside its form, all three modes), the date's row (the date
  squeezed, all three modes), the list `min-w-56 flex-1` again (the page
  scrolls sideways, 32 px root), `w-56 min-w-0 flex-1` (a row of the list does
  not fit, Android). **Two survived the block as first written.** Without
  `ml-auto` nothing looked at which side the form sat on (a lone item in a
  `justify-between` row goes to the left); the block now holds that the form
  ends at its card's content edge, and against it that mutation is red at
  normal text and the 32 px root (`aa7190c5`). Without `min-w-0` every unit
  and e2e check stayed green, because the list shrinks without it (§3.3); the
  class is removed (`10eba97c`) and the unit test no longer asks for it.
