# The booking funnel's « Confirmer » bar, at every text size

| | |
|---|---|
| **Status** | Built |
| **Owner** | Sadreddine Daher |
| **Last updated** | 2026-11-06 |
| **Governs** | the bottom bar, the summary panel and the hub's padding in `web/components/booking/BookingFlow.tsx` · the bar checks in `web/tests/e2e/type-overflow.spec.ts` |
| **Skills checked** | `myweli-web-guardrails` |
| **Builds on** | [The funnel at doubled text](web-funnel-doubled-text.md) §6 (where this was named) · #741's sticky salon bar (`ProviderView.tsx`, web-swiss-cards.md §2.4 decision 5), fixed again since decision 103 ([web-swiss-salon.md](web-swiss-salon.md) §3) |

---

## 1. Goal & scope

The phone bar (« total + Confirmer », parity 2.11) had two faults, measured on
#743's code in Chromium's mobile emulation on the e2e stub. **Real phones are
not verified.**

1. **At large text it took a third to half of the screen.** Android-style
   doubled text: 273 px (48 %) at 320×568, 193 px (30 %) at 360×640. With
   the browser font at 200 %: 177 px (31 %) at 320×568. The page reserved a
   guessed `pb-[6rem]` for it, an arbitrary value with an exception, and the
   doubled bar outgrew it.
2. **At every text size it covered the footer's last link at the end of the
   page.** « Instagram » sat 33 px under the bar at normal text, 48 at
   Android-doubled, 96 with the 200 % font. A `fixed` bar always sits on top
   of whatever ends the document. #741 met the same fault on the salon page.

## 2. UX — decided 2026-11-06

The owner approved the following as proposed (private plan with pictures).

1. **Sticky, like the salon page's bar.** The bar is the last thing in the
   funnel, `sticky bottom-0`, full width on a phone (`-mx-m` undoes `main`'s
   gutter). It rides the bottom of the screen while you scroll and stops above
   the footer at the end. It takes its own room in the flow, so the hub's
   `pb-[6rem]` and its exception are deleted.
   **Since 2026-11-06 the salon page's bar is no longer sticky** (decision
   103, [web-swiss-salon.md](web-swiss-salon.md) §3): it is fixed, and its
   page gives `<html>` a room under the footer measured to the bar's height,
   so it never leaves the screen and the footer's last link stays clear.
   This funnel's choice stays sticky until « Confirmer » is measured the same
   way and the owner answers (decision 105, open).
2. **Compact above a quarter of the screen.** When the full bar would be
   taller than 25 % of the screen, it holds only « Confirmer », full width.
   The total and the duration move into the summary panel (the desktop side
   panel), shown at the end of the steps without its own button. Below 25 %
   nothing changes.
3. **The summary's « Total » row gets the value rule:** the value moves under
   its label, on the right edge, when they can't share a line.

Measured:

| Text | Screen | Before | After |
|---|---|---|---|
| Normal | 320 · 375 · 768 | 65 px, covers « Instagram » | the same 65 px bar, covers nothing |
| Android doubled | 320×568 | 273 px · 48 % | 73 px · 13 % (compact) |
| Android doubled | 360×640 | 193 px · 30 % | 73 px · 11 % (compact) |
| Android doubled | 390×844 | 193 px · 23 % | full, unchanged |
| Font 200 % | 320×568 | 177 px · 31 % | 113 px · 20 % (compact) |
| Font 200 % | 390×844 | 129 px · 15 % | full, unchanged |

**Costs, as approved:**

- On a tablet (704–1023 px wide) the bar can't reach past `main`'s 672 px
  column, so it stops short of the screen edges (48 px each side at 768). On
  the stub's short funnel it sits under the steps, as a row of the page.
- At large text, the bar the server sent shows until the page's script loads,
  then the compact bar replaces it.
- In compact mode the total is in the page, at the end of the steps, not
  pinned.

**Rejected:**

- **Stack the bar like the app's summary.** It takes 121 px (21 %) even at
  normal text, and 38 % at doubled 320.
- **A bar in the flow, not pinned.** It loses parity 2.11's always-visible
  button.
- **Keep the bar fixed and only shrink it.** It still covers the footer.
  True of a fixed bar with no room under the footer. On the salon page
  decision 103 answers it with a room measured to the bar's height
  (web-swiss-salon.md §3.3); whether that answer suits « Confirmer » is
  decision 105's measurement, not yet made.

## 3. Build

- **The decision is measured, not a text-scale constant.** On the first render
  and whenever its inputs change, the page renders the full bar, measures it in
  a layout effect (before the browser paints), and switches to compact when it
  exceeds `0.25 × innerHeight`. The inputs are the total, the duration, the
  window's size and the web fonts finishing loading. A state keyed on those
  inputs prevents ping-pong: a measurement is taken only for a key it hasn't
  seen. This is the web twin of amounts-that-fit's « take the widest shape that
  fits », measured where the app uses `LayoutBuilder`.
- The layout effect is isomorphic (`useEffect` on the server), because nothing
  in `web/` used `useLayoutEffect` before and the server render must not warn.
- At `lg` the bar is `display: none`, so it measures 0 and never goes compact.
  The side panel and its button are unchanged at `lg`.

## 4. Testing

The funnel block of `type-overflow.spec.ts` gains a bar check at the steps (the
bar exists only before the confirm step). It runs in both doubled modes at
320×568 and at normal text at 320 and 375:

- the bar takes at most 25 % of the screen;
- the total is shown, visibly, in the bar or in the summary;
- at the page's end, neither the footer's last link nor the last step card is
  under the bar;
- at normal text, the bar itself carries the total.

The bar is found from the visible « Confirmer » button by walking up to its
first `sticky` or `fixed` ancestor, so the test doesn't depend on class names.

Watched red, each on a fresh build of committed code (§5):

- #743's `BookingFlow`;
- the bar `fixed` again;
- never compact;
- always compact;
- compact with the summary still hidden.

## 5. What was measured

**The guard, each run on a fresh build of committed code** (stacked on #743):

| Run | Result |
|---|---|
| The fix | 4 passed |
| #743's `BookingFlow` | red in all four: at the page's end the footer's last link is under the bar, from the first step |
| The bar `fixed` again (fit logic kept) | red in all four, the same check |
| Never compact | red: « the bar takes 48 % » (Android mode) · « 31 % » (browser font) |
| Always compact | red at 320 and 375: « at normal text the bar carries the total » |
| Compact, summary still hidden | red in both doubled modes: « no total is shown » |

**One spec followed the bar:** `booking.spec.ts` found it as `.fixed.bottom-0`
and now finds `.sticky.bottom-0`.

**The five store-linked pages.** The stylesheet gains exactly one rule,
`.-mx-m{margin-left:-16px;margin-right:-16px}`, and its hashed name changes.
Every element's computed style and box on the five pages stays identical at
375, 820 and 1280 (1,698 elements, against main). `BookingFlow.tsx` is outside
their import graph.

**The real code, looked at.** At Android-doubled 320×568 the bar is 73 px
(13 %), reading « Confirmer », and the summary shows « Total 15 000 – 25 000
FCFA · Durée : 2 h ». At normal 375×667 it is 65 px (10 %) with the total, and
there is no summary on the phone.

**Suites** (this stacked PR gets no CI until #742 and #743 merge):

- the full e2e suite on the default ports: 429 passed;
- unit: 195 files, 2,550 tests;
- lint and typecheck clean.

**Not verified:** real phones.

**The disk filled up mid-task** (117 MB free on a 460 GB volume). The owner
freed space; nothing of this branch was lost.
