# mobile-a11-width — one width is not every width (A11)

| | |
|---|---|
| **Status** | Draft (2026-07-28) |
| **Surface** | `mobile/` — the compact range, and the §10 rule nothing implemented |
| **PRD ref / phase** | FR-A11Y-001 · NFR-PERF (low-end Android) · **V1** |
| **Design system** | [SYSTEM.md §10](SYSTEM.md#10-layout-breakpoints-content-width-z-index) · §13.2 · §13.3 · §20 · §21 rows 40, 49 |
| **Mirror** | [WEB-SYSTEM.md](WEB-SYSTEM.md) §9 · §15 **row 1** — *"Layout works at every width"*, closed in **B0** |
| **Skills checked** | myweli-dev-guardrails · myweli-web-guardrails (the token mirror) |

## 1. Goal & scope

The design system has been designed, gated and photographed at **exactly one
device width**. The reasoning is written down, in the golden harness:

> `test/support/golden.dart:40-41` — *"A phone. The apps have no breakpoints
> (SYSTEM.md §10), so this is the only surface that matters today."*
> `const Size kGoldenPhone = Size(390, 844);`

**That inference is invalid, and it is the whole slice.**

§10's own table defines `compact` as a **range** — `< 600`, with no floor. The
sentence below it, *"There are zero breakpoints in the apps today"*, is a
statement of fact about the code, not a licence. And it points the other way: a
layout that **cannot adapt** has to work across the whole range, precisely
*because* it cannot adapt. The code read a range as a point, and picked the widest
phone in it.

### The three measurements

- **`test/a11y/` pins no surface at all.** Every assertion there runs at
  `flutter_test`'s default **800×600** — wider than any device this product ships
  on. §20 calls that gate "complete".
- **§20 has no Layout row.** §10 is the only substantive section in the document
  without a gate. That is exactly the condition §21 row 35 diagnoses for §17 —
  *"the only substantive section with neither a rule nor a §20 row, and the copy
  drifted exactly as that predicts"* — and the same thing happened here.
- **`contentMaxWidth = 720` has 1 mention in the docs and 0 usages in
  `mobile/lib`.** §10's one concrete number was never implemented, and unlike the
  web (which closed the identical gap as its own register row 7j) mobile has no
  row for it.

`PRD.md:126` names the target as *"Tecno/Infinix/Itel/entry Samsung … iOS is a
single-digit minority"*. **360dp is the modal device.** Nothing in 151 test files
has ever drawn this app below 390.

### In scope

A width gate across the compact range · the OTP row on both apps · two four-tab
bars · two section rows that fail at 200% · `contentMaxWidth` implemented · §10
gains a floor · §20 gains its first Layout row.

### Out of scope

- **The admin console.** A separate entrypoint (`main_admin.dart`), not reachable
  from either phone binary, and §10 names the reason itself: *"fine for the
  consumer app … and wrong for admin."* Its own `< 1000px` degradation is promised
  by `admin-console-ui.md:29` and unimplemented — filed, not fixed here.
- **`screens/provider/features/`** — `booking_journal_screen.dart:72` has the
  cleanest 390→360 grid regression in the repo and is **unrouted**; A10 already
  shelved the directory under §22.
- **320dp.** Six 48dp OTP boxes cannot fit 320 under any padding. Declared out of
  contract rather than half-supported.

## 2. ⚠️ The correction this spec has to make about itself

A11 was recommended on the claim that the OTP overflow meant *"every first-time
user on a 360dp Tecno meets a broken login gate, silently, in a release build."*

**That is false.** Both OTP screens are **unrouted**:

- `OtpVerifyScreen` is referenced nowhere outside its own file;
- `PhoneLoginScreen`, its only caller, is itself unreferenced;
- `phone_login_screen.dart:57` pushes `/verify-otp?phone=…` — **a path
  `app_router.dart` never declares** (its routes are `/splash /login /home
  /providers /provider/:id /booking… /bookings /appointment/:id /profile
  /notifications /a-propos /favorites`);
- pro's is documented as deliberately kept — `pro_router.dart:61-62`,
  *"`ProOtpVerifyScreen` kept for the Termii-era phone verification reuse."*

The overflow is real, reproduced on both apps, and worth fixing: this is live,
analysed, pin-tested code kept for a planned flow. But it is **the proof case, not
the headline**, and the register row says so. Writing it up as a shipped
user-facing defect would repeat exactly the error §21 row 37 records, where a CI
log was read instead of a build being reproduced.

**The reachable defects are the tab bars and the 200% cases.**

## 3. What is broken, measured

| Site | Arithmetic | Confidence |
|---|---|---|
| `otp_verify_screen.dart:232,336` · `pro_otp_verify_screen.dart:151,182` | 6×`Container(width: 50)` + 40 margins + `EdgeInsets.all(spacingL)` = **388dp**. Overflow **13@375 · 28@360 · 68@320** | **reproduced, both apps** |
| `earnings_screen.dart:99` | 4-tab `TabBar`, no `isScrollable`. Flutter wraps each tab in `Expanded` with `kTabLabelPadding` 16/side, so text room is `W/4 − 32` = **58@360 · 65.5@390** against « Aujourd'hui » ≈85dp — **it clips at 390 too** | computed **and photographed** (§21 row 40, A10's golden) |
| ↑ *corrected by C2* | the box arithmetic is exact — the gate measures **58.0@360 · 61.8@375 · 65.5@390**. The label estimate was not: « Aujourd'hui » in Roboto 14/w500 is **72.2dp**, not ≈85. The conclusion survives, because 72.2 > 65.5 | **measured** |
| `appointment_list_screen.dart:180` | the same bar, four French labels, **nested under** the 2-tab bar at `:120` | computed |
| `my_bookings_screen.dart:74` | 3 tabs — fits at 1×, **truncates at 2×** | computed; the case a width-only census misses |
| `home_screen.dart:259,352` · `reviews_screen.dart:108` | fit at 1× on ~12dp and ~32dp of slack; **cannot fit at 2×** | red at 2× either way |

