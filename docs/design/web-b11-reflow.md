# B11 — the reflow contract

| | |
|---|---|
| **Status** | Built |
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
at **15** subjects × 3 widths × 2 scales. (Row 29 says 9 and an early draft of
this spec said 13; `layout_test.dart` carries 16 `testWidgets`, 15 of them inside
the width×scale loop.)

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
the SYSTEM.md §13.2 48px tap floor, at **84 call sites** (83 before this slice
added one to `Faq.tsx`) — is already `3rem`,
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

The planning census counted **12** hard minimum widths with **9 live at 320**; a
review re-count found **13** and disputed which are breakpoint-gated. The
category is fuzzy — `min-w-*`, arbitrary widths, inline `style={{width}}` and
fixed grid tracks are not one thing — so the exact number is not load-bearing and
is not asserted here. What is measured is the outcome: the matrix is green at
320 on all 19 routes. The census called `pro/AvisClient.tsx:108`'s `min-w-56` (224px) the one
*uncontained* floor — **measured, that is wrong**: its parent `Card` is `flex
flex-wrap`, so the list wraps onto its own line and 224 fits the ~240 a 320
viewport leaves. `/pro/avis` was added to the matrix to settle it rather than
argue it, and passes. The census read the child and not the parent; all nine are
contained.

**The real cost is not the viewport.** It is the truncation clause, and those
defects are **width-independent** — four of them are live today at 1440px.

---

## 4. The gates

**Five** assertions per (route × viewport). Three existed; two are new.

| gate | status | what it proves |
|---|---|---|
| `noHorizontalScroll` | exists (`:77`) | the document does not scroll sideways |
| `overflowingText` | exists (`:88`) | an element's own text does not spill its box |
| `overflowingFlexRows` | exists (`:135`, B9) | a `nowrap` flex row's children fit their container |
| **`verticalClipping`** | **new** | an element's content is not cut off the bottom of its own box |
| **`truncationLosses`** | **new** | nothing is *actually* clipping text unless it is declared |

### 4.1 What the new gates can and cannot see

The honesty section. B9's and B10's specs both carry one, and both times the
list was the most useful part of the document.

**`verticalClipping`** is `scrollHeight > clientHeight + 1`, filtered to
`overflow-y: hidden|clip`.

- **`visible` is deliberately NOT a finding**, and this is where the web parts
  company with mobile: a web box paints its excess *outside* itself, so nothing
  is destroyed. Only `hidden`/`clip` loses information; `auto`/`scroll` leaves it
  reachable. Porting Flutter's predicate literally would have fired on every long
  page in the product.
- It skips boxes ≤1px in **both** dimensions. That is `sr-only` — the
  visually-hidden pattern is a 1px×1px box with `overflow: hidden` around real
  text, and the skip link matched on **every** route (24 of 1) the first time
  this ran. Keyed on geometry, not the class name. The first version used `||`,
  which exempted any zero-width text box too; the review caught that it was wider
  than the pattern it named.

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
  must carry a written reason within 10 lines:

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
| `booking/BookingFlow.tsx:479` | `lg:grid-cols-[…_320px]` duplicates the rail `tailwind.config.ts:151` already defines as `desk: 'minmax(0,1fr) 20rem'` and that `AujourdhuiClient.tsx:148` uses — **two names for one rail, one px and one rem**, which is exactly the drift the `desk` token was added to prevent. |
| `styles/globals.css:58` | `min-height: 48px` with a comment claiming *"the same floor as `TextField`'s `min-h-12`"*. `min-h-12` is `3rem`: identical at a 16px root, divergent at every other. |

---

## 7. Testing plan

- **e2e** — `tests/e2e/type-overflow.spec.ts` restructured to one `test.describe`
  per viewport with `test.use` inside it (the idiom already in this repo at
  `z-layers.spec.ts:35` and `booking.spec.ts:37`; `test.use` is a declaration and
  cannot be called inside a `test()` body or a bare loop). `VIEWPORTS` =
  `375×812` (kept as the regression guard), `320×512` (the width 1.4.10 names)
  and `320×256` (deliberately beyond the SC — see §2).
