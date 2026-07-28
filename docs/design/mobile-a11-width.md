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

Structural facts behind all of it, *at the time of the census*:
**`isScrollable` appeared 0 times** across four `TabBar`s — C4 set it on the
three that clip, and recorded why the fourth keeps `fill` · **`FittedBox` appears 0 times** in `lib/` · there is **no breakpoint
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
| `home_screen` | all three · **2× only** | overflow | ~~807px~~ → **236 / 221 / 206dp** at 360/375/390 on the `:259` heading row. *The 807 was measured under the placeholder font, before `loadRealFonts` landed in this very slice* — corrected by C5, which also found that `compact_appointment_tile` does **not** overflow at any supported width (that 38dp was the same artefact), and that the screen throws **three** exceptions, not one: `:259`, `:352` (89/74/59) and `widgets/home/search_bar.dart:27` (75/60/45) |
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

### 4.4 The OTP fix — ⚠️ corrected by C3, after the code disagreed with the sums

**The arithmetic below was right and the code prescribed for it was wrong.** Both
are kept, because the wrong version is the useful half.

The owner decision is *narrow the page padding*, and the sums are exact:
`360 − 2×spacingM(16) = 328`; `328 − 40 of gaps = 288`; `288 / 6 = **48.0**`.

Writing `width: 48` would satisfy it and measure **328 into 328 — zero slack**.
`RenderFlex` tolerates that (`_hasOverflow` is `_overflow > precisionErrorTolerance`),
so it passes today and re-opens silently on the next token nudge, at the exact
width the contract just promised. So: `Expanded`, making 48.0 a **property of the
layout instead of a coincidence** — `(W − 32 − 40)/6` is 48.0@360, 50.5@375,
53.0@390, and cannot overflow at any width.

#### What this section originally prescribed, and why it does not produce 48

> `Container(width: 50, …)` → **`Expanded(child: Container(…))`**, same margins.

`Expanded` divides the **whole** row, and a `margin` on the child is then spent
**inside** its own slot. At 360 each slot is `328/6 = 54.67`:

| | slot | margin | box |
|---|---|---|---|
| box 0 | 54.67 | right 4 | **50.67** |
| boxes 1–4 | 54.67 | left 4 + right 4 | **46.67** |
| box 5 | 54.67 | left 4 | **50.67** |

Four boxes at **46.67dp — under §13.2's 48 floor** — and six visibly unequal
boxes. **And it would have shipped green**: nothing overflows, so C2's gate says
nothing, and the padding change chosen *specifically* to buy the 48 floor would
have been spent on a shape that misses it. Measured, not reasoned: the C3
mutation that restores this shape reddens the arithmetic assertion at box 0 with
`Actual: 50.66666666666666`.

#### The shape that does produce it

The gaps have to leave the flex division. `Flex.spacing` (Flutter 3.27+;
`basic.dart:5357`) is where they go:

```dart
Row(
  spacing: AppTheme.spacingS,
  children: [for (var i = 0; i < 6; i++) Expanded(child: _box(i))],
)
```

`(W − 2×spacingM − 5×spacingS)/6` = **48.0 / 50.5 / 53.0**, all six equal, at
every width. 8 is exactly what the two 4dp margins already summed to between
adjacent boxes — the rendered gap does not move — and it is §13.2's adjacency
floor. `mainAxisAlignment: center` goes with the fixed widths, as
`pro_journal_screen` deleted its `spaceAround` when its 7 day pills adopted
`Expanded`.

Two further findings from doing it:

- **`height: 64` was already clipping.** Measured at removal: the field wants
  **66.0dp at 1×** and had 64 — ~2dp of every digit cut, on every device — and
  **99.0dp at 2×**. §21 row 52.
- **`width:` on the box is now dead code**, and the mutation that "restores" it
  is a no-op: `Expanded` hands down tight width constraints and `Container`
  enforces its own against them, so 50 clamps to the slot. The mutation that
  genuinely undoes C3 is *dropping the `Expanded`*, and that one reddens all 12
  OTP tests plus the growth test.

The padding change stays load-bearing: without it, the flexed boxes are
`(360 − 48 − 40)/6 = 45.33dp`, under §13.2, **silently** — the mutation reddens
the arithmetic assertion with `Actual: 45.33333333333334` and no overflow at all.
Both changes, one commit.

One property `width: 48` has that `Expanded` does not: at 320 (out of contract)
fixed boxes overflow **loudly** where flexed ones degrade to a 41.3dp target
quietly. At a width §10 now declares unsupported, the quiet degradation is the
better failure — a tight but usable screen rather than a striped banner.