Structural facts behind all of it: **`isScrollable` appears 0 times** across four
`TabBar`s · **`FittedBox` appears 0 times** in `lib/` · there is **no breakpoint
helper of any kind** (`LayoutBuilder` exists at three sites, none a width tier).

**The in-repo precedent.** `pro_journal_screen.dart:556-557` already hit this exact
class and fixed it:

> *"§13.2: fills its `Expanded` 1/7 slot (≥48 on normal widths …). A fixed
> `minWidth:48 × 7` overflowed narrow phones."*

A comment, and no test. A11's job is to give that comment a gate — and to adopt
its shape rather than invent another.

### 3.1 What C2 actually measured

48 pumps — 8 subjects × {360, 375, 390} × {1×, 2×}. **21 green, 27 red**, and
every red was named in the plan before the file was run:

| Subject | Red at | Assertion | Measurement |
|---|---|---|---|
| both OTP screens | 360, 375 · **both scales** | overflow | **28px@360 · 13px@375**; fits at 390 by 2dp |
| `earnings_screen` | **all three widths** · both scales | truncation | « Aujourd'hui » 72.2dp in 58.0 / 61.8 / 65.5; **143.4dp at 2×** |
| `appointment_list_screen` | **all three** · both scales | truncation | identical box arithmetic, one screen over |
| `my_bookings_screen` | all three · **2× only** | truncation | « Passés » 91.9 in 88.0@360 · « Annulés » 102.0 in 93.0@375 |
| `home_screen` | all three · **2× only** | overflow | the `:259` heading row overflows by **807px** at 390×2 |
| `reviews_screen` | **360 × 2× only** | overflow | **4.3px** — the `SizedBox(width: 100)` bar that will not grow |
| `LegalConsentText` | — | — | **green at all six** — §8's open question, answered |

Two estimates in the table above were wrong in the same direction and neither
changed a verdict: `my_bookings` and `home` were predicted to break at 360×2 and
break at **every** width at 2×; `reviews` was predicted to fail more widely and
fails only at the floor.

