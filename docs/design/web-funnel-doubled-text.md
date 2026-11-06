# The booking funnel at doubled text (and the 404, after Apple)

| | |
|---|---|
| **Status** | Built (funnel) · planned (404, after Apple's decision) |
| **Owner** | Sadreddine Daher |
| **Last updated** | 2026-11-06 |
| **Register row** | [WEB-SYSTEM.md](WEB-SYSTEM.md) §15 row 38 |
| **Governs** | `web/components/booking/BookingFlow.tsx` (`SectionCard`, `Recap`, the confirm heading, `totalLabel`) · the funnel block of `web/tests/e2e/type-overflow.spec.ts` |
| **Skills checked** | `myweli-web-guardrails` |
| **Builds on** | [The salon page's price row](web-salon-price-reflow.md) (the rule, the guard) · [Amounts that fit](amounts-that-fit.md) §2 |

---

## 1. Goal & scope

Register row 38 found seven more pages widening under Android-style doubled
text. This takes two of them: the booking funnel (`/{slug}/reserver`) and the
404. Measured on main (5e3b3449) in Chromium's mobile emulation (touch phone,
DPR 2, `text-size-adjust: 200%`). The browser-font-200 % mode is clean on both
pages. **Real phones are not verified.**

| Where | Width | Effect | Cause |
|---|---|---|---|
| Funnel, every open step | 320 | the page grows to 344×611, so the « Confirmer » bar is placed off screen | the step headers (`SectionCard`): « Spécialiste » + « Pas de préférence » need 311 of 254 px, and no word can break |
| Funnel, every open step | 360 | « Pas de préférence » runs 17 px out of its card | same row |
| Funnel, confirm step | 320 / 360 | the page grows to 333; the value runs out of its card | the recap rows (`Recap`, `dt`/`dd`, no wrap); « Confirmation » is one word that needs 260 of 238 px |
| 404 | 320 | the page grows to 336×597 | « introuvable » is one word that needs 320 of the heading's 288 px |

The fixed « Confirmer » bar the first sweep listed is a symptom: it spans
whatever width the page grows to.

**The 404 is frozen.** `app/not-found.tsx` is the not-found boundary for every
route, and its markup ships inside every page's HTML. On the built stub,
« Page introuvable » appears in the served HTML of all five store-linked pages.
While Apple reviews the iOS Pro app those pages may not change, so the 404's fix
(§5) waits for Apple's decision.

## 2. UX — decided 2026-11-06

The owner approved all of the following as proposed (private plan with
pictures).

1. **The salon price rule, applied to the funnel's rows.** When a label and its
   value can't share a line, the value moves under the label, on the right
   edge. This covers the three step headers and the recap rows.
2. **« Confirmation » becomes « Confirmer »**, the app's own title for this
   step (`booking_confirmation_screen.dart:226`). Its 9 letters fit at 2×;
   « Confirmation »'s 12 do not.
3. **The total prints « FCFA » once**, « 15 000 – 25 000 FCFA », as on the salon
   page and as [amounts-that-fit.md](amounts-that-fit.md) §2 requires. It read
   « 15 000 FCFA – 25 000 FCFA » in the bar, the side panel and the recap.
4. **The bar's shape is left for a follow-up** (§6).
5. **The 404 gets hyphenation after Apple's decision** (§5).

**Normal text.** Every step at 320 and 375 keeps its layout, with one
exception. Today the date card at 320 squeezes both sides: the title breaks
into « Date et / heure » and the date into a narrow column. With the fix the
title stays on one line and the date sits beside it, right-aligned. Elsewhere,
cards differ only by sub-pixel glyph positions. The recap is unchanged, even
with a long list of services.

**Rejected:**

- **Label gives way** (`flex-1` on the label, the value whole). It keeps the
  date on one line, but moves a long service list under « Prestations » at
  normal text.
- **Stack left** (`flex-wrap` only). It drops the date under its title at
  normal text.

All four states are unchanged.

## 3. Build

| Element | Before | After |
|---|---|---|
| `SectionCard` header `<button>` | `flex … justify-between gap-m` | `flex flex-wrap … justify-between gap-x-m` |
| its value `<span>` | `text-bodyMedium text-textSecondary` | `flex-1 text-right …` |
| `Recap` row | `flex justify-between gap-m` | `flex flex-wrap justify-between gap-x-m` |
| its `<dd>` | `text-right …` | `flex-1 text-right …` |
| confirm `<h2>` | « Confirmation » | « Confirmer » |
| `totalLabel` | `formatFcfa(min) – formatFcfa(max)` | `priceRange(min, max)` |

How it works. A `flex-1` value has a zero basis, so the line-break decision
weighs only its longest word against the label. When they fit, the value takes
the rest of the line and `text-right` keeps it on the edge. When they don't,
the value wraps to its own line and fills it, still right-aligned.

Only existing utilities are used, so the built CSS is unchanged.
`BookingFlow.tsx` is outside the store-linked pages' import graph.

## 4. Testing

A funnel block joins the doubled-text tests in `type-overflow.spec.ts`. It walks
the funnel in both modes at 320×568: steps open, slot picked, the confirm step.

| Assertion | Why |
|---|---|
| A step title is 32 px | The vacuity guard for the mode. |
| `innerWidth × innerHeight` equals the screen | The Android case, which `horizontalOverflow` can't see. |
| `horizontalOverflow` is empty | Names the element that starts an overflow. |
| Every value inside its row | A value can run out of its card without the page scrolling. |
| No token of a label or value spans two lines | A date, a time, a price, a salon's name: SYSTEM.md §13.3. |
| The file's five generic checks | They catch « Confirmation » spilling its card. |
| The bar's total equals `priceRange(15000, 25000)` | Nothing else pins the unit-once rule. |

**Normal text, at 320 and 375:** every value sits on its label's line, at the
row's right edge.

Controls are clicked through the DOM. At doubled text the bar covers half the
screen (§6), and a pointer click at the scrolled-to point lands on the bar.
That cost is recorded, not tested around silently.

Watched red, each on a fresh build of committed code (§7):

- main's `BookingFlow`;
- the header without `flex-wrap`;
- the recap row without `flex-wrap`;
- a header value that always drops (`basis-full`);
- the double-unit total;
- « Confirmation » back.

## 5. The 404 — after Apple's decision

A single word can't wrap its way out. SYSTEM.md §13.3 allows a hyphen between
letters, so the heading gets `hyphens-auto`, with `break-words` as the fallback
for browsers without French hyphenation. CI's Linux Chromium may be one of
them: there the word breaks without a hyphen rather than widening the page.
Android Chrome and Safari hyphenate French. Measured on the Mac's Chromium:
« Page / introu- / vable », and the page stays 320 wide. The guard then joins
the 404 to the doubled-text block, asserting the viewport and no spill but not
the hyphen, since CI can't produce it.

## 6. Seen, not fixed here

- **The bottom bar at doubled text** — *fixed since, in [web-funnel-bar-fit.md](web-funnel-bar-fit.md): sticky, and compact above a quarter of the screen.* It covered 42 % of a 360 or 390 screen
  before this change. After the fix it covers 57 % at 320; printing the unit
  once brings that to 48 % at 320 and 34 % at 360 and 390. Two follow-up
  options:
  - at large text, the total moves into the page and the bar holds only
    « Confirmer »;
  - the bar stacks like the app's summary (`booking_hub_screen.dart:820`).
- **Parity.** The app's summary shows one total (`formatCurrency(totalPrice)`);
  the web shows a range.

## 7. What was measured

**The guard, each run on a fresh build of committed code** (stacked on #742):

| Run | Result |
|---|---|
| The fix | 4 passed |
| Main's `BookingFlow` | red in all four: Android viewport `[344, 611]` at the first step; « FCFA » printed twice in the other three |
| Step header without `flex-wrap` | red: Android viewport grows at the first step |
| Recap row without `flex-wrap` | red: Android viewport grows at the confirm step |
| A header value that always drops (`basis-full`) | red at 320 and 375: « Choisir » left the line of « Prestations » |
| The double-unit total | red in all four: « a total prints « FCFA » twice » |
| « Confirmation » back | red: Android `<h2> "Confirmation" 260>238` spills its box; with the browser font, the « Confirmer » heading is not found |

The first green run failed on the guard itself: the step-title check matched
the recap's « Prestations » (a 14 px `dt`) by name. Rows now carry their kind.

**A measurement trap, found while prototyping.** Chromium implements
`text-size-adjust` through its text autosizer, which recomputes when the DOM
changes. An element screenshot, or a text node edited in place, silently put
the funnel back at normal size. The guard therefore checks the size at every
step, including a confirm-step check on the recap's 14 px labels (28 in the
Android mode). The plan's pictures are viewport screenshots, each checked
at 32 px.

**Two mutation runs timed out once** with « Timed out waiting 180000ms from
config.webServer »: a macOS background burst (Contacts, Reminders, Siri)
pushed the load average to 72. Rerun when it fell below 12, both went red.

**Beyond the guard:**

- **The funnel, walked step by step** at 320, 360 and 390 in both modes: the
  viewport keeps the screen's size and nothing runs past the edge.
- **The five store-linked pages:** the built CSS files are byte-identical to
  main's. Every element's computed style and box is identical at 375, 820 and
  1280 (1,698 elements).
- **Suites** (this stacked PR gets no CI until #742 merges):
  - the full e2e suite on the default ports: 429 passed;
  - unit: 195 files, 2,550 tests;
  - lint and typecheck clean.

**Not verified:** real phones. Every figure here is from Chromium's mobile
emulation.
