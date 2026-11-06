# The salon page's price row at doubled text

| | |
|---|---|
| **Status** | Built |
| **Owner** | Sadreddine Daher |
| **Last updated** | 2026-11-06 |
| **Register row** | [WEB-SYSTEM.md](WEB-SYSTEM.md) §15 row 38 |
| **Governs** | `web/components/provider/ServiceList.tsx` · the doubled-text block of `web/tests/e2e/type-overflow.spec.ts` |
| **Skills checked** | `myweli-web-guardrails` |
| **Builds on** | [B11 — the reflow contract](web-b11-reflow.md) · [Amounts that fit](amounts-that-fit.md) |

---

## 1. Goal & scope

At 200 % text on a 320–390 px phone, « Services & tarifs » on the salon page
pushed the whole page to **441 px** wide. A price was `whitespace-nowrap`, and
« 15 000 – 25 000 FCFA » at 32 px needs 301 px beside « Tresses ». This breaks
WEB-SYSTEM §9's « 320 wide » rule.

Measured on main (5e3b3449) in Chromium's mobile emulation on the e2e stub
(`/beaute-divine`). **Real phones are not verified.**

| Mode | What happened |
|---|---|
| **Android-style doubled text** (touch phone, DPR 2, `text-size-adjust: 200%`) | The layout viewport grew to **441×783** on a 320×568 screen (441 at 360 and 390 too). The « Réserver » bar sat at y 686–783, below the visible 568, until the user zoomed out. The favourites toast landed at x 94–347, y 623–759: off the bottom and 27 px past the right edge, with « Annuler » ending at x 323. |
| **Browser font at 200 %** (root 32 px) | The page scrolled sideways: scrollWidth 441 at 320, 360 and 390. |

The existing reflow gate runs 320 px only at normal text, so it never saw this.

**In scope:** the price row, and a gate that runs the salon page at doubled text.
**Out of scope** (§6): the seven other pages that widen under Android-style
doubled text, the bar's height at doubled text, and the duration variants the
app shows and the web does not.

## 2. Cause, verified with a control

The control used the same build and the same browser. Only the copy of the
served HTML changed: `whitespace-nowrap` was removed from the two price
paragraphs, and nothing else. As a negative control, a different class
(`text-textPrimary`) was removed from the same element instead.

| Mode | Screen | As served | Price `nowrap` removed | Other class removed |
|---|---|---|---|---|
| Android doubled | 320 | 441×783 | **320×568** | 441×783 |
| Android doubled | 360 | 441×696 | **360×568** | 441×696 |
| Android doubled | 390 | 441×643 | **390×568** | 441×643 |
| Font 200 % | 320 / 360 / 390 | scroll 441 | **320 / 360 / 390** | scroll 441 |

With the price free to wrap, the bar returned to y 431–568 and the toast to
x 34–286. The price is the only cause on this page.

The control also showed that **removing the class alone is not a fix**: both
the name and the price then shrink, so « 5 000 FCFA », which fits today, breaks
onto two lines beside « Soin / visage ».

## 3. UX — decided 2026-11-06 (option B)

**A price that can't sit beside its service moves to the line under it, still
on the right edge.** The content order stays name → duration → price. This is
[amounts-that-fit.md](amounts-that-fit.md)'s rule: take the widest shape in
which every value stays whole, and give up a column before you break a number.

- **A number never breaks.** `Intl.NumberFormat('fr-FR')` groups with U+202F,
  which is a no-break space. If the price is still wider than the whole line,
  it breaks only at a word space: « 15 000 – 25 000 » / « FCFA ».
- **Normal text size: unchanged.** The price moves only when the name's longest
  word and the full price can't share a line, which is exactly when the page
  used to overflow. Screenshots at 320 and 375, with short and long names, were
  byte-identical before and after.
- **Doubled text.** At 320 « Tresses » keeps its line and the price takes the
  next one (two lines, right-aligned); at 360 and 390 the price fits on one line
  under the name. « Soin visage » + « 5 000 FCFA » still share a line, as today.

**Rejected:**

- **A, the app's `_ServiceTile`** (an `Expanded` name beside a `Flexible`
  end-aligned price). The price stays beside the name and breaks in its own
  column, which is three lines at 320. It also fixes the overflow, but the
  range no longer reads as one line.
- **B-left** (the moved price starts at the left). Prices jump between left and
  right from one row to the next.

The flow is the app's; only the arrangement at doubled text differs
(web-design latitude).

All four states are unchanged: the list renders nothing when no service is
active, and it has no loading or error state of its own. The page owns those.

## 4. Build

`ServiceList.tsx` only:

| Element | Before | After |
|---|---|---|
| row `<li>` | `flex items-baseline justify-between gap-m py-s` | `flex flex-wrap items-baseline justify-between gap-x-m py-s` |
| name block | (no class) | `flex-1` |
| price | `whitespace-nowrap text-textPrimary` | `ml-auto text-right text-textPrimary` |

How it works. `flex-1` gives the name block a basis of 0, so the line-break
decision weighs only its min-content (its longest word) against the price's full
width. When they fit, the name grows into the free space, and the price sits
where it always did. When they don't, the price wraps to its own line, where
`ml-auto` keeps it at the right edge. The row gap stays 0: the duration's line
height already separates them.

**Only existing utilities.** Every class above was already in the built CSS,
and `whitespace-nowrap` and `gap-m` stay in use elsewhere, so the stylesheet is
unchanged. Checked by comparing the built CSS files before and after (§5).

