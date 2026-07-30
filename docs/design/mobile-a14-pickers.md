# A14 — our own date & time pickers

| | |
|---|---|
| **Status** | A14a built · **A14b in build** · A14c, A14d planned |
| **Owner** | Sadreddine Daher |
| **Last updated** | 2026-07-29 |
| **Register row** | [SYSTEM.md](SYSTEM.md) §21 row 73 (A14a) · **row 77 (A14b)** · row 75 (A14c) · row 76 (A14d) |
| **Skills checked** | `myweli-dev-guardrails` |
| **Preceded by** | [A12 — the fixed-box sweep](mobile-a12-fixed-boxes.md) · [A13 — copy & breaks](mobile-a13-copy-and-breaks.md) |
| **Scope** | **A14a** — the date picker (§1–§7) · **A14b** (this PR) — the time picker family (§8–§14) · **A14c** — retire `table_calendar` · **A14d** — the per-salon booking horizon |

---

## 1. Goal & scope

**Row 73, verbatim on the part that matters** (see §2.2 for the one claim in it that does not hold): *"at `accessibility-large`
(≈1.95×) on a 360×780pt iPhone, Material's `showDatePicker` calendar renders
**20, 22, 23, 24, 25, 26 as a single digit** — « 2 21 2 2 2 2 2 ». Only 21
survives, because « 1 » is narrow."*

Found on hardware during A12's device run. **Row 73 is mostly accurate** — its
day list, its arithmetic and its five call sites all check out, which is unusual
enough in this register to say out loud. Its *exoneration of our theme* does
not: see §2.2.

**In scope for A14a:** a house date picker that is correct across §10's compact
range at 1× and 2×, gated before it is built, and all five `showDatePicker` call
sites converted.

**Deliberately in scope for A14 overall** (the user's instruction was *"do what
is better for the long term so we don't need to come back to it"*): the six
`showTimePicker` sites and the three `table_calendar` sites, in A14b and A14c.
Leaving either is coming back.

### 1.1 One claim this spec must not make

An exploration agent reported §21 **row 29** as a *live* defect —
`DefaultMaterialLocalizations.parseCompactDate` reading `07/01/2026` as 1 July.
**That is wrong: row 29 is closed (✅ A9).** `french_test.dart:106` asserts
`picked == DateTime(2026, 1, 7)` — the correct French reading — because A9 wired
`GlobalMaterialLocalizations`. So *"input mode mis-parses French dates"* is
**not** a justification for this slice and appears nowhere in it. Row 73 stands
on its own.

---

## 2. Why the obvious framing is wrong

Row 73 says *"more width is not available"*, and the natural reading is that a
full-screen page fixes it. **It does not, or barely.**

| container | width per column at 360dp |
|---|---|
| Material's dialog (row 73's measurement) | ~46dp (dialog capped near 328) |
| `table_calendar` | ~39dp (after `cellMargin: EdgeInsets.all(6.0)`) |
| **our full-screen page** | **~46.9dp** (360 − 2×`spacingM`, ÷ 7) |

Seven columns of a 360dp screen is seven columns of a 360dp screen. **What buys
the fit is owning the cell's internals**, because Material spends its ~46dp on a
fixed circular indicator and its own insets before the glyph gets any.

### 2.1 The measured crossing — and why the day cell must not be a circle

The house already solved this for the week strip. `_WeekStrip._dayPill`
(`pro_journal_screen.dart:571-580`):

```dart
// A tight 32×32 around the day number clipped it at 200% (the bodyMedium line
// is 20 at 1× but 40 at 2×). The pill is a CIRCLE, so it has to stay square:
// diameter = the scaled line + breathing room, floored at the 32 the design
// draws at 1× (§13.3).
const style = AppTextStyles.bodyMedium;              // 14 × (20/14) = line 20.0
final d0 = math.max(32.0, scale(line) + AppTheme.spacingS);
```

At 2× that is `max(32, 40 + 8)` = **48.0dp**. Against **46.9dp** of column.

**A circular day cell does not fit a 360dp screen at 2×** — it misses by ~1.1dp.
That is the whole design constraint, and it is arithmetic rather than taste:

- **the cell is a rounded rectangle, not a circle.** Width = the column (46.9dp),
  height = `max(48, scaledLine + spacingS)`. The selection indicator fills the
  cell instead of being a square inscribed in it.
- **two digits fit the width.** The day is drawn at `bodyLarge` — the same size
  Material uses (§2.2) — so at 2× the gate's own measurement applies: **36.9dp**
  of glyph inside the **38.86dp** the cell leaves after its 8dp margin. Two dp of
  slack, which is why the margin is `spacingXS` and not `spacingS`.

So the month grid is expected to **survive** at 360 × 2×. The list reflow stays
specified because §3's measurement, not this arithmetic, decides.

### 2.2 Row 73's one claim that does not hold

Row 73 says the defect *"is not our widget and not our theme"* because
`AppTheme.datePickerTheme` *"never sets a `dayStyle`"*. The description is
accurate; the **implication is false**. `calendar_date_picker.dart:1174` reads
`datePickerTheme.dayStyle ?? defaults.dayStyle`, so `dayStyle` **is** reachable,
and one line in `AppTheme` would have cleared the 1.5dp.

It would have cleared it **by shrinking the day number** — M3's default is
`bodyLarge` (16sp, `date_picker_theme.dart:1315`), which is exactly why « 20 »
needed 36.9dp. So the only theme-level fix is a smaller font: the one remedy
§13.3 forbids in terms, and the one row 73's own sentence rules out.