#### The row is one widget now

`lib/widgets/common/otp_code_row.dart`. Not because of the copy count — two is
under §11's threshold of three — but because **the two copies had already
diverged, and every difference ran one way**: identical geometry wrapped around
behaviour only the consumer screen had (autofill, paste distribution, backspace,
auto-submit). A salon owner typing a code got the worse screen, and nobody chose
that. Extraction also puts the row where `androidTapTargetGuideline` and
`expectGrowsWithTextScale` can reach it: every a11y gate in the repo is
component-level, and the boxes land at **exactly 48.0 at 360** — the floor met
with zero slack, by six targets typed in sequence.

### 4.4b The tab bars — the rule §4 never wrote (added by C4)

§4 prescribed the OTP fix in 117 lines and said **nothing** about the tab bars,
though they are 15 of the gate's 27 reds. This is that section, written after
doing it.

**The defect.** A non-scrollable `TabBar` wraps every tab in `Expanded`
(`tabs.dart:1977`) so each gets `W/n`, and a `Tab`'s label is
`softWrap: false, overflow: fade` (`tabs.dart:183`) — hard-coded, no override.
A label too long for its share is **faded away without throwing**. That is why
`takeException` was silent and `expectNoUndeclaredTruncation` was not, and why
A10's `pro_earnings.png` shipped a truncated « Aujourd'hui » nobody read as a bug.

**The fix: `isScrollable: true` + `tabAlignment: TabAlignment.center`**, on the
three bars that clip. Not the two obvious alternatives:

| | why not |
|---|---|
| the M3 default (`startOffset`) | 52dp of empty leading gutter — 14% of a 360dp screen — **and** it is not in the scroll-centring math (`tabs.dart:1669-1683` reads `widget.padding` only), so the selected tab lands 52dp off-centre |
| `start` | no gutter, but ~75dp of dead space on the right at 390, where all three strips fit |
| **`center`** | looks like today while the labels fit; identical to `start` once they do not, because an overflowing strip fills the viewport and there is nothing left to centre. **The only alignment legal in both modes** (`tabs.dart:1809-1821`) |

Set at each call site, **never in `tabBarTheme`** — the assert is per-bar against
that bar's own `isScrollable`, so a theme value throws on every non-scrollable bar.

**The fourth bar keeps `fill`, and the reasoning is the transferable part.**
« Calendrier »/« Liste » is 257.8dp of strip at 200% text inside a 360dp bar —
measured. It fits everywhere §10 supports, and two tabs each taking half the bar
is the better control for a binary view switcher. What makes that safe long-term
is not the decision but the **gate**: `expectNoUndeclaredTruncation` walks every
paragraph on that screen at all six configurations, so a renamed or added tab
that starts clipping goes red on its own. *The idiom is not the protection; the
measurement is* — which is also why converting all four "for consistency" would
have bought nothing.

**Two consequences worth naming before someone finds them.** The nested bar lives
inside a `TabBarView` page, so a horizontal drag on the strip now scrolls the
strip instead of paging back to « Calendrier » — a gesture-arena change, not just
a paint one. And `_openProList` had to gain `ensureVisible`: at 200% text the
nested strip is 553dp inside a 360dp viewport and « Tous » sits fully off-screen,
where `tester.tap` prints a warning, dispatches into nothing and fails two lines
later on an unrelated assertion.

### 4.4c The headings — and the fix that would have passed every gate

§4 prescribed nothing for these either. This is it, written after doing it.

**The trap first, because it is the transferable part.**
`expectNoUndeclaredTruncation` skips any paragraph declaring
`TextOverflow.ellipsis` — correctly, because a declared ellipsis is §13.3-legal
for body copy. So `maxLines: 1, overflow: ellipsis` on « Derniers rendez-vous »
turns **every red in the slice green while shipping « Derniers rendez… »**, and
`find.text` does not object either: it matches the widget's string, not what was
painted. Three siblings of the same class — a heading squeezed to 3dp, a
progress bar flexed to 0dp, an action demoted to a 24dp glyph — are all green on
A, B and C. C5 therefore added the assertions **before** the fix, and each is
mutation-proven to fire alone.

**The shape.** At 200% a heading plus its action wants **564dp** in **328**.
`Expanded` on the title is honest but leaves it ~171dp — three narrow lines
beside a button. A `Wrap(alignment: spaceBetween)` is pixel-identical to the
`Row` at 1× and gives the title the **full width** when they stop fitting, with
the action on its own line. Two lines, a full-size tap target, no arithmetic.