**Apple constraint.** `ServiceList` is imported only by `ProviderView` (the
salon page and the Pro preview). It is not in the import graph of the five
store-linked pages, and neither is anything else this change touches.

## 5. Testing

The guard is a new block in `type-overflow.spec.ts`: the salon page at 320×568
in both doubled-text modes, plus normal text.

| Assertion | Why |
|---|---|
| The price's computed `font-size` is 32 px | The vacuity guard: if a Chromium build ignored the emulation, every check below would pass about 16 px text. |
| `innerWidth × innerHeight` equals 320 × 568 | A grown layout viewport is what put the bar and the toast off screen. This check doesn't depend on how the bar is built (#741 rebuilds the bar and the toast). |
| `horizontalOverflow` is empty | The existing helper; it names the element that starts an overflow. |
| Every price inside its row | A price can poke past its row without the page scrolling (§7). |
| The longest price really wraps | The vacuity guard for the next check. |
| No token of a price spans two line boxes | A token is a run between plain spaces: a number with its U+202F grouping, a word, the dash. This is amounts-that-fit.md §2's « whole ». Measured with a text `Range`, not inferred from class names. |
| The five generic checks of the file | Spill, nowrap rows, vertical clipping, truncation. |
| Normal text: each price sits on its service's line, at the right edge | The default look can't drift silently. |

**The stub's prices are too short to test the rule**, so the second service
shows `priceRange(150000, 250000)`, written into the page rather than the stub
(other specs count on the stub's prices). See §7 for why.

Watched red, each on a fresh build of committed code (§7): main's
`ServiceList`; `whitespace-nowrap` put back; a price that always takes its own
line (`basis-full`); `break-all` on the price.

Also checked:

- **The five store-linked pages:** the built CSS files are byte-identical,
  and every element's computed style and box is identical at 375, 820 and 1280
  (the dump was run twice on main first, to prove it is stable).
- The unit suite, lint, typecheck and the full e2e suite.

## 6. Seen, not fixed here

- **Seven more pages widen under Android-style doubled text** at 320 (the font
  200 % mode passes on all of them): `/` and `/recherche` 352 (the card's
  « Note ★ 4,8 » is `whitespace-nowrap`, and #737 rewrites that card),
  `/beaute-divine/reserver` 344 (fixed since, [web-funnel-doubled-text.md](web-funnel-doubled-text.md)),
  the 404 336 (frozen too: its markup ships in every store-linked page). Three are
  store-linked and frozen while Apple reviews the Pro app: `/support` 352,
  `/politique-confidentialite` 375, `/mentions-legales` 343
  (« support@myweli.com »). Register row 38.
- At doubled text the booking bar takes 137 px of a 568 px screen
  (« À partir / de 5 000 / FCFA » on three lines), and the toast sits over it.
- Parity: the app lists the Court / Moyen / Long duration variants under each
  service; the web doesn't.

## 7. What was measured

**Red on main first.** In the Android mode the guard read the viewport as
`[441, 783]`; with the 200 % font, `horizontalOverflow` named
`<p class="whitespace-nowrap text-textPrimary"> right 441 > 320`.

**The first version of the guard let two mutations pass, and that is the
finding of this build.**

- **`whitespace-nowrap` put back** on the fixed layout. The price drops to
  its own line, 301 px on a 288 px line, and ends at x 317: past its row,
  inside a 320 screen, and invisible to every check.
- **`break-all`.** At 32 px « 15 000 – 25 000 » still fits one line, so no
  number was ever asked to break.

The guard then gained the longest plausible price and the row-containment
check. `break-all` passed again, cutting « F / CFA » instead of a number,
until the token check took words as well as numbers. JavaScript's `\s`
matches U+202F, so tokens are split on U+0020 only. This is the trap
amounts-that-fit.md §1 recorded for Dart.

**The final guard, each run on a fresh build:**

| Run | Result |
|---|---|
| The fix | 4 passed |
| Main's `ServiceList` | red: viewport `[459, 815]` · the page scrolls sideways (two prices named, right 441 and 459) |
| `whitespace-nowrap` put back | red: viewport `[354, 629]` · scrolls sideways, right 354 |
| Price always on its own line (`basis-full`) | red at 320 and 375: « 15 000 – 25 000 FCFA » left the line of « Tresses » |
| `break-all` | red in both modes: a token breaks (« FCFA ») |

**On #741's tree** (345c6b44, the cover update, stacked on #737): with this
change cherry-picked, `type-overflow.spec.ts` and `provider.spec.ts` pass
(122 tests). With #741's own `ServiceList`, the guard fails the same way as on
main: `[459, 815]`. Both branches append to the end of
`type-overflow.spec.ts`, so the second to merge resolves a keep-both conflict.

**The five store-linked pages:**

- The built CSS files are byte-identical, with the same hashed names.
- Every element's computed style and box is identical at 375, 820 and 1280:
  1,698 elements. The dump was stable across two runs on main, and the
  comparator catches one planted property.
- No changed file is in their import graph (56 files from nine roots). The
  walker was checked against `lib/storeLinkedPages.ts` and
  `styles/globals.css`, which it finds.

**Suites:**

- Unit: 195 files, 2,550 tests. Lint and typecheck clean.
- `type-overflow`, `provider` and `axe` specs: 120 passed.
- The full e2e suite is left to CI. Another session's e2e run held ports
  3000/8787, so the local runs used a throwaway config on 3100/8887, and
  `booking.spec.ts` and `served-html.spec.ts` hardwire 8787.

**Not verified:** real phones. Every figure here is from Chromium's mobile
emulation.