**The gate's first run was wrong, and the reason is worth more than the run.**
It reported « Semaine », « À venir » and « Annulés » as clipped — three different
seven-letter words, all measuring **98.7dp to a tenth of a pixel**. That is
`flutter_test`'s fallback typeface, which draws every glyph as a square of the
font size. Roboto puts them at 55.3, 44.1 and 51.4dp; all three fit. So
**`test/a11y/` had been measuring a font the product does not ship** — invisible
to every assertion it made until now, because contrast, tap targets and
"did the height grow at 2×" are all relative or non-textual. A width gate is the
first absolute one. `pumpAtWidth` now pins `AppTheme.themeData(fontFamily:
kRealFont)` and refuses to run unless `loadRealFonts()` has been called.

**And the loop position was verified, not asserted.** Collapsing
`for (w) testWidgets` into `testWidgets { for (w) }` makes the OTP screen report
its overflow at 360 and **report nothing at 375, while still broken** —
`_overflowReportNeeded` latches once per render object. The probe output is
quoted in the file's docstring.

### The rule §13.3 states, and the twin it never wrote

> §13.3 — *"**A box that contains text may not have a fixed height.**
> `SizedBox(height: 50)` around a `Text` is a clip waiting to happen."*

Every bullet in §13.3 is vertical. There is no width analogue anywhere in the
document — and the OTP box is `Container(width: 50, height: 64)` around a
`TextField`. It violates the **written** rule as well as the unwritten one, and
neither was caught, because **no screen is in any a11y inventory**: `test/a11y/`
pumps eight components and zero screens.

## 4. Architecture & patterns

### 4.1 The gate

`test/a11y/layout_test.dart`, named for the section it gates (the house
convention: `motion_test` → §9, `field_error_test` → §14). Shared machinery joins
`test/a11y/_a11y.dart` rather than forking it.

`test/a11y/` is **platform-agnostic** (no `kGoldensSkip`) and must not import
`golden.dart`. So the shared machinery moves out of it into `test/support/`, one
file per job, and `golden.dart` re-exports each — one implementation, zero churn
across its 12 call sites:

| moved | to | why the a11y suite needs it |
|---|---|---|
| `goldenSurface`'s body → `pinSurface` | `surface.dart` | a width gate that does not pin a width is not a gate (C1) |
| `stubSecureStorage` | `secure_storage.dart` | `setupDependencyInjection()` wires `SecureSessionStore` (`dependency_injection.dart:101`) — the channel is reached whether or not a picture is taken |
| `settleMocks` | `settle.dart` | the mocks sleep 300ms and `BrandLoader` never settles; its own docstring counts 16 files that hand-rolled it before goldens existed |
| `loadGoldenFonts` → `loadRealFonts` | `fonts.dart` | see §3.1 — an absolute width assertion against the fallback font is meaningless |

**C2 corrected the "must not import `dart:io`" half of this rule.** `fonts.dart`
imports it, and has to: the SDK font cache is on disk. The substantive rule is
that a11y assertions must not be *platform-conditional*, and font **metrics**
are not — advance widths come from the font file through the same shaper
everywhere. It is **rasterisation** that differs by platform, which is why
goldens are Linux-only and this gate is not.

**Subjects are SCREENS**, with the components riding along. All five measured
defects are in screens and **none is in a component** — a gate that pumped the
existing eight-component inventory at 360 would be **green at base**, which is the
vacuity §20 already names twice (`text_scale_test`'s *"unbounded, nothing can
overflow and the gate is vacuous"*, and A8's four gate commits that all pumped
`BrandLoader`).

### 4.2 Three harness facts it must respect

1. **`_overflowReportNeeded` latches once per `RenderObject`, ever**
   (`debug_overflow_indicator.dart:127,327-328`; only `reassemble()` resets it).
   `pumpWidget` of the same tree retains the render objects, so a width loop
   *inside* one `testWidgets` leaves widths 2 and 3 **silently unmeasured**. The
   loop goes **outside**: `for (w) for (s) testWidgets(...)`.
