# A15 — an app-bar title that cannot fit (SYSTEM.md §21 row 79)

> Module: **design system** (docs/MODULES.md). Closes §21 row **79**.
> Prior art: [mobile-a11-width.md](mobile-a11-width.md) (the width matrix),
> [web-b11-reflow.md](web-b11-reflow.md) (the truncation gate + `clip-ok`,
> which this ports), [mobile-a13-copy-and-breaks.md](mobile-a13-copy-and-breaks.md)
> (§13.3 as amended: a salon's name may not be mangled).

## 1. Goal & scope

§13.3 says text **reflows** rather than truncates. An `AppBar` title is the one
place in the product that structurally cannot: Material wraps it in a
`DefaultTextStyle(softWrap: false, overflow: TextOverflow.ellipsis)`
(`app_bar.dart:1082-1086`) inside a bar of fixed `kToolbarHeight`. So the house
has a rule its own chrome breaks, and **no gate has ever measured it**.

A15 decides what the rule *is*, gates it, and pays the debt it exposes.

**Out of scope, in writing** (so the register does not acquire the next row by
silence):

- **The admin console.** All 13 admin screens use `AdminScaffold`'s custom
  `_TopBar` (`screens/admin/widgets/admin_scaffold.dart:44-77`) and contain zero
  `AppBar`s; `main_admin.dart:79-99` deliberately installs no
  `MaterialApp.builder`. The rule below is stated for `AppBar` and **does not
  bind `_TopBar`**. Filed as a follow-up row rather than assumed.
- **The 7 unrouted `screens/provider/features/` screens.** Imported by nothing in
  `lib/`, reachable only from tests, flag-hidden behind
  `FeatureFlags.futureProviderFeatures` (V2/V3). Six of the fourteen worst
  strings live there. Precedent exists both ways, and A15 follows the §5 spacing
  pin, which already excludes them (`design_system_pin_test.dart:28-34`). They
  re-enter the corpus the day the flag flips — which is the right trigger,
  because that is the day a user can read them.

## 2. What was measured, and three things row 79 got wrong

Row 79 was written from a device run. Re-measuring with `TextPainter` over the
real `appBarTheme.titleTextStyle` (headlineSmall 24/w600, `app_theme.dart:247-249`)
found the row's own reasoning wrong in three places, each of which changes the
answer.

| row 79 asserted | measured |
|---|---|
| *"an ellipsis is not overflow — the paragraph fits, having thrown the text away first"* and *"nothing computes today"* | **False.** `didExceedMaxLines` is **`true`** on the ellipsized title even with `maxLines: null`. `test/a11y/_a11y.dart:636` already holds that branch; it is skipped only by the `ellipsisIsFine: true` default at `:627/:633`, which **no call site overrides**. A gate is possible today. |
| *"a `softWrap: false` paragraph is single-line regardless"* | **False.** `maxLines: 2` wraps it — `rendering/paragraph.dart:846` gives a finite max width whenever `softWrap \|\| overflow == ellipsis`. |
| *"the bar's height is fixed"* | **Incomplete.** `toolbarHeight` feeds `preferredSize` (`app_bar.dart:231`) and `Scaffold` re-reads it per frame (`scaffold.dart:3012-3021`). Measured working at 96dp. |

**The scope is 63 titles, not 3 screens.** `mobile/lib` holds 64 app-bar
constructions; 63 set a `title:`, and **every one is a plain `Text`** — no
`Column`, no `FittedBox`, no `Semantics` title anywhere.

**Material clamps the title to 1.34×** (`_kMaxTitleTextScaleFactor`,
`app_bar.dart:44`, applied at `:1092-1095`), so a title never reaches 200% no
matter what the OS asks. At 360dp, against that clamp:

| residual title width | bar shape | lose at 1.34× | lose at 1× |
|---|---|---|---|
| 312dp | `titleSpacing: 0` + `leadingWidth: 48` | **7 / 63** | 0 / 63 |
| **272dp** | back button, no actions | **14 / 63** | 1 / 63 |
| 224dp | back button + 1 icon action | **33 / 63** | 9 / 63 |
| 176dp | back button + 2 icon actions | **42 / 63** | 28 / 63 |

Excluding the 7 unrouted screens: **8 / 63** at 272dp, **25 / 63** at 224dp.

**The existing matrix reads these green, and that is a harness defect.**
`pumpAtWidth` hands the subject to `home:` (`_a11y.dart:206-213`), so no leading
back button is ever drawn: `ProManualBookingScreen` (`layout_test.dart:312`) and
`DashboardScreen` (`:912`) are *already* subjects and measure **328dp** of room
instead of the 272 they get on a pushed route. Until subjects are pushed, every
per-bar number above is a bucket estimate rather than a measurement — and the
suite is green about a bar it never renders.

### 2.1 Five corrections the build made to this section

Written after the fact, from measurements rather than from arithmetic. §2 above
is left standing because the corrections only make sense against what it claimed.

1. **This spec's own headline example is outside this spec's own corpus.** §2
   counts `AppBar(title:)` sites. It misses **four titles that reach a bar
   through a picker's `helpText:`** — `availability_screen.dart:323`
   (« Dates à bloquer », *the string the device photographed and the reason row
   79 exists*), `availability_screen.dart:1017`, `pro_journal_screen.dart:470`,
   `weekly_hours_editor.dart:101`. The gate reads them out of source, so a claim
   to cover « the corpus » is now something a run can check.

2. **The count was stale and is now derived.** 63 was right when written and
   wrong by the time the branch opened (`salon_preview_screen.dart:90` landed in
   #308). The corpus run scans `lib/` on every invocation: **56 title literals**
   at the sweep, 57 after the journal's title became a ternary whose two arms are
   both real titles. Nobody maintains that number again.

3. **`DashboardScreen` is never pushed** — only `context.go('/pro/dashboard')`,
   three sites. §5②'s « push the subjects » is therefore **per subject, the way
   the product enters it**: 13 of the matrix's 16 are pushed and now say so with
   the deciding `context.push` site in a comment; the dashboard and the consumer
   home are `go`-only shell roots that draw no leading; the two OTP screens are
   unrouted. Pushing the dashboard would have gated a 216dp bar Material never
   draws and forced a copy change the product does not need.

4. **§5① settles the action-less bars only, and on the others the title is not
   the defect.** An action's `TextButton` label is scaled by the **full,
   unclamped** system scaler — the 1.34 clamp wraps the title alone
   (`app_bar.dart:1092`) — so « Réinitialiser » costs ~182dp at 2× and leaves
   « Dates à bloquer » ~98dp of a 280dp bar. §5③'s « titles are shortened as
   copy » is a good sentence about the wrong half of the population; the fix on
   that half is `IconButton` + `tooltip:`. `primitives_test.dart` pins it with a
   four-letter title (« Avis ») starved by a text action.

5. **The gate is a scope, not new machinery.** `expectNoUndeclaredTruncation`
   already held the predicate in two arms and an `AppBar` title is
   `softWrap: false`, so the second arm already applied — only the
   `ellipsisIsFine` early-`continue` kept it silent. Both helpers now call one
   `_truncationReason`. Two predicates for one question drift, and the drift is
   invisible because both are green.

**And the outcome differs from the table above, in the direction the table's
method predicts.** `TextPainter` over a literal is not the same measurement as a
`RenderParagraph` inside a real `AppBar` — the widget applies `titleTextStyle`
through the theme, the clamp through `MediaQuery.withClampedTextScaling`, and
`NavigationToolbar`'s own layout. The table was a bucket estimate and said so;
the corpus run is the number.

### 2.2 §5① was built, photographed and half of it rejected

`titleSpacing: 0` + `leadingWidth: 48` shipped first, and the regenerated
baselines killed the spacing half.

**`titleSpacing` is the gap on BOTH sides and it applies whether or not a
leading exists.** So on a *root* bar — which draws no back button — zeroing it
puts the title at **x = 0** while the body it heads keeps its 16dp gutter. One
screen with two gutters, on all 57 bars, and plainly visible the moment
`pro_deposit_settings.png` was looked at: « Acompte » flush to the bezel above a
card inset by 16.

**And the 32dp it bought were not comfort.** Measured at the 1.34× clamp:

| title | width |
|---|---|
| « Nouveau rendez-vous » | 315.5dp |
| « Configurer mon profil » | **309.3dp** |
| « Nouvelle réservation » | 298.4dp |
| « Salons & Barbiers » | 257.2dp |
| « Configuration » | 197.2dp |
| « Réservation » | 172.7dp |

At 312 the widest survivor cleared by **2.7dp** — a font update or a Flutter
bump erases that. The plan's fallback of `titleSpacing: spacingS` was measured
too and is strictly worse than either end: 296dp loses the same two titles as
280 *and* still misaligns every root bar.

**Shipped: `leadingWidth: 48` alone, budget 280dp.** Those 8dp are free —
`BackButton` occupies exactly 48, so nothing was ever painted in them — and the
two extra titles shortened instead, both to strings with >80dp of headroom.
The §13.3 move this slice already used twice (« Préférences » on the bar, the
long phrase on the row that opens it) applies to both.

## 3. The rule

Added to **SYSTEM.md §13.3**:

> **An `AppBar` title must render whole, or declare that it does not.**
> Material gives a title one line and an ellipsis, and its height is fixed, so
> §13.3's « text reflows rather than truncates » cannot be satisfied by layout
> here. It is satisfied by **length**: a title is a label, not a sentence, and a
> title that does not fit the narrowest bar it can appear in at the platform's
> own scale clamp is too long. Where a title genuinely cannot be shortened —
> because it carries data the product does not own — it may clip **only** with a
> written reason in source saying where that information appears instead.
> `expectAppBarTitleWhole` enforces both halves.

### 3.1 Why not the alternatives

- **Grow the bar** (`toolbarHeight` from the `MaterialApp.builder` seam +
  `maxLines: 2`) is rejected on **product** grounds, not only risk. Measured at
  ~110dp, and ~155dp on the three screens carrying a `bottom: TabBar`
  (`my_bookings_screen.dart:78`, `appointment_list_screen.dart:124`,
  `earnings_screen.dart:109`) — roughly a fifth of a 780dp phone spent on chrome
  **on exactly the screens where a low-vision user has least room to spare**. A
  product that is good at accessibility sizes keeps chrome compact and lets
  content carry the meaning. It is also dangerous half-done: `maxLines: 2` in a
  stock 56dp bar measures paragraph 272.0×86.0 with `didExceedMaxLines == false`
  and **15dp cut off the top and bottom of both lines** by the bar's own
  `ClipRect` (`app_bar.dart:1151-1154`) — invisible to
  `expectNoUndeclaredTruncation`, `expectNoLegibilityCrush` **and**
  `expectNoVerticalClip` alike.
- **`FittedBox` / AutoSizeText** is disqualified because it **cannot be gated**:
  measured, it reports `didExceedMaxLines == false` at full intrinsic width while
  painting at ≈0.86× — byte-identical to a title that fits, and blind to all
  three existing helpers at once. §13.3 already says twice (`:680-681`,
  `:696-697`) *"the fix is always more width, never a smaller font"*.
- **Clamping the title's own scaler** below Material's 1.34 is forbidden by
  §13.3's first bullet and already policed by `design_system_pin_test.dart:594-624`.
- **`SliverAppBar.medium` / `.large`** are ruled out **by name**, so they are not
  re-proposed: their heights are constants (`app_bar.dart:2578-2579`,
  `:2601-2602` — measured 112.0dp at *both* 1× and 1.95×) and the expanded title
  is `overflow: clip` at full intrinsic width inside a `ClipRect` — a horizontal
  cut with no ellipsis and `didExceedMaxLines == false`, i.e. **strictly less
  detectable than today**.

## 4. The gate

`expectAppBarTitleWhole(tester, at:)` in `test/a11y/_a11y.dart`: find the
`AppBar`'s title `RenderParagraph` and assert `didExceedMaxLines == false`,
unless its string carries a declared written reason.

Run over **route-pushed** subjects across the existing {360, 375, 390} × {1×, 2×}
matrix — the push is part of the gate, not a detail, because a bar without its
leading is a green assertion about nothing.

**Watched red today, with nothing planted.** Measured, Flutter 3.38.6, real
Roboto, 360×800: `AppBar(leading: BackButton(), title: Text('Nouveau rendez-vous'))`
at 1.95× → title box **272.0dp**, needs **315.5dp**, `didExceedMaxLines = true`,
`maxLines = null`, `takeException() = null`. At 1× the same bar is 235.4/235.4,
`exceeded = false`.

Three falsifiability directions (§21 row 70 — a helper that cannot fail is
indistinguishable from one that passes):

1. **Red on the real defect** — the two cases above, before any fix.
2. **Red on a regression** — lengthen any gated literal past its bar's residual.
3. **Not vacuous** — a `checked > 0` guard, the shape `expectNoMidWordBreak` uses
   at `_a11y.dart:297-303`. The counting hazard is real and named above.

**Two traps, both measured, both fatal to a naive implementation:**

- **Do not build it by flipping `ellipsisIsFine: false` on the existing sweep.**
  `_a11y.dart:633` skips *every* ellipsis and there are **45**
  `TextOverflow.ellipsis` sites in `lib/` — flipping reds all 45 at once. This is
  exactly why web needed `clip-ok` **before** it could flip its equivalent switch
  (`tokens.theme-pin.test.ts:319-321`).
- **Do not route it through `wrapApp`'s default theme.**
  `AppTheme.lightTheme` names no font (`pump_app.dart:31-37`, `:61`), so glyphs
  are placeholder squares and « Dates à bloquer » measures **360.0dp** (15 × 24.0)
  against Roboto's 168.9dp — numbers ~2× too wide and a spurious `RenderFlex
  overflowed` red. Pass `AppTheme.themeData(fontFamily: kRealFont)`.

### 4.1 The declaration

Ported from web's `clip-ok`, with web's justification requirement rather than
mobile's same-line `// ds-ignore` (`design_system_pin_test.dart:45`), because
web's own rule is right about why: *"a `clip-ok` has to say where else the
information appears, which takes more than a sentence"*
(`tokens.theme-pin.test.ts:344-348`). A shipped loss owes the reader more than
three words. Marker word and window are settled in the build step; the marker is
**not** `ds-ignore`, which already means « a fixed dimension §5 does not govern ».

## 5. What changes

**① The free width — take it first.** `titleSpacing: 0` + `leadingWidth: 48` on
the existing `appBarTheme` (`core/theme/app_theme.dart:242-251`). Neither is set
anywhere in `lib/` today, so Material's defaults apply: 56dp leading
(`app_bar.dart:43`) + 16dp `titleSpacing` (`navigation_toolbar.dart:39`) = **72dp
spent on chrome before the first glyph**. Measured effect: 272 → **312dp**, and
the over-budget population 14 → 7 (live 8 → 5). Two lines, one file, no a11y cost
— `leadingWidth: 48` is still ≥ §13.2's target floor. There is no argument
against it and it is not a rule; it is width the product was throwing away.

> **Half of this paragraph is wrong and §2.2 says why.** `leadingWidth: 48`
> shipped. `titleSpacing: 0` did not: the spacing is *not* width the product was
> throwing away — it is the gutter that aligns a ROOT bar's title with its body,
> and Material applies it whether or not a leading exists. Shipped budget is
> **280dp**, not 312.

**② The harness fix.** Push matrix subjects as routes so the leading is drawn.
This is what makes every number in §2 a measurement.

**③ The sweep.** The gate's first red run **is** the list — the repo's own
practice, and more honest than a list written in advance. Titles are shortened as
copy, not squeezed as layout: « Préférences de notifications » reads better as
« Notifications » at *every* scale, which is the tell that these were copy smells
before they were layout defects.

**④ The one title no source edit can reach — resolved without an exception.**
`pro_journal_screen.dart:80` renders `'${auth.salonName} — votre planning'` from
unbounded salon data. It is **not** decoration: it renders only in `ownMode`,
where the source comment says it *« grounds the boundary »* — a collaborator
seeing only their own appointments needs to know whose salon (T40).

The answer is not to drop the meaning and not to clip it. **The title becomes the
fixed « Votre planning », and the salon name moves to a context line directly
under the bar**, where it can wrap, take the full width and be *read* at 200%.
That strengthens T40 rather than trading it away — a salon name clipped to
« Institut de Beauté A… » grounds no boundary — and it leaves the rule with
**zero exceptions**, which makes the rule far stronger than one carrying a
carve-out for its hardest case. The declaration mechanism in §4.1 still ships,
because a rule whose escape hatch is untested is a rule with an untested escape
hatch; it will have no live user on the day it lands, and that is recorded rather
than hidden.

## 6. Tests

What shipped, against what this section planned:

- `expectAppBarTitleWhole` + **five** proofs in `test/a11y/primitives_test.dart`,
  not three. The two extra are the ones the ancestor filter needed: a `Tab` label
  and a `ButtonStyleButton` label are both `softWrap: false` inside an `AppBar`
  and would red this helper under the wrong rule, so the filter needs a pair
  showing it excludes them *and* still catches the title beside them. The fifth
  is the finding that a **text action starves a four-letter title** — the fixture
  for the filter proof was initially built with an unrealistically long action,
  which reddened correctly for the wrong reason; splitting it produced a pinned
  fact rather than a bad fixture.
- `test/a11y/a15_harness_test.dart` — four hazard proofs for `pumpPushedAtWidth`,
  written after **both** documented hazards turned out to be mis-stated (§2.1).
- The matrix, with **13 of 16** subjects pushed as routes (§2.1 correction 3).
- `test/a11y/a15_titles_test.dart` — the corpus run, the orphan rule, and the
  four-case `clip-ok` fixture through `scanAppBarTitles` itself.
- `pro_journal_own_mode.png` — a new baseline, because the T40 boundary had never
  been photographed at all; the two existing journal goldens are salon-mode.
- **Golden churn was larger than « position », and the pictures changed the
  design** — see §2.2. 26 baselines moved; looking at them is what rejected
  `titleSpacing: 0`.
- `pro_journal_own_mode.png` is also the first baseline of own-mode at all.

## 7. Open questions

- **Does the rule bind `_TopBar`?** Scoped out above in writing; needs its own row.
- **Do the `features/` screens re-enter when the flag flips?** Yes by
  construction — recorded so the flag flip carries the cost knowingly.

## 8. What A15 does not do

- Does not touch the admin console.
- Does not make the bar taller at any scale, deliberately (§3.1).
- Does not fix `TabBar`'s own unscaled 46dp (`tabs.dart:30`, measured 48.0 at both
  scales). Real, adjacent, and a different rule — filed, not absorbed.
- Does not widen `design_system_pin_test.dart:594-624`'s scaler regex, which
  misses `withClampedTextScaling` and `TextScaler.linear(1.0)`. Noted here so the
  gap is on the record; it is a separate pin's defect.