**A14a's first draft took that forbidden route by accident.** It drew the day at
`bodyMedium` (14sp) while crediting geometry, making the dominant term of the
"fix" a 12.5% reduction of the day number at every scale — inside an
accessibility slice. The review caught it; the cell uses `bodyLarge` now, the
same size Material used, and still fits (36.9 needed, 38.86 available).

### 2.3 The gate's first run — measured, and tighter than row 73 records

Written against Material's own picker and run before anything was built:

```
the day « 20 » has 35.4dp and needs 36.9 at 360dp × 2× text
  — it renders clipped, which is §21 row 73
```

**5 passed, 1 failed.** Three findings the row does not contain:

- **The defect is 1.5dp.** Not a rout — a hair. Which is why owning the cell's
  internals is the whole fix, and why a circle (which needs ~1.1dp more than the
  column has) is the difference between working and not.
- **It is 360-only at 2×.** 375 × 2× and 390 × 2× both pass. Row 73's *"Material
  caps the dialog near 328dp, seven columns of ~46dp"* reads as universal
  arithmetic; measured, the paragraph gets **35.4dp at 360** and enough above it.
  The cap is not the whole story — the dialog is also screen-relative.
- **1× is clean at every width**, so this is purely a scale defect and the 1×
  goldens should not move.

Row 73 was found on *"a 360×780pt iPhone"*, and 360 is exactly where this fires.
That is the register being right about the device it was found on, and slightly
loose about the mechanism.

### 2.4 The tap-target floor is unreachable horizontally, and that is not new

§13.2 requires ≥48×48. **Seven 48dp targets need 336dp plus padding — more than
a 360dp screen has.** No 7-column month grid on any phone can satisfy the floor
in both axes.

Both surfaces already accept this and record it rather than hiding it:

- `_WeekStrip` (`pro_journal_screen.dart:556-557`): *"A fixed `minWidth: 48` × 7
  overflowed narrow phones"* — solved with `Expanded` + `HitTestBehavior.opaque`,
  so the **slot** is the target.
- WEB-SYSTEM §15 row 7h on `MonthCalendar`: *"height floored at 48, width
  grid-bound (~43 at 375px) — recorded, not hidden."*

A14 takes the same trade, by the same reasoning, and says so here rather than
letting a reader discover it: **height floored at 48, width grid-bound, the whole
cell tappable.**

---

## 3. The gate, and why two pieces of it do not exist yet

**Gate-first: the assertion is written and watched fail before the widget.**

Two gaps make this more than adding a subject:

1. **No test anywhere drives a route-based dialog at a pinned width and text
   scale.** All 14 callers of `pumpAtWidth`/`pumpAtTextScale` pump a `home:`
   screen or an inline component. The nearest precedents are
   `feedback_test.dart:81-101` (host-behind-a-button, `pinSurface` + `wrapApp`)
   and `components_feedback_a6_golden_test.dart:25-44` (`addPostFrameCallback`
   to open with no tap — the right shape when the dialog *is* the subject).
2. **No assertion in the repo can see a missing digit.** `expectNoMidWordBreak`
   is the wrong instrument — a day is one token, not a wrapped word, and the
   defect is a clipped glyph rather than a break.

So A14a adds `expectTokensWhole` (working name), and — because §21 **row 67**
records **six helpers that shipped unable to fail** — it is proven falsifiable in
`primitives_test.dart` against a subject built to break it, exactly as every
other primitive is.

**Two mechanical hazards, stated because they would produce a green gate that
measures nothing:**

- `pumpAtWidth` defaults to a **1600dp-tall** surface. A dialog in a 1600dp
  viewport can never clip vertically. The subject pins `kFloorPhone`
  (`Size(360, 780)`, `support/surface.dart:60`).
- `pumpAtWidth` ends in `settleMocks`, not `pumpAndSettle`. The route needs its
  own `pump()` + `pump(400ms)` **after** the open, not the settle inside the pump.

The matrix loops stay **outside** `testWidgets` — `layout_test.dart:74-93`
measured that `_overflowReportNeeded` latches, so a width loop inside one test
silently skips every width after the first. *"Do not collapse it."*

Assertion order follows the file's own template: **C** (the calendar rendered) →
by-name → `expectNoUndeclaredTruncation` → `expectNoLegibilityCrush` →
`expectNoVerticalClip` → `takeException` last.

---

## 4. The five flows — UX before the widget

All five call sites pass **exactly four arguments** (`context`, `initialDate`,
`firstDate`, `lastDate`). No predicate, no builder, no localised strings — so
there is nothing per-site to preserve, but the house widget must supply every
string Material was giving us for free.

| # | site | the user's job | required? | after the date |
|---|---|---|---|---|
| 1 | `booking_hub_screen.dart:744` | pick the day of my appointment | **required to finish**, but pre-seeded to today so the flow works untouched | **step 1 of 2** — sets `_selectedDate` and re-queries slots; the booking's datetime is only set when a *time chip* is tapped |
| 2 | `pro_journal_screen.dart:119` | jump the journal to a date | **optional** — the chevrons and week strip do the same job | `journal.setDate(...)` → reloads the day |
| 3 | `pro_journal_screen.dart:419` | reschedule an appointment | **required, and it is a wizard** — chains straight into `showTimePicker` | composes a salon datetime, calls `reschedule`; failure is « Créneau indisponible. » |
| 4 | `pro_manual_booking_screen.dart:113` | take a walk-in booking | **required form field** | sets half of `_dateTime`; `_submit` blocks with field-level messages, never a snackbar (§14) |
| 5 | `availability_screen.dart:251` | close the salon for a day | **optional, repeated** | **writes to the server immediately, no confirmation** |

