# A12 — a list you read is not a census (mobile)

| | |
|---|---|
| **Module** | Design system (cross-cutting) — [MODULES.md](../MODULES.md) |
| **Status** | Shipped D0→D9 (2026-07-28) |
| **Governs** | `test/a11y/` · `lib/widgets/common/label_value_row.dart` · SYSTEM.md §13.3, §21 rows 60, 62, 66, 68 |
| **Predecessor** | [mobile-a11-width.md](mobile-a11-width.md) |

## 1. Goal & scope

A11 gave §10's `compact` range a floor of 360dp and gated **nine** subjects
across `{360, 375, 390} × {1×, 2×}`. Its closing act was a census of what it had
not covered — §21 **row 68**: twelve screens plus `EmptyState` still breaking at
360 × 200%, two of them later confirmed on real devices.

A12 closes that row. But the first thing verification found changed the slice's
shape: **row 68 was assembled by reading the code, not by sweeping it**, and it
shows — four of its figures are wrong, one entry contradicts another register
row, and one names a screen no user can reach.

So the goal is not "fix twelve screens". It is **sweep for the shapes, fix
everything the sweep finds, and make the two defect classes that no assertion
could see permanently catchable.**

### Out of scope

The web surface (§21 row 54's five tab strips) and the admin console beyond the
one contradiction resolved below.

## 2. What the census got wrong

Every figure re-derived and checked against three known data points —
`layout_test.dart`'s recorded 72.2dp for « Aujourd'hui » in Roboto (cited by content, not line — the line was wrong when written and had moved again by the review), and the
device's measured 16px / 2.6px `_StatCard` overflows.

| row 68 said | measured |
|---|---|
| `_StatCard` wants **165dp** of a 126dp tile | **~141dp** including the unscaled 20dp icon. Computed at the wrong font size — `bodySmall` is 12, not 14. The 126dp tile is exact. That model predicts ~15dp over; the **gate measured 19px** at a clean 2× and the **device 16px** at ≈1.95×. The three do not subtract to each other, and that is the point of the ±10% calibration note below: the model is what corrects 165 to the right order of magnitude, and the gate is what is true |
| booking confirmation is **~190px** over | worst single row is **~123px**. No arrangement produces 190 |
| `NotificationTile`'s title crushed to **~30dp** | **~86dp** — still unreadable, but not a fix budget |
| the 80×48 slot box needs **80.4dp** at 2× | **~72dp** — it *fits* at 2× and bites at ≈2.2× |
| the admin filter is in an **unbounded** Row | the Row is **bounded** — `admin_scaffold.dart:98` is a `Container(height: 64)` whose Row holds a `Spacer()`, impossible under an unbounded axis |

### The register contradicted itself

§21 **row 66** closed the admin audit filter deliberately (✅ A11 C8, *"excluded
on purpose … §10 leaves that surface uncapped"*). **Row 68 re-opened the same
widget.** Row 66 is right on the dropdown's width and row 68 is right that
something is wrong there — the real defect is the **fixed `height: 64`**, not
the dropdown. Resolved in row 66 rather than left for the next reader.

## 3. What the sweep found

A balanced-paren walk of `lib/` for four shapes, run before any fix:

| shape | swept | row 68 named |
|---|---|---|
| `Row` with ≥2 unflexed `Text` | **20** | 9 |
| fixed `width`/`height`/`childAspectRatio` constraining text | **16** (34 raw) | 2 |
| unflexed `Text` beside an `Expanded` `Text` — the crush | **64 raw**, not statically decidable | 1 |
| `Icon(size:)` beside an unflexed `Text` | 26 raw | 3 |

**The crush shape cannot be swept statically.** A flexed label that *fits* is not
a defect, and only `didExceedMaxLines` — a runtime signal — separates the two.
That is why the census for it had to be a report-only run of the new primitive
rather than a grep, and why the primitive had to exist first.

**Final triage: 20 hits → 13 defects fixed, 7 refuted.** The seven are rating
rows (★ + « 4.8 » + « (89) », a few glyphs in a 280dp budget) and blocks the
matcher mis-attributed — `provider_card:220` is already `Flexible`.

## 4. The two new primitives

### 4.1 `expectNoLegibilityCrush` — the truncating twin

`expectNoMidWordBreak` asks whether a *wrapping* paragraph got a box narrower
than its widest word. This asks whether a *truncating* one got a box narrower
than a readable prefix. Neither can be expressed by
`expectNoUndeclaredTruncation`, which skips a declared ellipsis **by design** —
which is why `NotificationTile`'s crushed title passed every assertion the repo
had.

Two preconditions, and **the second is the whole design**: a subject must be
flexed *and* have `didExceedMaxLines`. Without the second, every framing fires
on `CommunePill` — a `Flexible` in a `mainAxisSize: min` row lays out at
`min(intrinsic, available)`, so « Cocody » is narrow and entirely correct. The
question is not "is this label narrow" but "did it spend an ellipsis on a
squeeze it did not choose".

`Expanded`/`Flexible` create **no render object**, so the flex test is a parent
walk to the first `FlexParentData` — stopping at the first, because a paragraph
inside `Expanded(Column(Row(Text)))` is *unflexed* with respect to the Row that
squeezes it.

**`kMinLegibleChars = 8`, and the two numbers either side are the justification.**
It shipped report-only first (`0` prints the table, asserts nothing) and the
width matrix produced:

| | shows |
|---|---|
| « Salon Excellence », salon page @360×2× | **0** — an ellipsis and nothing else |
| « Beauté Divine », consumer home @360×2× | **2** |
| « Salon Excellence », app bar @390×2× | **7** ← worst defect |
| « avec Kouassi Jean », review tile @360×2× | **9** ← best legitimate |
| « Rechercher un salon… » | 13 — declared, §21 row 56 |

8 is the only value strictly between 7 and 9. **That is a one-character margin,
tighter than a threshold should be**, and it is recorded rather than smoothed
over: if a future legitimate site lands on 8, re-measure and move the number —
never widen `_kWidthEpsilon`. An earlier design pass proposed 12 without
measuring, which would have reddened the review tile.

### 4.2 `expectNoVerticalClip` — §13.3's oldest unenforced sentence

*"A box that contains text may not have a fixed height"* has been in §13.3 since
A5 with no expression. One pump, and the framework's own arithmetic:

```
getMaxIntrinsicHeight(size.width) > size.height
```

**Vertical only, deliberately.** The horizontal twin is true of almost every
sentence on a 360dp phone, because wrapping is *how the layout succeeds* — the
rejected first draft `expectNoUndeclaredTruncation` records. Height has no such
escape.

Plus a **`childAspectRatio` prohibition** in `design_system_pin_test.dart`. A
prohibition needs none of the `isExpanded` pin's four guards — no non-empty
guard on its hits (after the fixes the correct count is zero), no
inferred-generic form, no lookahead window — only the corpus guard.

**Rejected, with the reason recorded:** a `width:`/`height:`-near-a-`Text`
source pin. Its true-positive rate is ~1 in 6 (avatars, dividers, images), and a
pin that gets `ds-ignore`d into meaninglessness is not a pin.

## 5. The fixes

| | defect | fix |
|---|---|---|
| `CompactAppointmentTile` | the salon name crushed to **0 characters** at 360×2× | `Wrap` — and it is the **same defect A11 C5 fixed in `ReviewTile`**, three widgets away. C5 caught that one because it *overflowed* by 21dp; this one *crushed* silently. One shape, two widgets, only the visible one fixed |
| dashboard action grid | `childAspectRatio: 1.1` froze the tile at 143.6dp forever | `IntrinsicHeight` + two `Expanded`s, plus a `minHeight` so the airy card survives, plus **single column above 1.3×** because « Disponibil / ité » breaks a control's label |
| `provider_list` grid | `childAspectRatio: 0.75` | `ProviderCard.gridHeight` — `carouselHeight`'s twin, and it needs its own constant because a grid card is *compact*: the image absorbs a shorter box, so the **text** is what cannot shrink |
| `_StatCard` header | **19px** over — an icon does not text-scale | `Wrap`. « Aujourd'hui » is one word, so `Flexible` would trade an overflow for a crush |
| `EmptyState` | **46px** vertical at 360×780×2 | `LayoutBuilder` + scroll + `ConstrainedBox(minHeight:)`, with a `!hasBoundedHeight` branch five admin screens force |
| nine money rows | up to **~150dp** over | `LabelValueRow`, a shared `Wrap` — eleven call sites by the end, the last found by the review |
| `provider_list` filter row | **122px** on device | `Flexible` at the call site — the pill's own `Flexible` never bound while it was a non-flex child |
| `service_list`, `availability` | ~36dp, ~20dp | `Wrap`, `Flexible` |
| three form dropdowns | menu items clipped to 48dp | `itemHeight: null` |
| `service_selection_screen` | routed, unreachable, broken | **deleted** — 325 lines, 0 callers |

## 6. The harness — §21 row 60 closed

`pumpForA11y` pinned nothing, so `contrast`, `label` and `tap_target` measured
`flutter_test`'s **800×600**. One edit converted three files; `feedback` and
`motion` needed per-test pins. **6 of 11 → 11 of 11.**

It found **three reds and not one was a product bug**:

- `tap_target_test` pumped the four-label pro strip with `isScrollable: false` —
  a bar `lib/` has not had since C4, and one that *overflows* at 360. A
  guideline asserted against a layout that cannot render is not a measurement.
- `motion_test` tapped `Offset(700, 400)` for "the right 65%" of an 800dp
  surface. At 360 that is off-screen: the tap landed on nothing and two
  assertions read 0.0 pages.

`kFloorPhone = Size(360, 780)` is new and separate: 780 not 800 because both
were measured on hardware and 780 is the stricter. **`pumpAtWidth`'s 1600 height
is untouched** — that height is why horizontal overflows are reportable at all.

## 7. Where the instruments were wrong

Recorded because the slice's own lesson is that an unverified claim is worth
less than a measured one, and three of these were mine.

- **`_prefixWidth` measured a single line.** Right for the `maxLines: 1` crush,
  wrong for the salon header's `maxLines: 2`, which shows ~14 characters across
  two and was reported as 7. A false positive that would have driven a fix into
  a label that was fine. `_prefixFits` now lays the prefix out the way the
  framework does.
- **`_isPainted` took three attempts.** `tester.allRenderObjects` walks
  everything *laid out*, and layout is not visibility: `DropdownButton` builds
  every item into an `IndexedStack`. Walking for `RenderIndexedStack` finds
  nothing (the marker is a `Visibility` one level down); `RenderObject.paintsChild`
  finds nothing (it is not overridden by `_RenderVisibility`); the answer is
  both, plus an **element** walk, because the render object's `debugCreator`
  names the private `_Visibility` and never the public widget.
- **The `EmptyState` gate took three surfaces.** The component at `kFloorPhone`
  is green; the *screen* at `kFloorPhone` is green; only the screen **with the
  device's safe-area insets** — 50pt status bar, 34pt home indicator — is red.
  780pt is the screen; the body is 84dp less.
- **The `itemHeight` red was a false positive**, and the fix stands on
  `dropdown.dart:218` and §13.3 rather than on that red. Stated because the
  difference matters: the menu has not been opened in a test.

## 8. Testing plan

`test/a11y/` is now **14 `*_test.dart` files** (plus three shared `_`-prefixed
helpers). Eleven of the fourteen pin a phone — §21 row 60's target, and what
§9's DoD line counts. The three that do not are the ones that must not:
`content_width_test.dart` pins 1024 and 1200 **because the cap it tests is
about wide surfaces**, and pinning it to a phone would delete the test. A12's
first draft of this section said "14 files, all pinning a phone", which was two
claims welded into one wrong one. New: `primitives_test.dart`
(the gate's own gates — six subjects built to break each primitive and to be
ignored by it), `vertical_fit_test.dart` (the fold), `label_value_row_test.dart`
(42 tests over the real money pairs).

Every fix mutation-proven. The instruments too — that is what `primitives_test`
is for: everywhere else these helpers run across the width matrix where green is
the right answer and a useless one, and §21 row 67 records six unfailable gates
shipped in a single commit.

## 9. Definition of done

- [x] the sweep run and **every hit triaged** — 20 → 13 fixed, 7 refuted
- [x] both new primitives, calibrated from measurement and self-tested
- [x] all **11** `test/a11y/` files pin a phone (§21 row 60 closed)
- [x] the dead screen deleted
- [x] row 68's four wrong figures corrected; the row 66 contradiction resolved
- [x] goldens only where the fix is invisible at 390×1× — **1 added, 3 moved**,
      every changed PNG eye-reviewed, ledger from `git diff --name-status`
- [x] adversarial review, every finding hand-verified
- [x] the device re-run — the pro app on a 360×780pt iPhone at `accessibility-large` (≈1.95×), after the fixes

## 10. The device run

A11's lesson is that a device finds what the gates cannot, so the fixes were
re-driven on the surface that produced the original evidence: the pro app on a
360×780pt iPhone at `accessibility-large` (≈1.95×, the contract point).

| | before A12 | after |
|---|---|---|
| `_StatCard` « Aujourd'hui » + calendar icon | **16px** over, striped banner | icon wrapped below the label, **no banner** |
| `_StatCard` « En attente » + dot | **2.6px** over | **no banner** |
| the action grid | « Disponibil / ité », a control's label broken mid-word | **single column**, full width, « Disponibilité » whole on one line |
| the salon list filter row | **122px** over | the pill truncates, « 2 salons » sits at the edge, **no banner** |

No overflow banner appears anywhere on the dashboard or the salon list at the
contract point.

### And it found what the gates could not — twice, in the same widget

The consumer half of the run opened the salon grid, which **A12 had already
fixed**, and it was worse than before:

> « BOTTOM OVERFLOWED BY 55 PIXELS », both cards.

**No test in the repo could have seen it.** `_isGrid` starts `false`, so the
salon-list subject — and every other test — measured the *list* branch: A12's
grid fix was never once executed by an assertion. That is the A11 lesson
arriving one layer in, and it is why the gate now taps the toggle and asserts a
`GridView` is on screen before it measures anything.

The cause was **two formulas in one file that disagreed**:

```
gridHeight       = 142 + 68 × scale     ← derived from the COMPACT image floor
_buildGridCard   : compact = maxH < 260 ← a raw dp threshold
```

They cross at **≈1.74×**. Above that the card drew the 180dp *roomy* image
inside a box measured for the 110dp *compact* one. `compact` is now
`maxH < carouselHeight(context)` — the roomy layout's own height — so the two
cannot disagree by construction, and the compact image takes what is **left**
after the text rather than `maxH × 0.56`, which was the same
derive-from-something-that-does-not-scale mistake one level down.

Fixing the height exposed a second, real defect underneath, which the device had
also shown and which `expectNoLegibilityCrush` then reproduced: at 360dp a
two-column cell gives the salon's **name** 140dp, and that holds 8 characters
only to **1.90×** — just under the ≈1.95× contract point, which is why the
device read « Salon … » and « Barber… ». The crossing moves with the width
(375dp holds to 2.00×, 390dp past it), so the rule is about the **cell**, not
the text scale — a scale threshold would be wrong at two of §10's three widths.
`ProviderCard.minGridCellWidth`, and one column below it.

| the salon grid | before | after |
|---|---|---|
| card height | **55px** over, both cards | fits |
| the salon's name | « Salon … » — 3 characters | « Salon Excellence », whole, one column |

**The third instrument that was wrong before it was right.** `text_scale_test`
already had a test guarding this exact class — `carouselHeight never trips the
compact branch` — and it asserted `bound >= 260`, a *proxy* for the threshold.
The proxy is what let this through: it guarded the bound dipping **below** 260
at 0.85× and said nothing about a smaller bound crossing it going **up**. It now
asserts the thing itself, the image the card actually drew.

### What the run found that A12 does not own

Two things, recorded rather than absorbed, because both are decisions and not
patches:

- **Flutter's own date picker cannot show a date at 200%** — §21 row 73. On the
  booking flow at ≈1.95× the calendar renders « 2 21 2 2 2 2 2 » where 20–26
  should be. Not our widget, not our theme, and **more width is not available**
  (Material caps the dialog near 328dp; seven columns of ~46dp cannot hold two
  digits at that scale), so §13.3's standing fix does not apply. An input-mode
  fallback or a bespoke picker is a UX decision, and the standing rule is that
  those get signed off before they get built.
- **The booking hub's pinned summary takes ~2/3 of the viewport at ≈1.95×**,
  leaving a ~185dp scroll window for the four steps. It scrolls and nothing
  overflows, so no rule is broken — but the flow is tight enough to be worth a
  look on its own terms.

And one correction the device **confirmed**: §21 row 68 claimed the reschedule
picker's 80×48 slot box needed 80.4dp at 2×. A12 re-derived it at ~72dp and said
it *fits*. On the device at ≈1.95× the chips — « 09:00 » through « 11:30 » —
render whole, three to a row, with room to spare.

## 11. Open

- **Two screens are fixed but not gated.** Booking confirmation and the booking
  hub carry four of the money rows; both need a booking in progress to reach, so
  `LabelValueRow` is gated as a component. That proves the widget, not the
  wiring.
- **§21 row 62's two mid-word headings.** A12 found that « Prom/o W… » is a
  `Container(width: 92)` in `announcement_stories.dart` — a *fixed-width box*,
  not a design decision. « Salon Ex/cellence » remains a genuine one.
- **The §5 pin cannot see `crossAxisSpacing: 12`** — its `\b` cannot fire inside
  the compound name. Two raw literals were fixed here in passing; the pin gap
  is its own row.
