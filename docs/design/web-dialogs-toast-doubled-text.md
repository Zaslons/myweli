# The dialogs, the toast and `/mon-compte` at doubled text

| | |
|---|---|
| **Status** | Approved (2026-11-27), not built |
| **Approved** | by the owner, 2026-11-27, on §4 and §5: « Approve as recommended » (all four decisions as recommended) |
| **Owner** | Sadreddine Daher |
| **Last updated** | 2026-11-27 |
| **Register row** | [WEB-SYSTEM.md](WEB-SYSTEM.md) §15 row 40 (new) |
| **Rule** | [WEB-SYSTEM.md](WEB-SYSTEM.md) §9 « Text scale & reflow » (rule 1, a row that cannot fit must wrap; the doubled-text modes) · §8 Dialogs · the app's rule, [SYSTEM.md](SYSTEM.md) §13.3 |
| **Governs** | `web/components/Modal.tsx` · `web/components/Toast.tsx` · `web/components/pro/ChangeRoleDialog.tsx` · `web/components/pro/InviteMemberDialog.tsx` · the « Révoquer l’accès » dialog in `web/components/pro/EquipeClient.tsx` · the « Confidentialité » section of `web/components/account/AccountClient.tsx` · `web/tailwind.config.ts` (`max-w-gutterBound`) |
| **Skills checked** | `myweli-web-guardrails`, `myweli-dev-guardrails` |
| **Builds on** | [web-email-seams.md](web-email-seams.md) (#902, not merged; this branch is stacked on it) §7, its first three follow-ups |

---

## 1. Goal & scope

#902 measured three overflows at 320 px with Android's 200 % text that were
not about addresses, and left them out (its §7). This fixes them, and what
measuring them found behind them:

1. **`/mon-compte`** grows the layout viewport to 466 px in the Android mode,
   with any address: « Exporter mes données » is `shrink-0` in a row that
   cannot hold it.
2. **« Changer le rôle »**: its `<select>` and a button run past the screen.
   The dialog is fixed, so the page does not grow and no gate sees it.
3. **`Toast`**: the pill is as wide as its longest word, so a long word at
   200 % pushes it off both edges.

**Out of scope:** §7.

## 2. Measured before building

#902's head (`764e7598`), the e2e stub, Chromium at 320×568, the committed
Hanken Grotesk. Modes as in `type-overflow.spec.ts`: normal text, the Android
mode (`text-size-adjust: 200%` on a touch phone) and the browser font at
200 % (a 32 px root: px text stays, rem boxes grow). Raw readings:
the session notes' `doubled-text-three/` folder.

### 2.1 `/mon-compte`, « Confidentialité »

| | Normal | Android 200 % | 32 px root |
|---|---|---|---|
| Layout viewport | 320×568 | **466×828** | 320×568 |
| « Exporter mes données » | 147 px, x 140–287 | 289 px, x 177–**466** | 147 px |
| The sentence beside it | **91 px wide, 8 lines** | 128 px wide, 9 lines | 91 px, 8 lines |

The row is `flex justify-between gap-m` and the link `shrink-0`, so the
sentence « Recevoir une copie de vos données (profil, rendez-vous, favoris). »
gets what the link leaves: at normal text, a 91 px column of 8 lines. In the
Android mode the link alone is wider than its row (254 px).

**Behind it, found by a text-level scan once the link was fixed:** the section's
heading « Confidentialité », one word at 44 px, is 291 px in a 254 px column,
and the page still grew to **324×576**. The same failure as the 404's
« introuvable » (§15 row 38). Nothing else on the page, its deletion
confirmation included, crosses the screen.

### 2.2 « Changer le rôle » and its two siblings on `/pro/equipe`

The dialog's real failure is **vertical**, and the shared `Modal` has it: the
panel is centred in a fixed box that does not scroll, the page behind it is
locked, so a panel taller than the screen is cut at both ends with no way to
reach them.

| Dialog, state | Normal | Android 200 % | 32 px root |
|---|---|---|---|
| « Changer le rôle », as it opens | fits (454 px) | **988 px tall**, top at −210: the title and the address above the screen, « Annuler » / « Enregistrer » below it (y 695–753), « Annuler » also off the left (x −67) | fits |
| … « Collaborateur » chosen (the fiche `<select>`) | 576 px, top −4 / bottom 572; **« Créer une fiche » ends at x 330** | 1,194 px tall; the select ends at x 365, « Créer une fiche » at **496** | 666 px, title and « Enregistrer » cut; « Créer une fiche » at 330 |
| … « Créer une fiche » pressed (name field + « Créer ») | **« Créer » ends at x 343** | 1,136 px tall; the field ends at 430, « Créer » at **559** | « Créer » at 343 |
| « Inviter un membre », as it opens | 560 px, fits | 1,126 px tall, top −280; « Annuler » at x −58 | 638 px, both buttons cut |
| … « Collaborateur » chosen | **716 px tall on a 568 screen**: the title above it, **« Envoyer l’invitation » below it (y 562–618)**, unreachable; « Créer une fiche » at x 330 | 1,432 px tall | 836 px tall |
| « Révoquer l’accès » | fits | 618 px tall, top −26; « Annuler » at x −47 | fits |

« Annuler » could not be pressed at all in the Android mode (Playwright: not on
the screen, and nothing scrolls to it). Two causes:

- **The panel cannot scroll** (`Modal.tsx`). `ManualBookingDialog` already
  works around it with its own `max-h-[90vh] overflow-y-auto` (a declared
  arbitrary value); no other dialog does.
- **Three rows do not wrap.** The fiche row (`<select>` + « Créer une fiche »)
  and the name row (`<input>` + « Créer ») are `flex gap-s` with a `flex-1`
  field, and a form control's automatic minimum width is its intrinsic width
  (the select's longest option, the input's 20 characters), so the field does
  not shrink and pushes the button out — at normal text, too. The footer is
  `flex justify-end gap-s`: two buttons wider than the row overflow to the
  left, off the screen.

**The same footer elsewhere,** measured in the Android mode at 320: « Ajouter
un client » (`ClientsClient`) puts « Annuler » at x −20; « Nouveau
rendez-vous » (`ManualBookingDialog`) at x 0, outside its panel (content edge
41). « Modifier le numéro » (`ClientCardClient`) has the same two buttons as
« Changer le rôle » in the same panel (inferred: x −67; not opened, its
recipe needs a guest client). Every other dialog footer already wraps
(`BlockedDatesDialog`, `DisponibilitesClient`, `MediasClient`).

**Found by the gate, after the sign-off** (§6): « Nouveau rendez-vous »'s date
and time, two `flex-1` fields in a row that does not wrap, ran « Heure du
rendez-vous » to **x 340 at normal text** on a 320 phone (a date or time
field's automatic minimum width is its own drawing). The same rule as the
fiche row (§9 rule 1), fixed the same way, a unit check watched red first.

### 2.3 `Toast`

The live region is `fixed left-1/2 -translate-x-1/2` with no width. A box
placed by `left` alone is as wide as its content **up to the space right of
`left`: half the screen**. So:

- **A pill is at most half the screen wide**, unless one word is wider. At 320,
  normal text: 160 px, « Invitation renvoyée. » on 2 lines, « Budget de
  renvois épuisé pour cette invitation. » on 4. In the Android mode the same
  error is 7 lines, 296 px tall; « Ce client a un compte MyWeli : son numéro
  est celui du compte. » 10 lines, **416 px of a 568 screen**. This is a known
  residual ([web-pro-upload-resize.md](web-pro-upload-resize.md) §2.7 and §11
  item 13), and it is **deliberate in what it touches**: decisions 91 and 100
  place the favourite's message beside « Carte » on that width, the moves are
  pinned in `site-look.spec.ts` (« the favourite’s message and « Carte »
  (decision 100) », 24 tests with each slide, rise and drop measured), and a
  full-width pill was built once (`dd5fcd6f`) and taken out because it
  covered « Carte »'s label. `pro-upload.spec.ts` pins the half width (≤ 161 px).
- **A word wider than half the screen sets the width**, centred, and nothing
  caps it. A salon's name is data and can be one long word: « Vous avez
  rejoint Beautédivinecocodyriviera » is 220 px at normal text (fits), and in
  the Android mode the pill runs **x −34 to 354** on a 320 screen, both ends
  cut. (#902 found the same with an address; the team's toasts no longer
  carry one.)

## 3. Candidates, measured

Built and measured in all three modes (prototype, not committed; its patch in
the session notes).

| Place | Candidate | Result |
|---|---|---|
| `/mon-compte` | the row wraps (`flex-wrap`, `gap-x-m gap-y-s`), the link loses `shrink-0`; the heading `hyphens-auto` with `break-words` as the fallback | **320×568 in all three modes.** Normal text: the sentence takes the row's width, 3 lines, the link under it (was 8 lines in 91 px). Android: the sentence 5 lines, the link 2 (« Exporter mes » / « données »). Mac Chromium hyphenates « Confidentia- / lité »; CI's Linux Chromium may not, and then the word breaks without a hyphen (the 404's case, web-funnel-doubled-text.md §5) |
| `Modal` | the panel takes at most the screen's height less the wrapper's `m` padding (`max-h-full`) and scrolls inside (`overflow-y-auto`, `overscroll-contain` so the page behind does not scroll on) | every panel stays on the screen (y 16–552) and every control can be scrolled to and pressed, in all three modes. A panel that fits is unchanged |
| The fiche row, the name row | `flex-wrap`; the field `min-w-0 flex-auto` (it keeps its natural width when there is room, goes to a line of its own when there is not) | normal text at 320: the select full width, « Créer une fiche » under it; nothing past the panel in any mode. From the 448 px panel up (tablet, desktop) the row is as today |
| Every two-button footer | `flex-wrap`, as the three dialogs that already wrap | Android: « Annuler » on the first line, the action under it, both right-aligned, inside the panel. Normal text at 320: « Inviter un membre »'s « Envoyer l’invitation » goes under « Annuler » (it was squeezed to two lines) |
| `Toast` | the region keeps today's shrink-to-fit and gains a cap, the screen less its two `m` gutters (`max-w-gutterBound`: `calc(100% - 2 * 16px)`, the same 16 px the placement code keeps from an edge); the message in a `min-w-0 break-words` span inside the pill, so a word wider than the cap breaks | Android, the long name: the pill **x 16–304**, the text 40–280, 4 lines. **Every ordinary message keeps its box to the pixel** (80–240 at normal text, 74–246 in the Android mode): its width never reached the cap |

**What stays imperfect, measured:** at 200 % on a 320 phone the fiche
`<select>` is 238 px wide and « Choisir une fiche… » needs about 265 px at
32 px, so the closed control shows it cut after « fi ». A native select draws
one line and cannot wrap; the picker lists every option whole, and the label
« Fiche employé » names the field. A long fiche name is cut the same way. The
app's dropdowns ellipsize their chosen item for the same reason
(SYSTEM.md §21 row 66). And when « Révoquer l’accès » opens in the Android mode,
the focus goes to « Annuler » (SYSTEM §15: the safe path is focused), so the
panel opens scrolled to its end, with the title above (scroll up to read it;
a screen reader has it as the dialog's name).

## 4. The shape (proposed)

- **`Modal`: a dialog taller than the screen scrolls inside its panel.** Three
  classes in the shared component, outside `panelClassName`, so every dialog
  has them: `max-h-full overflow-y-auto overscroll-contain`. Nothing in any
  dialog is placed outside its panel (read: the Lightbox's panel is
  `contents`, which these classes do not touch; the before/after viewer's
  absolutes are inside its own frame), so the scroll clips nothing.
  `ManualBookingDialog` drops its own `max-h-[90vh] overflow-y-auto` and its
  `ds-ignore`: the rule it worked around is now the Modal's.
- **A row in a dialog that cannot fit wraps** (§9 rule 1): the fiche row and
  the name row in « Changer le rôle » and « Inviter un membre », the date and
  time of « Nouveau rendez-vous » (found by the gate), and every dialog footer — those two, « Révoquer l’accès », and (decision 2) « Ajouter
  un client », « Nouveau rendez-vous », « Modifier le numéro ». A field in a
  wrapping row is `min-w-0 flex-auto`.
- **`/mon-compte`:** the « Confidentialité » row wraps and its link is no
  longer `shrink-0`; the heading hyphenates, `break-words` as the fallback.
- **`Toast`: a pill is never wider than the screen less its gutters**, and a
  word wider than that breaks inside the pill. Its width otherwise does not
  change (decision 3).
- **WEB-SYSTEM:** §8 gains « a dialog taller than the screen scrolls inside
  its panel »; §9 gains « a dialog's row of buttons wraps » and « a toast is
  never wider than the screen less its gutters »; the declared loss of a
  native select at 200 % (decision 4); §15 gains row 40, closed.

No copy changes. No behaviour changes: the same controls, in the same order,
doing the same things.

## 5. Decisions (answered 2026-11-27: « Approve as recommended »)

1. **The shape in §4, as a whole.** *Recommended: approve.* — **Approved.**
2. **The three other dialog footers** (« Ajouter un client », « Nouveau
   rendez-vous », « Modifier le numéro »): the same one-class fix, measured off
   the screen (two of three opened). *Recommended: include them; the
   alternative leaves them as a follow-up.* — **Included.**
3. **The toast's width.** *Recommended: keep it at half the screen*, as
   decisions 91 and 100 were accepted on, and only cap it and break a too-long
   word (§4). The alternative, a pill as wide as the screen less its gutters,
   would cut the 10-line message to about half, but it changes the « Carte »
   moves the owner accepted with decision 100, which would have to be
   re-measured (on Linux CI too) and put to the owner again — a piece of its
   own. — **Kept at half the screen.**
4. **The native select at 200 %.** *Recommended: accept it and declare it* in
   §9 (the picker shows the options whole; the app does the same). The
   alternatives: shorten the placeholder to « Choisir… » (fits; a long fiche
   name is still cut), or replace the select with a list of choices (the
   app's sheet has one; a redesign, not this fix). — **Accepted and declared.**

## 6. Tests (red first, on the code before the change)

- **Unit** (`web/tests/dialogs-toast-doubled-text.test.tsx`): `Modal`'s panel
  carries `max-h-full overflow-y-auto overscroll-contain` whatever
  `panelClassName` it is given; in both team dialogs the fiche row and the name
  row wrap and their field is `min-w-0`, and every footer wraps; the
  « Confidentialité » row wraps, its link is not `shrink-0`, its heading
  hyphenates with `break-words`; the toast's region carries `max-w-gutterBound`
  and its message sits in a `min-w-0 break-words` span; the token is
  `calc(100% - 2 * ${spacing.m})` and `Toast.tsx`'s `EDGE` is the same
  `spacing.m`.
- **e2e** (`type-overflow.spec.ts`, a new block « the dialogs, the toast and
  /mon-compte at doubled text »), at 320×568 × the three modes, each with its
  vacuity guard (the mode applied: the drawn size):
  - `/mon-compte`: the layout viewport keeps the screen's size, no sideways
    scroll, and the link and the heading inside their section's content edge.
    #902's block drops its « No screen-size check here » exception and checks
    the screen's size on `/mon-compte` too.
  - Each dialog state of §2.2: the panel wholly on the screen; no control past
    the panel's content edge; **every control reachable** — scrolled into view
    inside the panel, it is wholly on the screen — and « Annuler » pressed
    closes the dialog; in the Android mode the panel does scroll (its content
    taller than its box: the guard that the scroll is what is tested).
  - The toast, through a real flow: the rejoin of roles.spec
    (« Vous avez rejoint {salon} ») with the invitation's salon name served as
    one long word; the pill whole on the screen and at least `m` from each
    edge, the word broken inside it in the Android mode (its vacuity guard),
    whole on one line at normal text.
  - **Kept green, unchanged:** `site-look.spec.ts`'s 24 decision-100 tests
    (the favourite's moves) and `pro-upload.spec.ts`'s half-width pin.
- **Mutations, on committed code**: each class above removed alone, each run
  against the unit file and the e2e block, all red.

## 7. Not covered — follow-ups

- **The toast's half width** (decision 3), if the owner takes the wider pill.
- **`/pro/avis` and the salon page's reviews**: two inline reply rows
  (`AvisClient`, `ReviewList`) are `flex justify-end gap-s` too; not dialogs,
  not measured here.
- `/politique-confidentialite`, the 404, the install banner, `/` and
  `/recherche` (§15 row 38) are unchanged.
- Measured in Chromium's mobile emulation; real phones not verified.
