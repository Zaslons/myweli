# Every other e-mail address on the website, broken only at its seams

| | |
|---|---|
| **Status** | Approved (2026-11-27), building |
| **Owner** | Sadreddine Daher |
| **Last updated** | 2026-11-27 |
| **Approved** | by the owner, 2026-11-27, on §4 and §5: « Approved, build it » · toasts « Drop the address » · store-linked pages « Unfrozen, include them » |
| **Register row** | [WEB-SYSTEM.md](WEB-SYSTEM.md) §15 row 39 |
| **Rule** | [WEB-SYSTEM.md](WEB-SYSTEM.md) §9 « An e-mail address breaks only at its seams » · the app's rule, [SYSTEM.md](SYSTEM.md) §13.3 (#895) |
| **Governs** | `web/components/BreakableEmail.tsx` (new) and every place §2 lists |
| **Skills checked** | `myweli-web-guardrails`, `myweli-dev-guardrails` |
| **Builds on** | [web-code-sent-to.md](web-code-sent-to.md) (#898, the code step; not merged yet — this branch stacks on it) |

---

## 1. Goal & scope

#898 brought the code step under §9's rule and named four other places that
draw an address, unmeasured. A sweep of `web/` found twelve. This brings them
all under the rule: an address breaks only before its « @ » or before a « . »
of its name part, and a sentence that names one gives it a line of its own.

**In scope:** §2's twelve places. **Out of scope:** §7.

## 2. Measured before building

#898's head (`a36f06d8`), the e2e stub, Chromium at 320×568 unless stated, the
committed Hanken Grotesk. Addresses: `aminata.kone@exemple.ci` and
`awa.kone.nouvelle@exemple.ci` (written « aminata » and « awa » below), the
support address `support@myweli.com`. Modes: normal text, the Android mode
(`text-size-adjust: 200%`, text at 28–32 px) and the browser font at 200 % (a
32 px root: px text stays, rem boxes grow).

| # | Place | Today | Normal text | Android 200 % |
|---|---|---|---|---|
| 1 | Équipe, the roster's « Membre » cell (`EquipeClient`) | `break-all` | cut anywhere: « aminata.kone@e » / « xemple.ci », « awa.kone.nouvel » / « le@exemple.ci ». **Also at 1024**: « aminata.kone@exem » / « ple.ci » | « aminat » / « a.kone » / « @exem » / « ple.ci »; at 1024 « awa.kone. » / « nouvelle@ » / « exemple.c » / « i ». At the 32 px root « aminata.ko » / « ne@exempl » / « e.ci » |
| 2 | The Pro sidebar, a member's address (`ProSidebar`, 189 px rail) | `break-all` | fits | « aminata.kone@e » / « xemple.ci », « awa.kone.nouvel » / « le@exemple.ci », at 320 and 1024 |
| 3 | Profil, a member's slim view (`ProfilClient`) | `break-all` | fits | « aminata.kone@ex » / « emple.ci »; « awa » fell on its seam by luck |
| 4 | « Changer le rôle » dialog (`ChangeRoleDialog`) | nothing | fits | **runs off the dialog and off the screen**: its text ends at 372 / 437 px on a 320 screen. The page does not grow (the dialog is fixed), so no gate sees it |
| 5 | « Révoquer l'accès » dialog: « {adresse} perdra immédiatement l'accès à … » (`EquipeClient`) | nothing | fits | the same, 372 / 437 px |
| 6 | The team's three toasts: « Invitation envoyée à {adresse}. », « Invitation renvoyée à {adresse}. », « Accès de {adresse} révoqué. » | nothing | the address alone on the second line, period drawn | **the pill is wider than the screen**, both ends cut: [−33, 353] / [−66, 386]. A pill is as wide as its longest word, so the address sets its width |
| 7 | « Alertes par e-mail »: « … nous vous écrivons à {adresse} : nouvelle demande, … » (`EmailAlertsPreference`, `/pro/notifications`) | `break-words` | the address moves whole to its own line; the next starts « : nouvelle demande » | **the page grows to 394×698 / 450×799**: `break-words` cannot narrow a flex item (it does not lower min-content). At the 32 px root, « awa » scrolls to 331 |
| 8 | `/mon-compte`, under the name (`AccountClient`) | nothing | fits | the address runs to 364 / 429 px. The page already grows to 466 with any address (§7) |
| 9 | `/mon-compte/donnees`, the « Profil » row (`DataExportClient`) | nothing | « awa » already runs 14 px past the card's content edge | **the page grows to 454×806 / 520×923** |
| 10 | `/pro/suppression-compte`, three times (`Email` in `LegalPage.tsx`) | `<wbr>` after « @ » | fits | « support@ » / « myweli.com » — the wrong seam |
| 11 | `/mentions-legales` « Nous contacter » (a store-linked page) | nothing | fits | **the page grows to 343×609** |
| 12 | `/support` « Nous écrire » (a store-linked page) | nothing | fits | **the page grows to 352×625**, the address out of its bordered link |

**What a screen reader gets.** Read off Chromium's accessibility tree (CDP),
not Playwright's: a bare `<wbr>` splits an address into three text nodes
(« aminata », « .kone », « @exemple.ci »), and it puts a space into a link's
name — today's `Email` is named **« support@ myweli.com »** there. Playwright
computes its own name and reports « support@myweli.com », so the existing e2e
cannot see it. With #898's pattern (an `sr-only` copy, the drawing
`aria-hidden`) the tree holds one text node and the link is named
« support@myweli.com ». Copying: a triple-click on the drawing copies the
address once in all three shapes.