**Four observations that shape the widget:**

- **#5 always opens on today** (`initialDate == firstDate == today`) and the user
  is nearly always navigating *away* from it. Month-to-month navigation matters
  most here, and blocking a week currently costs five separate dialogs.
- **#3 is the only site where the picker is the entry to a modal sequence.** A14a
  keeps the chain; A14b collapses it.
- **#4's error « Choisissez une date et une heure à venir. » exists only because
  the time picker has no past-time constraint** — today plus an earlier hour
  lands there. A combined picker in A14b deletes the error state rather than
  restyling it.
- Dismissal is a silent no-op at every site. That stays: a cancelled picker
  should change nothing and say nothing.

### 4.1 The horizons are inline literals, and they disagree

| site | horizon | in code |
|---|---|---|
| booking hub | **365 days** | inline `Duration(days: 365)` |
| journal reschedule | **365 days** | inline |
| availability | **365 days** | inline |
| manual booking | **90 days** | inline |
| journal jump | **`DateTime.utc(2024)` .. `utc(2030)`** | two magic literals, the only past-facing range |
| *(consumer `date_time_selection_screen`, `TableCalendar`)* | **90 days** | inline |

There is **no named constant anywhere**, and **no server-side bookable-horizon
rule at all** — the only `90` in `backend/` is `kProTrialDays`, unrelated. A14a
names them at the call sites it touches and records that the consumer funnel
currently offers **365 days on one screen and 90 on another for the same job**.

### 4.2 States & copy

Loading is not a state here (the calendar is synchronous). The four that exist:

- **empty** — a month with no selectable day inside `firstDate..lastDate`. The
  month still renders, every day disabled, and navigation to a month with
  selectable days stays available.
- **error** — none; the picker cannot fail. Errors belong to the flow that
  consumes the date (§14: field-anchored, never a toast).
- **success** — pops with the `DateTime`.
- **dismissed** — pops with `null`; every call site treats that as "change
  nothing".

Copy: the header is `Formatters.formatMonthYear` (already French,
`formatters.dart:104`). Weekday abbreviations need a new `Formatters` helper —
**`salon_time_pin_test.dart:64-78` forbids `DateFormat(` outside
`formatters.dart`**, so the calendar cannot build one itself. Confirm/cancel copy
follows §16's microcopy rules and is stated at implementation.

---

## 5. What the pins forbid, and how the widget answers

| pin | the natural thing it bans | what A14 does instead |
|---|---|---|
| **`childAspectRatio` — prohibited outright, no allowlist** (`design_system_pin_test.dart:517-555`): *"a tile height derived from its WIDTH cannot grow with the text inside it"* | the obvious way to make square day cells | **no `GridView` at all** — a `Column` of `Row`s of `Expanded`, the shape `_WeekStrip` reached for the same 7-across problem. (This cell said `mainAxisExtent` until the review noticed the spec was describing a design that was never shipped.) |
| numeric `crossAxisSpacing`/`mainAxisSpacing` (`:195`) | `crossAxisSpacing: 4` | `AppTheme.spacing*` |
| numeric `EdgeInsets` (`:219`), `BorderRadius.circular(N)` (`:229`), `fontSize:` (`:237`), icon `size:` (`:246`) | every one of them is on the path of least resistance for a calendar | tokens only |
| `Duration(milliseconds:)` / `Curves.` (`:318`, `:328`) | a month-slide transition | `AppMotion.*` |
| `(s)` plurals (`:667`), `'...'` (`:615`), `\'` (`:624`) | « 1 jour(s) » | `Formatters.count`, `…`, `’` |
| no `DateFormat(` outside `formatters.dart` (`salon_time_pin_test.dart:64-78`) | building weekday labels in the widget | a `Formatters` helper |
| no `DateTime.now()` outside the allowlist (`:139-160`) | "today" | `salonToday(tz:)` — the picker is **salon time**, never the device's |

---

## 6. Testing plan

- **a11y** — the new route-dialog subject at `{360, 375, 390} × {1×, 2×}`, one
  `testWidgets` per combination, on `kFloorPhone`.
- **primitives** — `expectTokensWhole` proven falsifiable, per row 67.
- **golden** — the **first picker golden in the repo**, at 1× and 2×. Regenerated
  with `./tool/update_goldens.sh` (Linux-only — a Mac-authored golden fails CI
  forever), ledger from `git status --short`, **every changed PNG opened**.
- **unit** — `weekdayInitials()` is tested in
  `test/widget/myweli_date_picker_test.dart`, along with the picker's *behaviour*:
  tapping a day returns that day, dismissing returns null, a disabled day is
  inert, an out-of-range `initialDate` clamps, and the year list jumps a year in
  two taps. **`Formatters.formatDate`/`formatDateShort` still have no test** —
  the spec promised them and A14a did not deliver, so it is recorded rather than
  quietly dropped.
- **device** — `accessibility-large` on the simulator that found row 73. A
  computed gate is not the same evidence as the screenshot the row is about.

### 6.1 The device run — row 73, closed where it was opened