- The `"375px"` literals baked into test names and assertion messages
  (`:187`, `:203`, `:284`, `:296`) become the viewport's own name. **A test name
  that lies is worse than no name.**
- `/pro/connexion` joins the public rows. `signInPro`/`signInConsumer` drive the
  real login UI, so if login breaks at 320 every authed row fails at sign-in and
  the failure is **misattributed to the page under test**. Login is proven first.
- **unit** — the `clip-ok` source pin in `tests/`.
- **Watched red before anything is fixed.** The deliverable of that step is a
  *named list per route*, not "it passes".

**A limit found the hard way: the local run is not authoritative.** CI caught a
320px overflow on `/pro/disponibilites` that passed on every local run — two
`<input type="time">` elements in a `nowrap` row, needing **332px of 291**. A UA
time input's intrinsic width is font- and platform-dependent, and Linux renders
it wider than macOS. So for reflow specifically, **green locally means "not yet
disproved", and CI is the measurement**. This is the one defect in the slice that
no amount of local iteration would have surfaced, and it is a good argument for
`retries: 0`: with a retry it would have been a `flaky` line nobody read.

**A stated limit of the method:** there is no screenshot harness on the web
(`type-overflow.spec.ts:10` says so). Mobile found SYSTEM.md §21 rows 62 and 69
by *looking at* the 2× goldens. Every finding here comes from computed geometry,
so anything that is ugly-but-not-clipped is outside what this gate can say.

---

## 7.1 What the gate actually found

Watched red before anything was fixed. **19 routes × 3 viewports + the journal
line-height test = 58 tests**, and 166 across the whole suite. (An earlier draft
said 18 and 55 — that was the count before `/pro/avis` was added to settle the
`min-w-56` question, and only 58 reconciles with the 166 total.)

**Round one — the two extra viewports, on the routes the file already had:**

| route | assertion | measurement |
|---|---|---|
| `/pro/rendez-vous` | page scrolls sideways | the journal's date navigator — `‹`, a 16px `type="date"`, `›`, « Aujourd'hui » — needed **312px of 272**. Its *parent* row already wrapped; this one did not |
| `/mon-compte` | `nowrap` flex row | **2 items need 262 of 254** — `justify-between` with no wrap and **no gap at all**. Both identity rows; only one fired, because the seeded name is shorter than the phone number |

**Round two — and this is the finding that matters.** Both new
loss-of-information gates were **green on their first run**, and that was not
reassurance: the four sites where a truncated string is the only copy of its
information live on routes this file **had never opened**. A gate is blind to a
page it does not visit. Six routes were added — every one already scanned by
`axe.spec.ts` with the same auth helpers, so reachability was never the obstacle
— including the **booking funnel**, the flow the product exists for, which this
gate had never rendered at any width.

| route | assertion | measurement |
|---|---|---|
| `/pro` | text spills its box | the three stat tiles are `grid-cols-3`: **46px each at 320, 64 at 375**, for labels like « Demandes en attente » (63) and « Revenus cette semaine ». **Broken at both widths, for as long as the route has existed** |
| `/pro/equipe` | truncation loss | the member's e-mail — the row's only on-screen identity — cut **213 → 108 at every viewport including 375**: « proprietaire@beaute-div… » |
| `/pro/clients` | truncation loss | « Koffi » cut at **28 of 32**; the avatar, gap and MyWeli chip had eaten the column so a five-letter name did not fit |
| `/pro/verification` | text spills its box | « Pièce d'identité (CNI / passeport) » needed **73 of 64** — the action buttons are `shrink-0`, so they took their width first |

