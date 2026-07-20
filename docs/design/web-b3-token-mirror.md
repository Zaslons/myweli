# web-b3-token-mirror — the Dart parser, the blocking comparator, and `gen:tokens` (B3)

**Status:** Built (2026-07-20). **Surface:** `web/` · the token seam itself.
**Design system:** [WEB-SYSTEM.md §1, §14](WEB-SYSTEM.md#1-tokens--tailwind) ·
[SYSTEM.md §3–§7, §9](SYSTEM.md#3-color). **Roadmap:** design-system programme,
slice B3 (register row 19).

## Goal & the debt

`web/styles/tokens.ts` is a **hand-mirror** of `mobile/lib/core/theme/`, and the
register counts **six drifts** in its short life:

1. `gold` dropped entirely → `TeamRoleChip` silently substituted `starRating`
   (1.62:1 — invisible) — row 4.
2. `spacingSM` (12) + `spacingXXXL` (64) silently dropped.
3. Tracking nearly dropped — §4's own table omitted `letterSpacing` while the
   code set it on 9 of 15 roles; mirroring the DOC would have shipped the web
   with no tracking. The lesson: **mirror the code, not the doc**.
4. / 5. `warningLight` `#FFB800` and `infoLight` `#2D3561` — mobile-only until
   this slice.
6. `borderFocus` missing while WEB-SYSTEM §5's own snippet consumed it — the doc
   promised a token whose absence would have **failed the build**, from B1 to B4.

Every one shipped, silently, past typecheck, lint, and every test. The mirror had
no gate. `tokens.ts:4` has named the fix since B1: *"A Flutter→web generator + a
CI drift gate is slice B3."*

**The user here is the next developer**, and the UX is the failure message they
see on drift. Owner decisions: **comparator gate + printer** (tokens.ts stays
hand-written — the six drift histories live as comments ON their keys, and a
wholesale generator would delete the project's memory) · **the two open drifts
close now** (the gate then asserts complete coverage — no skip list) · **the
doc-sourced web-only families get doc-pins** (motion vs SYSTEM §9's table, zIndex
vs WEB-SYSTEM §9's — drift #6 was exactly a doc↔code lie).

## Architecture

### `scripts/dart-tokens.mjs` — one parser, two consumers

Plain ESM (importable by both vitest and `node`), no Flutter required — the web
CI job has Node 22 and a full-repo checkout, so the **Dart source text is the
machine-readable truth** (mobile has no token export, and adding one would be a
second mirror to drift).

Parsers, one per declaration idiom (verified against the actual files):

| Source | Idiom | Parser |
|---|---|---|
| `colors.dart` (29) | `static const Color name = Color(0xFFRRGGBB);` | name + hex |
| `app_theme.dart` (19) | `static const double name = N.0;` | name + number (elevation getters, methods, the ThemeData builder don't match the idiom — skipped by construction) |
| `text_styles.dart` (15) | `TextStyle(fontSize: N, fontWeight: FontWeight.X, height: A / B, letterSpacing: L)` | the `TextStyle(...)` body parsed **field-by-field** (order-independent); `height`'s division expression evaluated |

**The self-check that closes the silent-parse hole:** per file, the raw count of
idiom openers (`static const Color` / `double` / `TextStyle`) must equal the
parsed count. A future declaration that deviates from the idiom — a computed
color, a reformatted style — fails loud (*"unparseable declaration"*) instead of
silently vanishing from the mirror. No hard-coded 29/15/19: new tokens flow
through; malformed ones scream.

**The mapping table, explicit** (the encoded deliberate divergences):

| Family | Mobile → web | Transform |
|---|---|---|
| colors | names 1:1 (`primaryHover` already aligned both sides) | hex passthrough |
| spacing | `spacingXS→xs … spacingXXXL→xxxl` | `${n}px`; **web adds `'0'`** (Tailwind's `inset-0`/`pb-0` need the key) — the one `WEB_ONLY` entry |
| radius | `radiusSmall→sm, Medium→md, Large→lg, XL→xl, XXL→xxl, Pill→pill` | `${n}px` |
| icon | `iconXS…iconXL` identity | bare `${n}px` — **no lineHeight** (B2c: baking one shrank 7 tap targets) |
| type | names 1:1 | `[${size}px, { lineHeight: round(height×size)px, letterSpacing: ${L}px }]` — **`fontWeight` stripped** (§3: "the single place the mirror diverges — B3's generator must encode it") |

**The doc pins:** `parseMdTable()` reads SYSTEM §9's motion table
(`motionStagger→stagger` 50 … `motionSlow→slow` 400) and WEB-SYSTEM §9's z-index
table (`z-base→base` 0 … `z-toast→toast` 50). Web-side declared additions:
`motion.DEFAULT` (= base — load-bearing: every bare `transition` reads it) and
`zIndex.auto` (the flex-item escape). `screens` stays unpinned — Tailwind's stock
values, already frozen by the closed theme.

### `tests/tokens.mirror.test.ts` — the gate

Runs inside the **existing blocking vitest job** — no new CI step. Unlike
`gen:api` (whose committed output is a build input, so CI regenerates + diffs),
tokens.ts is hand-owned; equality-at-test-time IS the gate. Asserts per family:

1. **Missing on web** — each with an actionable message: *"mobile `spacingSM` =
   12 → web `spacing.sm` — MISSING. Run `npm run gen:tokens`."*
2. **Extra on web** — anything not in `WEB_ONLY` fails (a web-invented token is
   a mirror divergence too).
3. **Exact value equality** (`toEqual` per family — vitest's object diff).
4. The parser self-checks.
5. motion / zIndex ≡ their doc tables + the declared additions.

### `npm run gen:tokens` — the healing tool

`scripts/gen-tokens.mjs` prints the five mirrored families rendered exactly in
tokens.ts's value style, with a header: paste the **values** into the existing
structure — the doctrine comments are yours to keep. It writes no files; the
comparator is the gate, the printer is the medicine.

### The new-token flow (the DX this buys)

A mobile dev adds `static const Color foo = …` → the web CI job goes red in the
mirror test with the exact key and value → the web dev runs `gen:tokens`, pastes,
adds the contrast row the contrast suite demands, and the closed theme + pin
tests take it from there. A drift can no longer land silently — the exact failure
class of all six historical drifts.

## Closing drifts 4/5

`warningLight: '#FFB800'` (= `starRating`'s hex under a different ROLE — same on
mobile, both deliberate) and `infoLight: '#2D3561'` land in `colors` with their
doctrine comments. `tokens.contrast.test.ts` gains the mobile-equivalent rows:
`warningLight` **below 3:1** on all three surfaces (the negative pin — ink-on-tint
only, mobile's own assertion), `infoLight` ≥ 4.5 as text — plus a **completeness
assertion** (every `colors` key appears in some contrast group) so the NEXT new
color can't land unasserted. Zero CSS change (no callers → no emitted utilities);
verified by the emitted-CSS diff.

## Testing plan

Proof-red is REAL, not staged: the gate fails on current tokens.ts (the two
missing colors) before ② closes them — output recorded below. Then two throwaway
mutations (never committed): a flipped mobile hex → the readable per-key failure;
a non-idiom declaration → the self-check failure. `gen:tokens` output pasted over
the five families in a scratch copy diffs clean against tokens.ts values.

**Proof-red (recorded, branch base — the gate's actual output, 8/9 green):**
```
colors.warningLight = "#FFB800" — MISSING on web. Run `npm run gen:tokens`.
colors.infoLight = "#2D3561" — MISSING on web. Run `npm run gen:tokens`.
```
Every other family already mirrored exactly — the drift was precisely and only
the two known open rows.

## Not in scope

Elevation (mobile's `BoxShadow` getters — no web counterpart; a web elevation
scale would be an invention) · `contentMaxWidth` (doc-sourced, lives in
tailwind.config — row 7j/B7 applies it) · a mobile-side JSON export (a second
mirror) · auto-writing tokens.ts (the comments are the project's memory).

## Definition of done

Row 19 → 0 with the six drifts recounted · the gate proven red then green · the
two colors mirrored with contrast rows + completeness · `gen:tokens` verified
paste-equivalent · full battery green · emitted CSS unchanged · adversarial
review passed · WEB-SYSTEM §1/§14 + ROADMAP refreshed in the same PR.
