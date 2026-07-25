# mobile-gold-reading — the mirror-debt close: gold ≥ 3:1 on every surface + the reading paragraphs at 16

**Status:** Shipped (2026-07-25) — see « As built ». **Surface:** `mobile/` (the Flutter theme
+ two screens) and the `web/` token mirror. **Design system:**
[SYSTEM.md §3.5](SYSTEM.md#3-colour) (gold-as-state) ·
[SYSTEM.md §4](SYSTEM.md#4-type) (reading text) ·
[SYSTEM.md §21](SYSTEM.md#21-the-known-violations-register) rows 3b/23/27 ·
[WEB-SYSTEM.md §15](WEB-SYSTEM.md#15-the-known-violations-register) row 23.
**Roadmap:** design-system programme — the mobile A-series follow-through to B3
+ B8. *(The mobile A-series usually inlines its spec in SYSTEM.md + ROADMAP;
this slice gets a doc because it is cross-register and touches two apps + the
mirror — the design-spec-per-part rule.)*

## Goal & the debt — two rows the web work surfaced from the outside

The Dart theme is the source of truth the web mirrors. Two rows whose fix is
mobile-side, both found by doing the web burn-down:

1. **`gold` fails the 3:1 non-text floor on `surfaceVariant`** (WEB-SYSTEM §15
   row 23). `gold #B8860B` measures **2.98:1 on `surfaceVariant` (#F5F5F5)** —
   below the WCAG 1.4.11 floor by 0.02. Mobile's A1 gold row (§21 row 3b) is
   ✅, but `design_contrast_test.dart` measures only **background / surface /
   card**; its own comment even calls `background` "the worst case" — and it is
   NOT: `surfaceVariant` (#F5F5F5) is darker than `background` (#F6F7F9), so it
   is the true worst surface, and it was never measured. B3's web review added
   `surfaceVariant` to the web contrast test and caught it, scoping gold off
   that surface with a "fix mobile-first; the mirror gate carries it over" note.
2. **Two reading paragraphs render one step small** (SYSTEM §21 row 27, created
   by B8). §4 declares `bodyLarge` = "Default reading text", yet the salon
   description (`provider_detail_screen.dart`) and the empty-state body
   (`empty_state.dart`) use `bodyMedium` (14). **Mobile has no density mode**
   (only layout-driven "compact"), so unlike web B8's HYBRID this is a clean
   2-site flip.

## The fix

### gold — the computed darkening (not a guess)

The darker gold must clear the 3:1 floor on ALL FOUR surfaces with a small
margin, while staying a recognizable brand gold (hue held at
42.7°→42.5°). Using the app's own WCAG math (`test/support/wcag.dart`):

| surface | #F6F7F9 bg | #FAFAFA surface | #FFFFFF card | **#F5F5F5 surfaceVariant** |
|---|---|---|---|---|
| `#B8860B` (old) | 3.04 | 3.12 | 3.25 | **2.98 ✗** |
| **`#B5830A` (new)** | 3.15 | 3.24 | 3.38 | **3.10 ✓** |

`#B5830A` is the value B3's review had already sketched; it clears 3:1 on the
worst surface with a ~0.10 margin and is visually near-identical. **Measured:
only `gold` fails on surfaceVariant** — every other token (text, borders,
favorite, category accents) clears its floor there with room (textTertiary
4.68, borderStrong 3.17), so adding surfaceVariant to the test's surface map is
safe and simply makes the true worst case explicit.

### The reading flip

`provider_detail_screen.dart` description + `empty_state.dart` body:
`bodyMedium` → `bodyLarge` (keep the `.copyWith(color: …)`).

## The mirror propagation (mobile → web)

The Dart theme is authoritative; `web/styles/tokens.ts` is hand-owned and
gated. Changing `AppColors.gold`:
1. `web/tests/tokens.mirror.test.ts` (parses `colors.dart` via
   `web/scripts/dart-tokens.mjs`) goes **red** on the drift.
2. `npm run gen:tokens` PRINTS the new value (it writes nothing); hand-paste
   `#B5830A` into `web/styles/tokens.ts:54` + its ratio comment.
3. `web/tests/tokens.contrast.test.ts`: add `surfaceVariant` to gold's `on`
   list and drop the "fix mobile-first" note — it now passes with the mirrored
   value, closing WEB-SYSTEM §15 row 23 on the web side.

## Goldens (Linux-authoritative)

These render the changed tokens and must be regenerated on Linux (they SKIP on
macOS; `tool/update_goldens.sh` via the pinned Docker image, or the
`goldens.yml` workflow):
- `tokens_color` — the gold swatch.
- `pro_team` — the TeamRoleChip owner chip (gold fill/border/text).
- `consumer_home` — AnnouncementStories' gold unseen-ring.
- `consumer_provider_detail` — the salon description (now bodyLarge).

**Every regenerated PNG is reviewed by eye** — gold visibly darker yet still
gold; the description visibly larger (16 vs 14); nothing else moves.

## Tests (proof-red)

- `design_contrast_test.dart`: adding `surfaceVariant` to the surface map makes
  the `gold` assertion go **RED at 2.98** before the darkening — the row's
  whole reason. Green on all 4 surfaces after.
- A widget-test pin (new/extended): the salon description Text and the
  EmptyState body resolve `bodyLarge` (16), never `bodyMedium` — so row 27
  cannot silently regress. Mirrors web B8's TextField pin.
- Untouched: `design_system_pin_test.dart` (no new literals — the change is a
  token value), the a11y guideline tests, the mirror gate (green once tokens.ts
  is updated).

## Flagged — NOT fixed this slice (honest register behaviour)

**Gold used as TEXT in TeamRoleChip.** The owner chip renders `gold` as text
(labelSmall, 11px) on a 12%-gold tint — text needs **4.5:1**; gold gives ~3:1
even after darkening. Row 23 is a NON-text (3:1) rule and row 3b is explicitly
"gold-as-state, not text", so this is out of scope — but it is a real,
newly-noticed a11y gap. Recorded as a **new §21 candidate row** (gold-as-text
below the 4.5:1 floor — the owner chip), fix sketch: a dedicated darker
gold-text token, or a neutral text colour on the tinted fill. The review
confirms the scoping call.

## As built — the deltas

- **The proof-red held exactly**: adding `surfaceVariant` to the surface map
  turned `gold` red at **2.98:1** and nothing else — every other token cleared
  it (measured: textTertiary 4.68, borderStrong 3.17 the closest). `#B5830A`
  greens all four surfaces.
- **Five goldens moved, not four.** The EmptyState body change reaches EVERY
  golden that renders an EmptyState with a description — so `admin_table_empty`
  moved alongside `components_empty_state` (both under-counted in the plan).
  The three gold goldens moved as predicted (`tokens_color`, `pro_team`,
  `consumer_home`).
- **`consumer_provider_detail` did NOT move.** The salon « À propos »
  description sits below that golden's 390×1200 capture, so the flip is
  code-verified only there. Recorded, not hidden: the shared `EmptyState` body
  (the reused reading surface) carries the widget pin; a focused
  description pin would need the full screen DI harness for one Text.
- **The gold-as-text finding is real and registered** (§21 row 28): the
  regenerated `pro_team` golden shows it — « Propriétaire » in gold on a pale
  gold tint. Flagged, not fixed (its own slice).
- **The mirror gate carried the value byte-for-byte**: `gen:tokens` printed
  `#B5830A`; `tokens.mirror.test.ts` is green against `colors.dart`.

## Dependency

Row 27 was created by web **B8** (PR #263), which is green but may be
unmerged when this lands. This branch is off `main`, so §21 adds row 27 in its
closed form; **merge #263 first, then rebase** — the row-27 line resolves to
this (closed) version. The code (gold, colors, tokens.ts, the two screens)
never overlaps B8's.

## Not in scope

The gold-as-text fix (flagged above) · A6 (snackbar/ConfirmDialog) · row 26
(segmented-control borders) · any other surfaceVariant token (none fail) · the
`starRating` decorative token (a separate glyph fill, untouched).

## Definition of done

Row 23 (web §15) + row 27 (mobile §21) → 0 · gold clears 3:1 on all 4 surfaces
with margin, mirrored byte-for-byte to `tokens.ts` · the 2 paragraphs read at
16 · the 4 goldens regenerated and eye-reviewed · full battery green (mobile
`analyze`/`test`/goldens + web vitest/gates/build) · adversarial review passed ·
SYSTEM §21 + WEB-SYSTEM §15 + ROADMAP refreshed in the same PR.
