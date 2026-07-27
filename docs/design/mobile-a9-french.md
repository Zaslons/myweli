# mobile-a9-french — the framework's English, a calendar in English, and a booking date that books the wrong day (A9)

**Status:** ✅ Shipped (2026-07-27). **Surface:** `mobile/` — all three apps.
**Design system:** [SYSTEM.md §17](SYSTEM.md#17-content--microcopy) ·
[§18](SYSTEM.md#18-market-data--salon-time) ·
[§20](SYSTEM.md#20-enforcement) ·
[§21](SYSTEM.md#21-the-known-violations-register) row 29.
**PRD:** FR-L10N-001 [V1] · FR-L10N-002 [V3] · NFR-I18N-001.
**Roadmap:** design-system programme, mobile A-series slice A9.

## Goal & the debt

`flutter_localizations` is absent — zero hits across `mobile/pubspec.yaml` and
all three app roots — so `DefaultMaterialLocalizations` supplies every Material
default **in English**, in a product §17 says is French everywhere.

## ⚠️ The census reframed the row, and two of the three worst findings are not fixed by the delegates

Row 29 reads as an accessibility footnote: *"found while building `ConfirmDialog`
(A6): the barrier a screen reader announces is not ours to word until this
lands."* That scopes it to screen-reader barrier labels. Measured, that is the
**smallest** part of it.

### 1. A booking date that books the wrong day

`showDatePicker` at `booking_hub_screen.dart:743` (**the consumer booking
funnel**) and `pro_manual_booking_screen.dart:111` both leave
`initialEntryMode` at its default, so the keyboard-entry mode is reachable. In
that mode Flutter parses with `DefaultMaterialLocalizations.parseCompactDate`
(`material_localizations.dart:903-929`), which reads:

```dart
// Assumes US mm/dd/yyyy format
final List<String> inputParts = inputString.split('/');
…
final int? month = int.tryParse(inputParts[0], radix: 10);
final int? day   = int.tryParse(inputParts[1], radix: 10);
```

**A French user typing `07/01/2026` — 7 janvier — books 1 July.** Silently, with
no error, and the field's hint says `mm/dd/yyyy`. It is not overridable by any
`showDatePicker` parameter. `GlobalMaterialLocalizations` replaces the whole
method with `_compactDateFormat.parseStrict` (`flutter_localizations/…/material_localizations.dart:185`),
i.e. the locale's own `dd/MM/yyyy`.

**This is a data-integrity bug in the booking funnel, not a copy bug**, and it is
the reason A9 stopped being a polish slice.

### 2. The consumer booking calendar is already in English — and the delegates do nothing for it

`Intl.defaultLocale` is **never set** anywhere in the repo. A locale-less
`DateFormat` therefore formats in `en_US`, and `defaultLocale ??= systemLocale`
(`intl/intl.dart:528`) pins the isolate to English on the first such call.

All three `TableCalendar` sites pass no `locale:` —
`date_time_selection_screen.dart:216` (**consumer**),
`appointment_calendar_view.dart:87` (pro), and one in dead code. So the booking
calendar's header reads **"July 2026"**, its weekday row **"Mon Tue Wed…"**, and
each cell announces **"Sunday, July 26, 2026"**.

`table_calendar` reads `Intl.defaultLocale`, **not `Localizations`** — so
`flutter_localizations` is irrelevant to it. One line per root fixes all of it.
The consumer site additionally defaults to `StartingDayOfWeek.sunday`, which is a
separate defect from the same screen.

### 3. The visible English row 29 never mentions

| Surface | Reach | What the user gets |
|---|---|---|
| `AppBar` back tooltip | **51 reachable** | "Back" — the highest-frequency English string in the product. Admin is immune: 0 `AppBar(`, its scaffold hand-rolls `tooltip: 'Retour'` |
| Date-picker headline (`formatMediumDate`) | 5 | **"Wed, Sep 27"** — prominent, not overridable |
| Date-picker month toggle (`formatMonthYear`) | 5 | **"January 2026"** — prominent, not overridable |
| Date-picker weekday row | 5 | **"S M T W T F S", week starts Sunday.** French starts Monday — structural, not a string |
| Text-selection toolbar | **50 reachable fields** | Cut / Copy / Paste / Select all |
| Time-picker AM/PM | 6 | a 12h dial whenever the device toggle is off |
| Dialog / sheet barriers | 29 | "Dismiss" / "Scrim" / "Alert" — the screen-reader part the row *did* catch |

## Two mechanism findings that change the fix

- **iOS reads `CupertinoLocalizations`, not Material,** for the selection toolbar
  (`adaptive_text_selection_toolbar.dart:211`). `app_theme.dart` never overrides
  `platform:`, so that branch is live on every iPhone. Material delegates alone
  leave Cut/Copy/Paste English on iOS across 50 fields — **even though the app
  imports zero Cupertino widgets.**
- **24-hour time needs no code.** `TimePickerDialog` resolves the dial via
  `MaterialLocalizations.timeOfDayFormat(alwaysUse24HourFormat: MediaQuery…)`,
  and `MaterialLocalizationFr.timeOfDayFormatRaw` is `TimeOfDayFormat.HH_colon_mm`;
  `timeOfDayFormat()` returns it unchanged when the flag is false and its 24h
  version when true. **Either way French gives 24h**, and the AM/PM buttons
  become structurally unreachable. The planned `MediaQuery` override was
  redundant — dropped, and gated instead.

## ⚠️ The trap that would break ~every widget test

`MaterialApp` **always** appends `DefaultCupertinoLocalizations.delegate`
(`material/app.dart:926-932`), which supports only `en`
(`cupertino/localizations.dart:362`). Adding the obvious pair —
`GlobalMaterialLocalizations.delegate` + `GlobalWidgetsLocalizations.delegate` —
leaves `CupertinoLocalizations` unsupported for `fr`; `_debugCheckLocalizations`
reports an error (`widgets/localizations.dart:906`), and `flutter_test`'s
`FlutterError.onError` turns that into a **hard failure in every test that pumps
a `MaterialApp`**.

**Use `GlobalMaterialLocalizations.delegates` (plural)** — it declares the
Cupertino one too. Three smaller traps:

- `supportedLocales` must contain **`const Locale('fr', 'FR')`**. With only
  `Locale('fr')`, `basicLocaleListResolution` matches at the language rung and
  resolves to `Locale('fr')`, so `countryCode` is null.
- **Three `locale: const Locale('fr','FR')` lines are dead today** —
  `golden.dart:150`, `consumer_screens_golden_test.dart:114`,
  `pro_screens_golden_test.dart:180`. With the default
  `supportedLocales: [Locale('en','US')]` they resolve to **`en_US`**, and
  `DefaultMaterialLocalizations` supports `en`, so nothing ever complained. All
  three must change together or the screen goldens diverge from the component
  goldens.
- `initializeDateFormatting` must stay **before** the first localized pump:
  `initializeDateSymbols` is a no-op once the table is seeded, and
  `GlobalMaterialLocalizations.delegate.load()` seeds it.

## What §17 actually says — and what it does not

§17 is six bullets: French everywhere · use the `core/utils/` formatters ·
buttons are verbs · the error formula · never blame the user · design for +20%
length. **It says nothing about typography** — no guillemets rule, no ellipsis,
no apostrophe, no non-breaking spaces. So "enforce §17's typography" is not a
thing that can be done; A9 writes the rules first, then sweeps.

And §17 is **the only substantive section with no gate** — §20's table has nine
rows and none of them is §17. That is precisely why the copy drifted.

Measured state:

| Convention | State |
|---|---|
| `…` vs `...` | **10 vs 5** — and `availability_screen.dart:509` says `Chargement...` while `brand_loader.dart:51` says `Chargement…`. Same word, two spellings, one app |
| `’` vs `\'` | **65 vs 104**, sometimes in adjacent files |
| Guillemets `« »` | 143 occurrences, **138 of them in doc comments**. Only ~5 in product copy. The documentation is better typeset than the product |
| Non-breaking space | **0 present**, 85 sites want one |
| Currency / date / phone | **correct and centralised** — `formatters.dart` names `fr_FR` on every call, pinned by `salon_time_pin_test.dart` |

**Decision: the inconsistencies only** (`…`, `’`). Guillemets and NBSP are not
inconsistent — they are *absent*, so there is no defect to close, only a
convention to invent. Inventing one app-wide, in invisible characters, across 85
strings whose tests assert them exactly, is not what this slice is for.

## Our own English — one real leak, and a parity regression

`admin/widgets/status_chip.dart:37-47` maps nine statuses to French and falls
through to `raw ?? '—'`. The kind switch above it already routes `confirmed`,
`cancelled` and `noShow` — but `_frenchLabel` has no case for them, so the admin
appointments table renders the **raw English enum**, `noShow` with its camelCase
intact.

And `noShow` renders three ways app-wide: `Absent` (consumer),
`Non présenté` (pro), raw `noShow` (admin).

`web/components/StatusChip.tsx:1-10` declares itself *"the web twin of the admin
console's `StatusChip.forStatus(String)`"* and at `:55-58` records the fix it
made and mobile never got — normalisation-robust labels, so `NO_SHOW` /
`noShow` / `no-show` are one status. **A mobile←web parity regression that
neither register records.**

## The PRD reconciliation

- **FR-L10N-001 [V1]** — "French UI throughout; … `fr_FR` dates. *(exists)*".
  The `(exists)` is **false**. A9 makes it true.
- **FR-L10N-002 [V3]** — English + Nouchi. Not V1.
- **NFR-I18N-001** — "All user-facing strings externalized (even though V1 is
  French-only)". **2540 hardcoded literals, zero externalized.** Unmet, and
  undiscussed anywhere in `docs/`. **A9 does not close it** — externalising 2540
  strings buys nothing until a second language is committed, and V1-scope
  discipline says don't build V3 speculatively. It becomes a register row,
  honestly open, rather than a claim nobody checked.

## Tests & gates — written first, watched fail, then swept

A8's rule, **with the correction A8's own review forced**: gate-first is
necessary and not sufficient. A8 wrote four gate commits that all pumped one
widget and shipped three defects in the other five call sites. So every gate
commit here names, in its message, the call sites it does **not** reach.

The gate is deliberately spread across *mechanisms*, because this slice has
three of them (Material delegates · Cupertino delegates · `Intl.defaultLocale`)
and a gate that only exercised one would certify the other two.

- **The date-corruption gate** — type `07/01/2026`, assert 7 janvier. The most
  valuable assertion in the slice, and the one no existing test could have
  caught: **no test in the suite pumps a date picker, a time picker or a
  `TableCalendar`** (measured: 0). That is why all of this shipped.
- **The iOS leg** via `debugDefaultTargetPlatformOverride`, because the selection
  toolbar needs a *different* delegate and would otherwise ship broken on every
  iPhone.
- **A source pin** over `lib/` **and `test/support/`**: every `MaterialApp`
  carries the delegates, globbed not listed — the fourth app root is covered the
  day it lands. Modelled on `salon_time_pin_test.dart:45`.

## What this slice will NOT do, and why

- **No ARB / `AppLocalizations` layer.** See NFR-I18N-001 above.
- **No guillemets or NBSP convention.** See §17 above.
- **The 7 `screens/provider/features/` screens, `phone_login_screen.dart` and
  `calendar/calendar_screen.dart` are not touched** — zero references from any
  router, §22 allowlists them, and they inflate every naive count (9 of the 60
  `AppBar(` sites, 2 of the 7 raw `TextField`s, 1 of the 3 `TableCalendar`s).

## What shipped, and what each gate cost

| Commit | Gate → red | Sweep |
|---|---|---|
| ① | the typed date · the picker · Monday · the calendar · the toolbar (both platforms) · 24h · the barrier · every `MaterialApp` — **+0 −10** | — |
| ② | — | plural delegates · `app_locale.dart` · Monday-first · dead dep dropped. **6 mutations** |
| ③ | the English leak · normalisation · one vocabulary · the pin — **+1 −10** | — |
| ④ | — | 8 maps → 1. **4 mutations, one of which changed the gate** |
| ⑤ | §17.1's two rules, then `...` **3** · `\'` **89 / 37 files** | — |
| ⑥ | — | the sweep + 32 double-quote conversions + 33 assertions. **3 mutations** |

### Six things this slice got wrong first, and what caught each

1. **The census said five status vocabularies.** The pin measured **nine**,
   then **eight** once it stopped counting a colour switch and a deposit-label
   switch. It went 9 → 8 by narrowing honestly, not by adding an allowlist — an
   allowlist is how a rule stops meaning anything.
2. **A mutation proved a claim I had not earned.** `supportedLocales:
   [Locale('fr')]` passed every assertion in the file while the comment in
   `main.dart` asserted the country code was load-bearing. There is now a test.
3. **A mutation proved a gate incomplete.** Restoring the admin chip's
   `?? raw` fallback kept everything green — because every assertion tests a
   status the map knows, while the fallback is precisely how English reached a
   user. An unknown status now asserts « — ».
4. **The typography sweep rewrote its own gate.** The script walked `test/`,
   found `'...'` inside the pin's `bad` predicate and converted it — inverting
   the rule so it flagged the correct character. Eight legitimate sites went red
   at once, which is the only reason it was obvious.
5. **The pin was blind to double quotes.** In `'l\'équipe'` the apostrophe is
   an escape; in `"l'équipe"` it is bare. The first pin measured **24** where
   there were 89. `dart analyze` then said the quiet part out loud: 32
   `prefer_single_quotes` infos — those strings were double-quoted *only* to
   dodge the escape.
6. **A failing test found a hole the gate could not.** A literal parser cannot
   see inside an interpolation, so
   `'heure du salon (${countryLabel ?? 'Côte d\'Ivoire'})'` passed a **green**
   pin while still holding a straight apostrophe. `\'` cannot legally appear
   outside a string in Dart, so the escaped form is now scanned at line level.

### The golden that showed a change from a different commit

Five goldens moved. Two show ⑥ (« conditions d’utilisation », « renvoyez
l’invitation »). But `admin_table_success` shows **④**: the status chips read
« Vérifié · En attente · Rejeté · Actif » where they had been lowercase. That
inconsistency was in no census — the gate found it and the golden confirmed it
was live in the admin console.

## Definition of done

Row 29 → **0** with the census corrected rather than restated · the booking-date
corruption gated and fixed · both calendars French · the selection toolbar
French on **both** platforms · the status vocabulary unified and the English leak
gone · §17 gains its two typography rules and §20 its **first §17 row** · new
register rows for NFR-I18N-001 and anything the review leaves open · goldens on
Linux · ROADMAP (French) · adversarial review.