**One trap inside the shape**, which no test caught: a `Wrap` shrink-wraps under
loose constraints, so `spaceBetween` had nothing to distribute and the action
rendered snug against the title. The layout was correct and only the alignment
was wrong. `SizedBox(width: double.infinity)` fixes it, and **the regenerated
golden is what found it** — §21 row 58.

**The pattern was three copies, not two**, and putting the third in the gate is
what made C5 bigger than planned. `provider_detail_screen`'s private
`_SectionCard` had drifted (`Spacer` not `spaceBetween`, `titleMedium` not
`titleLarge`, and the only `minHeight: 48` of the three) and sat outside every
gate. Adding the screen as a ninth subject took the count **4 → 7** and exposed
three more defects nobody had named: `expandedHeight: 160` clipping the salon
header by 92dp, three unflexed contact rows, and `review_tile`'s verified badge.

The header bound is derived rather than guessed, and the derivation is the
reusable bit: the overflow is **92dp at 360, 375 and 390 alike**, so the block
does not re-wrap and its growth is linear — `chrome + text = 160` at 1× and
`chrome + 2×text = 252` at 2× give `text = 92, chrome = 68`. Then
`AppTheme.textScaledBound`, exactly as `ProviderCard.carouselHeight` does.

### 4.5 `contentMaxWidth`, and the blocking dependency

`AppTheme.contentMaxWidth = 720`, applied through **one** shared widget
(`ColoredBox` → `Center` → `ConstrainedBox`) wired into each root's
`MaterialApp.router(builder:)`. **Three lines, zero screens touched.**

- **SnackBars are ~~unaffected~~ CAPPED too — corrected by C6.** The premise
  above is true and the conclusion does not follow: `ScaffoldMessenger` *is*
  above `builder`, but it is only the controller. The bar is rendered by
  **`ScaffoldState`** into its own `_ScaffoldSlot.snackBar` and laid out against
  the **Scaffold's** width, and the Scaffold is a route under the Navigator,
  under the builder. So the bar tracks the column. Reviewed and **kept**: a
  floating bar aligned with the content reads as belonging to it, and a 1400dp
  bar on a stretched window is the same defect §10 names for body copy.
  `content_width_test.dart` measures it, so nobody has to trust either account.
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
> **C6 shipped it, and found one more thing than the box predicted.** `maxWidth`
> had **no wiring assertion** — `tokens.theme-pin.test.ts`'s own comment calls its
> `fontSize` check *"the only assertion that notices a token that isn't wired"*,
> and it was. A `layout` export that never reached the config would have silently
> deleted the styling on all eight `max-w-content` call sites, green. Closed in
> the same commit and mutation-proven: removing `...layout` reddens it alone.
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

**Green-at-base assertions get mutations too**, each failing *exactly one*.
C3's six were run; the results and the one correction they forced:

