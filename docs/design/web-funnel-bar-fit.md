# The booking funnel's « Confirmer » bar, at every text size

| | |
|---|---|
| **Status** | Built (§1–§5, #744) · **§6, decision 105: the bar fixed, with measured room. Specified on 2026-11-09 before the code, then built the same day on `feat/web-funnel-bar-fixed`, stacked on #741, each new guard watched red (§6.7); merged 2026-11-10** (`dd8f312e`, #750), right after #741. Live: `myweli.com` serves the build of `9558c8ee`, which contains it (read 2026-11-12); not read on a page: with no public salon, the funnel redirects (307) to the salon's page |
| **Owner** | Sadreddine Daher |
| **Last updated** | 2026-11-09 |
| **Governs** | the bottom bar, the summary panel and the hub's padding in `web/components/booking/BookingFlow.tsx` · the salon page's `BarClearance` (`web/components/provider/BarClearance.tsx`), which the bar renders since decision 105 · the bar checks in `web/tests/e2e/type-overflow.spec.ts` and `web/tests/e2e/funnel-bar.spec.ts` · `web/tests/funnel-bar.test.tsx` · the bar's lookup in `web/tests/e2e/booking.spec.ts` |
| **Skills checked** | `myweli-web-guardrails` |
| **Builds on** | [The funnel at doubled text](web-funnel-doubled-text.md) §6 (where this was named) · #741's sticky salon bar (`ProviderView.tsx`, web-swiss-cards.md §2.4 decision 5), fixed again since decision 103 ([web-swiss-salon.md](web-swiss-salon.md) §3) · decision 105, the owner's answer of 2026-11-09 ([web-swiss-salon.md](web-swiss-salon.md) §4.1, §4.3) |

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

1. **Pinned at the screen's foot.** *As approved on 2026-11-06:* sticky,
   like the salon page's bar then. The bar was the last thing in the funnel,
   `sticky bottom-0`, full width on a phone (`-mx-m` undid `main`'s gutter).
   It rode the bottom of the screen while you scrolled and stopped above the
   footer at the end. It took its own room in the flow, so the hub's
   `pb-[6rem]` and its exception were deleted.
   **Since decision 105 (answered on 2026-11-09, §6): fixed, with measured
   room.** Sticky, the bar left the screen at the funnel's very end (up to
   604 px of scrolling back for « Confirmer » at normal text, 1,084 with the
   browser's font at 200 %), and the keyboard left 91 focused controls wholly
   under it in 48 of 108 settings. Below `lg` it is now `fixed` at the
   screen's foot, as the salon page's bar is since decision 103
   ([web-swiss-salon.md](web-swiss-salon.md) §3), and it renders that page's
   `BarClearance` unchanged: while the hub shows, `<html>` gets a bottom
   padding as tall as the measured bar, so the footer's last link stays clear
   above it, and a scroll padding of the bar plus 8 px, so what the keyboard
   reaches stops above it. « Confirmer » never leaves the screen, as the
   app's never does. The `pb-[6rem]` stays deleted: the room is measured.
2. **Compact above a quarter of the screen.** When the full bar would be
   taller than 25 % of the screen, it holds only « Confirmer », full width.
   The total and the duration move into the summary panel (the desktop side
   panel), shown at the end of the steps without its own button. Below 25 %
   nothing changes. **Kept by decision 105:** the same compact choice at 108
   of the 108 settings measured, and the room follows each switch (§6.3).
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
  *(Sticky only: fixed since decision 105, the bar spans the screen's width
  below `lg`, §6.3.)*
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
  decision 105's measurement, not yet made. **Made, and answered on
  2026-11-09:** it suits it (web-swiss-salon.md §4.1). The bar is fixed
  again, with the room (§6).

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
- **Since decision 105** the bar is `fixed` and renders `<BarClearance />` as
  its last child, which measures the same box as the compact rule, the bar,
  and writes the room on `<html>` (§6.3). The compact rule does not read the
  room, and the room follows the rule's switch.

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
These checks still hold with the bar fixed: the room keeps the page's end
clear. **Since decision 105**, `funnel-bar.spec.ts` holds the funnel's very
end, the keyboard, a visitor parked at the end before the page's script, print,
the compact switch and the confirm step (§6.7).

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
and now finds `.sticky.bottom-0`. Since decision 105 it finds the `fixed` bar
that holds « Confirmer » and reads its position (§6.7).

**The five store-linked pages.** The stylesheet gains exactly one rule,
`.-mx-m{margin-left:-16px;margin-right:-16px}`, and its hashed name changes.
The rule leaves again with decision 105 (§6.6).
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

## 6. « Confirmer » fixed, with measured room (decision 105)

**Status.** Decision 105 was measured privately on copies of the cover update's branch (#741 at `ce27e839`) and of `main` (`62547f91`) on 2026-11-07 and 2026-11-08, read by a critic and revised, then put to the owner with eight private sheets in French (grey placeholders and the generated test photo only; never committed or published), and answered on 2026-11-09 with the recommendation: « A2f, fixed bar » and « Own PR on #741 » (BACKLOG 105; [web-swiss-salon.md](web-swiss-salon.md) §4.1, §4.3). This section was written on 2026-11-09 **before the code**, on `feat/web-funnel-bar-fixed`, cut from `feat/web-salon-cover` at `be5eeb3e`, after decision 106's commits, and rebased on 2026-11-09 onto `1293bc4e`, that branch after its own review's fixes (the funnel's code and tests unchanged by the move, §6.7). Its PR's base is `feat/web-salon-cover`, and it merges after #741. The code follows in its own commits: the measured build's patch (`b120/confirmer/patches/a2f.patch`, scratch) applied and `BookingFlow.tsx` proved byte-identical to that build's, with the guards of §6.7, each watched red on a copy; then their record. **Built the same day:** the code and its guards in `74a351db` (`fbbb6299` since the rebase), their record in §6.7. **After the build's review,** the same day: the hub's stale comment fixed (`111615aa`), F3 at the 200 % font (`96e56f61`) and the figures before the script at every text setting (§6.3–§6.5), recorded in §6.7. **Not merged.**

**How to read this.** « Today » is #741 at `ce27e839`; its `BookingFlow.tsx` is byte-identical on `main` (`62547f91`) and at this branch's base. « A2f » is the measured build of the answer. **Measured (plan 105)** is that plan's own runs (`b120/confirmer/plan.md`, scratch; its figures in `vals.json`, block `revision`): private `next build`s served alone on 127.0.0.1 against the e2e stub, scanned in Playwright's **Chromium 149.0.7827.55** (headless), load timing in **Google Chrome 156.0.8078.80**, every request off 127.0.0.1 aborted, popups closed, nothing downloaded. **108 settings:** nine screens (320×568, 360×640, 390×844, 412×915, 844×390, 640×400 at DPR 2, 1023×768, 768×1024 and 320×256, WEB-SYSTEM §9's reflow screen) × three text settings (normal; « doubled », Chrome's text scaling on Android: `isMobile`, `hasTouch`, DPR 2, `text-size-adjust: 200%`; « the 200 % font », a 32 px root) × four states of the hub (nothing chosen; a service; « Pas de préférence »; a time, with « Confirmer » enabled). Real phones, Safari and Firefox are not verified.

### 6.1 Goal & scope

**What it fixes, measured (plan 105).** Sticky, the bar is the hub's last child and stops above the footer, so at the funnel's very end « Confirmer » has left the screen: up to 604 px of scrolling back to have it whole with normal text, 652 with doubled text and 1,084 with the 200 % font (579, 819 and 1,059 on the 320×256 screen). It is wholly on the screen at the end in 8 of 108 settings, and at the top in 100: on the 320×256 screen with doubled text or the 200 % font, not even there. Two Tab walks leave **91 focused controls wholly under the sticky bar, in 48 of 108 settings** (WCAG 2.4.11; up to 96 px under): « Spécialiste » 15 times, « 14:00 » 15, « Date et heure » 14, « 09:00 » 13, « 10:30 » 13, the date field 8, « Prestations » 8, a service's checkbox 3, a radio 2. Production has the same fault: 46 in 23 of the 54 settings measured on `main`.

**The app (read).** The hub's summary (Total, « Confirmer ») sits below the scrolling list, outside it, and never leaves the screen (`mobile/lib/screens/booking/booking_hub_screen.dart:417-447, 820-890`); the confirmation step's button is inline at the end of its scroll (`booking_confirmation_screen.dart:463-476`), as the web's confirm step is. A2f matches the app; today departs from it at the funnel's end.

**In scope.**
- `web/components/booking/BookingFlow.tsx`: the bar's classes and comment, and `<BarClearance />` rendered inside it (§6.3). Byte for byte the measured build's file in `74a351db`; since the build's review, that file plus one comment fix (the hub's comment, which still called the bar sticky).
- `web/components/provider/BarClearance.tsx`: **reused unchanged** (decision 105's answer): #741's file, the same bytes.
- The guards of §6.7, and `booking.spec.ts`'s lookup of the bar.
- The docs: this section; §2–§5 of this spec where they state the sticky choice; WEB-SYSTEM §9 (one rule for both bars, and `z-sticky`'s row) and §15 row 38; `web-swiss-salon.md` §1.7, §3.3, §3.6 and §4.3; `web-funnel-doubled-text.md` §6; BACKLOG decision 105 and batch 11's row; the design README's row; a roadmap entry.

**Not in scope.**
- **`data-floating-control` on the funnel's bar** (the plan's critic, nit 1): the mark `Toast` reads to move a message clear of a floating control. The funnel shows no toast (no `Toast` or `useToast` in `components/booking/`), and the measured build does not carry it, so it is not added; a toast in the funnel would need it (§6.9).
- **Moving `BarClearance.tsx`** out of `components/provider/` now that two folders use it: it stays where #741 put it, so this branch's file is #741's (§6.9).
- **The app's « Confirmer » is always enabled** and says what is missing; the web's is disabled until a service and a time are chosen (the critic's nit 3). It predates decision 105.
- **The install banner's row with doubled text** (WEB-SYSTEM §15 row 38): `AppInstallBanner` is in the five store-linked pages' import graph, so its fix waits for Apple's decision.

### 6.2 The owner's answers

Asked on 2026-11-09 with the cover's question (decision 106) and the upload's (decision 107), and answered the same day, each with the recommendation. The costs put with each are in [web-swiss-salon.md](web-swiss-salon.md) §4.1 and §6.5 below.

| BACKLOG | Question | Answer | Not chosen |
|---|---|---|---|
| 105 | At the very end of the booking funnel, how should the phone bar with « Confirmer » behave? | **« A2f, fixed bar »** (recommended): decision 103's pattern, the bar fixed, `BarClearance` reused unchanged | « SP, sticky, keyboard fixed » (the bar sticky, with `BarClearance`'s scroll padding only: 0 focused controls hidden, the end as today); « Keep today's bar » |
| 105 | If « Confirmer » changes, where does it ship? | **« Own PR on #741 »** (recommended): this branch | « On main now »: each of the five store-linked pages would load 13 scripts instead of 12 during Apple's review, because `BarClearance` would bring `styles/tokens.ts` into the funnel on `main` and webpack would move three modules into a new shared chunk (measured (plan 105)) |

**Earlier answers this touches.** #744's « sticky, like the salon page's bar » (§2) is replaced for this bar; its compact rule stays. Decision 91 (« Carte » stops above the footer) stays. WEB-SYSTEM §9's « sticky, not fixed », to which decision 103 gave one written exception, is rewritten as one rule for both pinned action bars (§6.6).

### 6.3 The mechanism, precisely

**The bar.** Still the hub's last child, after the summary panel, with the same content: the total and the duration unless compact, and « Confirmer ». Its classes go from `sticky bottom-0 z-sticky -mx-m border-t border-divider bg-secondary px-m py-s lg:hidden` to `fixed inset-x-0 bottom-0 z-sticky w-screen max-w-full border-t border-divider bg-secondary px-m py-s print:hidden lg:hidden`:
- `fixed inset-x-0 bottom-0`: at the screen's foot, never leaving it. `-mx-m` goes: it undid `main`'s gutter for a box in the flow, and a fixed box is placed against the screen.
- `w-screen max-w-full`, as the salon page's bar has it since its build's review (web-swiss-salon.md §3.3): as wide as the screen and never wider, so a row wider than the screen with Android's large text (WEB-SYSTEM §15 row 38) cannot carry it past the screen's right edge, and a window's classic scrollbar stays out of it. On a tablet (768×1024) the bar now spans the screen, where the sticky bar stopped at `main`'s 672 px column, 48 px from each edge.
- `print:hidden`: a fixed bar would stand at the foot of every printed page; the sticky bar printed once, after the steps.
- Its height is today's at 108 of 108 settings (measured (plan 105)): 65 px with normal text; with doubled text 73 px compact and up to 193 px full; with the 200 % font 113–129 px.

**`BarClearance`** (web-swiss-salon.md §3.3, unchanged), rendered as the bar's last child, after its row, as a `<span hidden>`: no box, no text, no stop for the keyboard or a screen reader. It measures its parent, the bar, the same box the compact rule measures through `barRef`. While the bar has a height it writes, on `<html>`'s inline style, a `padding-bottom` of that height and a `scroll-padding-bottom` of that height plus `s` (8 px): 65 and 73 px with normal text; 73 and 81 for the compact bar with doubled text at 320×568; 113 and 121 with the 200 % font at 320×568. It writes in a layout effect, before paint, and again on a `ResizeObserver` call or a window `resize`, but only when the bar's height changed. From `lg` the bar is `display: none`, its height 0, and both styles are taken off; when the bar goes, both are taken off. Whoever is at the page's very end when the room changes is scrolled to the new end.

**The compact rule and the room.** The compact rule (§2, §3) measures the full bar in its own layout effect and may switch to « Confirmer » alone; `BarClearance`'s observer then sees the bar's new height, and the room follows. They do not feed each other: the rule's key (screen, total, duration, fonts) does not hold the room, and the room is on `<html>`, not on the bar. Measured (plan 105) at 320×568 with doubled text: before a choice the full bar is 113 px, the room 113 and 121; a service chosen, the full bar would take more than a quarter, so the bar keeps « Confirmer » alone, 73 px, and the room is 73 and 81. The compact choice is today's at 108 of 108.

**Where the bar goes.** Only the hub renders it: the confirm step and the done step return before it (`BookingFlow.tsx`, `phase === "confirm"` and `phase === "done"`). So pressing « Confirmer » unmounts the bar, `BarClearance` takes both styles off, and the confirm step, whose « Confirmer la réservation » is in the page as the app's is, carries no room; going back to the hub mounts it again. A client-side visit away, to `/cgu` from the footer, leaves `<html style="">`, and coming back sets the room again (measured (plan 105) at 390×844).

**Before the script runs, and with JavaScript off,** neither style is set: the bar is fixed with no room, and at the very end « Instagram » is 32.8–33.2 px under it and does not answer a press (measured (plan 105) with JavaScript off at 320×568, 390×844 and 844×390). That is normal text. With larger text the bar is taller and the link further under it, also not answering (found by the build's review and measured again by its fix stage, JavaScript off, Chromium 149, on a build of `65b38d85`): with doubled text 41.0 px at 390×844 and 40.8 at 844×390 (a 73 px bar), and 81.2 at 320×568 (113 px), where the 48 px link is wholly under the bar; with the 200 % font 80.8–81.2 px at the three (113 px), the 96 px link partly under it. The salon page's bar is in the same case before its script, up to 105.5 px with doubled text ([web-swiss-salon.md](web-swiss-salon.md) §3.3). Once the script runs, a visitor at the very end is moved to the new end (§6.4). With JavaScript off for good the last link stays under the bar (inferred).

**The shared stylesheet.** The bar's new classes are all in it already (the salon page's bar brought `fixed`, `inset-x-0`, `w-screen`, `max-w-full` and `print:hidden`), and `.-mx-m{margin-left:-16px;margin-right:-16px}`, which only this bar used, leaves: 601 rules, then 600, nothing added, the other 600 in their order (measured (plan 105) on the built CSS). Tailwind reads comments too, so the new comment does not spell the class.

### 6.4 Every state

A2f, measured (plan 105), unless the row says otherwise; today's figures for comparison.

| State | Behaviour |
|---|---|
| **The very end, at the 108 settings** | « Confirmer » wholly on the screen and answering a press at 108 of 108 (today 8). « Instagram », the footer's last link, 31.8–32.5 px above the bar and answering at 108 of 108; every footer link, brought into view, answers, with 0 px under the bar. The control, A2f with its room forced off (27 settings, a time chosen): « Instagram » under the bar, up to 96 px, answering at 0 of 27 |
| **The top** | « Confirmer » wholly on the screen at 108 of 108 (today 100: on the 320×256 screen with doubled text or the 200 % font the sticky bar is below the first screen) |
| **The keyboard (WCAG 2.4.11)** | Two Tab walks per setting, from the skip link and after a scroll through: **no focused control under the bar, wholly or partly**, at 108 of 108; every walk ends on `<body>` after the footer's 8 links. Today 91 wholly hidden, in 48 settings |
| **The page's length, the bar, the compact choice** | Today's at 108 of 108: the room equals the room the sticky bar took in the flow |
| **The screen left above the bar at the very end** | 191–959 px with normal text, 183–951 with doubled text, 143–911 with the 200 % font. Today the footer has the whole screen there, because the bar has left |
| **The quarter rule** | Even compact, the bar takes more than a quarter of the screen at 5 settings, today as with A2f: 320×256 at every text setting (25.4, 28.5 and 44.1 %), and 844×390 and 640×400 with the 200 % font (29.0 and 28.3 %). Fixed, it now stays there for the whole page (§6.6) |
| **A compact switch** | The room follows the bar's height: 113 → 73 px at 320×568 with doubled text (§6.3) |
| **The confirm step, the done step** | No bar, and `<html>` has neither style |
| **The `lg` edge** | At 1023×768 the room is 65 and 73 px; at 1024 the bar is hidden and `<html>` has no inline style; back at 1023, the room is back |
| **A client-side visit away, and back** | `<html style="">` on `/cgu`; the room again on the funnel |
| **Turning the phone** | Parked at the end at 390×844 with the 200 % font, turned to 844×390 and back, and three other turns: « Confirmer » whole at every reading, the room following 129 → 113 → 129 px (the plan's critic, on builds of the same patch) |
| **Parked at the end before the script runs** | At 9 of 9 runs the page is at its new end once the script has run, « Instagram » clear and answering, and no layout-shift entry: at 320×568 with normal text, from 743 to 808. With the 200 % font at 320×568 (the build's review, then F3's third case since `96e56f61`): from 1,363 to 1,476, « Instagram » 31.8 px clear and answering. Before the script: §6.3's figures, up to 81 px under the bar |
| **Layout stability, speed** | CLS at load (Chromium 149, unthrottled), where the compact rule switches after hydration, the same in both builds: 0.1961 and 0.1762 at 844×390 and 640×400 with the 200 % font, 0.0921 at 320×256 with normal text; **at 320×256 with the 200 % font 0.0269 today, 0.1843 with A2f** (the switch moves « Confirmer » within the fixed bar, on the screen). Elsewhere 0. LCP in Chrome 156 (slow 4G, CPU ×4, 5 runs) within run-to-run noise of today's at the five settings timed |
| **Print** | The bar is not printed (today it printed once, after the steps) |
| **The install banner** (once a store link is set; no e2e build sets one) | With doubled text its row lays the page out 418 px wide at 320×568 (742 px tall). The bar keeps to the screen's width (0–320), but its foot is the layout's, at 742, and « Confirmer » is not on the 568 px screen, at the top as at the end; today's sticky bar is not on it at the top either, and has left at the end (measured (plan 105)). The banner's fix waits for Apple's decision (WEB-SYSTEM §15 row 38) |
| **Screen reader** | Unchanged: the bar is in the hub, in the same DOM order; the `<span hidden>` is not exposed |
| **Safari, Firefox, real phones** | UNVERIFIED (§6.9) |

### 6.5 Costs, in plain words

**Put to the owner with the question, and accepted with « A2f, fixed bar »:**
- Until the page's script runs, « Instagram » is about 33 px under the bar; once it runs, the page moves to its new end by itself.
- On the 320×256 test screen with the browser's font at 200 %, the load shift goes from 0.03 to 0.18.
- The compact bar still covers 25–44 % of the screen at 5 settings, and now never leaves it.
- The bar is no longer printed.
- The unused rule `.-mx-m` leaves the stylesheet the five store-linked pages share: a written exception to the gate's condition 3; their computed style is identical (§6.6).
- WEB-SYSTEM §9's « sticky, not fixed » is rewritten for both bars: « a pinned action bar is fixed, with measured room »; « Carte » stays sticky.

**Put with « Own PR on #741 »:** the funnel's keyboard fault stays on production until this PR merges, after #741.

**Measured and not put in these words, for the owner with the PR:**
- Before the script runs, the « about 33 px » put with the question is the figure at normal text. With doubled text « Instagram » is 41 px under the bar at 390×844 and 844×390, and 81 px at 320×568, where the 48 px link is wholly under it; with the 200 % font about 81 px (§6.3; found by the build's review, 2026-11-09). Once the script runs, the page moves to its new end (§6.4: with normal text, and with the 200 % font at 320×568).
- On a tablet below `lg` the bar now spans the screen's width (the sticky bar stopped 48 px from each edge at 768).
- Links within the page and find-in-page stop above the bar (the scroll padding).
- With JavaScript off for good, the footer's last link stays under the bar at the very end (inferred).
- `booking.spec.ts` found the bar by its sticky classes; it now finds the fixed bar that holds « Confirmer » (§6.7).
- `BarClearance`'s doc comment names the salon page's bar only (§6.9).

### 6.6 The design system, and the five store-linked pages

- **WEB-SYSTEM §9, one rule for both bars.** « A pinned bar … is sticky, not fixed » (#744), with the salon page's bar as its one written exception (decision 103), becomes « **a pinned action bar is fixed, with measured room** »: the salon page's « Réserver » and the funnel's « Confirmer », both with `BarClearance`. « Carte » stays sticky (decision 91): a floating control over a list, not a page's action bar. A fixed bar anywhere else still needs its own decision.
- **WEB-SYSTEM §9, the quarter rule.** Unchanged for this bar: the compact rule. It does not bring every setting under a quarter: at the 5 settings of §6.4 the compact bar takes 25.4–44.1 %, today as with A2f; written down beside the salon page's bar's exception (decision 104), as accepted with decision 105.
- **WEB-SYSTEM §15 row 38:** the funnel's bar keeps to the screen's width too (`w-screen max-w-full`).
- **Tokens:** no new token and no arbitrary value; `BarClearance` reads `spacing.s`, as it does for the salon page. **48 px targets:** unchanged (« Confirmer » is `min-h-12`). **Focus never hidden:** none hidden at 108 of 108 (§6.4).
- **The five store-linked pages** (`/support`, `/politique-confidentialite`, `/cgu`, `/mentions-legales`, `/suppression-compte`) must not change in content or computed style, on screen and in print, while Apple reviews. Measured (plan 105), A2f against today, both on #741:
  - **Their code.** The walker (`b114/map-tools/closure2.py`, scratch) gives the same 56-file closure, every file byte-identical; `BookingFlow.tsx` and `BarClearance.tsx` are outside it, and its control, seeded from the funnel's page, reaches both.
  - **Their scripts.** 12 per page before and after, 2 bytes fewer compressed in all, identical once build noise (module ids, hashes) is normalised. On #741 `styles/tokens.ts` already sits in a shared chunk, so nothing moves; on `main` it would (« On main now », §6.2).
  - **Their stylesheet.** 601 rules, then 600: `.-mx-m` removed, nothing added. None of the five uses the class.
  - **Their computed style and pixels:** identical at 45 of 45 cases (nine sizes × five pages) and in print at 10 of 10, in two captures each (Chromium 149).
  - **The gate's condition 3** (web-swiss-cards.md §13, as web-swiss-salon.md §1.7 amends it for #741 with `.lg:col-span-2` and `.pb-xxl`) reads, for this PR: « every old CSS rule still present, in order, except `.lg:col-span-2`, `.pb-xxl` and `.-mx-m`, which none of the five uses; added rules allowed ». Condition 5, their computed style and pixels, is what proves the removal harmless.
- **Security, privacy:** no new route, call, cookie, origin, secret or CSP change. Pictures for the PR use grey placeholders or the generated test photo only (`web/tool/test-photo.mjs`): no face, no AI image, no demo salon photo (decision 37).
- **SEO, performance:** the funnel is `noindex` (`app/[slug]/reserver/page.tsx`), and no metadata changes. The funnel's script gains `BarClearance` (about 50 lines); its bytes are not measured on their own, and LCP is within noise (§6.4).

### 6.7 Tests

Each new guard is watched red on committed work, on a copy (`git archive` into scratch), never by editing and restoring in the branch's tree, and recorded with its commit. The last column is filled by the build stage.

**E2E, a new file, `web/tests/e2e/funnel-bar.spec.ts`** (Playwright, the repository's config and ports; the bar found from the visible « Confirmer » by its first `fixed` or `sticky` ancestor, never by its classes; steps taken with DOM clicks, as `type-overflow.spec.ts`'s `walkFunnel` takes them; every request off 127.0.0.1 aborted):

| # | What it holds | Non-vacuity | Mutation → red | Green, then red (build stage) |
|---|---|---|---|---|
| F1 | At 390×844 and 320×568 with normal text, at 320×568 with the 200 % font, and at 320×568 with doubled text (Android); a service, « Pas de préférence » and a time chosen; scrolled to the very end: « Confirmer » wholly on the screen and answering a press at its centre; « Instagram » above the bar and answering; the footer's foot within 1 px of the bar's top; every footer link, brought into view last first, answers | The page scrolled and is at its very end; « Confirmer » enabled; the text setting read at the measurement (the step titles at 32 px with doubled text, the root at 32 px with the 200 % font); the layout is the screen's size | The bar `sticky` again; `BarClearance` removed | **Green** 4 of 4, 0.3–0.6 s each: at the very end (`scrollY` 511, 811, 1,621 and 1,789, the plan's), « Confirmer » whole and answering, « Instagram » 31.8–32.0 px above the bar and answering, the footer's foot within 0.2 px of the bar's top (bars of 65, 65, 113 and 73 px), every footer link answering. **Red:** the bar sticky again, 4 of 4 (« « Confirmer » is above the screen »); `BarClearance` removed, 4 of 4 (« « Instagram » reaches the bar »); and the observer removed, 1 of 4, with doubled text (« the footer ends at 455.15625, the 73px bar starts at 495 »: the room stayed the full bar's after the compact switch) |
| F2 | At 320×568 and 320×256 with doubled text (Android), the same choices, a Tab walk from the top of the document through the steps, the bar and the footer: no focused control wholly under the bar, and none partly under it where it fits, with its 8 px, in the room above | The walk starts at « Aller au contenu » and reaches « Prestations », a time, the bar's « Confirmer » and the footer's last link, « Instagram » | The scroll padding removed; `BarClearance` removed | **Green** 2 of 2, 0.35 s each: 22 stops, 8 of them in the footer, the last « Instagram »; nothing under the bar, wholly or partly. **Red:** the scroll padding removed, 2 of 2 (« 14:00 » hidden whole at 320×568; « Connexion Espace pro », « Mentions légales » and « Instagram » at 320×256); `BarClearance` removed, 2 of 2 (the same four); the bar sticky again, 0 of 2: the scroll padding still keeps focus above it, and F1, F3, F5 and F7 hold that mutation, as decision 103's D4 found for the salon page |
| F3 | At 390×844 and 320×568 with normal text, and since the build's review at 320×568 with the 200 % font, the page's script held back (its chunks routed, released once the visitor is parked at the very end): once it runs, the page is at its new end, and « Instagram » is clear of the bar and answers | Before the script, the bar is fixed, `<html>` has no room, and « Instagram » is under the bar; since the review, the root's size read at the parking (16 or 32 px) | The stay-at-end branch removed; since the review, the stay-at-end moving by the normal bar's 65 px instead of to the new end | **Green** 2 of 2, 0.24–0.26 s each: parked at 459 (390×844) and 743 (320×568), « Instagram » 33.0 and 33.2 px under the bar, no room on `<html>`; once the chunks were let through, at 524 and 808, the new ends (the plan's), « Instagram » 32.0 and 31.8 px clear and answering. **Red:** the stay-at-end branch removed, 2 of 2 (« left at 459, the page now ends at 524 »; 743 and 808); `BarClearance` removed, 2 of 2 (no room ever written); the bar sticky again, 2 of 2, on its precondition (« sticky », not « fixed »). **Since the review** (`96e56f61`): **green** 3 of 3, the third parked at 1,363 with « Instagram » 81.2 px under the bar and the root at 32 px, then at 1,476, the new end, « Instagram » 31.8 px clear and answering. **Red:** the stay-at-end moving by 65 px, 1 of 3, the 200 % font only (« left at 1428, the page now ends at 1476 »), the two normal-text cases green because 65 px is their bar; the stay-at-end branch removed, 3 of 3 (« left at 1363, the page now ends at 1476 » at the 200 % font) |
| F4 | At 390×844 in print media: the bar is not displayed, and no « Confirmer » shows | On the screen the bar is displayed, with its « Confirmer » | `print:hidden` removed | **Green**, 0.2 s: on the screen `block`, with one « Confirmer » shown; in print `none`, and none shown. **Red:** `print:hidden` removed (in print still `block`, with its « Confirmer ») |
| F5 | At 320×568 with doubled text (Android): before a choice the bar is full and the room is its height, with 8 px more of scroll padding; a service chosen, the bar keeps « Confirmer » alone and the room is the compact bar's height; at the very end « Confirmer » is whole, « Instagram » clear, and the footer's foot meets the bar | The bar turned compact and changed height | `BarClearance`'s observer removed (the room stays the full bar's); `BarClearance` removed | **Green**, 0.2 s: before a choice the bar 113 px with its total, the room 113 and 121; a service chosen, the bar compact at 73 px, the room 73 and 81; at the very end (2,113) « Confirmer » whole, « Instagram » 31.8 px clear, the footer's foot at the bar. **Red:** `BarClearance`'s observer removed (113 and 121 under a 73 px bar); the bar sticky again (« « Confirmer » is above the screen »); on its precondition, `BarClearance` removed and the scroll padding removed |
| F6 | At 390×844, the choices made and « Confirmer » pressed: on the confirm step `<html>` has no room and no scroll padding, inline or computed | The hub had both | `BarClearance`'s clean-up removed | **Green**, 0.33 s: on the hub 65 and 73 px; on the confirm step `''` inline, `0px` and `auto` computed. **Red:** the clean-up removed (65 and 73 px kept on the confirm step); on its precondition, `BarClearance` removed and the scroll padding removed |
| F7 | `booking.spec.ts`, « the pinned bottom bar gates then confirms (parity 2.11) », at 375×812: the bar is the fixed bar that holds « Confirmer » (it was `.sticky.bottom-0`), and its computed position is `fixed`; the rest unchanged | — | The bar `sticky` again | **Green**, with the rest of `booking.spec.ts`, 8 of 8. **Red:** the bar sticky again (« element(s) not found ») |

**Unit, a new file, `web/tests/funnel-bar.test.tsx`** (jsdom; the bar's box given, 65 px on a 568 px screen):

| # | What it holds | Mutation → red | Green, then red (build stage) |
|---|---|---|---|
| U-F1 | While the hub shows, `<html>` gets `padding-bottom: 65px` and `scroll-padding-bottom: 73px`, and the box measured is the bar that holds « Confirmer » | `BarClearance` removed | **Green** 2 of 2 in the file. **Red:** `BarClearance` removed; the scroll padding removed |
| U-F2 | « Confirmer » pressed: on the confirm step both are `''` | `BarClearance`'s clean-up removed | **Red:** the clean-up removed; `BarClearance` removed, on its precondition (« no room while the hub shows ») |

**Unchanged, and run:** `type-overflow.spec.ts`'s funnel block, whose bar checks (at most a quarter of the screen at 320×568 in both doubled modes and at 320 and 375 with normal text, a total shown, nothing under the bar at the page's end) hold with the room; `bar-clearance.test.tsx`; the unit files that render `BookingFlow`.

**Also run:** `tsc --noEmit`; ESLint `--max-warnings=0` on the changed files; vitest on the targeted files, then the whole unit suite; `booking.spec.ts` and `funnel-bar.spec.ts`; the five pages' walker with its controls, and the built stylesheets compared with the measured build's.

**The build's record (2026-11-09).** *Browser:* Playwright's own Chromium 149.0.7827.55, with the repository's `playwright.config.ts` unchanged, on its ports 3000 and 8787, both free before and after every run. *Code:* `74a351db`'s `BookingFlow.tsx` is byte for byte the measured `a2f` build's (sha-256 `c501b592…`), and its `BarClearance.tsx` is #741's (`df3e84fa…`); the whole `web/` tree equals `a2f`'s but for decision 106's three files, this branch's three test files and what a build writes (`public/flags`, `next-env.d.ts`). Its build's three stylesheets are byte for byte the measured `a2f` build's. *Green:* `tsc --noEmit`; ESLint `--max-warnings=0` on the four changed files; vitest on the 7 unit files that reach the bar or `BarClearance`, 118 of 118, and the whole unit suite, 2,749 of 2,749 in 207 files; `funnel-bar.spec.ts`, `booking.spec.ts` and `type-overflow.spec.ts` together, 138 of 138 (11, 8 and 119); the whole e2e suite, 665 of 665 in 3.7 min. The new e2e cases take 0.2–0.6 s each.

*Mutations,* each on its own `git archive` copy of `74a351db` (`node_modules` cloned, the same lockfile), never in the branch's tree; each edit asserted to apply exactly once, and the mutated files diffed with the commit's, only the intended lines differing. On each copy, `funnel-bar.test.tsx`, then `funnel-bar.spec.ts` with `booking.spec.ts`, 19 cases, the app built each time (48–61 s a run). A copy with no edit: 2 of 2 and 19 of 19. Seven mutations, **7 of 7 red**:

| Mutation | Unit, red of 2 | E2E, red of 19 | The guards that went red |
|---|---|---|---|
| The bar `sticky bottom-0 … -mx-m` again, `BarClearance` kept | 0 | 8 | F1 4 of 4, F5, F7; F3 2 of 2 on its precondition |
| `BarClearance` removed (with its import) | 2 | 10 | F1 4 of 4, F2 2 of 2, F3 2 of 2; F5 and F6 on their preconditions; U-F1, U-F2 |
| The scroll padding removed (`BarClearance`) | 1 | 4 | F2 2 of 2; F5 and F6 on their preconditions; U-F1 |
| `print:hidden` removed | 0 | 1 | F4 |
| The stay-at-end branch removed (`BarClearance`) | 0 | 2 | F3 2 of 2 |
| The observer removed (`BarClearance`) | 0 | 2 | F5; F1 with doubled text |
| The clean-up removed (`BarClearance`) | 1 | 1 | F6; U-F2 |

ESLint on two more copies: `print:hiddn` refused (`tailwindcss/no-custom-classname`), `w-[100vw]` refused (`tailwindcss/no-arbitrary-value`).

*The five store-linked pages* (§6.6), on this branch. **Their code:** the walker gives the same 56 files on `74a351db` as on `be5eeb3e` and on `ce27e839`, all byte-identical, `SiteFooter.tsx` and `FooterGroups.tsx` among them, `BookingFlow.tsx` and `BarClearance.tsx` not; its controls: seeded from the funnel's page it reaches both (61 files), and an import of `BarClearance` planted in `/cgu` gives 57 and the byte check names `app/cgu/page.tsx`. **Built:** `be5eeb3e` and `74a351db`, each from a fresh `git archive`, with the plan's environment (a dummy store link, so the install banner's code is in) against one stub. Conditions 1 and 2, the words, links and classes and the decoded payload: the same at 5 of 5 (controls: a word changed in `/cgu`, 1 of 5; a letter in the payload, 1 of 5). Scripts: 12 and 12 per page, 2 to 5 bytes more compressed, identical once normalised (60 pairs, 0 left; control: a token appended, 1 left). The stylesheet: 601 rules then 600, `.-mx-m` removed, nothing added, the rest in order, the same file for all five. **Computed style and pixels** (condition 5; the plan's `capture.mjs` and `compare2.py`, Chromium 149, one build at a time on 3502): 45 of 45 identical, every element's every computed property and box and the full-page PNG; print 10 of 10; `/recherche` 9 of 9. Controls fire: the funnel at 390×844 differs (49 elements, the PNG); `.-mx-m` put on `/cgu`'s first heading changes it (1 element: the rule is gone on this branch); the salon page is identical at 390 and 1280.

*Not run:* Lighthouse; Safari, Firefox and real phones (§6.9); CI (nothing is pushed by the build stage).

**After the build's review (2026-11-09).** The review found no blocker and no major; every figure it measured again matched this record. It found two minor faults, both fixed. The hub's comment in `BookingFlow.tsx` still said the bar was sticky and took its own room in the flow: fixed in `111615aa`, comment only, with the class-like tokens it named before (Tailwind reads comments). The « about 33 px » before the script had been measured at normal text only: §6.3–§6.5 now give every text setting, measured again here with JavaScript off. Of its three nits, the design README now has rows for this spec and for `web-funnel-doubled-text.md`; decision 105's « Open » reads « to be specified and built » and web-swiss-salon.md §4.3 names the cover update's branch, both fixed on #741 (`1293bc4e`); and the guards that do not reach are written down in §6.9.

*The rebase.* After #741's own review fixes, this branch was moved with `git rebase --onto 1293bc4e be5eeb3e`. Three docs conflicts were resolved by taking this branch's text with #741's two word fixes: BACKLOG decision 105, web-swiss-salon.md §4.3 and WEB-SYSTEM §9. In WEB-SYSTEM §9, #741's large-text figures for the salon page's bar return in this commit, for both bars. The code commit is now `fbbb6299`: its `web/` differs from `74a351db`'s only in #741's two files, `ProviderView.tsx`'s comment and `site-look.spec.ts`. So `BookingFlow.tsx`, `BarClearance.tsx`, `funnel-bar.spec.ts`, `funnel-bar.test.tsx` and `booking.spec.ts` are byte for byte `74a351db`'s.

*F3 at the 200 % font, watched red on `96e56f61`.* Driver `b121/fix/tools/mutate_a2f.py`, logs `b121/fix/mutlogs-a2f/` (scratch). Each run used its own `git archive` copy and its own `next build`, then ran `funnel-bar.test.tsx`, then `funnel-bar.spec.ts` with `booking.spec.ts`: 20 cases, ports 3000 and 8787 free before and after. Each edit was asserted to apply once, and the mutated file was diffed with the commit's:

| Mutation | Unit, red of 2 | E2E, red of 20 | The guards that went red |
|---|---|---|---|
| None (the control) | 0 | 0 | none: 20 of 20 green |
| The stay-at-end moves by the normal bar's 65 px, not to the new end (`BarClearance`) | 0 | 1 | F3 at the 200 % font only: « left at 1428, the page now ends at 1476 ». With normal text 65 px is the bar's height, so those two cases stay green |
| The stay-at-end branch removed (`BarClearance`) | 0 | 3 | F3 3 of 3; at the 200 % font « left at 1363, the page now ends at 1476 » |

*Gates on `96e56f61`* (this commit adds docs only):
- `tsc --noEmit`, and ESLint `--max-warnings=0` on `BookingFlow.tsx` and `funnel-bar.spec.ts`.
- vitest on the 7 unit files that reach the bar or `BarClearance`, plus `salon-page.test.tsx`: 126 of 126.
- `funnel-bar.spec.ts`, `booking.spec.ts` and `type-overflow.spec.ts` together: 139 of 139, with its own `next build`, in Playwright's Chromium 149, ports 3000 and 8787 free before and after.
- That build's three stylesheets are byte for byte the review's build of `65b38d85` (the same three files), so the new comment spells no class.
- The five store-linked pages: the walker (`b120/confirmer/tools/walker.py`) finds their 56 files, none changed from `ce27e839`, with `BookingFlow.tsx` and `BarClearance.tsx` outside. Its controls fire: seeded from the funnel it reaches both (61 files), and `BarClearance` planted in `/cgu` on a copy grows the closure to 57 and names `app/cgu/page.tsx`.
- The whole e2e suite, 668 of 668 in 3.7 min (665 before, plus #741's two new cover rows and F3's third case), then the whole unit suite, 2,749 of 2,749 in 207 files, one at a time, ports 3000 and 8787 free before and after.

*Not run after the review:* Lighthouse; Safari, Firefox and real phones; CI.

### 6.8 Rollout

- `feat/web-funnel-bar-fixed`, cut from `feat/web-salon-cover` at `be5eeb3e`: this spec in its own docs-only commit; then the code, `a2f.patch` applied and `BookingFlow.tsx` proved byte-identical to the measured build's, with its tests; then the record in §6.7; after the build's review, rebased onto `1293bc4e`, then the hub's comment, F3 at the 200 % font, and these corrections with their record. Commits authored as the owner, conventional, with no tool attribution.
- **Pictures** (2026-11-09): one sheet, [before and after](assets/web-funnel-bar-end.png), `1293bc4e` (this branch's base, the funnel's code as on `main`) against `991f5f75`, each the gate's `next build` from a fresh archive, served side by side against one stub, in Playwright's Chromium 149, the install banner dismissed; the funnel shows no photo, and any image would have been a grey placeholder. The very end, with a service, « Pas de préférence » and a time chosen, at 320×568, 390×844 and 844×390 with normal text and at 320×568 with doubled text: before, « Confirmer » comes back after 267, 15, 604 and 507 px of scrolling; after, it is whole and answers, and « Instagram » is 31.8–32.2 px clear of the bar and answers. At 390×844 with doubled text, ten Tabs reach « 09:00 »: before, wholly under the 193 px bar; after, scrolled 409 px and clear. Every box and scroll-back the shots read matches plan 105's (`vals.json`, block `revision`), and each caption is checked against its shot before the sheet is drawn.
- Its PR's base is `feat/web-salon-cover` (#741); it merges after #741, after Apple's decision on the Pro app and on the owner's word. Whether CI runs on a PR into a branch other than `main` depends on the workflow's triggers (unverified), so the local gate runs first, one suite at a time.

### 6.9 Open items

- **UNVERIFIED:** Safari/WebKit and Firefox/Gecko (not installed; downloading them needs the owner's word): `position: fixed` under iOS Safari's moving toolbar and `scroll-padding` on `<html>` in WebKit; real phones and real text scaling; the signed-in hub (inferred the same: the session is read on the confirm step only); salons other than the stub's; Lighthouse; that no salon is public today (taken from the earlier stages).
- **`BarClearance`'s doc comment** (« The room the salon page's fixed booking bar is owed (BACKLOG 103) ») describes one of its two users. It is left as it is, because the answer reuses the component unchanged; a wording fix, or moving the file to `components/`, is a later choice.
- **`data-floating-control`** on the funnel's bar, if the funnel ever shows a toast (§6.1).
- **After Apple's decision:** the install banner's row (§6.4).
- **Guards that do not reach, with no defect today** (the build's review):
  - F2, the keyboard, runs with doubled text only (320×568 and 320×256).
  - F3 runs with normal text and the 200 % font, not with doubled text.
  - No guard holds the bar's layer: with `z-sticky` removed the funnel's e2e cases stay green, because the only positioned element after the bar is Next's route announcer.
  - In print `<html>` keeps the bar's inline `padding-bottom` (65 px), the height of the bar that printed before, so a printout is no longer than before.

### 6.10 What this writes in BACKLOG, word for word

Each body below is in `docs/BACKLOG.md` exactly once, character for character. Decision 105 is **appended to**, so what web-swiss-salon.md §3.12 and §4.6 wrote there stays whole. Batch 11's row in « The plan at a glance » is a status line, edited in place and not mirrored.

- **Decision 105**, at its end, before the code: « **Specified on 2026-11-09, before any code,** on that branch, cut from the cover update's branch after decision 106's commits (`web-funnel-bar-fit.md` §6): the bar fixed, `BarClearance` reused as it is, the compact rule kept, and new checks for « Confirmer » and the footer's last link at the funnel's very end, the keyboard, a visitor at the end before the page's script runs, printing, the switch to the compact bar and the confirm step, each to be watched failing on a copy before it counts. »
- **Decision 105**, at its end, after the build: « **Built on 2026-11-09** on `feat/web-funnel-bar-fixed`, each new check watched red on a copy (`web-funnel-bar-fit.md` §6.7); not merged: its PR, based on the cover update's, merges after #741. »