## 3. Candidates, measured

The shape of §4, built and measured in all three modes (prototype, not
committed). With the seams alone, two places still cut inside a piece at 200 %,
because their column is narrower than « @exemple.ci »:

| Place | Seams only (Android 200 %) | + its layout change |
|---|---|---|
| 1, the roster (« Membre » ≈ 100 px at 320, 132 at 1024) | « aminata » / « .kone » / « @exem » / « ple.ci »; at 1024 « @exemple » / « .ci » | « Membre » 3 → 5 parts of the row: « aminata » / « .kone » / « @exemple.ci »; at 1024 « aminata.kone » / « @exemple.ci »; whole on one line at 1024, normal text |
| 9, `/mon-compte/donnees` (≈ 155 px beside « Profil ») | « aminata » / « .kone » / « @exemple.c » / « i » | the row wraps: the address goes under « Profil », « aminata.kone » / « @exemple.ci » |

Everything else, seams only: 2, 3, 4, 5, 8 « aminata.kone » / « @exemple.ci »
and « awa.kone.nouvelle » / « @exemple.ci » (or « awa.kone » / « .nouvelle » /
« @exemple.ci » in the sidebar); 7 no growth at any size; 10, 11, 12
« support » / « @myweli.com » and no page grows. Normal text: every address
whole wherever it fit before.

## 4. The shape (proposed)

- **`BreakableEmail`** (`web/components/BreakableEmail.tsx`): the address read
  as one word (an `sr-only` copy), drawn `aria-hidden` with a `<wbr>` at each
  seam (`emailSeams`) and `break-words` as the fallback. Its drawing alone,
  `EmailSeams`, serves the sentences — and `CodeSentTo`, which keeps its shape
  and drops its own copy of the loop. In a flex or grid item the item needs
  `min-w-0`, or the fallback cannot narrow it.
- **An address on its own** (1, 2, 3, 4, 8, 9): `BreakableEmail`, same colour
  and size as today. Plus two layout changes: the roster's « Membre » column
  takes 5 parts of the row instead of 3 (« Rôle », « Employé », « Statut » keep
  theirs; the table already scrolls sideways below 640 px), and the
  « Profil » row of `/mon-compte/donnees` wraps.
