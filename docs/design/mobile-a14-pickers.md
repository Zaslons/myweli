# A14 — our own date & time pickers

| | |
|---|---|
| **Status** | A14a built · A14b built · A14c built · A14d built · **A14e built — the campaign is closed** |
| **Owner** | Sadreddine Daher |
| **Last updated** | 2026-07-31 |
| **PRD ref / phase** | **V1.** No numbered PRD requirement — how far ahead a salon accepts bookings was never specified, which is precisely what §21 row 76 records. A14d answers it as a product decision (§20.2), so the decision itself lives here rather than being cited from elsewhere |
| **ROADMAP entry** | [ROADMAP.md](../ROADMAP.md) — A14c 🟢 · A14d 🟢 · **A14e 🟢** (all 2026-07-31) |
| **Module** | [`journal`](../MODULES.md#1-journal--bookings--journal-) (the pro calendar) · [`online-booking`](../MODULES.md#2-marketplace--online-booking--online-booking-) (the consumer funnel) — the campaign straddles two, which is why the `table_calendar` sites did not fall out of one module's slice |
| **Register row** | [SYSTEM.md](SYSTEM.md) §21 row 73 (A14a) · row 77 (A14b) · row 75 (A14c) · **row 76 (A14d)** · **row 78 (A14e)** |
| **Skills checked** | `myweli-dev-guardrails` · `myweli-web-guardrails` (A14c §17, A14d) · `myweli-backend-guardrails` (A14d) |
| **Preceded by** | [A12 — the fixed-box sweep](mobile-a12-fixed-boxes.md) · [A13 — copy & breaks](mobile-a13-copy-and-breaks.md) |
| **Scope** | **A14a** — the date picker (§1–§7) · **A14b** — the time picker family (§8–§14) · **A14c** — retire `table_calendar` (§15–§19) · **A14d** — the per-salon **bookable window**, server-enforced (§20–§28) · **A14e** — multi-select blocking (§29–§34) |

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

---

# Part C — A14c, retiring `table_calendar`

## 15. Goal & scope

Row 75: **`table_calendar` is text-scale-blind, and one of its rows clips at
1×.** The package contains zero `MediaQuery`, `textScaler`, `maxLines` or
`FittedBox` anywhere in its `lib/`; `rowHeight` is a fixed `52.0` and
`daysOfWeekHeight` a fixed `16.0`, summed into a `SizedBox(height:)` — the
fixed-box-around-text shape §13.3 forbids. Three call sites, two of them live.

A14c converts all three, deletes two dead screens, rebuilds consumer reschedule,
and drops the dependency.

### 15.1 What A14b already did, so this section does not re-promise it

The grid extraction A14c was going to need **already shipped in A14b**:
`myweli_month_grid.dart` exports `MyweliMonthGrid`, `MyweliMonthBar`,
`MyweliWeekdayHeader`, `MyweliYearList`, `MyweliMonthNavigator` and a public
`isSameDay`. A14c starts at the conversions.

### 15.2 The importer count is four, not seven

`grep -l table_calendar` returns seven files. Four contain an actual `import`:
`date_time_selection_screen.dart:7` · `appointment_calendar_view.dart:4` ·
`booking_journal_screen.dart:2` · `test/unit/french_test.dart:9`.

The other three — `app_locale.dart`, `myweli_month_grid.dart`, `pump_app.dart` —
name the package **only in comments**, and those comments need rewording rather
than deletion. `app_locale.dart:7-17` in particular documents *why the locale
seam exists at all*; deleting it would orphan a live rationale.

## 16. Three defects in our own grid, none of them recorded

Before a single conversion, the widget the conversions depend on has three
problems. **All three were found by reading A14a's code, not by a gate** — which
is itself the finding.

### 16.1 `_cellHeight` scales the wrong quantity, and no test here can see it

`myweli_month_grid.dart:428-435`:

```dart
final line = (style.fontSize ?? 14) * (style.height ?? 1.4);
return math.max(
  AppTheme.spacingXXL,
  MediaQuery.textScalerOf(context).scale(line) + AppTheme.spacingS,
);
```

`_dayStyle` is `bodyLarge` — `fontSize: 16`, `height: 24 / 16`. So this computes
`scale(24)`. **Flutter's line box is `scale(16) × 1.5`**: the scaler applies to
the font size, and the height multiple applies to the result.

`TextScaler` does **not** promise linearity. Its whole reason for replacing the
old `textScaleFactor` double is that a platform may scale non-linearly — Android
14 does exactly that, compressing large sizes so headlines do not run away. Under
any linear scaler `scale(a × b) == scale(a) × b` and the two expressions are
algebraically identical, which is why **every test in this repo is blind to it**:
`layout_test.dart`'s 3 widths × 2 scales, `date_picker_test.dart`, and both
goldens all use `TextScaler.linear`.

**Measured**, under a scaler that triples up to 16sp and then flattens to 1.2×
(`myweli_month_grid_test.dart`'s `_NonLinearScaler`):

| | value | how |
|---|---|---|
| Flutter's line box for one day number | **72.0** | measured from a bare `Text`, not computed |
| the cell the grid gave it | **65.6** | measured — `max(48, scale(24) + spacingS)` |
| the cell it needs | **80.0** | `max(48, 72 + spacingS)` |

So the day number **paints 6.4dp outside its own cell**, over the weeks above
and below. `Container` does not clip, so this is *overlap*, not truncation —
there is no overflow banner and no clipped glyph, which is why looking at a
screenshot would not have found it either. This is row 73's species: real,
device-only, and unfalsifiable by the instrument pointed at it.

⚠️ **That scaler is a model, not Android's curve.** The claim is not *"Android
14 produces 65.6"* — it is that the expression assumes a linearity the interface
does not guarantee. The gate is written against that property rather than
against a vendor's numbers, and the companion test at linear 2× is kept
**precisely to show it passes either way**, i.e. that it cannot be the gate.

### 16.1.1 It is three sites, and A14a and A14b both inherited it

The formula did not originate in A14a. `_WeekStrip._dayPill`
(`pro_journal_screen.dart:632-635`) wrote it first; A14a's day cell copied it
with the floor raised 32 → 48; A14b's `_rowHeight`
(`myweli_time_picker.dart:830-835`) copied that. **One arithmetic slip reached
three files through three consecutive slices whose entire subject was text
scale**, and no gate in any of them could see it.

Fixed by deleting the formula from all three and putting it in one place —
`AppTheme.scaledLine(context, style)`, beside `textScaledBound`, which was
already correct and is worth saying why: it scales a **measured 1× block
height**, not a `fontSize × height` product, so there is no ordering to get
wrong. There is no longer a formula at any of the three sites to copy.

### 16.2 Nothing asserts that a selected day is painted selected

`myweli_date_picker_test.dart` has six `testWidgets`: tap→pop, dismiss→null,
out-of-range inert, clamping, the year jump, and the today announcement. **None
of them checks that `selectedDay` renders as selected.**

That matters now because §17.1 changes the selection parameter's *type*. A
migration that produced zero selected days would leave every existing test green.
The hole gets closed **before** the migration, not after.

### 16.3 `Set<DateTime>` is a trap in this file

`DateTime.==` compares microseconds **and `isUtc`**. `salonToday(tz:)` returns
`DateTime.utc(y, m, d)` (`salon_time.dart:74`); the grid builds `DateTime(y,m,d)`,
local. A `Set<DateTime>` seeded from the salon-time seam therefore **contains
nothing**, silently, and every day renders unselected.

`isSameDay` already solved this for one day by comparing fields. The set and map
cases need the same answer in a shape a `Set` can use: a `CalendarDay` value type.

## 17. The API changes, and why each is the smallest one

### 17.1 `selectedDay` → `selectedDays`, not both

`MyweliMonthGrid` has **exactly one caller** — the navigator, at `:395`. The
navigator has two: `myweli_date_picker.dart:137` and
`myweli_date_time_picker.dart:234`. **Three lines**, so there is no reason to
carry a second selection parameter alongside the first and an `assert` to keep
them apart. One concept.

`onDayTap` is unchanged. **The toggle-vs-replace policy lives in the page**,
which is the seam this file's own header argues for: the picker pops on tap, and
A14e's multi-picker toggles a set. The grid paints what it is told.

### 17.2 `Map<CalendarDay, String>? markers` — one dot, and the count in speech

The pro calendar needs *"this day has at least one appointment"*. The map's value
is the French phrase appended to that cell's accessibility label, so *"is it
marked"* and *"what does it announce"* are one lookup rather than a predicate
plus a second parameter.

**Null is not the same as empty, and the difference is the cell's height.** Null
turns the channel off and keeps A14a's geometry byte-for-byte — which is what
leaves the two picker goldens alone. A non-null map, *even an empty one*,
reserves the marker row on every cell, so the card does not change height when a
pro pages from a busy month to a quiet one.

**Never a colour** (§13.6, and the status hues are already spent on the chips
directly below on that screen). **Never a count in pixels** — and that is not a
taste judgement, it is a measurement the app already made:

> `pro_journal_screen.dart:656-660` draws the week strip's marker as
> `width: count == 0 ? 0 : (3 + count.clamp(0, 5)), height: 4,
> shape: BoxShape.circle`. `BoxShape.circle` paints
> `drawCircle(center, rect.shortestSide / 2)`. The shortest side is **4 for every
> count**, so one appointment and five paint an **identical 4dp dot** — the width
> only widens an invisible box. The count encoding has never rendered.

So the count goes where it costs zero pixels and reads perfectly: « 3 rendez-vous,
jeudi 19 mars 2026 », through `Formatters.count` (A13 row 41's pin, because
« rendez-vous » is invariant in the plural and a bare `$n` would not know that).
A screen-reader user gets strictly more than the eye does.

### 17.3 `shrinkWrap`, because the navigator would throw

`MyweliMonthNavigator` uses `Expanded` at `:376` and `:389`. Both new consumers
put a calendar inside a `Column`, and **a `Column` hands its non-flex children
unbounded main-axis constraints** — so the navigator does not merely look wrong
there, it throws `RenderFlex children have non-zero flex but incoming height
constraints are unbounded`.

`shrinkWrap` defaults to `false`, so both picker screens are unchanged.

Its one visible cost, accepted and recorded: in shrink-wrap mode the year list
replaces the grid, and three `ListTile`s are shorter than six week rows, so the
card **jumps** when the year toggle is pressed. It is one tap and reversible; the
alternative is arithmetic on a widget that has no business knowing the grid's
height. **Photographed in a golden so it cannot drift silently.**

### 17.4 No `onMonthChanged` — and that is a finding, not an omission

The reason to want one is *"recompute markers for the visible month"*. With
§17.2's map that recomputation **does not happen**: markers are keyed by absolute
day, and `widget.appointments` is already fully in memory
(`appointment_list_screen.dart:161`). A callback would serve nothing.

Recorded with its trigger: *if `ProAppointmentProvider` ever fetches per month,
the navigator gains `ValueChanged<DateTime>? onMonthChanged`, fired from `_shift`
and the year pick. It stays a **notification**, never a two-way binding — the
refusal to resync `_month` in `didUpdateWidget` (`:343-350`) is the fix for
`date_time_selection_screen`'s month-yank and must survive.*

A quieter consequence, also recorded: without resync the pro calendar **cannot
programmatically jump to a month**, so there is no « Aujourd'hui » button. Nobody
has asked for one.

### 17.1.1 The trap was watched, not just described

The migration went through `Set<DateTime>` **on purpose**, so §16.3 would be a
measurement rather than an argument. Seeding the grid with
`DateTime.utc(2026, 3, 15)` — byte-for-byte what `salonToday(tz:)` returns — and
asking the cell what it announces:

```
Which: missing flags: isSelected
```

Then `CalendarDay`, and green. Without that step the type would have been
justified by reasoning about `DateTime.==` rather than by a failure, and this
register's whole complaint is that reasoning of that kind has been wrong on
nearly every slice.

## 18. The pro calendar, measured for the first time

Row 75 says the weekday row *"clips at 1×, today"* on two live screens and that
*"nothing has ever measured it — no golden, no a11y subject"*. **Both halves are
true, and the reason the screen escaped is one line long.**

Calendrier is `TabController` **index 0 — the default**. It is what renders on
first pump. And both instruments aimed at this screen call `openProList(tester)`
as their *second statement*, whose entire job is to tap from Calendrier to
Liste. `layout_test.dart:249` and `pro_screens_golden_test.dart:345` each
navigate off the calendar before measuring anything. The new subjects are the
old ones **minus** a line.

Measured, at 360dp × **1×**:

```
« lun. » needs 20.0dp in a 16.0dp box
« mar. » needs 20.0dp in a 16.0dp box
… all seven, twice each
```

Red at all six configurations. `daysOfWeekHeight: 16.0` around a 20dp line,
summed into a `SizedBox(height:)`. Two things the register did not contain: the
labels are « lun. » « mar. » « mer. », **not** the house « L M M J V S D » that
`Formatters.weekdayInitials()` renders; and the clip is **doubled**, because the
package keeps neighbouring month pages alive in a `PageView`.

### 18.0 What the conversion found that the clip did not

**The page had no room for an honest calendar.** `table_calendar` pins
`rowHeight: 52.0`, so a calendar that refuses to grow makes the layout around it
look fine too. The moment the house grid sized from the text, the view's
`Column` overflowed by **40 pixels** at 2×, on all three widths.

**And the 40 was width, not height.** Measured rather than reasoned: card margin
16 + card padding 16 + the navigator's own page inset 16 = **48 a side**, leaving
**37.7dp** a column against the **44.9** §2.1 requires. So « 15 » wrapped to two
lines — 2 × 48 + 8 = 104 in a 64 box, exactly 40 over. The first hypothesis
(the empty state overflowing) was wrong and a probe said so.

The page inset belongs to the page: `shrinkWrap` now selects `spacingS` when
embedded and `spacingM` when the navigator *is* the page. With the card at
`spacingS` the embedded column is **46.86dp** — the same number the full-screen
picker gets, which is the invariant worth stating instead of two values that
happen to work.

**Pull-to-refresh was dead on quiet days.** `BrandRefresh` needs a scrollable and
the only one here was the inner `ListView`, which the empty branch replaced with
a `Center`. One `CustomScrollView` fixes the overflow and the gesture together.

**`_focusedDay` was never state** — mutated without `setState` in
`onPageChanged`, never read back. Deleted rather than ported.

**`eventLoader` ran 42 times a build**, each call `.where()`-ing every
appointment with a `context.read` *and* a `toSalonTime` inside the loop, because
`_tz` was a getter re-read per element: ~4,200 provider lookups and ~4,200
timezone conversions **per frame** at 100 appointments — and the marker builder
then asked only `events.isNotEmpty`. Now one indexing pass per data change.

### 18.1 The empty-state lockout

`appointment_list_screen` replaced the whole calendar with a centred « Aucun
rendez-vous » whenever the salon had none — so a **new salon could not open its
calendar at all**, could not browse forward to plan, and the calendar's own
per-day empty state (« Aucun rendez-vous **pour mercredi 11 mars 2026** », which
names the day) was unreachable and never photographed.

A calendar with nothing in it is not an error state. It is a calendar.

### 18.2 The dead screen, and the pin it freed

`booking_journal_screen` is `FeatureFlags`-dead behind a `const false` with zero
references. Converted rather than deleted — the dependency is going, so the
choice was convert or delete, and a V2 screen someone will un-shelve is worth
more converted. Its three `DateTime.now()` reads went with it, taking its
`salon_time_pin_test.dart` entry: **seven allow-listed files become six**.

**Then the pin went red on that same file** — for a `DateTime.now()` that existed
only inside the comment explaining the three real ones had just been removed.
The pin matched raw source.

A gate that reddens when you *document* fixing it is a gate people route around,
and it cuts the other way harder: a **commented-out** call would keep a file
looking like an offender forever, so the allow-list entry justifying it could
never be retired. `stripDartComments` now runs first, with a falsifiability case.

The web side had the identical hole and records the identical lesson —
`scripts/dart-tokens.mjs` strips comments because *"every parser hole below
traced back to reading comments as code"*. Same defect, same answer, two
languages apart.

### 18.3 Two visible changes, and a picture

« Today » is a **ring**, not a 50 %-alpha primary fill, and the day cell is a
**rounded rectangle**, not a circle. Both are forced by §2.1's arithmetic (a
circle needs ~1.1dp more than a 360dp column has at 2×) and by §13's rule against
meaning carried by colour alone.

`pro_appointment_calendar_w360.png` is **the first picture this screen has ever
had**. Regenerating produced **exactly one new PNG and moved no existing one** —
which is the check that `markers: null` keeps A14a's geometry byte-for-byte and
that §16.1's fix is linear-scale-neutral.

**There is no before/after pair, and saying so is more honest than implying
one.** The "before" evidence is the measurement above — `« lun. » needs 20.0dp
in a 16.0dp box`, seven labels, at 1× — which is stronger than a photograph of
the same thing.

**A real phone is tested separately, because the matrix does not use one.**
`pumpAtWidth` defaults to `height: 1600` so full content can be measured without
scroll clipping; nothing in it exercises the real vertical budget. The calendar
is the screen where that matters, so `appointment_calendar_view_test.dart` pumps
`kFloorPhone` (360×780) at 1× and 2× directly.

## 19. The consumer funnel: one slot picker, and two screens deleted

### 19.1 Why the booking hub could not be reused

The obvious answer to "reschedule needs a date and a slot" is *"open the hub
with everything preselected"*. **The contract forbids it.**
`POST /appointments/{id}/reschedule` (`openapi.yaml:2494-2503`) accepts
`newDateTime` and an `artistId` marked **PROVIDER ONLY**, and states *"Deposit +
balance carry over unchanged"*.

| hub section | on a consumer reschedule |
|---|---|
| services | **forbidden** — changing them changes the price, so the deposit, which the endpoint cannot express. That is a cancel-and-rebook. |
| artist | **forbidden** — `artistId` is provider-only (journal J1's drag-across-columns) |
| date/time | the only thing that may change |
| confirm → deposit sheet → `createAppointment` | **actively wrong** — the deposit is already paid |

A "reschedule mode" would suppress two thirds of a 1,226-line screen and replace
its ending. **The reuse belongs one level down**, at the block both surfaces
actually share.

### 19.2 `SlotPicker`, and the four things the extraction found

- **There were only three states.** `AppointmentProvider.getAvailableTimeSlots`
  swallowed every failure into `return []`, so « Aucun créneau disponible » was
  the sentence for a fully-booked Saturday *and* for a dead network — §14 wants
  four, and the missing one was the only one a user can act on. The layer below
  always knew; `ApiResponse` carries `error`. Two more places were silently
  wrong for the same reason: `_validateSelectedDateTime` **cleared the user's
  chosen time** on a failed request, and `_findEarliestSlot` walked up to 15
  more days after the first failure.
- **`date_time_selection_screen` had no in-flight guard**, so rapid day taps
  could paint one day's slots under another day's heading. The hub had one; the
  duplicate did not.
- **It compared slots by hour and minute**, which matches 14:00 on any day.
- **The hub rendered no `SalonTimeHint`** — the one picking surface without it.

**Where the country lookup lives is a performance decision.** Three screens
write `context.watch<LocalityProvider>().countryName(...)` in their own `build`;
on the hub that redraws 1,226 lines to update one line of grey text. It is a
`Selector` scoped to the hint now. **`SalonTimeHint` stays pure** — no provider
dependencies, which is what lets it be pumped in isolation with a
`deviceOffsetOverride`, and pushing the lookup into it would take that from
every future test. The same duplication on two other screens is **left alone
deliberately**: fixing it means touching screens this slice has no business in.

### 19.3 The reschedule route, and the live defect it closes

The old flow pushed `/booking/date-time` **without `durationMinutes`**, so the
target recomputed the booking's length from the salon's *current* catalogue and
a freshly-defaulted hair-length variant. **A three-hour braid could be offered
thirty-minute slots.** The router and the target both accepted the parameter
already; only the caller never sent it.

The duration now comes from the salon's own services, because
`Appointment.durationMinutes` is a *provider-enriched* field that can be null on
a consumer payload — which is also why the salon must be loaded, and
`_maybeResolveProviderFacts` was already loading it on every appointment and
**throwing it away**. Retaining it costs one reference and pays for the context
header the bare picker never had.

**Choosing is not submitting.** The old flow popped the instant a time was
tapped; the button now states what will happen and is inert until it can.

### 19.4 `Intl.defaultLocale`: the seam outlives its only consumer

Retiring `table_calendar` removed **the only thing in the product that read
`Intl.defaultLocale`** — every `intl` call in `lib/` passes an explicit locale,
`Formatters` included.

`initAppLocale()` is **kept**, and the justification changes rather than the
code: *"no caller today"* is not *"no caller"*, and `defaultLocale ??=
systemLocale` means the **first** bare `DateFormat` pins the isolate for its
lifetime. So the seam stops being defended by a dependency we deleted and starts
being defended by a rule — a pin forbidding locale-less `DateFormat` /
`NumberFormat` in `lib/`, with a falsifiability case, since the assertion is
green from birth.

The widget half of the old mechanism-3 gate is replaced by that pin; the bare
`DateFormat.yMMMM()` assertion **survives verbatim** as a live demonstration
that the seam is what makes it French.

### 19.5 Web: the obligation recorded in source and in no document

`MonthCalendar.tsx` drew out-of-month days dimmed **and clickable**, so clicking
one selected a day the header does not name. Recorded only in
`myweli_month_grid.dart`'s docstring — *"A14c changes web to match this, not the
other way round"* — and nowhere in `docs/`, which is why it survived.

**The first gate for it was vacuous and green against the defect.** It asserted
no rendered day was `> 30`; June's trailing cells are 1–5 **July**, which render
as « 1 »…« 5 ». Counting identities — 30 buttons, not 42 — is what made it fail.
That is the fourth vacuous gate this campaign caught by mutating or re-reading
its own new test, and the reason the step is not optional.

---

# Part D — A14d, the bookable window

## 20. Goal & scope

**Row 76 asks a product question, and A14d answers it:** *how far ahead does a
salon accept bookings?* Today the answer is « whatever a developer typed », and
the register row says so — *"the app offers a year on one screen and three
months on another because two people picked a literal, not because a salon said
so."*

### 20.1 Row 76's body is stale; its live half is the whole slice

The row is legitimately still open, but two of its sentences are no longer true
and must not be quoted forward:

> *"**2 screens**: `booking_hub_screen` uses the house picker over **365 days**;
> `date_time_selection_screen` uses `table_calendar` over **90**."*

`date_time_selection_screen` **was deleted in A14c**, and
`booking_horizons.dart:7` already records that *"its 90 died with it."* The
365-vs-90 consumer split the row describes does not exist any more.

What survives is the sentence that matters, and it is still exactly true:

> *"**there is no server-side bookable-horizon rule at all.**"*

Verified again at the source before writing this: a repo-wide grep of
`backend/` for `bookingHorizon|horizonDays|maxAdvance|advanceBooking|leadTime`
returns nothing, and `slot_service.dart` contains no `Duration(days: …)` bound
of any kind. **Today a client may request slots for any date, in any year, and
the server will compute them.** The row's body is rewritten in this PR to say
that, rather than to describe two screens of which one is gone.

### 20.2 The scope decision: one setting with two ends

Scoping this slice surfaced a sibling defect the plan had not seen, and the
owner's decision was to close both together.

`SlotService` already enforces a **minimum notice** — *"for today, only offer
starts ≥ 1h from now"* (`slot_service.dart:101-105`) — as a bare `60` with no
constant, no setting and **no test**. It is duplicated independently in
`mock_appointment_service.dart:358-361` as `Duration(hours: 1)`, so mobile's
mock and the API agree only by coincidence.

So A14d ships the **whole bookable window**, not half of it:

| | field | default | bounds |
|---|---|---|---|
| **near end** | `minimumNoticeMinutes` | **60** — today's literal, preserved exactly | `0 … 10080` (0 = walk-ins welcome; 7 days) |
| **far end** | `bookingHorizonDays` | **365** — the consumer funnel's current constant | `1 … 730` |

Both defaults are chosen so that **A14d changes no salon's behaviour on the day
it ships**. The near end preserves the literal it replaces; the far end
preserves `kBookingHorizon`. The feature is the *ability* to change them.

**Why 730 and not unbounded.** `MyweliMonthNavigator` builds a year list from
`firstDate.year` to `lastDate.year`, so an unbounded horizon is an unbounded
`ListView`. Two years is generous against every competitor we checked (Square
caps at 365) and finite. `bufferMinutes` — the only numeric precedent — has **no
upper bound at all** (`999999999` validates and stores today), so a ceiling is a
new pattern here and needs its own justification rather than a copy.

**Why the two are cross-validated.** If `minimumNoticeMinutes` exceeds
`bookingHorizonDays × 1440`, *nothing is ever bookable* — the near end sits past
the far end and every day returns empty. That is not a configuration, it is a
mistake, and the server rejects it with `invalid_input` rather than silently
making a salon unbookable.

**Out of scope, named:** un-publishing a salon whose window makes it unbookable.
`publishGate` inspects profile, location and services and **never reads
availability**, so a salon with an absurd window stays listed and `active`. That
is a pre-existing gap A14d does not widen (the cross-validation above is the
mitigation) and it is not this slice's job.

## 21. What verification corrected before a line was written

Seven read-only agents re-checked every load-bearing claim in the A14d plan
against `main`. **Fourteen came back not-confirmed.** The three that would have
produced wrong code:

**① `invalid_state` does not map to 409 on the booking route.** The plan
proposed `beyond_horizon` as *"409, the status `invalid_state` already maps
to."* It does not: `routes/appointments/index.dart:165-170` names
`provider_not_found`, `slot_unavailable` and `provider_suspended`, and
everything else falls to `_ => HttpStatus.badRequest`. The 409-for-`invalid_state`
convention is real but lives in `responses.dart:35-36`, `:101` and
`deposit.dart:59-60` — three files the booking route does not use. A new code
added without an explicit `case` **ships as a 400**.

**② The availability route test has neither a 403 nor a 405 leg.** The plan said
it lacked them *"unlike every neighbour"*; the truth is the whole test is two
legs — a 200 GET and a 200 PUT (`provider_catalog_test.dart:614-639`) — while
the route itself has 401 (`:14-16`), 403 (`:17-19`) and 405 (`:35-36`) branches,
**all three unexercised**. There is also no cross-tenant test for
`replaceAvailability` at all.

**③ Web does not set `min` on every date input — only on 3 of 7.** The plan's
web half was written as *"add a `max`, `min` is already everywhere."* Four
inputs set **neither** bound, including both pro reschedule fields
(`JournalPanel.tsx:243-249`, `ProAppointmentDetailClient.tsx:340-346`) and the
blocked-date picker (`DisponibilitesClient.tsx:179-185`).

Three plan file paths were also wrong — there is no `backend/lib/src/services/`
directory (it is `backend/lib/src/`), the Postgres repository is under
`lib/src/db/`, and **`insertProviderAvailability` is not in the repository file
at all** — it lives in `migrations.dart:949-959`, which means a new column
missed there is dropped by the **backfill** as well as the API write.

## 22. The contract, the storage, and the two allow-lists that would eat it

### 22.1 Two silent-drop traps, on opposite sides of the wire

This is the sharpest thing in the slice, and it is why the gate asserts a
**round trip** rather than a 200.

**Server** — `provider_catalog_service.dart:272-278`. `replaceAvailability` does
not spread the body; it rebuilds a fresh map from exactly five keys. A field not
added there is dropped **with no error**: the PUT returns 200 and the setting
vanishes. `_validateAvailability` never rejects unknown keys either, and the
OpenAPI schema has no `additionalProperties: false`, so nothing anywhere says
no.

**Mobile** — `availability.dart:99-107`. `Availability.toJson()` is the same
shape: a hand-built literal, not a spread. A field added to the model but not to
`toJson` is erased **by the pro app** the moment anyone opens Disponibilités.

**Web is the asymmetry**: its BFF forwards `JSON.stringify(availability)`
verbatim (`app/api/pro/disponibilites/route.ts:7-16`), so the round trip already
works — but `web/lib/api/schema.ts` is **generated** from `openapi.yaml` and CI
enforces its freshness (`ci.yml:241-244` runs `npm run gen:api` then `git diff
--exit-code`), so the contract change breaks web CI until it is regenerated in
the same PR.

### 22.2 Storage is four tables, and the scalar one is the target

`provider_availability` (`migrations.dart:168`) is the only per-provider scalar
config table — `provider_id` PK plus `buffer_minutes`. Both new fields are
scalars, so both belong there. **Migration `0031`**, on `0029`'s
`ALTER TABLE … ADD COLUMN IF NOT EXISTS` precedent (`0030` is last).

Five write/read sites, all of which must learn the fields or the value is lost
in one backend and not the other:

| site | file |
|---|---|
| the allow-list rebuild | `provider_catalog_service.dart:272-278` |
| the validator | `provider_catalog_service.dart:652-689` |
| in-memory seed (4 salons) | `providers_repository.dart:459-464` |
| in-memory seed (fresh pro) | `providers_repository.dart:717-722` |
| Postgres read | `db/postgres_providers_repository.dart:467-495` |
| Postgres empty fallback | `db/postgres_providers_repository.dart:554-560` |
| the INSERT **and the backfill** | `db/migrations.dart:949-959` |

`_emptyAvailability` matters as much as the read: it is what a salon that never
saved availability returns, so the defaults must be written there too or the
same salon answers differently depending on whether a row exists.

## 23. The gate

### 23.1 Consumers only — and that costs a parameter

`availableSlots` has **four** callers, verified directly:

| caller | what it is | bound? |
|---|---|---|
| `booking_service.dart:84` | the consumer books | **yes** |
| `routes/availability/index.dart:29` | public browse | **yes** |
| `routes/providers/index.dart:36` | `?availableToday` search filter | yes (today is never beyond any sane horizon) |
| `appointment_lifecycle_service.dart:105` | `_moveTo` — shared by **consumer** `reschedule` **and** `rescheduleByProvider` | **split** |

That last row is the finding. The plan claimed *"one edit makes browse, book and
reschedule correct together"* — true, but it would also bind **the salon moving
its own booking**, including the journal drag, which contradicts the principle
that already exempts `bookManual` (*the salon owns its calendar*).

**Owner's decision: consumers only.** So `availableSlots` takes
`bool enforceBookingWindow = true` — **default true, so it fails closed** — and
the two pro paths pass `false` explicitly. `bookManual` stays exempt as before,
by never reaching the slot engine at all.

### 23.2 The return shape, and the 404 trap

A new error code from `availableSlots` would produce **three different HTTP
statuses for one condition**, because the browse route maps any non-`invalid_artist`
failure to `HttpStatus.notFound` — a horizon breach would answer **404
« beyond_horizon »** on browse, something else on book, something else again on
reschedule.

So the gate follows the shape its three siblings already use — past day
(`:62-64`), blocked date (`:70-76`), closed weekday (`:79-82`) — and returns
**`(ok: true, error: null, slots: [])`**. Browse stays 200 with an empty list.

`BookingService.book` then carries its **own** explicit checks, because
`slot_unavailable` says *"that time isn't free"* when the truth is *"we don't
take bookings that far out"*. Two new codes, **each with an explicit `case` in
the route switch** (see §21 ①):

- **`beyond_horizon`** → 409
- **`too_soon`** → 409

### 23.3 The lead time cannot stay a today-only filter

Today's rule is expressed as *minutes past salon midnight, for today only*:

```dart
final minStartMinute = dayBounds.startUtc.isAtSameMomentAs(todayBounds.startUtc)
    ? now.difference(dayBounds.startUtc).inMinutes + 60
    : -1;
```

`-1` for every other day. That is correct for a 1-hour notice and **structurally
incapable** of expressing a longer one: a salon requiring 48 hours must exclude
*tomorrow* too, and this branch cannot say that.

Making the near end per-salon therefore forces a restructure, and the restructure
is strictly more correct: compute one absolute instant

```
earliestStartUtc = now + minimumNoticeMinutes
```

and compare each slot's absolute UTC start against it, on every day. The
today-only special case disappears; the 1-hour default behaves exactly as
before.

### 23.4 Whose « now »

The zone was already settled and the clock never was. Mobile bounds with
`salonToday(tz:)` — the salon's **zone** applied to the **device's** instant
(`AppClock.now()`); the server uses `DateTime.now().toUtc()` — the salon's zone
applied to the **server's** instant. A repo-wide grep for
`serverTime|clockSkew|skew` returns nothing: there is no reconciliation
anywhere.

So the horizon is defined as **N salon calendar days from the salon's today as
the *server* computes it**, and the client bound is a **hint that may be off by
a day**. Everything downstream is written so that being off by a day degrades
into the fifth state (§24), never into an assertion or a crash.

Day arithmetic uses the constructor-rollover idiom the existing helpers already
use (`tz.TZDateTime(location, y, m, d + N)`, `salon_time.dart:74-76`) and **not**
`startUtc.add(Duration(days: N))`, which drifts an hour across a DST boundary.
Invisible today — every seeded city is `Africa/Abidjan` — but `localities.timezone`
is free per-city text and the multi-country flip is executed.

## 24. The fifth state — the horizon must not say « the salon is full »

`SlotPicker` has four states, and A14c added the fourth deliberately because the
hub *"rendered « Aucun créneau disponible » for a failed request too — telling a
user the salon was full when the truth was that we never reached it"*
(`slot_picker.dart:227-231`).

A horizon breach fits **neither** remaining state:

- as **empty**, the copy asserts the salon is full — false;
- as **error**, it renders a « Réessayer » button that can never succeed —
  and §12 requires a retry control precisely because errors are retryable.

So it is a **named fifth branch**, on both platforms, with no retry control and
the salon's own dates in the sentence:

> « Ce salon accepte les réservations jusqu'au **{date}**. »
> « Ce salon demande un délai de **{durée}** avant chaque rendez-vous. »

**No new response shape is needed to render it.** `GET /providers/{id}` returns
the whole provider document including `availability`, and
`models.Provider.availability` is already non-nullable on the consumer payload —
so the client **already holds the window** and can name the condition locally.
The server gate is the authority for *writes*; the client copy is the
explanation. Verified: both `SlotPicker` call sites already have the full
`models.Provider` in scope, so wiring costs one argument each.

**Five sentences in the product currently lie about this**, and all five say
some version of *someone else took your slot*:

| surface | today's copy |
|---|---|
| web consumer ×2 | « Ce créneau vient d'être pris. Choisissez-en un autre. » |
| mobile | « Ce créneau n'est plus disponible. Choisissez un autre horaire. » |
| web pro detail | « Créneau indisponible. Choisissez un autre horaire. » |
| web journal panel | « Action impossible. Réessayez. » |

None is true for a window breach, and none can be corrected without the distinct
codes §23.2 adds.

**Web needs its fourth state before it can have a fifth.** `fetchSlots` swallows
every failure into an empty array (`web/lib/booking/client.ts:69-72`), so web
renders « Aucun créneau disponible » for an outage — the *exact* bug A14c fixed
on mobile. A14d cannot claim parity without closing it, so it is in scope.

## 25. Grandfathering — existing bookings are never re-validated

**Owner's decision: grandfather.** A salon that shortens its window does not
cancel, flag or move the bookings already past it.

This is what the code does today and the precedent is exact: blocking a date
does **not** touch that day's appointments — `JournalService._hoursFor` returns
`null` for a blocked day while the day's bookings are still listed unchanged —
and `replaceAvailability` never reads `appointments` at all.

Three consequences follow, and **two of them are defects A14d must fix**:

1. **The booking stands** — visible, honoured, cancellable. Correct, no work.
2. **The consumer's reschedule screen strands them.** `RescheduleScreen` seeds
   its date from the appointment's own salon day; `SlotPicker._pickDay` then
   opens the picker with `lastDate: today + horizon`, `clampToRange` silently
   pins the month to `lastDate`, and the first `_load()` renders « Aucun créneau
   disponible ». The user is told the salon is full when the truth is that their
   own booking is outside the new window. **The fifth state fixes this**, and the
   picker opens on the last bookable day rather than on a clamped surprise.
3. **The pro can still move it**, because `rescheduleByProvider` passes
   `enforceBookingWindow: false` (§23.1). That falls out of the exemption rather
   than needing its own mechanism.

## 26. Every surface that shows a bookable range

Fifteen, so that no sweeping assertion is written against a list that was never
enumerated. **Bound by the window:**

| # | surface | today |
|---|---|---|
| 1 | mobile `SlotPicker` day picker | `today + horizon`, default 365; **neither call site passes `horizon:`** |
| 2 | mobile hub earliest-slot scan | 15 sequential requests, `daysAhead: 14` |
| 3 | web consumer funnel date input | `min` only |
| 4 | web consumer reschedule | `min` only |
| 5 | web `findEarliestSlot` | `for (let i = 0; i <= 14; i++)` |

Both earliest-slot scanners are **search windows, not policy bounds**, and with
a per-salon window they become wrong in both directions — a 7-day salon burns
requests past its own horizon; a 60-day salon reports « aucun créneau » when it
is merely quiet for a fortnight. Both are clamped to `min(14, horizon)`.

**Exempt, and named so a sweep does not fail on them:** the pro's manual booking
(90 days, `bookManual` never reaches the slot engine), the pro journal
reschedule picker, the pro blocked-date picker, the pro journal day-jump (bounds
are relative to the *selected* day, so it walks forward indefinitely — navigation,
nothing written), the pro calendar month grid (±365), the dead
`booking_journal_screen`, the web pro journal navigator, and the public browse
route itself.

**Two web pro surfaces are already the hostile-client shape by design** —
`JournalPanel` and `ProAppointmentDetailClient` free-type a date and a time and
POST with **no slot fetch at all**. Nothing bounds them today and nothing bounds
them after A14d; for those two the server verdict is the only control, which is
exactly why the authority is server-side.

## 27. Tests

**Watched red first, every one.** The specific traps this slice must prove
against:

- **the round trip, not the 200.** A PUT carrying the new fields must be
  readable back with those values. Against today's allow-list this fails while
  the request succeeds — which is the whole point.
- **`days: 7` is the repo-wide fixture convention in six places.** Any default
  horizon below 7 breaks unrelated suites; 365 is safe, and this is recorded so
  the number is a decision rather than a coincidence.
- **the empty-list shape**, so browse still answers 200 `slots: []` and not 404.
- **the two 409s**, each asserted by status *and* code, because the missing
  `case` would silently make them 400 (§21 ①).
- **`enforceBookingWindow: false`** on both pro paths — asserted by a pro
  reschedule succeeding beyond the horizon that refuses a consumer.
- **the three unexercised route branches** (401/403/405) and the **absent
  cross-tenant test** for `replaceAvailability`.
- **the past-day and lead-time siblings have no test at all** — both get one
  while the third is added beside them.
- **the mock must mirror the API.** `mock_appointment_service.dart` recomputes
  the slot engine client-side; every mobile widget and unit test runs against
  it, so a gate that passes on the mock and fails on the server is worse than no
  gate. `availability_buffer_test.dart` is the existing seam that drives a pro
  setting and asserts on consumer slots, and it is the shape to copy.
- **falsifiability** for each new gate, per row 67.

## 28. Open questions

- **A pro-facing list of bookings now outside the window.** The owner chose
  grandfathering over flagging; a « ces rendez-vous dépassent votre limite »
  view is a real pro surface and a slice of its own, not a side effect.
- **Un-publishing an unbookable salon** (§20.2) — a pre-existing `publishGate`
  gap, recorded, not widened.
- **`GET /providers/{id}` has no public-field allowlist** and returns the entire
  document. The window rides to the client free, which A14d depends on (§24),
  but the absence of an allowlist is its own security question and is not
  A14d's to answer.

---

# Part E — A14e, blocking dates in bulk

## 29. Goal & scope

**Register row 78.** Blocking a week cost a week of round trips: the pro picked
one day, confirmed, and the app wrote — then repeated. Each write is a `DELETE`
of the salon's entire availability plus a re-insert of four tables, so
« bloquer les fêtes » was fourteen of those.

**Toggle, not range, and not a rule.** A range cannot express « tous les
dimanches d'août » at all, and a recurring rule is a different data model —
`blockedDates` is a list of days. Toggle is the only single mode that expresses
both real jobs and the only one that fits what exists. Range mode and recurring
closures are refused **on the record**; what would reopen them is a
`blockedRules` field, not a picker change.

## 30. The delta, and the erasure it makes impossible

`showMyweliMultiDatePicker` returns **`({Set<CalendarDay> added, Set<CalendarDay>
removed})`** — what changed, never what is held.

**The reason is a silent, permanent data loss.** The picker's `firstDate` is the
salon's today, so `MyweliMonthGrid._enabled` refuses every earlier day: a past
blocked date cannot be in a selection, and seeding one would paint it selected
and inert. A page handed a full set would have to *remember* to re-merge the
days the picker never showed — and forgetting deletes them, on the first save,
with no error and nothing on screen to notice, because the server replaces the
whole set.

A delta cannot express the days it did not show. Four consequences follow, and
they are why this shape was chosen over a set:

1. **Correctness stops depending on the seed.** A future change to `firstDate`
   cannot reintroduce the bug.
2. **It matches the gesture.** The pro toggles days; a full set would make a
   screen that rendered one month assert authority over a year.
3. **The confirm copy falls out of it** — « 3 ajoutées · 1 retirée » is two
   lengths. With a set the page must diff in order to *speak*, and if it must
   diff to speak it may as well diff to write.
4. **The empty selection stops being ambiguous.** `_selected.isEmpty` means
   « unblock everything » or « nothing to do » depending on history; the delta
   distinguishes them, and §31 shows why that matters.

The composition lives in `core/utils/blocked_dates.dart` as a top-level
function, not a private method, so it has a test subject that is not a widget
pump — §16 records what the alternative cost. Survivors keep their **original
stored instant** (a day this write is not changing must not be rewritten into a
flavour it did not arrive in); only genuinely new days go through
`salonDateTime`, per §18. Matching is `CalendarDay.of(toSalonTime(...))` and
never `Set<DateTime>`, whose `==` compares `isUtc` and would silently match
nothing across the three flavours the list can hold.

**Watched red twice, and mutated twice.** `return fresh` reddens four of six
unit tests including the erasure one; dropping the `removed` filter reddens a
*different* test while the erasure one stays green — which is what proves the
pair is not one assertion wearing two hats. And the property is asserted again
end-to-end, on what the **service** receives, because it survives `copyWith` →
`toJson` → the wire or it does not survive at all.

## 31. One confirm, named by direction

**Adding always confirmed and removing never did** — the guard was on the safer
half. A14a restored the add dialog deliberately, because the single picker pops
on first tap and the write is immediate and un-undoable; that justification is
satisfied by a screen with its own labelled commit button. It does not carry,
for one reason: the gesture can now **unblock**, and unblocking is the direction
that produces an unwanted booking.

> **Every write to `blockedDates` passes exactly one confirm. The verb names the
> direction. The rung is set by the worst half present.**

| change | title | confirm | destructive |
|---|---|---|---|
| add, n = 1 | « Bloquer cette date ? » | « Bloquer » | yes |
| add, n > 1 | « Bloquer ces dates ? » | « Bloquer N dates » | yes |
| remove | « Débloquer cette date ? » / « ces dates ? » | « Débloquer » | **no** |
| mixed | « Modifier vos dates bloquées ? » | « Enregistrer » | yes |

n = 1 names the date and n > 1 gives a count: enumerating three dates would be a
third place the same information lives, and the grid and summary bar are both
better at it — but losing the named date in the commonest case would be a copy
regression, so the singular branch keeps A14a's exact sentence. Pure removal is
`isDestructive: false` because opening your calendar destroys nothing, and
`ConfirmDialog`'s own docstring warns that red on a non-destructive action
dilutes the signal. Mixed commits with **« Enregistrer »** because no single
verb names both directions and picking either would misname half the change —
recorded because it looks like the lazy answer and is not.

## 32. The screen

`Scaffold` + close leading + `SafeArea` + `MyweliMonthNavigator` + a bottom
summary bar and a full-width `AppButton`. The one structural difference from the
single picker is the one that matters: **it cannot pop on tap** — selecting is
not submitting.

**Already-blocked days paint through `selectedDays`, not `markers`.** « Already
blocked » and « just chosen » are the *same* fact here — this day will be
blocked when I save — so one paint says both. A marker would also be **stale by
construction**: tapping an already-blocked day deselects it, and the dot, drawn
from `availability.blockedDates`, would still assert « blocked » while the
intent is the opposite.

**The enablement trap.** `onPressed: _selected.isEmpty ? null : …` reads
sensibly and makes « tout débloquer » unreachable: the pro deselects their last
blocked day and the button dies with the change unsaved. Gated on the **delta**
instead — one rule, both cases right — and both halves of the pair are asserted,
because « always enabled » is a different bug wearing the same green.

**The blocked-date picker keeps its full 365-day range**, deliberately, even
though A14d may make days past the salon's horizon unbookable. Blocking is
*planning*: a salon may mark Christmas while its window is 30 days and widen it
later, and the write is harmless either way. Recorded so a future sweep does not
"fix" it into agreement.

## 33. A14b's open question, answered by measurement

§14 left `_PickerField`'s row honestly unresolved: *"Whether « 15/01/2024 » at 2×
wraps or overflows depends on the ICU break opportunity at `/`. **Not
measured.**"* The spec's line reference had also drifted — the row is `:308-328`
and the class `:415-451`, not `:243-263`.

**It overflows: 49 pixels, three of six configurations.** Measured by pumping the
screen with `initialDateTime` set, because the placeholders — « Date » and
« Heure », four and five characters — fit at any scale and would have passed
vacuously, which is the exact failure mode this campaign hit four times. The
`Text` is now `Expanded` and wraps.

## 34. What A14e does not do

- **Range mode and recurring closures** (§29), refused on the record.
- **Un-blocking a day that already has bookings** does not warn. The precedent
  is A14d's: nothing in this codebase re-validates a stored appointment against
  availability, and blocking a day has never cancelled its bookings either.
  Naming it here so the silence is a decision rather than an oversight.
- **`docs/modules/online-booking.md`** remains an honest, pre-existing gap.

---

# Part F — the device run (A14)

## 35. What a phone said about A14, and the outage it found

Same instrument as every prior run, and §21 row 63 is why there is one at all:
*"a golden is a picture of a tree the test built, and a device is the only
instrument that renders the tree the product builds."*

**Provenance.** The repo's `A11 360dp` simulator — an iPhone 13 mini profile at
the **360×780pt** floor A11 pinned, not the stock 375×812 — with
`xcrun simctl ui … content_size accessibility-large`, ≈ **1.95×**. Both apps in
**debug** (the striped overflow banner is debug-only; row 63), both built with
`--dart-define=USE_API_BACKEND=true` against `dart_frog dev` on `:8080`. Route,
as a tap chain: **pro** — e-mail OTP → Tableau de bord → « Disponibilité » →
« Fenêtre de réservation » → « Gérer les dates bloquées » → back → « Rendez-vous »
→ « Ma journée » → the **Calendrier** tab → « Nouveau rendez-vous »; **consumer**
— `/provider/{id}` → « Réserver » → « Date et heure » → the date picker → the
slot grid → « Confirmer ».

Unlike A14a's and A14b's runs this one was driven **pro → server → consumer on
one live backend**, because that is the only way a horizon set in one app can be
read back in the other. The fixture (`device.run@salon.test`, salon
« Salon Test A14 ») lived in the dev server's memory and **nothing about it is
committed**.

### 35.1 The outage — an open window is a range, and two engines read it as a minute

The whole reason the campaign's plan insisted on a live round trip.

`SlotService._openMinutes` enumerated each `weeklySchedule` entry's `startTime`
and **discarded its `endTime`**. That is correct only if the template holds one
entry per 30-minute step — eighteen of them for a 09:00–18:00 day, which is what
`seedProviders`' `_defaultWeeklySchedule` builds.

**Who actually writes what.** `draftSalonDocument` gives a fresh registration an
**empty** `weeklySchedule`, so a salon is closed every day until its owner
authors hours — in the pro app's day editor, or in the web dashboard's
« Disponibilités » (`web/lib/pro/availability.ts`'s `toApi`). Both store **one
entry per range the owner enters**: « 09:00 – 18:00 » is one entry. Nothing
*forbids* eighteen — the day editor appends without a cap or a merge, and the
server checks only `start.isBefore(end)` per slot — but nothing authors them
either, and outside the two fixtures the shape has never existed.

Nor did it take an exotic day. Measured against the engine, same service, same
day:

| the day's `weeklySchedule` | 30-min service | 60-min service |
|---|---|---|
| one entry `09:00 → 18:00` — what both editors write | **1 slot** (09:00) | **0 slots** |
| two entries `09:00 → 12:00` + `14:00 → 18:00` — a lunch closure | **2 slots** | **0 slots** |
| eighteen entries `09:00→09:30 … 17:30→18:00` — the fixtures | 18 | 17 · *unchanged by the fix* |

The 30-minute column is the tell: nine open hours offering one start means the
end was never read, and the split day — the most ordinary schedule a salon has —
offered two. The consequence is a **silent booking outage**: the first time a
salon authored its own hours, every service lost almost all of its starts and
anything longer than one step lost all of them, so the client saw « Aucun
créneau ce jour-là » on every open day with no error on either side to say why.

**It was in two engines, not one.** `mock_appointment_service.dart` mapped each
template entry to `s.startTime` and never touched `s.endTime` either — the same
code, made invisible by the same thing, because `MockData._generateTimeSlots`
emits one entry per step just as the server seed does. The device run found the
server half; the **adversarial review of this section** found the app half, which
would otherwise have left « closed » true of one surface and false of the
product.

**Fixed on both** ([SYSTEM.md §21](SYSTEM.md#21-the-register) row **83**) by
enumerating `[start, end)` in steps, which is strictly a superset: an entry
exactly one step long still contributes exactly its own start, so the fixtures'
eighteen stay eighteen and « 09:00 and 14:00 only » stays two. Each engine has a
red-first gate plus a paired guard that was green throughout and is what stops
the fix degenerating into « every day is open all day » —
`slot_service_test.dart` (**watched red at `[540]`** against the eighteen it
expects) and `mock_open_hours_test.dart` (**red at `[540]`**, and at
`[540, 840]` for the split day against the fourteen it expects).

**What "nothing could see it" actually means**, because the first draft of this
section overstated it and the review caught that. Backend tests *do* build a
single multi-hour window — `provider_catalog_test.dart:153`,
`db/postgres_repositories_test.dart:566`, `salon_lifecycle_test.dart:97` — but
every one of them asserts **storage**, that the PUT round-trips. Not one asserts
a **slot count** against that shape, and every test that does assert slot counts
is seeded from a fixture that holds the eighteen-entry shape. The blindness was
not « no test used the shape »; it was « no test asked the engine a question the
shape could answer wrongly », which is the more useful lesson and the harder one
to notice.

### 35.2 A14's own surfaces, held

| what a prior slice recorded | what the device showed |
|---|---|
| row 73: Material's picker rendered « **2 21 2 2 2 2 2** » on this phone | **20 21 22 23 24 25 26** — every day whole, re-photographed where row 73 was found |
| row 77: Flutter's time picker « refuses to scale » | `MyweliTimePicker`'s two labelled columns, « 17:50 » preview, « Confirmer » pinned — every number whole |
| row 62's salon header, which A14a's run first saw stacked | **stacked** again on the API backend and a different salon — logo above name, « Salon Test A14 » wrapping to two lines, no mid-token break |
| A14b's `Expanded(child: Text(label))` on the manual-booking row | « 12/08/2 / 026 » **wraps inside its button** and « Heure » keeps its width — no overflow |
| row 76: the salon now owns its window | pro set « **1 mois** » → the consumer picker disables **31 août** and greys the « › » chevron; september is unreachable |
| A14e's delta write | the pro's mixed delta (`−31 juillet, +14 août`) reached the server, and the consumer funnel answered « Aucun créneau ce jour-là — Ce salon n’a plus de disponibilité le **lundi 3 août 2026**. » |

A14e's multi-picker at 1.95× carries its worst case with room: **août 2026 is a
six-row month**, and the grid, a two-line summary (« 3 dates bloquées » /
« 1 ajoutée · 1 retirée ») and the full-width « Enregistrer » all fit above the
safe area with ~13pt to spare. « Enregistrer » is **inert** on an empty delta and
live the moment anything changes; a re-opened picker paints its seeded days
selected; and all three confirm dialogs — add, remove, mixed — fit without
scrolling.

**Also confirmed on the same screens, none of which a computed gate asserts:**
the weekday row Monday-first as `L M M J V S D`, French month names
(« juillet 2026 », « août 2026 »), the disabled « ‹ » at the range start and the
disabled « › » at the horizon, today painted as a **ring** and a chosen day as a
**fill**, the blocked-date cards in **chronological** order (A14e's sort, which
nothing photographs), every slot time whole in the grid — which laid out three
chips per row at this width, though that is a `Wrap` finding its own line breaks
and not a declared column count — and curly apostrophes throughout (« n’a »,
« Aujourd’hui »).

### 35.3 What the run found and did not fix

Recorded rather than repaired, because each needs a product decision or a change
wider than a device run should carry. Rows **79–82** of
[SYSTEM.md §21](SYSTEM.md#21-the-register) hold them.

- **App-bar titles ellipsize, and at 1.95× the actions crush them.** Three
  instances in one session: « Dates à bloquer » → « **Dat…** » the moment
  A14e's « Réinitialiser » action appears, « Tableau de bord » → « **Tableau de
  b…** », « Nouveau rendez-vous » → « **Nouveau rendez…** ». The last has **no
  actions at all**, so this is not only a crowding problem and the fix is not
  only « move the action » — it is §13.3 asking what an `AppBar` title should do
  when it cannot fit. Row **79**.
- **`appointment_calendar_view._emptyDay()` hand-rolls an empty state.** No
  padding and no `textAlign: TextAlign.center`, where the shared `EmptyState`
  has both. At 1.95× « Aucun rendez-vous » wraps with line two left-aligned
  under line one, and « pour vendredi 31 juillet 2026 » runs edge to edge with
  ~3pt of inset. Separately — and **not** something adopting `EmptyState` would
  fix, because it has no FAB inset either — the branch is a
  `SliverFillRemaining(hasScrollBody: false)` with no bottom padding, so its
  last line is the bottom of the scroll extent and cannot be moved clear of the
  FAB. Row **80**.
- **The pro journal offers the same action twice and they collide.** The empty
  state's « + Nouveau rendez-vous » and the extended FAB « + Nouveau » do the
  same thing, and at 1.95× the FAB's top edge sits ~3pt inside the CTA so the
  two black surfaces read as one broken control. Dropping one is a product call.
  Row **81**.
- **A salon that is not yet `active` fails with « Une erreur est survenue. »** on
  *both* sides. `provider_suspended` (409) is the code for a never-published
  draft as well as a banned salon, and neither the consumer funnel nor the pro's
  own manual-booking screen has a sentence for it — so the very first thing a
  newly registered salon owner tries ends in a bare generic error, on a dashboard
  whose go-live card is meanwhile inviting them to « Complétez les étapes pour
  aller en ligne ». Row **82**.

### 35.4 What this run did not cover

- **Completing a booking, and therefore chain A.** The run's fixture is a salon
  created through registration, so it is `status: 'draft'` and the server refuses
  both the consumer write and the pro's manual booking with `provider_suspended`
  — correctly. Going live is one call, `POST /providers/{id}/publish`, but
  `SalonProvisioningService.publishGate` holds it behind a checklist of five
  keys covering seven conditions: `profile` (a description, an address and a
  resolvable commune), `location` (map coordinates), `services` (**three**
  active), `photos` (**three**), and `availability` (at least one open day).
  Satisfying it is salon-onboarding work, not device-run work, so the fixture
  stayed a draft. **A14b §13.1's reschedule debt is therefore still open**, and
  it is now open for a *different* reason than the one A14b recorded: not *"the
  seeded salon had none"* but *"this run's salon cannot have one"*. The weaker
  artifact standing in its place is unchanged — `reschedule_screen.dart`'s and
  the pro journal's widget tests, plus the combined picker's own goldens.
- **Two of A14d's four empty reasons, and the run saw fewer distinct ones than
  it first appeared to.** `_EmptyReason` has four members
  (`past`, `beyondHorizon`, `tooSoon`, `full`), and `full` is the documented
  catch-all: it absorbs closed weekdays, blocked dates and genuine capacity
  alike. So the blocked 3 août and the outage-emptied 5 août rendered the **same
  branch** with the same title, and the run exercised **one** of the four, plus
  `past` only implicitly through disabled cells.
  - **« Trop loin dans le temps »** (`beyondHorizon`) is **not reachable by
    navigation**: the date picker's `lastDate` *is* the salon's horizon, so a
    beyond-horizon day cannot be selected. The branch answers a stale selection
    or a horizon shortened under a client that already had a later date.
  - **« Réservation trop proche »** (`tooSoon`) was never reached either — the
    fixture's notice was the 60-minute default and the run never asked for a
    slot inside it.
- **The seeded salons' images.** Every seeded `imageUrls` entry points at
  `asset:assets/images/barber1.jpg` and friends, and `mobile/assets/images/`
  ships only `providers/` and `stories/` — so in API mode every discovery card
  renders Flutter's red « Unable to load asset » box in debug. Noted, not filed:
  it is dev-fixture data, and a real salon uploads its own images.

### 35.5 What the adversarial review of this section changed

Recorded because the practice is the point: **84 claims from §35 and rows 79–83
were re-checked against source by verifiers told to refute them.** 48 held, **26
were over-reads by the verifiers themselves and were rejected on cross-check**,
and ten survived — of which the load-bearing one was that
`mock_appointment_service.dart` carried the same defect the server had, so
« closed » was true of one engine and false of the product. Also corrected here:
a **table cell that read 17 where the engine returns 18**, an « impossible
shape » that is merely an unauthored one, a **second writer of that shape on
web** that the section had not mentioned, a « no test could see it » that was
false as written, an `AppBar` `maxLines` that Material never sets, an
`EmptyState` credited with FAB clearance it does not have, and a
`consumer_reschedule` that is not the name of any file in this repo.