2. **Overflow reports from `paint`, not layout** (`flex.dart:1315,1364`). A flex
   scrolled out of the first viewport never reports. The gate proves *"the first
   viewport at these widths"* — a bound stated in the docstring and in §20's row,
   the way the web's own spec states its tracking limit. Mitigated by pumping at
   `height: 1600` and by dragging where the defect is below the fold.
3. **`MediaQueryData.size` is the wrong mechanism.** It changes what widgets
   *read* without changing what the tree is *constrained to*, so a `Row` would
   still lay out at 800 and the gate would be green against every defect it
   exists to catch.

### 4.3 The two assertions `takeException` cannot make

- **`expectNoUndeclaredTruncation`** — a clipped label is not an overflow.
  Walks every `RenderParagraph`; flags any that is not `TextOverflow.ellipsis`,
  cannot wrap (`softWrap: false` or `maxLines != null`), and whose `size.width <
  getMaxIntrinsicWidth`. **Tight rather than noisy, and measured**: `lib/` has
  **0** `TextOverflow.fade/.clip/.visible`, **0** `softWrap:`, and all 46
  `TextOverflow` sites are `ellipsis` — so the only paragraphs it can fire on are
  framework-supplied, and `Tab` is exactly one (`tabs.dart:183` — `softWrap:
  false, overflow: fade`).
- **`expectGrowsWithTextScale`** — already in `_a11y.dart`, and the assertion that
  proves a fixed height is gone. A fixed bound does not overflow; it **clips
  silently**.

### 4.4 The OTP fix, and why `Expanded` rather than `width: 48`

The owner decision is *narrow the page padding*, and the arithmetic is exact:
`360 − 2×spacingM(16) = 328`; `328 − 40 of margins = 288`; `288 / 6 = **48.0**`.

Writing `width: 48` would satisfy it and measure **328 into 328 — zero slack**.
`RenderFlex` tolerates that (`_hasOverflow` is `_overflow > precisionErrorTolerance`),
so it passes today and re-opens silently on the next token nudge, at the exact
width the contract just promised.

`Expanded` makes 48.0 a **property of the layout instead of a coincidence**:
`(W − 32 − 40)/6` is 48.0@360, 50.5@375, 53.0@390, and cannot overflow at any
width. Same six boxes, same margins, same autofill, same floor at the floor — and
it is the `pro_journal_screen` precedent's own shape.

The padding change stays load-bearing: without it, `Expanded` at 360 yields
`(360 − 48 − 40)/6 = 45.3dp`, under §13.2, **silently**. Both changes, one commit.

One property `width: 48` has that `Expanded` does not: at 320 (out of contract)
fixed boxes overflow **loudly** where flexed ones degrade to a 41.3dp target
quietly. At a width §10 now declares unsupported, the quiet degradation is the
better failure — a tight but usable screen rather than a striped banner.

### 4.5 `contentMaxWidth`, and the blocking dependency

`AppTheme.contentMaxWidth = 720`, applied through **one** shared widget
(`ColoredBox` → `Center` → `ConstrainedBox`) wired into each root's
`MaterialApp.router(builder:)`. **Three lines, zero screens touched.**

- **SnackBars are unaffected** — `material/app.dart` wraps `ScaffoldMessenger`
  *above* `builder`, so §15's bars stay full-bleed.
- **Dialogs are capped**, because a dialog is a route under the Navigator. That is
  desirable and a no-op on a phone.
- **Admin is excluded.** §10 names the reason itself; a data-dense ops console
  wants its width. The exclusion is held by a **negative assertion**, not a
  paragraph that can drift.
- **No other exclusion list.** Web's row 7j exempts maps, journals and card grids
  because web *has* deliberately wide desktop designs; mobile has none — §10 says
  so — and capping a stretched phone column at 720 improves it. Copying web's list
  would be cargo cult.