| mutation | reddens | measured |
|---|---|---|
| drop the `Expanded` + restore `width: 50` | all 12 OTP tests **+ the growth test** | the original bug, back |
| restore `height: 64` | **the two growth tests, alone** | 64.0dp at 1× *and* at 2× |
| margin back inside the `Expanded` (§4.4's first draft) | the arithmetic, all 12 | box 0 = **50.67** |
| page padding back to `spacingL` | the arithmetic, all 12 — **and no overflow at all** | **45.33** at 360 |
| drop `spacing:` from the Row | the arithmetic, all 12 | **54.67** |
| write `spacing: 10` | the §5 pin **and** the arithmetic | — |

Two honest results rather than one clean table. **`width: 50` on its own is not a
valid mutation** — under an `Expanded` it is a no-op (tight constraints, and
`Container` enforces its own against them), so it can never fail and the gate is
right to stay green; the real undo is dropping the `Expanded`. And **the
adjacency assertion cannot fire while the arithmetic one holds**, because the row
width is fixed and pinning each box pins the gaps by subtraction. It is kept, and
labelled, for the configuration the arithmetic *would* accept: a smaller
`spacing:` paid for with a wider padding still lands every box on 48 while
putting the targets 4dp apart.

**C4's four, run and tabled** — and two of them did not come out clean:

| mutation | reddens | note |
|---|---|---|
| drop `isScrollable` on earnings | the truncation walk, all 6 configs | as predicted |
| `tabAlignment: startOffset` | **nothing in `flutter test`** — only `pro_earnings.png`, and only on Linux | see below |
| revert the earnings first load to unbounded | the **golden's** content assertion (« Aucune transaction » must be present) | Linux-only, i.e. CI |
| `tabAlignment` in `tabBarTheme` | the appointment subject ×6, on the SDK assert | as predicted |

**`tabAlignment` is barely gated, and that is the honest statement.** The gate
measures *truncation*, and `startOffset` does not truncate — it adds a gutter. So
the only thing that sees it is the earnings golden (diff 1.47% → 1.65% locally,
where 1.47% is macOS rasterisation noise; on Linux the baseline is 0%). The
appointment list and my-bookings have no golden, so their alignment is
unprotected. Recorded rather than patched: a leading-gutter assertion would have
to encode "centred when it fits, flush when it scrolls", which is the framework's
behaviour restated, not a product rule.

**And the first-load fix is gated only on Linux.** The assertion that catches it
lives in a golden test, which `kGoldensSkip` skips off Linux — so `flutter test`
on a Mac is green against that regression. Named because a developer's local run
will not tell them.

**C5's five, run and tabled** — every one fired alone:

| mutation | reddens | measured |
|---|---|---|
| `maxLines: 1, overflow: ellipsis` on the heading | the no-ellipsis assertion, **all 6 configs × 2 screens** | *"declares an ellipsis"* — the gate now sees the false fix |
| `Wrap` → `Row(spaceBetween)` | the overflow assertion, **2× only** | 112 / 127 / 142 / 206dp |
| the reviews bar → `SizedBox(width: 0)` | the ≥24dp bar assertion, **all 6** | *"has collapsed … a rating histogram whose bars carry no length"* |
| drop `Expanded` in `AppSearchBar` | the overflow assertion, 2× only, home alone | 45 / 60 / 75dp |
| « Voir tout » in a 24dp box | the ≥48 action assertion, **all 6** | *"is 24.0×24.0 … §13.2 says every touch target is ≥48×48"* |

A sixth was authored and thrown away: replacing the `TextButton` with an
`IconButton` reddens with `Bad state: No element`, because it deletes the label
the finder looks for. A mutation that changes two things proves neither.

**C6's five, run and tabled:**

| mutation | reddens | measured |
|---|---|---|
| `contentMaxWidth` 720 → 320 | the identity-below-720 assertion, **alone** | not one golden — see §6 |
| delete the cap from `main.dart` | the positive source pin, alone | — |
| add the cap to `main_admin.dart` | the negative source pin, alone | — |
| drop the `unclaimedDoubles` filter clause | the mirror gate, alone | *"expected ['contentMaxWidth'] to deeply equal []"* |
| remove `...layout` from `tailwind.config.ts` | the new wiring assertion, alone | *"maxWidth.content is not wired into the config"* |

A sixth, renaming the web key, reddens the **mirror** test rather than the wiring
one — the config spreads `...layout`, so a renamed key stays wired, just to the
wrong name. Recorded because it is the mutation one reaches for first.

Older predictions, for the rest of the slice: dropping `isScrollable` reddens only the truncation
walk · ~~`contentMaxWidth` 720 → 320 reddens the 390 assertion and the 26 goldens~~ —
**false, and C6 measured it**: the mutation reddens the identity assertion in
`content_width_test.dart` **alone**, and cannot touch a single baseline, because
**no test in this repo renders an app root** and the cap lives at
`MaterialApp.builder` · and the **meta-mutation**: collapsing `for(w) testWidgets` into
`testWidgets { for(w) }` turns widths 2 and 3 green while the bug is present.

## 6. Rollout & scope discipline

Deploy order is irrelevant — this is app-only plus a token mirror. V1 only.

**Exactly one existing golden should move: `pro_earnings.png`.** The OTP screens
and `appointment_list_screen` appear in no golden, and `contentMaxWidth` is
analytically inert below 720 (a `ConstrainedBox(maxWidth: 720)` under a tight 390
constraint passes it through; `Center` on a tight-width child is the identity).
**The unchanged golden suite is the no-regression proof, and it is free.**
⚠️ *C6 correction: for the cap it is free and **vacuous**. Zero baselines moved,
and none could have — `grep MyweliApp mobile/test/` returns nothing, so
`MaterialApp.builder` is in no tree any golden photographs. §6's stated reason
(analytic inertness below 720) is also true, but it is the second reason.* Any
other diff means something changed that should not have.

### 6.1 What the pictures found (C7)

Three baselines moved in the whole slice, and `consumer_home.png` moved **zero
bytes** while C5 rewrote two of its sections — it is pumped signed out, and both
headings are behind `isAuthenticated`. That is the coverage §21 row 61 records.

And the first 2× pictures immediately found something no gate can: **at 200% text
several labels break mid-word.** « Salon Ex/cellence », « Prom/o W… »,
« Appel/er », and a date rendered « 13/03/20 » / « 26 ». The truncation walk
permits wrapping *by design* — a heading that wraps is C5's fix — and an overflow
never fires because wrapping is how the layout succeeds. So it is the horizontal
twin of the gap §13.3 had before A11: a real rule with no expression. Recorded as
row 62, not fixed here.

### 6.2 What the DEVICE found (C8) — three defects no gate could see

C7's pictures found what the gate could not. C8 put the pro app on a **360dp
Android emulator** (720×1600 @ 320dpi, xhdpi — the Tecno/Infinix class the PRD
names) and found what neither could. **No prior slice had run this app on a
device at all.**

All three are invisible to `flutter test` for the same structural reason: they
are `RenderFlex` overflows, and the striped « RIGHT OVERFLOWED BY » banner is
**debug-only**. In the release build a user installs, the content is simply cut
off at the edge with nothing reported anywhere.

| # | where | at 360dp × 2× | why the gate was blind |
|---|---|---|---|
| 1 | `AppButton`'s label — every button in both apps | « + Nouveau rendez-vous » **32px** over, « Voir toutes les communes » **65px** | the label was a NON-flex child of a `Row`, so it measured its full intrinsic width and the Row overflowed instead of the label shrinking. `layout_test.dart`'s nine subjects do not include the journal, where it was seen; and `expectNoUndeclaredTruncation` walks paragraphs — this paragraph is not truncated, it is drawn in full past its parent |
| 2 | the pro login + register « Pas encore de compte ? » prompt | **149px** over (134 at 375, 119 at 390) | a centred `Row` holding a sentence and a `TextButton`, neither able to give way. The overflow barely moves with the width — the signature of content with a fixed intrinsic width. **The auth screens were a subject of no width test at all** |
| 3 | `DropdownButtonFormField` × 3 phone forms | **79px** over on « Institut de manucure » | a dropdown sizes its button to its WIDEST item unless `isExpanded: true` |

**The strongest evidence that a picture at one point is not coverage:**
regenerating all 32 baselines after fixing #2 and #3 changed **nothing**. At
390 × 1× neither defect exists. `pro_login_w360_x2.png` is the 33rd, and the
first picture of that screen at any width — the goldens held a `consumer_login`
and nothing for the other app.

Finding #1 also produced the slice's only near-miss. Making the label flexible
put a condition on where a button may live, and the first version of that
condition written down was wrong in **both** directions — the narrow, measured
version is that `RenderFlex` permits flex children under an unbounded main axis
for `MainAxisSize.min` + loose, i.e. exactly what `isFullWidth: false` selects.
Only `isFullWidth: true` needs a bound. Six tests in
`pro_invitations_screen_test.dart` went red the moment the one offending call
site was left unfixed, which is the argument for leaving that assertion loud
rather than absorbing it in a `LayoutBuilder` — a LayoutBuilder cannot answer
intrinsic queries, and `IntrinsicHeight` is used twice in `lib/`.

### 6.3 The device run itself

No screenshot tooling exists in this repo and no prior slice recorded a device
run, so this sets the convention — a numbered prose note, the shape
`DEPLOYMENT.md` uses for its push smoke test.

1. **Surface.** Android AVD `a11_360dp`, 720×1600 @ 320dpi = **360dp at
   xhdpi** — 2× DPR with FreeType glyphs, not the 3× CoreText of an iOS
   simulator. `flutter build apk --debug --flavor pro`, installed with
   `adb install -r`.
2. **Session.** `jean@salon-excellence.test`, dev code `123456` (rendered on
   screen when `ENV != prod`).
3. **Seen at 1×.** Dashboard → **Revenus**: all four tab labels complete
   (« Aujourd'hui » « Semaine » « Mois » « Tout ») where « Aujourd'hui » used to
   fade out of a 58dp box. Dashboard → Rendez-vous → journal → appointments →
   **Liste**: the nested four-tab bar, all four labels whole.
4. **Seen at 200% text** (`adb shell settings put system font_scale 2.0`). The
   four-tab bar scrolls and « Aujourd'hui » stays whole. The journal's empty
   state showed the striped banner — finding #1.
5. **Re-run after the fixes.** « Continuer avec Google » wraps to two lines
   inside its button; « S'inscrire » drops below « Pas encore de compte ? »;
   no banner anywhere on the auth screens.
6. **The OTP screen was not driven, and could not be — at any width, on any
   device.** It is unrouted in both apps (`app_router.dart:32-34`,
   `pro_router.dart:61-63`) and its only push comes from a screen that is
   itself unreferenced. The live login OTP step is a single `AppTextField`, not
   `OtpCodeRow`. Reaching it needs a temporary route that cannot be committed,
   which makes it a strictly **weaker** artifact than the `layout_test.dart`
   measurement already covering it at 360 × {1×, 2×}. Recorded rather than
   ticked.

## 7. Definition of done

- [x] §10 states a **floor** (360, 320 out of contract) and the admin exclusion
      (C6); §20's Layout row landed in C2
- [x] `golden.dart` corrected (C6) — the sentence had drifted to `:50-52`;
      *"the only surface that matters today"* is gone
- [x] §21 row 40 → 0 (four sub-defects), row 49 → **1 of 2, the clip half
      measured**, and **twelve** new rows opened (51–62) — not three — plus
      rows 15 and 16 reopened and re-closed
- [x] `flutter analyze --fatal-infos --fatal-warnings` = 0 · format clean · tests green
- [x] web `tsc` · lint · vitest green, **including the new token family**
- [x] every gate mutation-proven red before its fix — **20 mutations tabled**
      across C3–C6 (§5). C2 needed none: it *was* the red, 27 of 48. C7 is
      goldens, where §20.1's eye review is the instrument
- [x] **five** new baselines at the floor, eye-reviewed; **three moved by fixes**
      (`pro_earnings`, `pro_earnings_all`, `consumer_provider_detail`) and the
      other **24 byte-identical** — 32 on disk. *(This line read "the other 27"
      until C8: 6 new + 2 regenerated + 24 untouched = 32, and 27 contradicted
      §6.1's own "three baselines moved".)* The set became
      `consumer_home_w360_x2`, `consumer_provider_detail_w360_x2`,
      `consumer_my_bookings_w360_x2`, `pro_appointment_list_w360`,
      `pro_reviews_w360` — `pro_earnings` was already photographed twice
      post-fix and the OTP screen is unrouted. Two-instant ledger:
      `pro_reviews_w360` identical, the other four differ in the dates they
      print, where identity would have been the bug
- [x] **both tab screens driven on a real 360dp device** at 1× and 200% text —
      a gate that passes is not a screen that looks right, and this one found
      **three** defects no gate could (§6.2). The OTP screen is **recorded, not
      ticked**: it is undriveable at any width on any device, being unrouted in
      both apps (§6.3 ⑥)
- [x] the three device defects fixed, each mutation-proven: **34 new tests**
      (`app_button_test.dart` 13, `auth_layout_test.dart` 21) plus a
      discovered-not-listed source pin for `isExpanded`, and the **33rd**
      golden — `pro_login_w360_x2`, the first picture of that screen at any
      width
- [ ] Feature branch → PR → **the user merges**; no Claude attribution

## 8. Open questions

- ~~**`Tab`'s framework `height: 46`**~~ — **answered by C4, and it is a measured
  green.** `_kTabHeight` is 46.0, 2dp under §13.2's floor, with no override short
  of `Tab(height:)` at every call site — and `androidTapTargetGuideline` **passes
  anyway**, in both scrollable and fixed mode, because it evaluates semantics
  nodes rather than that box. §21 row 55. The related platform limit stands: a
  `Tab` cannot grow with the text scale, so `titleSmall` at 2× is 40dp inside 46
  — it survives 200% by 6dp and clips above ≈2.3×.
- **The consumer phone-auth chain is unrouted and pushes an undeclared path.** A
  routing bug found by a layout census. Recorded; a routing slice should own it.
- **Should `test/a11y/` pin a device width by default**, rather than inheriting
  800×600? **Still open, and now precisely measurable: 6 of 11 files pin.**
  `layout_test`, `content_width_test`, `app_button_test`, `auth_layout_test`,
  `field_error_test` and `text_scale_test` do; `contrast`, `label`,
  `tap_target`, `feedback` and `motion` still inherit. The
  mechanism now exists and is documented as reusable (`support/surface.dart`),
  which is what makes the follow-up cheap — and after C6 the right default is
  **360**, the floor §10 now names, not 390. It
  would make every existing a11y assertion a phone assertion — a strictly better
  gate, and a change large enough to deserve its own slice and its own red count.
