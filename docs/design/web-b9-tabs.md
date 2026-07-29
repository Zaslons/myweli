# B9 — five copies of a strip nobody owned (web)

| | |
|---|---|
| **Module** | Design system — web (cross-cutting) — [MODULES.md](../MODULES.md) |
| **Status** | Draft |
| **Governs** | `web/components/Tabs.tsx` · `web/tests/e2e/` · WEB-SYSTEM §10, §15 rows 7h + 28 · SYSTEM.md §21 row 54 |
| **Predecessor** | [web-b8-reading-text.md](web-b8-reading-text.md) · [mobile-a11-width.md](mobile-a11-width.md) (C4, the same defect on mobile) |
| **Skills checked** | myweli-web-guardrails |

## 1. Goal & scope

§21 row 54 and WEB-SYSTEM §15 row 28 record the same defect in two registers:
web's tab strips can push the page sideways, and the overflow gate cannot see
them. This closes it.

But verification changed the shape of the slice twice, and both corrections are
the point:

1. **The stated reason the gate is blind is false.** Both rows say
   `type-overflow.spec.ts` "runs `PUBLIC_ROUTES` only". It does not — it has a
   `loginPro` helper and two authed tests. One of them stands on
   `/pro/rendez-vous`, the page carrying the first strip, and **asserts only a
   computed `line-height`**. The gate was already there and looked the other way.