Same device (`A11 360dp`, iPhone 13 mini, 360×780pt), same setting
(`content_size accessibility-large`, ≈1.95×), same route: home → Beauté Divine →
« Réserver » → « Date et heure » → the date row.

| | |
|---|---|
| row 73 recorded | « 2 21 2 2 2 2 2 » — only 21 survived, because « 1 » is narrow |
| measured after A14a | **20 21 22 23 24 25 26** |

Every day number whole and legible. Also confirmed on the same screen, none of
which a computed gate asserts: « juillet 2026 » in French, the weekday row
Monday-first, days before today correctly disabled, the left chevron disabled at
the range start, and the selected day a filled rounded rectangle rather than a
circle — the shape the 1.5dp bought.

Worth recording as a second observation from the same run: the salon page's
header renders **stacked** at 1.95×, which is A13's row 62 fix holding on
hardware. That was gated but never re-photographed on a device.

**One more hole this slice stands on, and A14a did NOT close it:** the
booking-hub subject in `layout_test.dart` — the screen the picker launches from
— is one of the subjects missing `expectNoVerticalClip`. The spec claimed A14a
adds it; the review found `layout_test.dart` is not in the diff at all. Left
open, said so. **A14b closes it — and the count in this paragraph was wrong.**
It said *four*; counting `testWidgets(` against `expectNoVerticalClip` in file
order gives **five of fifteen** (§13).

---

## 7. Open questions

- ~~Does `_WeekStrip` itself overflow at 360 × 2×?~~ **No, and the question's
  premise was wrong.** The strip pads by `spacingS` (8), not `spacingM`, so its
  slot is (360 − 16)/7 = **49.14dp** and the 48dp pill fits with 1.1dp to spare.
  The 46.9 belongs to *this* picker's grid. An open question that a two-line read
  closes should not have shipped as one.
- Multi-select for `availability` (blocking a week is five dialogs today) — a
  product question, deliberately out of A14a.

---
---

# Part B — A14b, the time picker family

## 8. Goal & scope

**Six `showTimePicker` sites, and three flows that ask the user to answer two
modals in a row.** A14b replaces Material's time dialog with a house family, and
in doing so deletes three error states that exist only because Material's picker
cannot express a constraint.

There is **no register row for the time picker**. Row 73 is the date picker and
is closed; row 68 mentions *"the reschedule time picker's hard `80×48` box"* but
that is **our own slot chip, not Material's dialog**, and row 68's figure was
already corrected once in A12 (it fits at 2×, bites at ≈2.2×). **Do not cite row
68 as prior art for A14b.** A14b opens its own row.

### 8.1 The claim this section must not make

A14a's case was *"Material clips a digit by 1.5dp."* **A14b's case is not that,
and borrowing the framing would be false.** Material's time picker does not clip.
It does four other things, each verified below against Flutter 3.38.6 source.
Write it as its own defect or the review will catch the borrowed sentence.

---

## 9. What Material's time picker actually does at 200%

All four measured in
`/Users/sadreddinedaher/development/flutter/packages/flutter/lib/src/material/time_picker.dart`.

### 9.1 It refuses to scale its primary content — as a literal

```dart
// time_picker.dart:387 — the hour and the minute
child: Text(text, style: effectiveStyle, textScaler: TextScaler.noScaling),
```

Also `:528` (the `:` separator) and `:2263` (`MediaQuery.withNoTextScaling`, the
input mode). In dial mode M3's `hourMinuteTextStyle` is `displayLarge`, which in
this app is **57sp on a 64dp line** (`text_styles.dart:6-11`, wired at
`app_theme.dart:203`), inside a hard-coded 80dp box.

**64dp in 80dp fits at 1×, and fits identically at 200%, because it never grows.**
The biggest text in the dialog is the one text the user's setting cannot touch.
That is not a clip; it is worse. A clip is visible.

### 9.2 It caps its own container at 1.1×, and says why

```dart
// time_picker.dart:2544-2552 — Flutter's own comment, verbatim
// parts of the time picker scale up with textScaleFactor, we cap the factor
// to 1.1 as that provides enough space to reasonably fit all the content.
final double textScaleFactor =
    MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.1).scale(...)
```

`:2589` applies it to **height only**; in portrait the width stays `310`, a
literal, at every scale.

### 9.3 The dial's numbers scale to 2× inside a ring geometry that does not

The dial labels get `clamp(maxScaleFactor: 2.0)` (`:1515`) — they *do* grow. The
rings they sit on do not:

```dart
// time_picker.dart:49,51 — both const, both unreachable from any theme
const double _kTimePickerInnerDialOffset = 28;
const double _kTimePickerDialPadding = 28;
```

`_DialPainter.paint` (`:1050-1059`) computes `labelRadius = dialRadius − 28` and
`innerLabelRadius = labelRadius − 28`, so the 24-hour double ring has its two
label centres a fixed **28dp apart**. `dialTextStyle` is `_textTheme.bodyLarge!`
(`:3775-3777`) = our `AppTextStyles.bodyLarge` = 16sp on a **24dp line**
(`text_styles.dart:72-77`, wired at `app_theme.dart:212`). At 2× that is a
**48dp line box**, and labels are painted **centred on the ring point**
(`:1082`). Along the radius, two 48dp boxes 28dp apart overlap by **20dp** — at
12 and 6 o'clock, where the radius is vertical.

#### ⚠️ Two earlier drafts of this overstated it, and both were caught

