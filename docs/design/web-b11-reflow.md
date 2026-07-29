# B11 — the reflow contract

| | |
|---|---|
| **Status** | Draft |
| **Owner** | Sadreddine Daher |
| **Last updated** | 2026-07-29 |
| **Register row** | [WEB-SYSTEM.md](WEB-SYSTEM.md) §15 row 29 (the reflow half) · row 26 (folded in) |
| **Skills checked** | `myweli-web-guardrails` |
| **Preceded by** | [B9 — the tab strips](web-b9-tabs.md) · [B10 — the flake](web-b10-flake.md) |

---

## 1. Goal & scope

The web has **no text-scale or reflow contract at all**. `WEB.md`,
`WEB-SYSTEM.md` and `WEB-DESIGN-STANDARDS.md` contain zero occurrences of 200%,
reflow, WCAG 1.4.10 or zoom; no web test has ever rendered below **375px**,
varied a root font size, or zoomed. Mobile's twin — SYSTEM.md §13.3 — is gated
at 13 subjects × 3 widths × 2 scales.

**In scope:** a real WCAG 1.4.10 gate (320 CSS px wide **and** 256 CSS px tall
**and** without loss of information **and** with declared 2D-layout exceptions),
the contract written into the design system, the defects the gate finds, and the
defects the px/rem split already causes.

**Out of scope, deliberately:** migrating the type and spacing scales to `rem`.
That is row 29's other half and its own slice — see §8.

### 1.1 Two corrections this slice starts from

Row 29 was written by B9 and corrected by B10's scoping **before any code**.
Both corrections change what B11 must do.

**(a) "Add 320 to the matrix" is not a 1.4.10 gate.** The SC has three parts and
the naive reading covers one:

| 1.4.10 requires | covered by adding a 320 viewport? |
|---|---|
| no horizontal scrolling at **320 CSS px** | **yes** — `noHorizontalScroll` is exactly this |
| no vertical scrolling at **256 CSS px** | **no** — nothing in the suite measures a vertical dimension |
| no **loss of information** | **no** — `overflowingText:95` skips `textOverflow: ellipsis`, so every `truncate` site reads clean while clipping |

**(b) "A browser font preference has no effect on this product whatsoever" is
false**, and the truth is worse than the claim. `tailwind.config.ts:139-145`
extends `width`, `height`, `minWidth`, `minHeight`, `maxHeight`, `inset` and
`translate` from `defaultTheme.spacing` — which is **rem** — while the type
scale (`styles/tokens.ts:138-162`) and the spacing scale (`:81-93`) are **px**.

So under a large browser font the **boxes grow and the type does not**. The
product does not ignore the preference; it **distorts** under it. `min-h-12` —
the SYSTEM.md §13.2 48px tap floor, at **83 call sites** — is already `3rem`,
and nobody decided that: `defaultTheme.spacing` did.

---

## 2. The standard, precisely

**WCAG 2.1 SC 1.4.10 Reflow (AA).** Content must be presentable without loss of
information or functionality, and **without two-dimensional scrolling**, at:

- **320 CSS px** wide, for content that scrolls vertically
- **256 CSS px** tall, for content that scrolls horizontally

Those are the 400%-zoom equivalents of a 1280×1024 viewport (1280 / 4 = 320;
1024 / 4 = 256). This is why the SC is specified as a **CSS-pixel width** and
not as a font multiplier: page zoom scales the viewport too, so a multiplier
would not describe it.

**The exception clause** covers "parts of the content which require
two-dimensional layout for usage or meaning" — data tables, maps. That carve-out
is real and this slice uses it, but §5 declares each one: *an undeclared
exception is indistinguishable from a bug.*

### 2.1 What this contract does NOT buy

It does not make Chrome's Appearance → Font size work. That needs `rem`, and
that is row 29's other half. Saying so here is the point — B9 recorded a gap it
had not measured, and this document exists partly to stop that repeating.

---

## 3. Why 320 is cheaper than it looks, and where the real cost is

**320 is below every breakpoint.** `styles/tokens.ts:252-258` sets
`sm: 640px`. So at 320 every `sm:` / `md:` / `lg:` / `xl:` rule is off, and the
page renders **the same mobile-first layout it renders at 375** — just 55px
narrower. There is no new layout to design; there is an existing layout to make
survive less room.

That single fact retired two of the four hazards the planning census went
looking for:

- `booking/BookingFlow.tsx:479` `lg:grid-cols-[minmax(0,1fr)_320px]` — **`lg:`,
  inert below 1024px**
- `discovery/RechercheClient.tsx:148` `lg:grid-cols-[minmax(0,55%)_minmax(0,1fr)]`
  — **`lg:`, inert below 1024px**

Of **12** hard minimum widths in `web/{app,components,lib}`, **9 are live at
320** and **exactly one is uncontained** — `pro/AvisClient.tsx:108` `min-w-56`
(224px) on the rating-distribution list. The other eight already sit inside
`overflow-x-auto` or `max-h` boxes.

