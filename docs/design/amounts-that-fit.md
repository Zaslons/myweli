# Amounts that fit — and the four other defects the review of build 569 confirmed

| | |
|---|---|
| **Status** | **Approved** (owner, 2026-10-13: the direction — « measure, then lay out », no smaller font, no shorthand — then « yes to all » on the six questions of §11) — building |
| **Owner** | Sadreddine Daher |
| **Last updated** | 2026-10-13 |
| **PRD ref / phase** | Pro app — clients, home · consumer app — reviews · web Pro dashboard · V1 |
| **ROADMAP entry** | [2026-10-13-build-569.md](../roadmap/entries/2026-10-13-build-569.md) (« Défauts confirmés par la revue, pour le build suivant ») |
| **Skills checked** | myweli-dev-guardrails · myweli-web-guardrails · myweli-verification-guardrails |
| **Governs** | `Formatters.formatCurrency` / `formatPriceRange` · a new `core/utils/text_fit.dart` · `client_detail_screen.dart` (`_StatsStrip`) · `dashboard_screen.dart` (stat rows) · `my_bookings_screen.dart` (`_summaryMetric`) · `test/a11y/_a11y.dart` (`expectNoMidWordBreak`) · `provider_provider.dart` (`addReviewLocally`) · web `ManualBookingDialog.tsx`, `ClientCardClient.tsx`, `lib/format.ts` |

## 1. Goal & scope

The adversarial review run before build 569 was uploaded confirmed five
defects, none a blocker ([pro-screenshot-shoot-fixes.md](pro-screenshot-shoot-fixes.md)
shipped the fixes they sit next to). Each was re-read in the code on
2026-10-13 by a mapping pass (five readers and a critic); what was **observed**
rather than computed is marked.

1. **A money amount breaks in the middle of the number.** On the Pro client
   card, « Dépensé » sits in a quarter-width tile: on a 360 dp phone a
   six-digit amount breaks from about 1.04× text and a seven-digit amount at
   the default size. On the Pro home, « 114 000 FCFA » breaks from about 1.5×.
   Both layouts choose their shape from a **text-size constant**, which cannot
   know the amount or the width (SYSTEM.md §13.3 already says a width question
   is not a scale constant). *Widths are computed from the font tables, not
   yet rendered — step 1 measures them.*
2. **The guard could not see it.** `expectNoMidWordBreak` splits its text on
   `\s`, and Dart's `\s` matches the no-break spaces that group French numbers
   — **observed**: `RegExp(r'\s')` matches U+202F and U+00A0. « 180 000 » was
   checked as « 180 » and « 000 ».
3. **Every price carries a doubled gap before « FCFA ».** **Observed**:
   `formatCurrency(180000)` is `180` U+202F `000` U+00A0 U+0020 `FCFA` — the
   no-break space the French currency pattern leaves behind, then the plain
   space the code adds. It shows in every screenshot (« 10 000  FCFA »), the
   web prints one space, and a price range prints the unit twice
   (« 15 000 FCFA – 25 000 FCFA ») where its own doc comment and the web
   print it once.
4. **A review sent again is counted twice** (consumer app). The server keeps
   one review per appointment and replaces it; the app adds one to the count,
   blends the average and shows both. And only the open salon page is
   updated: the map sheet, the home cards and the favourites keep « Nouveau »
   until a reload.
5. **Two web Pro gaps.** The manual-booking dialog still shows the SMS
   checkbox, ticked by default (« bientôt disponible »), and sends
   `sendSmsInvite: true`; the web client card prints the raw
   `+2250700000101`.

Found on the way, small enough to ride along: « dernière À l’instant » in
the Pro clients list (`formatRelative` returns a capitalised phrase that the
list puts mid-sentence).

**Out of scope, registered instead** (SYSTEM.md §21, one row each, with the
computed limit): the visit-history rows and the earnings total and rows, the
manual-booking date field, the appointment list and calendar lines, the admin
console tables. They are the same class at far larger text sizes; the
report-only sweep of step 1 gives their real count. Also out: a real
« modifier mon avis » flow (consumer-reviews.md §9), and the backend change
that would make the review figures exact (§3).