- *"the rings overlap by 20dp **at every clock position**"* treats a **radial**
  constant as though it were vertical everywhere. Away from the vertical the
  governing dimension is the label's **width**, not its line height: at 3 and 9
  o'clock the outer label is one digit and the inner is two, so their half-widths
  sum to roughly 27 against 28dp of separation and the boxes do **not** meet.
- *"the painted ink overlaps by nearer 4dp"* read a 32sp font size as 32dp of
  ink. A Roboto digit's cap height is ≈0.71 em ≈ 22.7dp at 32sp, which yields no
  ink overlap even at 12 o'clock. **Whether the glyphs actually touch was never
  measured**, and the estimate should not have been written as if it had been.

What *is* derivable from the two constants and the one style is enough, and it is
the honest version: **the dial reserves 28dp of radial room for text that
occupies a 48dp line box.** Flutter's own 1.1× container cap (§9.2) exists for
precisely that class of problem, and §9.4 is why nothing here can measure the
result either way.

### 9.4 No assertion in this repo can fail on any of it

The dial is a `CustomPaint` (`:1702`) driven by `_DialPainter` (`:1000`), inside
`GestureDetector(excludeFromSemantics: true)` (`:1697`) and `ExcludeSemantics`
(`:3041`).

Every helper in `test/a11y/_a11y.dart` — `expectNoVerticalClip`,
`expectNoUndeclaredTruncation`, `expectNoLegibilityCrush`, A14a's own
`expectTokensWhole` — walks `tester.allRenderObjects.whereType<RenderParagraph>()`.
**The dial contains zero `RenderParagraph`s and zero semantics nodes.**

A gate pointed at `showTimePicker` reports green unconditionally. This is the
structural reason A14b cannot be *"measure it, then decide"* the way A14a was:
there is nothing to measure through. §12 says what replaces that.

### 9.5 The theme cannot reach any of it

A14a's honest phrasing for `dayStyle` was *"reachable only by doing the forbidden
thing"* — the theme could fix the clip, but only by shrinking the font §13.3
protects. **The time picker is worse in both directions:**

| | reachable from `TimePickerThemeData`? |
|---|---|
| `hourMinuteSize` `Size(96,80)`, `dialSize` `Size.square(256)`, `dotRadius`, `handWidth` | **No.** They are abstract getters on the private `_TimePickerDefaults` (`:3310`, `:3347`, `:3373`). `grep -c 'dialSize\|hourMinuteSize' time_picker_theme.dart` → **0**. |
| `hourMinuteTextStyle` | Reachable (`:372-375`) — **and useless.** `TextScaler.noScaling` at `:387` is a literal, so the field cannot be made to respond to the user's setting at any font size. |
| `dialTextStyle` | Reachable (`:1622`) and it does scale — but shrinking it to stop the overprint is the §13.3-forbidden remedy, and the radii it must fit are private. |

So: you can shrink the font, and you can never grow the box. `AppTheme.timePickerTheme` **set** three of twenty-three fields —
`backgroundColor`, `elevation`, `shape` — and none of the typography, so
everything above is what the app shipped right up until this slice. §13 debt 4
deletes the block: with zero Material pickers left in `lib/`, `app_theme.dart:525`
now carries only a note saying both picker themes were there and why they went.

---

## 10. The six sites and the three chains — UX before the widget

Six syntactic call sites. `WeeklyHoursEditor` holds **two** of them and is
mounted from **two** screens (`availability_screen.dart:114` for breaks,
`artist_form_screen.dart:253` for artist hours), so the reachable
(site, route) pairs are `4 + 2×2 = **8**`, spread over **five** routes. An
earlier draft said *"seven (widget, route) pairs"*, which is what you get by
adding one for the extra mount and forgetting the widget contains two sites.

| # | site | the user's job | required? | cancel behaviour today |
|---|---|---|---|---|
| 1 | `pro_journal_screen.dart:433` | reschedule — **chain A**, after the date | required | **destroys the date already chosen**, silently |
| 2 | `pro_manual_booking_screen.dart:126` | a walk-in's time | required to submit, **not sequenced** — two independent, re-editable fields | true no-op; the previous `_time` survives. Best of the six. |
| 3–4 | `availability_screen.dart:633`, `:640` | a working slot's start, then end — **chain B** | both required | cancelling the end discards the start; on *edit*, indistinguishable from doing nothing |
| 5–6 | `weekly_hours_editor.dart:61`, `:68` | a day's hours (or a break) — **chain C** | the day is optional; once editing, both required | same, plus `:74` omits the `context.mounted` guard `:67` has |

Sites 5–6 are the **only picker calls in the app that pass a localised string** —
`helpText: 'Heure de début'` / `'Heure de fin'`. `myweli_date_picker.dart:112-114`
already records that the house API keeps that affordance; here it becomes
load-bearing, because in chain B the two dialogs carry **no** `helpText` and are
therefore visually identical with nothing on screen saying which one you are in.

### 10.1 Error states that exist only because the picker is blind

Each is a round-trip or a message standing in for a constraint the control could
have expressed. Where the constraint can be expressed, A14b makes the invalid
state **unreachable** rather than restyling the message.