**The real cost is not the viewport.** It is the truncation clause, and those
defects are **width-independent** — four of them are live today at 1440px.

---

## 4. The gates

Four assertions per (route × viewport). Three exist; two are new.

| gate | status | what it proves |
|---|---|---|
| `noHorizontalScroll` | exists (`:77`) | the document does not scroll sideways |
| `overflowingText` | exists (`:88`) | an element's own text does not spill its box |
| `overflowingFlexRows` | exists (`:135`, B9) | a `nowrap` flex row's children fit their container |
| **`overflowingVertical`** | **new** | an element's content is not cut off the bottom of its own box |
| **`truncationLosses`** | **new** | nothing is *actually* clipping text unless it is declared |

### 4.1 What the new gates can and cannot see

The honesty section. B9's and B10's specs both carry one, and both times the
list was the most useful part of the document.

**`overflowingVertical`** is `scrollHeight > clientHeight + 1`, filtered to
`overflow-y: visible`.

- It is **vertical only, and that is not an oversight.** Mobile's twin
  (`mobile/test/a11y/_a11y.dart:551`) says why: the horizontal equivalent is
  true of almost every sentence on a narrow screen, because **wrapping is how
  the layout succeeds**. Its rejected first draft is the warning worth
  repeating — *"a gate that is red on correct behaviour gets deleted, and takes
  the true positives with it."*
- It cannot see a box that clips a *group* (an icon plus a label) rather than a
  single element's own content.
- It respects the performance constraint at `type-overflow.spec.ts:138-142`: a
  `getComputedStyle` on every node of a pro page is expensive enough to push
  **sibling spec files** past the 30s timeout, which is how B9 produced two
  unrelated flakes. Cheap DOM filter first.

**`truncationLosses`** keys on **actually clipping right now** —
`textOverflow: ellipsis` **and** `scrollWidth > clientWidth` — never on merely
carrying the class.

That two-condition design is borrowed, not invented. Mobile's
`expectNoLegibilityCrush` (`_a11y.dart:399`) requires both real truncation and
being flexed, because *"the question is not 'is this label narrow' but 'did this
label spend an ellipsis on a squeeze it did not choose'."* A label that is short
because its content is short is correct, and a gate that reds on it will be
deleted.

- It cannot judge whether the clipped string is the **only copy** of that
  information. No machine can. That judgement is made once, by a human, per
  site, and recorded as `clip-ok` (§4.2).
- It sees only what is clipping **at the viewport under test**. A string that
  fits at 320 with the stub's short fixture data and clips with a real user's
  long one is invisible to it. Named, not solved.

### 4.2 The anti-cheat, and why it matters most

The obvious fix for a red overflow is to add an ellipsis. That turns the gate
green **while shipping « Derniers rendez… » to the user**, and mobile has a
dedicated assertion against exactly that move — `_expectHeadingIsWhole`
(`mobile/test/a11y/layout_test.dart:830`), which asserts `overflow != ellipsis`
**and** `!didExceedMaxLines`:

> **A heading may wrap. A heading may not be cut.**

`overflowingText:95` is that hole on the web: it *skips* anything with an
ellipsis. So the pair of gates has to be read together — `overflowingText` says
"nothing spills", `truncationLosses` says "and nothing was silenced to achieve
that".

### 4.3 The declared-truncation policy

Two complementary mechanisms, because neither alone works:

- **Browser gate** (`truncationLosses`, Playwright) — catches what is clipping
  *now*, at this viewport, including markup no source scan can attribute.
- **Source pin** (Vitest, modelled on `tests/tokens.theme-pin.test.ts:278-296`)
  — every `truncate` / `line-clamp-*` / `text-ellipsis` in `web/{app,components}`
  must carry a written reason within 6 lines:

```
// clip-ok: <why the clipped text is not the only copy of this information>
```

A distinct marker from `ds-ignore`, deliberately. `ds-ignore` means *"no token
can express this"*; `clip-ok` means *"this clipping loses nothing"*. They are
different claims and conflating them would make both unreadable.

---

## 5. The declared 2D exceptions

| exception | why the SC's carve-out applies | already contained |
|---|---|---|
| `components/DataTable.tsx` (4 consumers) | a real `role="table"` with column↔cell association; collapsing the columns destroys the row-wise comparison that *is* the table | `overflow-x-auto` on the box, not the page (`:99`) |
| `components/pro/JournalGrid.tsx` | the horizontal axis **is** the artist dimension and the vertical axis **is** the clock | `max-h-[70vh] overflow-auto` (`:117`) |
| the three map canvases (`ResultsMap`, `SalonLocationMap`, `LocationPicker`) | spatial data; pan and zoom are the interaction, not a reflow failure | all `width: 100%` inside a rem-sized box |
| `components/pro/MonthCalendar.tsx` | a month grid is seven columns by definition | tracks are `1fr` with no `min-w`; ≈35px per cell at 320 |