## 2. UX & flows

**One rule replaces three constants: a layout takes the widest shape in which
every value stays whole.** Nothing is ever shrunk, cut or abbreviated; what
gives way is the number of columns.

| Surface | Shapes, tried in this order | Today |
|---|---|---|
| Pro client card — Visites · Dépensé · Absences · Dernière | 4 across → 2 × 2 → one per row | 4 across, 2 × 2 above 1.1× text |
| Pro home — the count row and the money row | 2 across → one per row, **all four cards together** | always 2 across |
| Consumer « Mes rendez-vous » — the two summary tiles | 2 across → one per row | always 2 across, uneven heights |

- **« Whole »** means no line break inside a token. Tokens are what the text
  engine may not break: a number with its grouping spaces, a word. The space
  before « FCFA » and a hyphen stay legal breaks — « 114 000 » / « FCFA » and
  « Rendez- » / « vous » are what ships today and stay acceptable.
- **The default look does not change where everything fits.** A new client,
  « 0 FCFA », « — »: four across, as in App Store frame 5. Frames 3 and 5 are
  re-checked on the simulator before anyone decides to reshoot (step 6).
- **Target: an amount of up to nine digits stays whole at 200 % text on a
  360 dp phone** in the widest shape (computed: one column holds nine digits
  to about 3.6× on the client card and 2.3× on the home). Beyond that an
  amount may break — said here rather than discovered later.
- **Equal heights hold in every shape**, row by row. Cards stacked one per
  row may differ in height (« 0 FCFA » beside a two-line amount); that is
  legal.
- The Pro home changes all four stat cards together, so the page never shows
  a two-across row above a stacked one.
- Roles without `finances.view` have no money row: the count row decides
  alone.
- **Prices:** one plain space before the unit, in every price of both apps;
  a range prints the unit once — « 15 000 – 25 000 FCFA ».
- **Reviews:** after « Publier », the salon page shows the review once, on
  top, with the count and average adjusted (a replacement does not add one),
  and the same figures on the map sheet, the home cards and the favourites.
  A background re-read of the salon then replaces the estimate with the
  server's figures; if it fails, what is shown stays.
- **Web:** the SMS checkbox is gone and the dialog sends `false`, as the app
  does. The client card reads « +225 07 00 00 01 01 » on one line; « Appeler »
  and « WhatsApp » drop below it when the row is too narrow, and keep the raw
  number in their links.
- **Copy:** « dernière à l’instant ».

All four states of each touched screen are unchanged; no new control, no new
colour or size — tokens only.

## 3. API & contract

None in this slice. `sendSmsInvite` stays in the contract and is sent `false`.

*Not done here, and why:* the exact fix for the review figures is the server
returning the salon's new count and average (and the stored review id) in the
`201` — additive, but a backend change and a production deploy, which is the
owner's call (§11 Q4). Without it the app estimates, then re-reads.

## 4. Data model

None.

## 5. Architecture & patterns

- **`core/utils/text_fit.dart`** — one helper, used by the three surfaces: it
  takes the same (text, style) pairs the tiles draw, measures each token with
  a `TextPainter` built the way `Text` builds its own (the `DefaultTextStyle`
  merge, OS bold text, the ambient `TextScaler`, locale and direction — the
  app's styles name no font, so a bare style measures the wrong one), and
  returns the first shape whose cell holds every token. Each surface wraps its
  block in a `LayoutBuilder` **outside** the `IntrinsicHeight` rows and asks
  with the real width, so a tablet or a wide phone keeps the wide shape.
- The scale constants `_kStatsTwoByTwoAbove` and its test expectation go;
  `_kActionGridSingleColumnAbove` (a static label, already guarded) stays.
- **Reviews:** `ProviderProvider.addReviewLocally` replaces or adds, keyed on
  the review's `appointmentId` (the review `id` is not usable: the server
  returns a new one on a resubmit and keeps the old one stored), newest
  first; the same count and average are patched in place onto the list, the
  featured list and — through a small patch method — the favourites. A new,
  non-destructive, time-limited re-read then overwrites on success only (the
  existing `loadProviderById` blanks the page on failure, so it is not
  reused), with the same stale-answer guard.
