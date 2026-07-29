# A14 — our own date & time pickers

| | |
|---|---|
| **Status** | Draft |
| **Owner** | Sadreddine Daher |
| **Last updated** | 2026-07-29 |
| **Register row** | [SYSTEM.md](SYSTEM.md) §21 row 73 |
| **Skills checked** | `myweli-dev-guardrails` |
| **Preceded by** | [A12 — the fixed-box sweep](mobile-a12-fixed-boxes.md) · [A13 — copy & breaks](mobile-a13-copy-and-breaks.md) |
| **Scope** | **A14a** (this PR) — the date picker · **A14b** — the time picker + combined sheet · **A14c** — retire `table_calendar` |

---

## 1. Goal & scope

**Row 73, verbatim on the part that matters:** *"at `accessibility-large`
(≈1.95×) on a 360×780pt iPhone, Material's `showDatePicker` calendar renders
**20, 22, 23, 24, 25, 26 as a single digit** — « 2 21 2 2 2 2 2 ». Only 21
survives, because « 1 » is narrow."*

Found on hardware during A12's device run. **Row 73 is one of the accurate
ones** — its cause, its exoneration of our theme, and its five call sites all
check out, which is unusual enough in this register to say out loud.

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
- **two digits fit the width comfortably.** At 2× `bodyMedium` is 28px; Roboto's
  digit advance is ≈0.5566 em, so « 28 » is ≈31.2dp of glyph plus 0.5 of
  tracking — under 32dp inside a 46.9dp cell.

So the month grid is expected to **survive** at 360 × 2×. The list reflow stays
specified because §3's measurement, not this arithmetic, decides.

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

### 2.2 The tap-target floor is unreachable horizontally, and that is not new

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

So A14a adds `expectDayNumbersWhole` (working name), and — because §21 **row 67**
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
| **`childAspectRatio` — prohibited outright, no allowlist** (`design_system_pin_test.dart:517-555`): *"a tile height derived from its WIDTH cannot grow with the text inside it"* | the obvious way to make square day cells | `mainAxisExtent`, computed from the scaled line |
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
- **primitives** — `expectDayNumbersWhole` proven falsifiable, per row 67.
- **golden** — the **first picker golden in the repo**, at 1× and 2×. Regenerated
  with `./tool/update_goldens.sh` (Linux-only — a Mac-authored golden fails CI
  forever), ledger from `git status --short`, **every changed PNG opened**.
- **unit** — `Formatters.formatDate`/`formatDateShort` have **no test today**
  (`formatters_test.dart` covers six other formatters); the new weekday helper
  arrives with one, and the two existing gaps get filled since the calendar
  stands on them.
- **device** — `accessibility-large` on the simulator that found row 73. A
  computed gate is not the same evidence as the screenshot the row is about.

**One more hole this slice stands on:** the booking-hub subject
(`layout_test.dart:588`) — the screen the picker launches from — is one of four
missing `expectNoVerticalClip`. A14a adds it.

---

## 7. Open questions

- Does `_WeekStrip` itself overflow at 360 × 2×? Its pill is 48dp at 2× in a
  slot of ≈46.9dp, which is the same arithmetic that forces this spec's
  rounded-rect cell. **To be measured** — if it does, it is a defect in the
  precedent this design copies, and gets its own row rather than a silent fix.
- Multi-select for `availability` (blocking a week is five dialogs today) — a
  product question, deliberately out of A14a.