> ### ⚠️ Adding the constant reddens a blocking **web** job
>
> `web/tests/tokens.mirror.test.ts:102-105` asserts `unclaimedDoubles` is empty —
> every `static const double` in `app_theme.dart` must belong to a family in
> `dart-tokens.mjs:356`. Its own failure message says so: *"add them to
> SPACING_KEYS/RADIUS_KEYS/ICON_KEYS … or they can never reach the web."*
>
> The web half — a `LAYOUT_KEYS` family, the `layout` export, `tailwind.config.ts`
> reading it instead of its hard-coded `'720px'`, and a mirror test — ships **in
> the same commit and is verified first.** §10's one shared dimension then becomes
> pinned identically on three surfaces, which is what row 19's generator exists for.

## 5. Testing plan

`subjects × {360, 375, 390} × {1.0, 2.0}` — roughly 54 `testWidgets`, no images,
each failure naming its own width and scale.

**Named reds, before running:** OTP ×2 @360/375 · earnings @360/375/**390** ·
appointment-list @all (the gate must **tap « Liste »** and assert the tap landed —
`TabBarView` builds lazily) · home + reviews @2× · the 1024 cap assertions ·
my-bookings @2×. `LegalConsentText` @375×2 is §21 row 49's open property —
**green there is a result to record, not a red to manufacture.**

**Green-at-base assertions get mutations too**, each failing *exactly one*:
reverting the OTP padding reddens only the six width assertions (proving the
padding is what buys the floor) · restoring `height: 64` reddens only
`expectGrowsWithTextScale` · dropping `isScrollable` reddens only the truncation
walk · `contentMaxWidth` 720 → 320 reddens the 390 assertion **and** the 26
goldens · and the **meta-mutation**: collapsing `for(w) testWidgets` into
`testWidgets { for(w) }` turns widths 2 and 3 green while the bug is present.

## 6. Rollout & scope discipline

Deploy order is irrelevant — this is app-only plus a token mirror. V1 only.

**Exactly one existing golden should move: `pro_earnings.png`.** The OTP screens
and `appointment_list_screen` appear in no golden, and `contentMaxWidth` is
analytically inert below 720 (a `ConstrainedBox(maxWidth: 720)` under a tight 390
constraint passes it through; `Center` on a tight-width child is the identity).
**The unchanged golden suite is the no-regression proof, and it is free.** Any
other diff means something changed that should not have.

## 7. Definition of done

- [ ] §10 states a **floor** and the admin exclusion; §20 gains its first Layout row
- [ ] `golden.dart:40-41` corrected — leaving it lets the next slice re-derive the
      same wrong conclusion from the same sentence
- [ ] §21 row 40 → 0, row 49 → 0 or **verified**, three new rows opened
- [ ] `flutter analyze --fatal-infos --fatal-warnings` = 0 · format clean · tests green
- [ ] web `tsc` · lint · vitest green, **including the new token family**
- [ ] every gate mutation-proven red before its fix
- [ ] the three new baselines eye-reviewed; the other 25 byte-identical
- [ ] **the OTP screen and both tab screens driven on a simulator at 360dp** — a
      gate that passes is not a screen that looks right
- [ ] Feature branch → PR → **the user merges**; no Claude attribution

## 8. Open questions

- **`Tab`'s framework `height: 46`** (`tabs.dart:189-233`) is a fixed height
  around text — §13.3's written rule, supplied by Flutter, with no override short
  of `Tab(height:)` at every call site. Measured headroom: `titleSmall` at 2× is
  40dp inside 46, so it survives 200% by 6dp and clips above ≈2.3×. Recorded in the
  shape of row 33 (*"platform limit — recorded, not fixable here"*) rather than
  papered with a fixed dimension of our own, which is A5's *"wrong fix for a fixed
  bound"* lesson.
- **The consumer phone-auth chain is unrouted and pushes an undeclared path.** A
  routing bug found by a layout census. Recorded; a routing slice should own it.
- **Should `test/a11y/` pin 390 by default**, rather than inheriting 800×600? It
  would make every existing a11y assertion a phone assertion — a strictly better
  gate, and a change large enough to deserve its own slice and its own red count.