- **Web:** no flag mechanism exists on the web, so the SMS control is removed
  rather than hidden. `formatPhoneNumber` is a hand-written twin of the app's
  in `web/lib/format.ts`, same rule and same test vectors: +225 with 10 or 8
  national digits in pairs, anything else unchanged.

## 6. Security & authz

Nothing new. The web card still shows the full number only where it already
does; links keep the raw value; no number goes into a URL parameter.

## 7. Performance

A handful of `TextPainter` layouts per build of three small blocks — eight
strings on the client card, four on the home. No `FittedBox`, no extra frame.
The review re-read is one public `GET /providers/{id}`, unawaited, with a
time limit; the sheet does not wait for it.

## 8. Testing plan

Every guard is watched failing on today's code before the fix lands
(verification rule 2), and the order below exists for that.

1. **Probe and guard — tests only.** Pin what is only computed today: the
   code points of a formatted price, the test font's width for the grouping
   space, and where the engine breaks « 180 000 FCFA » in boxes of 60, 56 and
   30 dp. Add the falsifier the instrument never had — a grouped amount in a
   box narrower than the number but wider than each group must fail — and
   watch it pass wrongly on today's helper. Then make the helper split only on
   characters that are break opportunities. Expected red on today's product:
   the client card with a **seven-digit** amount at 1× (about 69 dp in 60),
   and the home with « 114 000 » at 2×. Add a report-only sweep over every
   paragraph on the layout-gate screens, to count the sibling sites.
2. **Formatter.** `formatters_test` pins the exact string (it only asserts
   starts/ends/contains today), red, then one space; the range prints the
   unit once. Its own commit and its own golden re-baseline.
3. **Layouts.** Client card: amounts of 0, 5, 6, 7 and 9 digits × widths 360,
   393, 430 × scales 1, 1.3, 2 — every value whole (the corrected guard, read
   from the rendered paragraphs, never from the helper), equal heights per
   row, and the widest shape that fits. Home: the same with and without the
   money row. Consumer summary likewise. Re-pump at another scale and after a
   refresh that brings a bigger amount: the shape re-decides.
4. **Reviews.** Unit: a resubmit keeps the count and replaces the tile; a
   first review flips « Nouveau » everywhere; the review is first in the
   list; the list, featured and favourites copies agree; a failed or late
   re-read changes nothing; an answer for another salon is ignored.
5. **Web.** RTL: no SMS text, `sendSmsInvite` false, with and without a
   pre-picked client. Unit: the phone twin, exact strings, including a Gabon
   and a French number left unchanged. The client page joins the reflow and
   axe matrices.
6. **Mutations** on committed code for each guard; goldens regenerated on
   Linux and each changed PNG looked at; `flutter analyze` 0; full suites one
   after another.

### 8.1 What was observed, steps 1–3 (2026-10-13)

- **The engine, read rather than computed** (titleMedium, real fonts):
  « 180 000 » is 58.9 dp and « 1 250 000 » 71.5; in a 60 dp box the first is
  drawn whole with its unit on the next line, in 56 dp it is « 180 00 » /
  « 0 FCFA ». A no-break space left at the end of a token hangs past the edge
  (63.0 dp in 60, drawn whole) — so the guard and the helper do not count it.
- **The guard.** Two falsifiers red on the old helper (« returned `<null>` »
  where a failure was expected). Of its 23 call sites exactly one changed
  verdict — the client card at 1.1×, « 180 000 » needing 64.7 dp of 60 —
  pinned with a seven-digit amount at 1× and the home's « 114 000 » at 2×; all
  three pins failed, as designed, the moment the layouts measured.
- **The sweep** (`gluedTokenBreaks`, report-only, 19 gate subjects): glued text
  examined on 8, **0 broken** — with the gate's fixtures nothing else breaks.
- **The layouts, red first:** 12 of 45 client-card cases and most
  visit-summary cases failed on the old layouts; the phone line failed at
  360 dp from 1.1× and at 393 dp from 1.3×.