| where | what it says | outcome |
|---|---|---|
| `weekly_hours_editor.dart:75` | **nothing** — `if (end <= start) return;`, a bare silent `return`. Two modals, then the row simply does not change: an invalid answer indistinguishable from a cancel. | **Deleted.** The range picker will not offer an end at or before the start. The highest-value deletion in A14b. |
| `availability_screen.dart:673-681` | « L'heure de fin doit être après l'heure de début » + a snackbar, losing both answers, because dialog 2 could not be given a lower bound of `pickedStart` | **Deleted**, same constraint. |
| `pro_manual_booking_screen.dart:142-149` | « Choisissez une date et une heure à venir. » | **Kept, and demoted** — see below. |

#### ⚠️ The third one does not die, and this spec said it would

Every earlier draft of §8–§13 — and A14a's §4 before it — said A14b *"deletes the
error state rather than restyling it"*. **That is wrong, and it was wrong for a
reason worth keeping.**

`minTime` does close every path a *tap* can take: the time picker floors at the
salon's now when the chosen day is today, and `_pickDate` re-applies the floor
when the day changes, which covers the other fill order (these are two
independent fields, not a chain — site 2 is the one site of the six where either
may be filled first).

But **the wall clock moves while the form is open.** Pick today at 14:05 at
14:00, take five minutes over the phone number, submit at 14:10 — and
`dt.isBefore(AppClock.now())` is true. A guard that is nearly unreachable is
still reachable, and deleting it would have traded a rare field-level message
for a server round-trip.

So the count is **two deleted, one demoted to a drift backstop** with its comment
rewritten to say which it is. The original comment claimed it was reachable
*"because the time picker has no past-time constraint"*; that clause is now
false, and leaving it would have been a second wrong claim replacing the first.

**A fourth message is not touched at all.**
`pro_manual_booking_screen.dart:138-141`'s « Choisissez une date et une heure. »
guards two independent *optional* fields. It is a real empty-field validation,
not a blindness artefact.

### 10.2 What must survive the conversion

- **§18.** `availability_screen.dart:651-669`'s `salonDateTime` recombination is
  an A10 sweep miss that was already fixed once, with an in-source note saying
  *"The pin cannot see this: there is no clock token here."* A14b must not
  reintroduce `DateTime(y, m, d, h, m)` on that path.
- **One `onChanged`, on confirm only.** `WeeklyHoursEditor` is a
  `StatelessWidget` that calls `onChanged` exactly once, on success
  (`:76`). `availability_screen.dart:114` wires that straight to
  `provider.updateAvailability` — **a server write**. A control that emitted per
  edit would write per keystroke.
- **`defaultStart`/`defaultEnd`/`offLabel` stay on the editor**, not the picker:
  the two callers differ (`12:00`/`13:00`/« Aucune » for breaks,
  `09:00`/`17:00`/« Repos » for hours).
- **24-hour, `HH:mm`.** `french_test.dart:159-173` asserts fr resolves to
  `TimeOfDayFormat.HH_colon_mm`, so no AM/PM control is built. A house widget
  inherits nothing from `MaterialLocalizations`, so that guarantee must be
  re-established in our own code — see §13.

---

## 11. The three controls

The chains are three different shapes, so one control would be one shape forced
onto three flows. Chain A is date→time; chain B and C are **time ranges with no
date at all**; site 2 is two independent fields. Hence a family.

### 11.1 `MyweliTimePicker` → `Future<TimeOfDay?>`

The leaf, replacing all six sites. A full-screen route, mirroring
`showMyweliDatePicker`'s shape (`myweli_date_picker.dart:61-86`), with
`MyweliTimePickerScreen` **public so tests can pump it without a navigator** —
the thing that makes `date_picker_test.dart` and its golden possible.

- **Two scrollable columns**, Heures (00–23) and Minutes (`minuteStep`, default
  5). Each entry is a **text row**, so its height comes from the text and grows
  with the scale — the opposite of a 96×80 box and a fixed-radius ring. Height
  uses `_cellHeight`'s formula (`myweli_month_grid.dart`): the house
  already has one answer to *"a row that must grow"* and should not gain a
  second.
- **A header showing the running « 14:30 »**, formatted by `Formatters`, so the
  value is legible without decoding two highlighted rows.
- **« Confirmer » commits.** A14a's pop-on-tap doctrine does not transfer: a time
  is two values, so there is no single tap that means *done*.
- **`minTime`** — the constraint Material could not express, and the reason
  §10.1's third error state disappears.

### 11.2 `MyweliTimeRangePicker` → `Future<({TimeOfDay start, TimeOfDay end})?>`

Chains B and C, on **one** surface. A two-chip selector at the top
(« Début 09:00 » / « Fin 17:00 ») chooses which value the columns below edit, so
both are visible at all times and the modal-identity problem of chain B
disappears with the second modal.

- **The end is after the start by construction** — the constraint is enforced in
  the control, so §10.1's first two error states have nothing left to catch.
- **Moving the start past the end drags the end forward**, preserving the
  behaviour `availability_screen.dart:643`'s `pickedStart.hour + 1` currently
  fakes with arithmetic because the two dialogs cannot see each other.
- **`startLabel` / `endLabel`** — chain C's « Heure de début » / « Heure de fin »
  become field labels rather than two modal titles.

### 11.3 `MyweliDateTimePicker` → `Future<({DateTime date, TimeOfDay time})?>`

Chain A. One route, two steps, a header carrying both. **Back preserves the
chosen date** — the defect being fixed. When the chosen day is today, the time
step's `minTime` floors at `salonNow(tz:)`, which is what finally makes
`pro_journal_screen.dart:449`'s « Créneau indisponible. » a server-side backstop
rather than the user's first feedback.