2. **The two registers disagree on the count.** SYSTEM.md says five (corrected by
   A11 C8d's review); WEB-SYSTEM says two and was never updated — the row that
   lives in the *right* register is the one still carrying the wrong number.

### Out of scope

The web **text-scale contract**, which does not exist — see §9. And
`RevenusClient.tsx:95`, which the registers cite as the precedent that "solved it
with `flex-wrap`": it is a `ChipButton` pill row, not this control. Web did not
solve the problem, it built a different widget and got wrapping for free.

## 2. What is actually there

Five strips, byte-identical, found by the class string rather than by reading —
`grep -rn "flex gap-s border-b border-divider" web/components` returns all five
in one line, and cross-checking `border-b-2 border-primary` and the tab-state
hooks returns the same five. **There is no sixth.**

| | file:line | labels |
|---|---|---|
| 1 | `pro/RendezVousClient.tsx:174` | « Journée » · « Calendrier » · « Liste » |
| 2 | `pro/RendezVousClient.tsx:308` | « Aujourd'hui » · « À venir » · « En attente » · « Tous » |
| 3 | `pro/CatalogueClient.tsx:106` | « Services » · « Employés » |
| 4 | `pro/MediasClient.tsx:65` | « Photos » · « Avant / Après » |
| 5 | `account/AccountClient.tsx:269` | « À venir » · « Passés » · « Annulés » |

Container `mt-l flex gap-s border-b border-divider`; buttons
`px-m py-s text-bodyMedium` + an active `border-b-2 border-primary`.
**No `flex-wrap`, no `overflow-x`, no `shrink-0`, no `min-w-0`, no `min-h`** at
any of the five. No `role="tab"` anywhere in `web/`.

### The mechanism

A `<button>` flex item's `min-width` computes to `auto`, so per CSS Flexbox §4.5
its automatic minimum size is its content-based minimum and `flex-shrink: 1`
cannot take it below its own text. The row's used width is therefore
`Σ(text) + n·32px + (n−1)·8px`, and since no ancestor sets `overflow`, the excess
propagates to the viewport: **the page scrolls sideways.** It does not clip —
the exact inversion of mobile's `TabBar`, which clipped silently behind
`softWrap: false, overflow: fade`.

### One live, four latent — and the spec says so

Content boxes measured from source: pro pages get **327px** at a 375px viewport
(`ProShell`'s `p-l` inside a non-flex parent below `lg`), the account page
**343px**. Only strip #2 (`LIST_TABS`) exceeds that, at ≈368px. **The pattern is
defective at all five; the overflow is live at one.** Claiming five reds would be
the kind of number this campaign keeps having to correct.

### A second defect in the same five elements

Every button is `py-s` around a 20px line — **36px tall**, under §13.2's 48px
floor, with no `min-h`. `tap-targets.spec.ts` does not measure them, and
WEB-SYSTEM §15 **row 7h claims "0 remaining"**. Fixed here, because they are the
elements this slice is already editing.

## 3. Why there are five copies

**WEB-SYSTEM §10's component inventory has no `Tabs` and no `SegmentedControl`,
and neither is in its "to build" table.** The web design system specifies nothing
at all about tab or segmented controls. Five hand-rolled copies is the predicted
consequence, and patching them in place would leave the cause and invite a sixth.

## 4. The fix

### 4.1 `<Tabs>` — wrap, not scroll

Mobile answered the identical question with `isScrollable: true` (A11 C4, all
three bars). **Web wraps instead**, deliberately:

- a horizontal scroller on desktop has no swipe affordance — off-screen tabs are
  discoverable on a phone and invisible with a mouse;
- A11 C4 records that a scrollable strip at 200% put « Tous » fully off-screen and
  forced `ensureVisible` before every `tester.tap`. The web twin of that is every
  Playwright `.click()` needing a scroll first;
- and mobile-a11-width.md's own closing line is the licence:
  *"the idiom is not the protection; the measurement is"* — the fourth bar kept
  `fill` because the gate walks it, not because the idiom is safe.

Plain `<button>`s, **not** `role="tablist"`. Real ARIA tabs oblige APG arrow-key
navigation and a roving tab stop (WEB-SYSTEM row 21's radio-group conversion is
the precedent for what that costs). That is a keyboard contract worth writing —
and worth writing deliberately, not as a side effect of an overflow fix.

Tokens only: `flex-wrap`, `min-h-12`, `gap-s` are first-class utilities, so
**no `ds-ignore` is needed** (§2 bans arbitrary values, not these). `min-h-12` is
`ChipButton`'s existing §13.2 idiom.

### 4.2 The gate — extended *before* the component exists

- **Factor the four copy-pasted login helpers** (`pro.spec.ts`,
  `type-overflow.spec.ts`, `tap-targets.spec.ts`, `axe.spec.ts`,
  `pro-mobile-nav.spec.ts`) into one module. Four copies is *why* the matrix
  stayed a public-route array with authed exceptions bolted on by hand.
- **Make the authed routes matrix entries**, each with an optional `setup` step:
  `/pro/rendez-vous` (+ a « Liste » click — strip #2 is behind `view === 'list'`
  and the default is `journal`, so a test that only loads the page never sees
  it), `/pro/catalogue`, `/pro/medias`, `/mon-compte`. And make
  `/pro/rendez-vous` run the two overflow assertions it currently skips.
- **`overflowingText` is structurally blind to this defect** even on a covered
  route: its selector is `h1,h2,h3,p,span,button,a,label` and the overflowing box
  is a `<div>`; each `<button>`'s `scrollWidth === clientWidth`, because
  `min-width: auto` sizes it exactly to its text. It overflows its *parent*, not
  itself. Only `noHorizontalScroll` can see it today. The selector gains the
  container elements.
- `tap-targets.spec.ts` gains the five strips.

## 5. States, copy, parity

No new states, no new copy — the labels are unchanged at all five sites, and the
active/inactive treatment is preserved exactly. Parity is unaffected: these are
the web twins of mobile's already-converted bars, and after this both surfaces
answer the same question, differently and on the record.

## 6. Security & performance

Neither is touched. No data access, no session change, no new route. The
component is presentational; the gate additions reuse the existing stub-API login
(`tests/e2e/stub-api.mjs`, wired as a Playwright `webServer`), so no new
credentials or fixtures enter the repo.

## 7. Testing

| | |
|---|---|
| `type-overflow.spec.ts` | the five strips' routes, at 375px, both assertions — watched RED first |
| `tap-targets.spec.ts` | the five strips against the 48px floor — watched RED first |
| `axe.spec.ts` | unchanged; it already scans these routes and has no overflow rule |
| unit | a `Tabs` render/selection test beside the other component tests |

Every gate watched red before its fix. The red count and each strip's measured
overflow are recorded here when they are taken — replacing the arithmetic above,
which is computed from source and not from a browser.

## 8. Definition of done

- [ ] the gate red first, with the live/latent split measured rather than assumed
- [ ] `<Tabs>` built, in §10's inventory
- [ ] all five converted; `grep "flex gap-s border-b border-divider" web/components`
      returns **zero**
- [ ] the 48px floor met and gated
- [ ] the four login helpers deduplicated
- [ ] both registers corrected — the count, and the false `PUBLIC_ROUTES` claim
- [ ] row 7h's "0 remaining" corrected
- [ ] the missing web text-scale contract opened as its own row
- [ ] lint · typecheck · `next build` · vitest · e2e · Lighthouse green
- [ ] adversarial review, every finding hand-verified

## 9. Open

**Web has no text-scale contract at all.** Zero mentions of 200%, reflow, WCAG
1.4.10 or zoom in `WEB.md`, `WEB-SYSTEM.md` or `WEB-DESIGN-STANDARDS.md` — and
the type scale is in `px` (`styles/tokens.ts:140-160`), so a browser font-size
preference has **no effect on this product at all**. Only page zoom scales it,
and zoom scales the viewport too, which is why WCAG specifies reflow as 320 CSS
px rather than as a font multiplier.

Mobile's equivalent is §13.3, gated at 9 subjects × 3 widths × 2 scales. Web's
does not exist. Recorded as a new WEB-SYSTEM row and deferred to **B10**, with
the two candidate answers named: migrate the scale to `rem`, or gate reflow at
320 CSS px. Folding it into B9 would make the overflow fix unreviewable.