- **A sentence that names one** (5, 7) takes `CodeSentTo`'s shape: a screen
  reader hears the sentence whole, period included; the drawing puts the
  address on a line of its own, in ink, no period after it.

  ```text
  aminata.kone                                     ← « Révoquer l'accès »
  @exemple.ci
  perdra immédiatement l'accès à Beauté Divine. Son compte MyWeli n'est pas supprimé.
  ```

  ```text
  Si une notification de l'app MyWeli Pro ne peut pas vous     ← « Alertes par e-mail »
  parvenir (nouvelle demande, report, annulation, justificatif
  d'acompte), nous vous écrivons à
  aminata.kone@exemple.ci
  ```

  The second sentence is reordered so the address can end it (its words are
  [salon-email-alerts.md](salon-email-alerts.md) §4's, which this amends).
  Without an address: « …, nous vous écrivons à votre adresse e-mail. »
- **The toasts** (6) say what happened without the address: « Invitation
  envoyée. », « Invitation renvoyée. », « Accès révoqué. ». The row they speak
  of is on screen, updated; a pill too narrow for a line of its own cannot
  give an address one. (The alternative, §5.)
- **The legal pages** (10, 11, 12): the same component inside the link, so
  the seam moves before the « @ » and the link is named « support@myweli.com »
  again. In the prose the address keeps its place rather than taking a line of
  its own: it is short and fixed, never breaks at normal text, and a block in
  mid-paragraph would break the prose at every size. 11 and 12 are in (§5). 10 is not a store-linked page, but `Email`
  lives in `LegalPage.tsx`, which all five import; their HTML does not change.

§9 of WEB-SYSTEM gains the component, the `min-w-0` condition, the legal-prose
exception and « a toast does not carry an address »; §15 row 39 closes.

## 5. Decisions (answered 2026-11-27)

1. The shape in §4, as a whole (including the two layout changes and the
   reordered « Alertes par e-mail » sentence) — **« Approved, build it »**.
2. The toasts — **« Drop the address »**. The alternative was the address on a
   line of its own, which needed the shared `Toast` to take an address and cap
   its pill at the screen's width.
3. `/support` and `/mentions-legales`, frozen while Apple reviewed the Pro
   app — **« Unfrozen, include them »**: 11 and 12 are in.

## 6. Tests (red first, on the code before the change)

- **Unit** (`web/tests/breakable-email.test.tsx`): the component (one text for
  a screen reader, the drawing hidden, cut at exactly its seams, the fallback),
  and each place rendered with a long address: it goes through the component;
  a sentence is heard whole; the toasts' words.
- **e2e** (`type-overflow.spec.ts`, a new block « every other address »): each
  place × the two addresses (+ a piece wider than a line where the column is
  narrow) × normal, Android 200 %, 32 px root, at 320×568, and 1024 for the
  roster and the sidebar. The layout viewport keeps the screen's size; the
  address's text stays inside the screen and its own box; its lines, exactly,
  are its seams. A screen reader's name read off Chromium's tree for the
  legal links.
- **Mutations** on committed code: each place back to its old markup; the
  copy or the hiding removed; a seam moved; `min-w-0` or a layout change
  removed.

## 7. Not covered — follow-ups

- `/mon-compte` grows to 466 px in the Android mode with **any** address:
  « Exporter mes données » is `shrink-0`. Not an address; measured with the
  stub's own `awa@example.com`.
- The « Changer le rôle » dialog's `<select>` and a button run past a 320
  screen in the Android mode.
- `Toast`: a pill is as wide as its longest word, so any long word at 200 %
  pushes it off both edges.
- The app's team screen says the same three sentences with the address inline
  (`team_screen.dart`, `invite_member_sheet.dart`); SYSTEM.md §21 row 99
  covered five other sites.
- The Pro sidebar at the 32 px root on a 320 phone was not measured: the
  drawer did not come fully on screen in the probe.