The date half is `MyweliDatePickerScreen`, unchanged. **It inherits A14a's clamp**
(`myweli_date_picker.dart:135-147`): rescheduling a past appointment passes a
past `initialDate` against a `firstDate` of today, and the clamp is what stops
that being a dead end.

### 11.4 States & copy

- **loading** — none; every control is synchronous.
- **empty** — a `minTime` that excludes every remaining minute of the day. The
  columns still render, the excluded rows are disabled, and « Confirmer » is
  disabled rather than absent.
- **error** — none. The controls cannot fail; errors belong to the flow that
  consumes the value (§14: field-anchored, never a toast).
- **success** — pops with the value.
- **dismissed** — pops with `null`, and every call site treats that as "change
  nothing". Unchanged from today, and the one thing about the current flows that
  is already right.

Copy: « Confirmer » · « Annuler » · « Heures » · « Minutes » · « Début » ·
« Fin ». Titles default to « Choisir une heure » / « Choisir un horaire », with
`helpText` overriding, exactly as the date picker does (`:171`).

---

## 12. The gates — and why the usual instrument is blind

Gate-first still holds, but §9.4 rules out the obvious gate: an assertion pointed
at `showTimePicker` **cannot go red**, because the dial has no paragraphs. Two
gates replace it.

**① `test/a11y/time_picker_test.dart`** — the house controls at
`{360, 375, 390} × {1×, 2×}` on `kFloorPhone`, one `testWidgets` per combination.
It lands against a **deliberately naive first widget** (fixed-height rows), so it
goes red for a real reason and the fix greens it. Without that, the first commit
would be a gate that has never failed — row 67's exact failure mode.

The mechanical hazards A14a recorded still apply and are repeated because they
produce a green gate that measures nothing:

- `pumpAtWidth` defaults to a **1600dp-tall** surface; the subject pins
  `kFloorPhone` (`Size(360, 780)`).
- The matrix loops stay **outside** `testWidgets` — `_overflowReportNeeded`
  latches (`layout_test.dart:74-93`). *"Do not collapse it."*
- `pumpAndSettle` hangs: the loading state is an infinitely repeating Lottie.
  `settleMocks` is the house idiom.

**② A source pin: `TextScaler.noScaling` and `MediaQuery.withNoTextScaling` are
forbidden in `lib/`.** This is the rule Flutter breaks at `time_picker.dart:387`,
and the reason A14b exists — so the app should be unable to grow its own copy of
it, in this widget or any future one.

It is **green from birth** (`lib/` has none today), which is precisely row 67's
trap: six helpers shipped unable to fail. So it gets a falsifiability case
feeding the rule a synthetic source string, the `primitives_test.dart` pattern.

---

## 13. The four debts A14a left, all closed here

The user's instruction was *"let's also fully A14"*. All four were verified in
this repo, not carried over from a note.

| # | debt | verification |
|---|---|---|
| 1 | **`formatDate`, `formatDateShort`, `formatMonthYear`, `weekdayInitials`, `formatTime`, `formatDateTime` have no unit test.** `test/unit/formatters_test.dart` has six groups and none of them is these. A14a made four load-bearing: `formatDate` is now **every day cell's accessibility label** (`myweli_date_picker.dart:494-495`), `formatMonthYear` is the month bar *and its `Semantics.label`*, `weekdayInitials` is the « L M M J V S D » row, and `formatDateShort` labels
the manual-booking date field and the combined picker's date chip — **four**. | §6 promised them and A14a said so when it did not deliver |
| 2 | **Five of fifteen `layout_test.dart` subjects lack `expectNoVerticalClip`** — consumer OTP `:151`, pro appointment tabs `:233`, consumer bookings `:265`, **booking hub `:588`**, booking confirmation `:613`. §6.1 said *four*; counting `testWidgets(` against the helper in file order gives five. The booking hub is the screen row 73 was found on, and booking confirmation is the screen after it — the two consumer screens immediately before payment. | counted, not recalled |
| 3 | **`french_test.dart:83-88` still pumps a live `showDatePicker`.** Its comment at `:74-77` cites `booking_hub_screen.dart:743` and `pro_manual_booking_screen.dart:111` — both have moved — and claims *"Both leave `initialEntryMode` at its default, so keyboard entry is one tap away."* **That is now false in a way no line-number fix repairs:** `showMyweliDatePicker` has no `initialEntryMode` and `MyweliDatePickerScreen` has no text-entry mode at all, so the `mm/dd/yyyy` parse defect is unreachable from `lib/`. `:31-33`'s *"5 `showDatePicker` … sites"* is now zero. `:129-138`'s three `reason:` strings describe a dialog the app no longer shows. | read |
| 4 | **`AppTheme.datePickerTheme` is dead product code.** There is no `showDatePicker`, `DatePickerDialog`, `CalendarDatePicker`, `showDateRangePicker` or `InputDatePickerFormField` anywhere in `lib/`. Its only remaining consumer is debt 3's test, via `pump_app.dart`'s `AppTheme.lightTheme`. Its comment (*"The 11 date/time pickers were the worst purple offenders"*) is stale twice: there are six, and they are all time. | grepped |

**Debts 3 and 4 are one change, not two.** Deleting the theme block while leaving
the test leaves the test measuring a widget the product cannot show; deleting the
test while leaving the block leaves genuinely unreachable code. They land
together.