- **Mutations on committed code: 39, all red** — 6 on the guard and the sweep,
  7 on the formatter, 26 on the helper and the three layouts (the helper
  ignoring the theme's style, bold text, the scaler or the spacing overrides;
  each candidate list truncated; each cell width without its padding; each
  row un-levelled; the phone's three shapes).
- **A wrong expectation of mine, kept as a test:** I expected a new client to
  stay four across at 1.3× on 360 dp. It goes 2 × 2 — « Absences » itself
  outgrows a quarter tile there, which is what the old constant had measured.
- **Goldens:** six moved with the price string, each compared old against
  new (only the gap narrows); none moved with the layouts — 51 byte-identical.

**What tests cannot show:** they run as Android with Roboto at 360–430 dp;
the store frames are shot on an iPhone 17 Pro simulator at 402 pt in SF Pro.
The shape the iPhone takes is checked there (step 6), not asserted.

## 9. Rollout & scope discipline

Five pull requests, in this order, each green before the next:

1. the guard (tests only); 2. the price string, with its goldens; 3. the
measured layouts; 4. the review figures (app); 5. the web gaps — 4 and 5 are
independent and can land at any point. Then a build, the simulator check at
the default and the largest text size, and a reshoot of frames 3 and 5 only
if they changed. No production deploy is part of this slice; a new TestFlight
build is asked for when the PRs are in.

## 10. Definition of done

- [x] Steps 1–3 (the guard, the price string, the measured layouts): each
      guard watched red on the old code, then green — the record is §8.1.
- [ ] Steps 4–5 (review figures, web gaps): the same, in their own PRs.
- [x] `flutter analyze` 0 and the full mobile suite green on steps 1–3.
- [x] Goldens regenerated on Linux and reviewed: six moved with the price
      string (run 38388637917), none with the layouts (run 38390654129).
- [x] SYSTEM.md §13.3 states the rule (shape by measured fit; what a token
      is); §21 rows 93–95 for what is fixed, row 96 for what is registered.
- [x] The simulator check at 402 pt (iPhone 17 Pro, SF Pro, the demo salon,
      2026-10-13). At the default size the home and the client card take the
      same shapes as store frames 3 and 5 — two across, four across, the
      actions beside the number. At the largest accessibility size (≈3×) both
      go one per row with every amount whole; the client's number, which
      cannot fit even the card's full width there, wraps between two pairs,
      never inside one. **Found there, fixed:** with the narrower price, a
      visit-history date that fits its line exactly ran into the amount
      (« 08:007 000 FCFA ») — the row had no gap after the date.
- [ ] Store frames: the home (3) is unchanged; the client card (5) differs
      by the single space before « FCFA » in its history rows — not worth a
      reshoot on its own (§11 Q1). Reshoot with the next build if wanted.
- [ ] Roadmap entry; this spec's status and §11 closed.

## 11. Open questions

None open. The six below were put to the owner on 2026-10-13 and answered
**« yes to all »** — each recommendation is now the decision:

1. **One space before « FCFA » in every price, and the unit once in a range**
   (« 15 000 – 25 000 FCFA »)? *Recommended: yes.* It moves every golden that
   shows a price, and the store frames just reshot would differ from the next
   build by that one space — not worth a reshoot on its own.
2. **Home cards: all four go one per row together** when one value does not
   fit? *Recommended: yes* — never a two-across row above a stacked one.
3. **A phone number never wraps** — the actions drop below it instead, in the
   app and on the web? *Recommended: yes.* The design rules already say a
   phone number may not break; the app's client card can wrap between pairs
   from about 1.03× on 360 dp today.
4. **Review figures: the app-only fix now**, the server change later with
   its own deploy go-ahead? *Recommended: yes.* Until then two rare cases stay
   approximate for a moment — a resubmit whose first review is older than the
   ten the page loads, and a 0,1 rounding difference — and the re-read
   corrects both.
5. **The consumer « dépensés » tile in this slice**, the other sites
   registered? *Recommended: yes.*
6. **The web client page joins the reflow and accessibility checks**,
   accepting it may surface older findings there to fix or declare?
   *Recommended: yes.*
