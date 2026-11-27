# « Équipe » in the Pro app: every member's address, broken only at its seams

| | |
|---|---|
| **Status** | Approved (2026-11-27); built; one question re-opened by the first picture and answered the same day (§3, §5.3) |
| **Approved** | by the owner, 2026-11-27, on §5: « Approve as recommended » (the shape in §4 as a whole; the snackbars drop the address); then §5.3, re-opened by the first picture: « Drop it everywhere » (the roster's initial avatar) |
| **Owner** | Sadreddine Daher |
| **Last updated** | 2026-11-27 |
| **Module / phase** | `access` (team) · V1 |
| **Register row** | [SYSTEM.md](SYSTEM.md) §21 row 99 (extended) |
| **Rule** | [SYSTEM.md](SYSTEM.md) §13.3 « An e-mail address breaks only at its seams » and « A sentence that names an address gives it a line of its own » (#895) |
| **Parity** | the website's « Équipe » ([web-email-seams.md](web-email-seams.md), PR #902, not merged) |
| **Governs** | `mobile/lib/screens/provider/team/team_screen.dart` · `mobile/lib/screens/provider/team/invite_member_sheet.dart` · [team-access-r3-app.md](team-access-r3-app.md) §2.1 (its copy) |
| **Skills checked** | `myweli-dev-guardrails` |

---

## 1. Goal & scope

§13.3's e-mail rule (#895) covered five app sites: the three sign-in code
steps, the address change and « Modifier le profil ». The website brought its
own « Équipe » under the rule (#902). The Pro app's « Équipe » draws a
member's address in seven places and was never measured. This brings all
seven under the rule.

**In scope:** the seven places in §2, all on the owner's « Équipe » screen,
in its sheets, in its dialog, or in its snackbars.
**Out of scope:** §7.

## 2. Measured before building

`main` at `2e148f89`. Roboto, the real font. Measured with a throwaway widget
probe through the real screen and the mock team service. Addresses used:
`aminata.kone@exemple.ci`, `awa.kone.nouvelle@exemple.ci`,
`koffi.yao@gmail.com`, `awa@exemple.ci`, and `ouattaraaminatakone@exemple.ci`,
whose name part is a single piece wider than a line at 200 %. Widths: 360 and
390 dp (the golden's). Text: 1× and 2×.

| # | Place | Today | 1× | 2× (360 dp) |
|---|---|---|---|---|
| 1 | **The roster row**: the address beside the role chip (`_MemberRow`, `bodyLarge`, `Flexible`, ellipsis) | **cut at every size** | 360: **every address cut**: « aminata.kone… », « koffi.yao@g… », « awa@exempl… », « jean@salon-excel… ». 390: still five of six cut. The committed `pro_team.png` shows it: « fatou.reception@… », « sonia.staff@m… » | **one to four letters**: « a… », « o… » (28 dp beside « Collaborateur »), « ko… », « aw… », « ami… », « jean… ». At 390, « amin… » and « o… ». A roster that cannot tell its members apart |
| 2 | **The actions sheet's heading**: the address beside the chip (`titleMedium`, `Expanded`, ellipsis) | cut when long | whole up to ≈ 28 characters; « ouattaraaminatakone@exempl… » | « aminata.kone… », « awa.kone.… », « ouattaraa… ». The sheet that is about to revoke someone does not say whom in full |
| 3 | **« Révoquer l’accès ? »**: « {adresse} perdra immédiatement l’accès à {salon}. Son compte MyWeli n’est pas supprimé. » | inline, first | fits on line 1 | **cut mid-word**: « aminata.kone@exe » / « mple.ci perdra »; « awa.kone.nouvelle@ » / « exemple.ci perdra » (the wrong seam) |
| 4 | **The invite sheet's role step**: « Quel rôle pour {adresse} ? » | inline, last | fits; a long one moves whole to line 2, « ? » drawn after it | **cut mid-word**: « Quel rôle pour adjoua.ko » / « uame@exemple.ci ? », « …marie.clai » / « re.yao@exemple.ci ? » |
| 5 | Snackbar « Invitation envoyée à {adresse} » (invite sheet; **no period**, unlike the others) | inline, last | the address alone on line 2 | « adjoua.kouame@exe » / « mple.ci » |
| 6 | Snackbar « Invitation renvoyée à {adresse}. » | inline, last | the address alone on line 2, period drawn | « awa.kone.nouvelle@ » / « exemple.ci. » |
| 7a | Snackbar « Accès de {adresse} révoqué. » | inline, middle | fits | « Accès de aminata.ko » / « ne@exemple.ci » / « révoqué. » |
| 7b | Snackbar « Rôle de {adresse} : {Rôle}. » | inline, middle | fits | « Rôle de aminata.kon » / « e@exemple.ci : » / « Réception. » |

**Why no gate saw it.** No a11y test pumps « Équipe ». The legibility sweep,
`expectNoLegibilityCrush`, would not have seen place 1 anyway, and the probe
showed why: the row's `Text` has an ellipsis but no `maxLines`, and the sweep
measures « how many characters fit » with no `maxLines`, so the text wraps
freely. It reported the 28 dp row as showing all 30 characters (§7).

**What a screen reader gets today.** The row reads its address whole, since an
ellipsis is drawn, not heard. A sighted owner at 200 % sees « a… ».

## 3. Candidates, measured

The shape of §4 was built as a throwaway prototype, measured, then reverted.

| Place | Candidate | 1× | 2× (360 dp) |
|---|---|---|---|
| 1, the roster | the address alone as the row's title, breaking at its seams; **the role chip moves under it**, first line of the subtitle | 360 (192 dp of title): « aminata.kone » / « @exemple.ci »; « koffi.yao@gmail.com », « awa@exemple.ci » and the owner's « jean@salon-excellence.test » whole. 390: « aminata.kone@exemple.ci » whole | « aminata » / « .kone » / « @exemple.ci » · « koffi.yao » / « @gmail.com » · « awa » / « @exemple.ci » · « awa.kone » / « .nouvelle » / « @exemple.ci » · « jean@salon- » / « excellence.test » (a hyphen: the engine's own legal break, which the gate allows) |
| 2, the sheet's heading | the address on its own, full width; the chip under it | whole, the wide one included | « aminata.kone » / « @exemple.ci » · « ouattaraaminatakone » / « @exemple.ci » (328 dp holds it whole) |
| 3, « Révoquer l’accès ? » | the address first, on a line of its own, in ink; then the sentence | whole | « aminata.kone » / « @exemple.ci », then « perdra immédiatement l’accès à… » |
| 4, the role step | « Quel rôle pour », then the address on a line of its own, in ink | whole | « adjoua.kouame » / « @exemple.ci » · « marie.claire.yao » / « @exemple.ci » · « kouadioyaoarmandxx » / « @exemple.ci » |

**What still breaks inside a piece:** a single piece wider than the line. On
the roster at 2× on 360 dp, the title has 192 dp, about 11 characters, so
« ouattaraaminatakone » reads « ouattaraami » / « natakone » / « @exemple.ci ».
In the dialog (264 dp) it reads « ouattaraaminatakon » / « e@exemple.ci ».
§13.3 already accepts this: past that point, no layout has more to give.
Dropping the row's initial avatar would give the title 248 dp, but measured,
that does not hold this piece either (≈ 285 dp at 2×). It would only join
« aminata » / « .kone ». The avatar stays.

**⚠️ Corrected after the first Linux picture (2026-11-27, `pro_team_w360_x2`,
run 46056862693).** The paragraph above measured a NAME piece and missed the
DOMAIN. The picture showed the seed addresses broken inside their domain:
« retard » / « @myweli.tes » / « t ». A domain is one piece (§13.3 never breaks
it at its « . »), and at 2× several common ones are wider than the roster's
192 dp (Roboto, measured):

| Domain | 1× | 1.5× | 2× |
|---|---|---|---|
| `@hotmail.com` · `@outlook.com` | 110 | 162 | **214** |
| `@myweli.com` (our own) | 105 | 155 | **205** |
| `@myweli.test` (the seeds) | 102 | 149 | **197** |
| `@yahoo.com` · `@icloud.com` | 98–99 | 145 | **192** |
| `@gmail.com` · `@exemple.ci` | 95–96 | 139–142 | 184–187 |
| `@hotmail.fr` · `@outlook.fr` · `@orange.ci` · `@yahoo.fr` | 77–89 | 114–130 | 150–172 |

Without the initial avatar the title gets **248 dp** (288 on the owner's row,
which has no chevron), measured on the screen, and every domain above fits at
2×. The gate tests did not see it because their addresses all end in
`@exemple.ci` or `@gmail.com`, which fit. Taken back to the owner (§5,
question 3).

## 4. The shape (proposed)

- **The roster row (1).** The address is the row's title, on its own, breaking
  only at its seams (`Formatters.breakableEmail`), with no ellipsis. The role
  chip moves to the first line under it. « Employé : … », « Invitation
  envoyée · expire le … », « Expirée » and « Accès révoqué » follow, as
  today. At 1× a long address takes two lines where it used to be cut. Every
  row now has a chip line, so rows get one line taller.

  ```text
  aminata.kone                         ›
  @exemple.ci
  [Manager]
  ```

  **The initial avatar is gone** (§5.3, after §3's correction): it left the
  address 192 dp at 200 %, too narrow for a twelve-character domain. A screen
  reader hears the address first (without its break marks; it used to hear
  the initial before it), then the role, then the subtitle lines. The row's
  semantics are merged by `ListTile`, as today.
- **The actions sheet's heading (2).** The address on its own at
  `titleMedium`, breaking at its seams. The chip goes under it.
- **« Révoquer l’accès ? » (3).** This is the website's shape. The address
  comes first, on a line of its own, in ink. The sentence follows in the
  dialog's own style, with no period drawn after the address. A screen reader
  hears one node, the sentence exactly as it was: « {adresse} perdra
  immédiatement l’accès à {salon}. Son compte MyWeli n’est pas supprimé. »

  ```text
  Révoquer l’accès ?

  aminata.kone
  @exemple.ci
  perdra immédiatement l’accès à Salon Excellence.
  Son compte MyWeli n’est pas supprimé.
  ```
- **The role step (4).** This is `CodeSentTo`'s shape: « Quel rôle pour », then the
  address on a line of its own, in ink. The « ? » is not drawn: on a line of
  its own it would read as part of the address, as the period would in
  `CodeSentTo`. A screen reader hears « Quel rôle pour {adresse} ? ».
- **The snackbars (5, 6, 7a, 7b).** They say what happened without the
  address, as on the website: « Invitation envoyée. », « Invitation
  renvoyée. », « Accès révoqué. », « Rôle mis à jour. ». Every one closes the
  sheet it was raised from onto the roster, and the row it speaks of is on
  screen, updated. (The alternative is in §5.)
- **One shared drawing for « a sentence that names an address ».**
  `CodeSentTo` keeps its API and its tests and draws through it. The
  revoke dialog uses the address-first form, the role step the address-last
  form.

[team-access-r3-app.md](team-access-r3-app.md) §2.1 is amended to match (the
row, the sheet, the four messages). §13.3's text does not change: these
places follow rules it already states. §21 row 99 gains these seven places.

## 5. Decisions (answered 2026-11-27, « Approve as recommended »)

1. **The shape in §4 as a whole.** This includes the chip moving under the
   address on the roster and in the sheet, rows one line taller, and the role
   step's « ? » heard but not drawn. **Approved.**
2. **The snackbars.** **Drop the address (approved)**, the website's choice
   (web-email-seams.md §5, 2026-11-27). The alternative is the address on a
   line of its own inside the snackbar. That needs `AppSnackBar` to take an
   address and draw it as `CodeSentTo` does, a change to the shared
   component every snackbar in both apps goes through.

3. **The roster's avatar at 200 %** (asked 2026-11-27, after the correction
   in §3) — **« Drop it everywhere »**, as recommended: **drop the initial avatar at every size**: the title
   gets 248 dp at 360, every common domain fits at 2×, no branch can rot, and a
   screen reader stops saying « A » before each address (it hears the initial
   today: « A, aminata.kone@exemple.ci, Manager »). The 1× roster loses its
   initial circles. Alternative: **hide it only when an address's widest piece
   would not fit beside it**, measured on the roster's data as
   [amounts-that-fit.md](amounts-that-fit.md) does, so 1× keeps the circles.
   Or keep it, and a 12-character domain breaks inside at 200 %
   (« @hotmail.co » / « m »).

## 6. Tests: red first, on the code before the change

- **`test/a11y/team_email_test.dart` (new)**, through the real screen at
  360 dp × 2× and 1×, in the real font, with the addresses of §2:
  `expectEmailAddressOnItsOwnLine` on each roster row (the owner's included),
  the sheet's heading, the revoke dialog and the role step. What a screen
  reader hears: the row's merged label holds the address without U+200B, the
  dialog is one node with the sentence as it was, and the role step is one
  node with its « ? ». Each red first for its own reason: a cut row, a cut
  heading, a mid-word break, a « ? » drawn after the address.
- **`team_screen_test.dart` and `invite_member_sheet_test.dart`**: the four
  snackbars' new words, red first, and the rows found as drawn
  (`Formatters.breakableEmail`).
- **Goldens, authored on Linux** (`gh workflow run goldens.yml`):
  `pro_team.png` changes (390 × 1×, now whole addresses and the chip line).
  A new `pro_team_w360_x2` photographs the roster at 200 %, where the defect
  was. Every changed image is looked at.
- **Mutations, on committed code**, each with its failure text. Each place
  goes back to its old drawing (ellipsis, chip beside, inline sentence, drawn
  « ? »). Also: the break marks heard, the dialog's semantics node dropped,
  each snackbar with its address back.

## 7. Not covered: follow-ups

- **`expectNoLegibilityCrush` cannot see an ellipsis without `maxLines`**
  (§2). `_prefixFits` lays the prefix out with `maxLines: null`, so it wraps
  and always « fits ». Its doc comment says such a site is « out of this
  sweep's reach » because `didExceedMaxLines` is false. The probe read it
  true. Fixing the gate may turn other screens red: a task of its own.
- **Two other Pro screens draw an address, unmeasured.** The Pro « Profil »
  shows the account's address (`pro_profile_screen.dart`, ~89 and ~102). The
  Android sign-up's « Compte : {email} » is a sentence that names one
  (`pro_sign_up_screen.dart`, ~815).
- **The invite field** (« E-mail du membre ») is an input. It scrolls on one
  line, and the rule is about drawn text.
- A single piece wider than a line still breaks inside (§3).