**What debt 3 must keep:** `french_test.dart:159-173`, the 24-hour assertion, is
still exactly true and is **A14b's inherited guarantee** (§10.2) — a house time
picker renders its own hours and inherits nothing from `MaterialLocalizations`,
so if that assertion goes, nothing holds the app to `HH:mm`.

---

## 13.0 What the adversarial review found, after the goldens

The gates were green, the device run was clean, and every picture had been
looked at. Three read-only reviewers then found **nine more things**, and the
pattern is worth stating: *the pictures caught what the gates could not, and the
review caught what neither could — boundary values nobody would tap, and prose
nobody would re-derive.*

**Five defects in the code.** Each is now covered by a test named for it.

| | what |
|---|---|
| `hour: 24` | Lifting a below-floor selection by ceiling the *minute component* and carrying gave `hour: 24` for a floor of 23:58. **`TimeOfDay` has no assert** (`time.dart:55`), so nothing threw: « Confirmer » stayed enabled and `salonDateTime(hour: 24)` normalised to the **next day at 00:00** — a reschedule silently booking a different day than the one on screen. Reachable whenever the salon clock's minute is past `60 − step`. |
| two closed-form predicates | `(hour + 1) * 60 > start` asks whether an hour *ends* after the bound, but the largest minute the column offers is `60 − step`. With a start of 10:55, hour 10 read as enabled while all of its minutes were disabled, and tapping it landed the user on **11**. The same shape sat in the combined picker against the floor. Notably the **one** predicate written by enumerating the grid was correct; both written as closed forms were wrong at the same boundary. |
| an off-grid start | The range start was clamped to `_lastGridMinute − 1` = **23:54**, which a 5-minute column never renders. |
| an off-grid repair | `_clampEnd` did `start + step`, crossing the hour without re-snapping: at a step of 7, 10:56 → **11:03**. |
| an unsnapped lift | `pro_manual_booking._pickDate` assigned the raw wall clock, so moving the date to today at 14:07 put **14:07** in a field the 5-minute picker would never have offered. |

**Two holes in the gates.** `expectTokensWhole` accumulated one vacuity counter
across its whole token list, so six of eighteen runs measured a single paragraph
while the comment claimed both columns — it guards **per token** now. And no
picker was a subject of any `meetsGuideline` gate, which is how A14a's month bar
shipped a **40dp** year toggle: the `Row` around it is 48 because of the
chevrons, so it looked right and measured short.

Three behaviour tests were also **unfalsifiable** — one passed on a silent swap,
one asserted a clause its own `reason` admitted it could not distinguish, and one
was a tautology the type system already guaranteed.

**And a page of prose that was wrong**, corrected in place rather than quietly:
the "20dp overlap at every clock position" (radial constant treated as vertical),
the "~4dp of painted ink" (a font size read as ink), "seven (widget, route)
pairs" (it is eight, over five routes), a return type, a widget name, three line
citations this slice's own commits had moved, and a "for three years" invented in
a correction about an invented claim.

---

## 13.1 The device run — chain C, on the hardware A12 uses

Same device as A14a's (`A11 360dp`, iPhone 13 mini, 360×780pt), same setting
(`content_size accessibility-large`, ≈1.95×). Route: pro app → « Disponibilité »
→ the « Pauses » editor → tap Mardi's « 13:00 – 14:00 ».

| | before A14b | measured after |
|---|---|---|
| what opens | **two `showTimePicker` dialogs in a row**, with no `helpText` on the availability pair and nothing on screen saying which one you are in | **one screen**, titled « Mardi — horaires » |
| both values | only ever one at a time | « Heure de début 13:00 » **and** « Heure de fin 14:00 », both on screen |
| at 1.95× | Material's hour field is the same size it is at 100% | the chips **wrapped onto two rows** and the wheel rows grew |
| an end before the start | two modals, then `if (end <= start) return;` — the row silently did not change | **hours 07, 08, 09, 10 render in `textTertiary` and do not respond**, because they precede the 13:00 start |

The last row is the one worth photographing. The invalid state is not *caught*
any more; it is **unreachable**, and the disabled greys are what that looks like
to a user who tries.

Also confirmed on the same screens, none of which a computed gate asserts:
« Heures » / « Minutes » in French, every two-digit hour and minute whole at
1.95×, the chip highlight moving between the two halves, and the hours column
re-anchoring to the value of whichever half is being edited.

**What this run did not cover.** Chain A (the combined picker, reached from a
journal reschedule) needs an appointment on the day, and the seeded salon had
none. Its 1× and 2× goldens exist and were reviewed; the device evidence here is
for chain C only, and saying otherwise would overclaim it.

---

## 14. Open questions (A14b)

- **`minuteStep` defaults to 5.** Salon slots are 15 or 30 in practice, but a
  reschedule may need to match an arbitrary server slot, so the leaf takes the
  parameter rather than the family assuming a granularity. If a site turns out to
  need exact minutes it passes `1`. Revisit if any call site wants something the
  parameter cannot express.
- **`pro_manual_booking_screen.dart:243-263`'s `_PickerField` row** is the one
  place a combined control changes visible layout: an unflexed `Text` in a `Row`
  with no `Expanded` — the shape row 68 catalogues — in an `Expanded` slot of
  ~156dp at 360dp. Whether « 15/01/2024 » at 2× wraps or overflows depends on the
  ICU break opportunity at `/`. **Not measured.** The gate in §12 covers it once
  the row is a subject; until then it is an open question, not a claim.