**Round three — the source pin**, red on **eight** undeclared sites. Two were further
losses and were fixed (the KYC filename, which appears nowhere else in the
product; the catalogue's service name, which the table view showed nowhere
else). Six were declared, each with a reason **checked rather than assumed** —
the census's justification for the sidebar's salon name ("it is also the
dashboard `h1`") is **false**: that heading reads « Aujourd'hui » for an owner
and only names the salon in the staff branch.

**Latent, fixed anyway:** four title toolbars (heading + French button, no wrap)
that all pass at 320 with the seeded copy. B9 shipped five byte-identical tab
strips of which exactly one was live; latent-and-identical is a shape this
codebase has already been bitten by.

## 7.2 The slow-run red, sighted a second time

B10 recorded one red in 17 runs — `axe.spec.ts:86`, a test it did not touch, on
the single run whose wall-clock was 2.7× the median — and left it **named rather
than retried**, without claiming a cause it had not captured.

B11 saw the same shape once: **1 red in 5 runs**, `locator.click` timing out at
30s, on a run that took **1.2 min against a 40–50 s median**. Four runs either
side were clean at 166/166.

What that adds up to, stated at the strength the evidence supports: two
sightings, two different tests, both on runs that took ≈2.5× the median. That is
consistent with a host-level stall against the per-test budget rather than a
defect in either slice — and *inconsistent* with B10 §3.2's finding that uniform
CPU load does **not** break the suite, because a transient stall is not uniform
load. It is **not** proof: neither sighting captured the failure text, and I did
not identify which test B11's was.

The instruction stands and is followed: no retry, no raised timeout, no
`test.slow()`. With `retries: 0` a recurrence fails CI loudly, and the next step
when it does is to **capture the failure text before theorising** — which is the
step both sightings skipped.

## 7.3 What the adversarial review changed

It found a **shipped regression** and a **vacuity hole**, both fixed here, plus a
long tail of my own wrong numbers.

**The regression.** Row 26's fix gave `Faq.tsx`'s `<summary>` `flex
items-center` to centre the label in a 48px box. A `<summary>`'s disclosure
triangle is its `::marker`, and a marker only renders while the element is
`display: list-item` — so `flex` **deleted the triangle** on every public salon
page, trading the affordance that says "this opens" for vertical centring. The
comment I wrote even stated the trade without noticing its cost. Now `min-h-12
py-s`: the label sits at the top of a box that clears the floor, and the
triangle stays.

**The vacuity hole, and it is the one that matters.** Every authed client hands
`ErrorState` its own page title, and `ErrorState` renders that title as an
`<h1>`. So the anchor — *the vacuity guard itself* — matches on a failed page,
and all five assertions then scan a heading, a sentence and a button: nothing
overflows, nothing clips, nothing truncates. **Green, about nothing**, on 11 of
12 authed rows including all six added *because the gate was blind to pages it
did not open*. `ready` was the documented escape hatch and only `/mon-compte`
used it.

Fixed with one structural check rather than eleven bespoke ones: a page-level
`ErrorState` renders `<p role="alert">` carrying its message. The **text filter**
in that check is load-bearing — Next.js ships
`<div id="__next-route-announcer__" role="alert">` on every page, always present
and empty, and keying on the role alone reddened all 11 rows on framework
chrome. An error state is an alert *with something to say*.

**Also fixed:** the fifth and sixth copies of the "heading beside a control, no
wrap" toolbar — and they are the two that matter most, because their heading is
a **salon name**, unbounded user data, where the four found earlier all hold
fixed page titles. The census had filed them under "button clusters".

**Recorded, not fixed** — each is real and each is out of this slice's scope:

- **Nothing enforces the 2D-exception list.** The four exceptions live in §5 of
  this document and in no gate, so a fifth could be added tomorrow with no
  declaration. `clip-ok` shows the shape a fix would take; doing the same for 2D
  layout needs a marker convention that does not exist yet.
- **The matrix is 19 routes, not every route.** Several — `/pro/abonnement`,
  `/pro/profil`, `/pro/salons`, `/mon-compte/[id]` among them — are in neither
  this matrix nor `axe.spec.ts`. §14's row now says *"every route in its matrix
  (19 today, not every route in the app)"*, because the first draft said "every
  route" and that was an overclaim.
- **The `clip-ok` pin scans `app` and `components` only.** A truncating class
  written in `web/lib` or `globals.css` is invisible to it.

**My own numbers, corrected:** 18 routes → **19**; 55 tests → **58**; "six
undeclared sites" → **eight**; mobile's twin at 13 subjects → **15**;
`min-h-12` at 83 call sites → **84**; `tailwind.config.ts:131` → **:151**; the
switch knob stopped at *two-thirds* of its travel, not a third; and both pin
failure messages still said "within 6 lines" after B11 widened the window to 10,
which is a gate lying about its own rule in the sentence a reader sees when it
fires.

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
