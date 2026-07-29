# A13 — two breaks, one pin, and twelve plurals (mobile)

| | |
|---|---|
| **Module** | Design system (cross-cutting) — [MODULES.md](../MODULES.md) |
| **Status** | Shipped (2026-07-29) |
| **Governs** | `announcement_stories.dart` · `provider_detail_screen.dart` (header) · `design_system_pin_test.dart` (§5, §17.1) · `Formatters.count` · SYSTEM.md §13.3, §17.1, §21 rows 41, 62, 71 |
| **Predecessor** | [mobile-a12-census.md](mobile-a12-census.md) · [web-b9-tabs.md](web-b9-tabs.md) (the same campaign's web half) |
| **Skills checked** | myweli-dev-guardrails · myweli-backend-guardrails |

## 1. Goal & scope

The mobile half of the four-row campaign B9 started. Rows **62**, **71** and
**41**, plus the « Client » placeholder row 41 found in its own golden.

Verification corrected three of the four rows before any code, and one
correction changes the *fix* rather than the prose:

| the row says | measured |
|---|---|
| 62: both open items are **headings**, and whether a heading may break "is a design decision this slice does not make" | The story card declares **`Semantics(button: true)` + `InkWell(onTap:)`, and its title IS the control's accessible name** (`announcement_stories.dart:133-137`). §13.3 already forbids breaking "any control's label" — it was never a heading question. Only the salon header is |
| 71: "two live ones remain in its corpus"; the excluded pair are `10` | **All four `10`s are in the corpus** (4 literals, 2 files). The `features/` pair are **`12`** |
| 41: "1 confirmed, unswept" | **12 plural defects** — 7 `(s)` + 4 hard-coded + 1 n=0 bug — plus 1 latent and 1 gender `(e)`. **Two** committed goldens photograph them |

## 2. Row 62 — the story cards

### 2.1 Three mechanisms, stacked

- `:52` — the hyphen in `'Promo Week‑End'` is **U+2011, NON-BREAKING**, so
  `Week‑End` is a single unbreakable token;
- `:140` — `Container(width: 92)`, a **fixed width around text**;
- `:118` — `SizedBox(height: 126)`, a **fixed height around text**;
- and the ring is **inset twice**: `Container` applies `decoration.padding`
  (= the border's dimensions) *on top of* the explicit
  `Padding(all: ringWidth)`. So the text box is `92 − 4·ring − 16`.

That last one has a consequence worth naming: **the title's box depends on
whether the story has been seen** — 64dp unseen (ring 3), 72dp seen (ring 1).
A fix must compute from `ringWidth`, not hard-code either number.

### 2.2 The break starts at 1.20×, not 2× — so a threshold is the wrong tool

Measured from the SDK's own Roboto (`hmtx`/`cmap`, validated to ±1% against the
four widths `test/support/fonts.dart:40-47` already records):

| token | breaks the 64dp unseen box above |
|---|---|
| `Week‑End` | **1.20×** |
| `Nouveau` | 1.38× |
| `Dernière` | 1.43× |

**All three titles break**, so replacing the U+2011 with a breaking hyphen fixes
one of three and is not a fix. And **`_kActionGridSingleColumnAbove = 1.3` would
be too late** — it would leave `Week‑End` broken across 1.20×–1.3×, which is
inside the range users actually pick.

### 2.3 The fix: a scale-tracking width

The idiom is `ProviderCard.minGridCellWidth` (`provider_card.dart:100-107`) — a
cross-axis measure computed with `AppTheme.textScaledBound`, where `constant` is
the chrome that must not move and `text` is the 1× text box:

```
constant = 16 (the Positioned insets) + 4 · ringWidth
text     = 92 − constant
```

`textScaledBound` is `constant + max(text, scale·text)`, so this returns
**exactly 92.0 at 1×** and at every scale below it. **The 1× goldens are
byte-identical**, which is the property a threshold was chosen for — obtained
here without the 1.20×–1.3× hole. Clears every token to 3× with ≥23% headroom.

The `height: 126` goes the same way — but **computed, not intrinsic**, and §8
records why the first attempt was wrong. The tempting argument (three items,
nothing to virtualise, so drop the bound as `CategoryChips` and
`client_list_screen` did) collapses these cards to a bare ring: their content is
a `Stack` of `Positioned.fill` children, which contribute nothing to intrinsic
height. Those precedents work because their chips wrap real text.

## 3. Row 62 — the salon header

`provider_detail_screen.dart:283`. The name gets `W − 24 − 72 − 16 − 24` = **224dp
at 360**, while `Excellence` needs **270.3dp at 2×** — so it breaks above
**1.66× / 1.77× / 1.88×** at 360/375/390, and « Salon Ex / cellence » at the
≈1.95× contract point is reproduced exactly by that arithmetic.

**Shrinking `_SalonLogo` cannot work.** Measured: even at a 40dp logo the name
box is 256 and still breaks; **deleting the logo entirely** gives 312 and only
just clears 2×. Rejected on measurement, not taste.

**`maxLines: 3` is worse than useless.** `expectNoMidWordBreak` compares widest
word against box width and is line-count-blind, so a third line moves the
assertion by zero — and it adds 72dp at 2× to a header with **0.0dp of slack**
(see below), converting a mid-word break into a `RenderFlex` overflow.

**The fix is to stack** — the logo above the name above a text-scale threshold,
giving the name the full 312dp (clears to 2.31×). Two precedents in this very
file's history: `provider_detail_screen.dart:1053` stacks the action bar, and
`dashboard_screen.dart:397` stacks the action grid. The threshold here is
**~1.6×, not 1.3×**, and it is worth saying why: the true crossing is
width-dependent (1.66 / 1.77 / 1.88), which is exactly the situation
`provider_card.dart:92-99` says makes a scale constant wrong. We take the worst
case and accept that 390dp stacks marginally earlier than it must, rather than
computing a width-dependent branch for a header that has one call site.

**The constraint that decides the implementation.** `expandedHeight` is
`textScaledBound(constant: 68, text: 92)` = **252 at 2×**, and the content at 2×
measures **252 exactly**: 144 (2 name lines) + 8 + 32 + 4 + 32 + 32 padding.
**Zero slack.** Stacking adds the 72dp logo plus its gap, so `_headerChrome`
needs a stacked twin (≈148) — and it must be **re-measured**, not assumed, the
way the original 68/92 split was.

## 4. Row 71 — the pin

Widen with an **explicit alternation**, not a wildcard:

```dart
(?:\b(?:run)?|(?:cross|main)Axis)[Ss]pacing:\s*\d
```

A naive `[A-Za-z]*[Ss]pacing:` reds on **7 `letterSpacing:` false positives** —
precisely what the original `\b` existed to prevent, so the wildcard would
"close" the gap by reintroducing the bug it was written against. `\s*` also
closes the wrapped-argument hole.

Red at **4**: `pro_photos_screen.dart:141-142` and
`mock_image_picker_sheet.dart:46-47`, all `10`, which is not on the scale
(4/8/12/16/24/32/48/64) → `spacingSM`. Plus the **non-empty corpus guard** the
spacing test lacks; the `childAspectRatio` and animation tests have one and this
test has been borrowing their credibility.

## 5. Row 41 — the plurals

**The true count is 11 conversions**, not 1 — and the first draft said 12 by
counting the sweep's *sites* rather than its *edits*. Honestly decomposed: 7
literal `(s)`, **3** hard-coded plural nouns (two in `pro_onboarding_screen`,
one in `message_templates`), and one n=0 bug — plus a latent `== 1` and a gender `(e)`.

**And the first draft said web had zero, which the review disproved.**
`JournalPanel.tsx` hard-coded « visites » and « absences » unguarded — « 1
visites » for a one-visit client — and `lib/pro/clients.ts` used `=== 1` rather
than `> 1`. Both fixed here with a `countFr` twin over `Intl.PluralRules('fr')`,
so the claim now true is: web had **two**, mobile had twelve.

**One helper.** `Formatters.count(n, one, other)` wrapping `Intl.plural` with an
**explicit `locale: kAppLocale`**. That argument is load-bearing:
`Intl.getCurrentLocale()` falls back to `en_US`, and English differs from French
**only at n = 0** — which is exactly the bug — so a test outside `wrapApp` would
silently pass on the wrong rule. `Intl.plural` needs no other wiring;
`initAppLocale()` already runs in all three roots and in `wrapApp`, and has had
**zero callers** since A9 wired it.

**A third §17.1 pin**, beside the ellipsis and apostrophe ones. §17.1's own
precedent is the justification — *"A9 fixed what the app contradicted itself
about"* — and the app contradicts itself here: `(s)` in 7 places against 17
correct plurals.

**`invité(e)` is not in scope.** It is gender, not count, and it is asserted
verbatim by `pro_login_invitations_test.dart:92,137,149`. Named as an exception
with prose rather than swept in silently.

## 6. « Client » — the placeholder that ships

`booking_service.dart:123` writes `'clientName': null` for **every
app-originated booking**, so a pro sees « Client » for every booking made
through the app. The literal is duplicated in three Flutter screens and once in
`clients_service.dart:370`.

**The erasure pre-check is done: SAFE.** `eraseUser` **hard-deletes** the
identity row (`postgres_auth_repository.dart:375`,
`DELETE FROM users WHERE id = @id`; in-memory twin `auth_repository.dart:425`;
asserted at `me_erasure_test.dart:428`). There is no foreign key from
`appointments.user_id`, so the id dangles harmlessly. No name can be resurrected.

**But the fix is neither a `users` join nor `clientName`:**

1. `appointment_card.dart:265` gates the **« Réservé par votre salon »** badge on
   `clientName != null` (pinned by `appointment_card_test.dart:35`). Filling
   that field would fire the badge on every booking.
2. `salon_clients.display_name` **already holds the real name**, written at
   booking time by `recordBooking` (`clients_service.dart:355`), and erasure
   **already anonymises it** to the same `'Client'` literal
   (`postgres_clients_repository.dart:225`, `anonymized_identity.dart:29`).
   Safe by two mechanisms rather than one.

So: a new **`clientDisplayName`**, surfaced through the existing `_identityOf`
hook (`clients_service.dart:453`) inside `enrichForProvider` (`:422`) — the one
point both name-carrying pro reads funnel through
(`routes/appointments/index.dart:70`, `journal_service.dart:77`).

**It joins the off-day mask.** `maskContactsOffDay` (`:403-418`) strips
`clientPhone` only; `clientDisplayName` strips with it, so an own-scope
Collaborateur cannot harvest the salon's client list by browsing days they do
not work (BACKEND.md T40/R4a). The threat model gains a row stating that
off-day masking now covers **name + phone**.

**Known staleness, recorded not fixed:** `recordBooking` early-returns when the
`salon_clients` row exists (`:340`), so a later profile rename does not
propagate to `display_name`.

### 3.1 The threshold was taken from the wrong population

Found by the adversarial review, and it is the sharpest finding in the slice.

**The verified badge is a SIBLING of the name's `Flexible`**, and a `RenderFlex`
lays its non-flex children out first — so `spacingS` (8) + `iconS` (20) come off
the name's box before it gets anything. **196dp at 360, not 224.** Since
`headlineMedium` has `letterSpacing: 0`, « Excellence » scales exactly linearly
from 134.85dp at 1×, which puts the real crossings at:

| | unverified | **verified** |
|---|---|---|
| 360 | 1.661× | **1.453×** |
| 375 | 1.772× | **1.565×** |
| 390 | 1.884× | **1.676×** |

A single 1.6 threshold therefore left « Salon Ex / cellence » live from **1.45×
to 1.60×** on a 360dp phone — on the salons the marketplace most wants to
promote. `_headerStacksAboveVerified = 1.45` covers it, rather than dragging
every unverified salon to an early stack.

**And the gate was blind twice over**: `MockData` sets `verified` on no provider
at all, and `layout_test`'s `scales = [1, 2]` skips the entire defective band.
`salon_header_test.dart` closes both — it reproduces the header's `Row`
arithmetic and asserts the un-stacked geometry breaks at each width's *own*
crossing (1.5 / 1.6 / 1.7), plus that an unverified salon at 1.5× does not,
which is what makes two constants right rather than one conservative one.

## 7. Testing

| | |
|---|---|
| row 62 | `expectNoMidWordBreak` on all three story titles at the consumer-home subject, and on « Salon Excellence » at the salon-page subject — 3 widths × 2 scales each |
| row 71 | the widened §5 pin, red at 4, plus a non-empty corpus guard |
| row 41 | the §17.1 `(s)` pin red at 7, plus a `Formatters.count` unit test **including n = 0 with the locale unset**, which is the only configuration where the bug is invisible |
| « Client » | three backend negatives: an **erased** user's bookings still read « Client »; an **off-day Collaborateur** sees neither name nor phone; a normal provider sees the name |

Every gate watched red before its fix.

## 8. Definition of done

- [x] every gate red first — story titles **3 of 6** (64.0dp box, « Week‑End »
      needs 104.1); salon name **3 of 6** (224.0 / 239.0 / 254.0 against 269.7,
      at 2× only — the box does not scale, so 1× was never red); §5 pin **4**;
      §17.1 pin **7**. *The salon subject did fail 6 of 6 on its first run, but
      for a different reason — `tester.renderObject` threw «Too many elements»
      at every configuration, which is the instrument bug §7 records, not the
      defect.*
- [x] the three story titles and the salon name whole at 2× on all three widths
- [x] §5 pin widened without the 7 `letterSpacing` false positives; the 4
      literals converted; the sweep gained the non-empty guard it lacked
- [x] the plural sweep's true count reported (**12**) and fixed; §17.1 gains its
      third row; §13.3's salon-name carve-out rewritten
- [x] `clientDisplayName` shipped with its negatives, the off-day mask widened,
      T40 restated, `openapi.yaml` + web schema in step
- [x] goldens: **4 moved, and `consumer_home.png` was NOT one of them** — but it
      moved on the first regeneration and the picture showed why (see below).
      `consumer_provider_detail.png` never moved. Every changed PNG opened
- [x] device run at both sides of the branch — 1× unchanged, and at ≈1.95×
      « Promo / Week-End » and a stacked header both confirmed on hardware
- [x] adversarial review — **14 findings, every one hand-verified.** Two were
      real defects: the stacking threshold measured on unverified salons only
      (live 1.45×–1.60× at 360, and the gate blind twice over), and the
      « Client » fix stopping at the app while five web pro components still
      showed the placeholder. Seven were wrong claims in A13's own prose,
      including a non-existent French string shipped into the API contract

### The regeneration caught a regression the arithmetic did not

The first pass dropped the strip's bounded height entirely, on the argument that
three items need no virtualising — the same argument `CategoryChips` and
`client_list_screen` used. `consumer_home.png` moved, and opening it showed the
strip rendered as **three thin gold bars**: a card's content is a `Stack` whose
children are all `Positioned.fill`, and positioned children contribute **nothing**
to intrinsic height. Those precedents work because their chips wrap real text.

The height is computed like the width now, and `consumer_home.png` is
byte-identical again. **No assertion in the suite failed on this** — 1019 tests
were green with the collapsed strip, because nothing overflowed and nothing
truncated. §20.1's "look at every changed PNG" is the only thing that caught it.

## 9. Two things rejected explicitly

So they are not re-proposed as fresh ideas:

- **Replacing U+2011 with a breaking hyphen.** Fixes `Week‑End` to 2.02× and
  leaves `Nouveau` broken from 1.38× and `Dernière` from 1.43×.
- **Shrinking `_SalonLogo`.** Measured at 56/48/40dp: all still break at 2×.
  Deleting it outright only just clears. And §13.3's standing answer applies —
  *"the fix is always more width, never a smaller font."*