**Rejected as exceptions**, because they are ordinary grids that can go
one-column: `provider/Gallery.tsx:17`, `provider/BeforeAfter.tsx:13,19`, and
`pro/AujourdhuiClient.tsx:185,197` — three stat tiles at ≈85px each at 320,
holding French labels like « Revenus cette semaine ».

`RevenusClient.tsx:141` already overrides `DataTable`'s floor with
`minWidthClassName="min-w-0"`, which is the precedent that the 640px floor is a
per-caller decision rather than a property of the component.

---

## 6. The px/rem split — stated, and its victims fixed

§2's ⚠️ block in WEB-SYSTEM discusses the sizing keys' *literals* (`w-full`,
`h-auto`, `w-1/2`) at length and never mentions that the keys themselves are
sourced from a **rem** scale. That omission is what row 29 is about, and this
slice writes it down.

**The decision recorded:** the 48px tap floor growing with the root font is
**accepted**. WCAG 2.5.5 is a *minimum*, so a target that grows is still
conformant, and a user who has asked for larger text plausibly wants larger
targets. What changes is that it is now **decided** rather than inherited from a
Tailwind default nobody read.

**What is not acceptable is a px offset positioned against a rem box.** Those
drift, and four are fixed here:

| site | the drift |
|---|---|
| `account/NotificationsClient.tsx:242` | the switch knob's travel is `left-[22px]`, inside a track that is `w-11` (2.75rem) with a `w-5` (1.25rem) knob. The `ds-ignore` states the arithmetic **in px** — 44 − 20 − 2 = 22 — which is true only at a 16px root. At 24px the correct travel is 33px and the knob **stops mid-track**. |
| `pro/JournalGrid.tsx:252,270,303,335` | four `style={{ top: 32 + … }}` offsets against a `sticky h-8` header, where `h-8` is **2rem**. At a 24px root the header is 48px and every block sits 16px too high. |
| `booking/BookingFlow.tsx:479` | `lg:grid-cols-[…_320px]` duplicates the rail `tailwind.config.ts:131` already defines as `desk: 'minmax(0,1fr) 20rem'` and that `AujourdhuiClient.tsx:148` uses — **two names for one rail, one px and one rem**, which is exactly the drift the `desk` token was added to prevent. |
| `styles/globals.css:58` | `min-height: 48px` with a comment claiming *"the same floor as `TextField`'s `min-h-12`"*. `min-h-12` is `3rem`: identical at a 16px root, divergent at every other. |

---

## 7. Testing plan

- **e2e** — `tests/e2e/type-overflow.spec.ts` restructured to one `test.describe`
  per viewport with `test.use` inside it (the idiom already in this repo at
  `z-layers.spec.ts:35` and `booking.spec.ts:37`; `test.use` is a declaration and
  cannot be called inside a `test()` body or a bare loop). `VIEWPORTS` =
  `375×812` — kept as the regression guard — plus `320×512`.
- The `"375px"` literals baked into test names and assertion messages
  (`:187`, `:203`, `:284`, `:296`) become the viewport's own name. **A test name
  that lies is worse than no name.**
- `/pro/connexion` joins the public rows. `signInPro`/`signInConsumer` drive the
  real login UI, so if login breaks at 320 every authed row fails at sign-in and
  the failure is **misattributed to the page under test**. Login is proven first.
- **unit** — the `clip-ok` source pin in `tests/`.
- **Watched red before anything is fixed.** The deliverable of that step is a
  *named list per route*, not "it passes".

**A stated limit of the method:** there is no screenshot harness on the web
(`type-overflow.spec.ts:10` says so). Mobile found SYSTEM.md §21 rows 62 and 69
by *looking at* the 2× goldens. Every finding here comes from computed geometry,
so anything that is ugly-but-not-clipped is outside what this gate can say.

---

## 8. What stays open

- **The `rem` migration** — row 29's other half, its own row. The measured risk:
  `tests/tokens.mirror.test.ts:127,155` deep-equal **raw strings** and
  `scripts/dart-tokens.mjs:274,284` hardcodes `px`, so the failure message says
  *"run `npm run gen:tokens`"* and the generator prints px — **the healing path
  actively fights the migration**. And `bodyLarge` in rem at Chrome's "Small"
  root drops the typed field below 16px, re-enabling iOS Safari's focus zoom,
  which B8 explicitly bought off.
- **`JournalGrid`'s px geometry** — `PX_PER_MIN`, `MIN_BLOCK_PX = 24`, the
  text-clipping `overflow-hidden` at `:332`, and `box.height > 34` gating
  whether a price renders. That last one is SYSTEM.md §13.3's named A12 defect
  — *"a constant that gates a text-dependent branch has to move with the text"* —
  reproduced on the web. Rebuilding the journal's geometry is its own slice.

## 9. Open questions

None outstanding. Three were resolved before this spec: the gate's scope (full
1.4.10), the px/rem question (document and fix the victims; do not migrate), and
the truncation policy (a declared allowlist).
