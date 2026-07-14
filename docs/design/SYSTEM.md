# Myweli — the design system (apps)

The canonical design system for the three Flutter surfaces (consumer · pro ·
admin). It defines **every token, component, state and rule** a screen is allowed
to use, and it lists — honestly, in §14 — everywhere the current code still
breaks them.

**This document supersedes `DESIGN-STANDARDS.md`.** The web surface has its own
companion, [WEB-SYSTEM.md](WEB-SYSTEM.md), which shares these tokens and rules
and only documents what differs in a browser.

> **Standing rule** (enforced by the `myweli-dev-guardrails` skill): before any
> UI work — read this doc and the part's `docs/design/<part>.md` spec, design *to*
> the system, then build. After building, run the enforcement in §13. A screen may
> never invent a color, size, duration or pattern that isn't here. If you need one
> that doesn't exist, **add it to the system first** — that's a change to this
> doc, not a literal in a widget.

**Contents** — [1 Identity](#1-identity) · [2 How to read a token table](#2-how-to-read-a-token-table)
· [3 Color](#3-color) · [4 Type](#4-type) · [5 Spacing](#5-spacing) · [6 Radius](#6-radius)
· [7 Icon size](#7-icon-size) · [8 Elevation](#8-elevation) · [9 Motion](#9-motion)
· [10 Layout](#10-layout-breakpoints-content-width-z-index) · [11 Components](#11-components)
· [12 The four states](#12-the-four-states) · [13 Accessibility](#13-accessibility)
· [14 Forms & validation](#14-forms--validation) · [15 Feedback & destructive actions](#15-feedback--destructive-actions)
· [16 Iconography](#16-iconography) · [17 Content & microcopy](#17-content--microcopy)
· [18 Market data & salon time](#18-market-data--salon-time) · [19 Sanctioned exceptions](#19-sanctioned-exceptions)
· [20 Enforcement](#20-enforcement) · [21 The known-violations register](#21-the-known-violations-register)
· [22 Deferred](#22-deferred)

---

## 1. Identity

**Minimalist monochrome.** Black, white and gray carry the interface; **color is
reserved for status and the single primary action**, never decoration. Generous
spacing, rounded corners, semibold headlines. The admin console wears the same
identity adapted to a data-dense desktop tool
([admin-console-ui.md](admin-console-ui.md)).

### The two blacks — brand vs ink

This is the one identity rule that is easy to get wrong, because both colors were
`#000000` until this document existed.

| Role | Token | Value | What it is |
|---|---|---|---|
| **Brand** | `AppColors.primary` | `#000000` | The thing you look **at**. Button fills, selection strokes, the logo, the active indicator, the focus ring. Pure black is the identity — white on it is 21:1, and its absoluteness is what makes the monochrome read as *deliberate* rather than *unstyled*. |
| **Ink** | `AppColors.textPrimary` | `#1A1A1A` | The thing you read **through**. Every glyph of body and heading text. |

Long runs of pure-black glyphs on a near-white field halate — the eye fights the
maximum-contrast edge and the page feels harsh. `#1A1A1A` is still **16.24:1** on
our background (AAA, nearly three times the 4.5:1 floor), so nothing is lost but
the glare. A black *fill* has no such problem: it is one large edge, not
thousands.

**So:** text is never `primary`; a fill is never `textPrimary`. The logo, the
Lottie brand loader and the Android adaptive icon are brand assets and stay pure
black — do not "fix" them.

---

## 2. How to read a token table

Every color token carries the contrast ratio it achieves against our three
backgrounds and, critically, **what it is allowed to be used for**. WCAG 2.1 AA
sets three different floors, and a token that is legal as an icon can be illegal
as a label:

| Floor | Applies to | Rule |
|---|---|---|
| **4.5:1** | Normal text (< 18.66px regular / < 24px bold) | WCAG 1.4.3 |
| **3:1** | Large text (≥ 18.66px bold / ≥ 24px), **icons, borders of controls, focus rings, chart strokes** | WCAG 1.4.3 + **1.4.11 non-text contrast** |
| *(none)* | Disabled controls, pure decoration, logos | Exempt by 1.4.3 — but see the disabled rule in §13 |

Our three backgrounds, worst → best: `background #F6F7F9` (the scaffold),
`surface #FAFAFA`, `secondary #FFFFFF` (cards). **A token must clear its floor on
`background`** — the worst case — to be used anywhere.

---

## 3. Color

Source: `mobile/lib/core/theme/colors.dart`. Tints via `.withValues(alpha: …)`,
never a new hex.

### 3.1 Brand & surface

| Token | Value | On bg | Use for | Never |
|---|---|---|---|---|
| `primary` | `#000000` | 19.59 | Primary button fill, selected states, active indicators, focus ring, logo | Body text |
| `primaryHover` | `#333333` | 11.79 | The hover/pressed step off `primary` (12.63:1 under white) | Anything static |
| `secondary` | `#FFFFFF` | — | Card surface, text **on** `primary` (21:1) | A page background |
| `secondaryVariant` | `#F5F5F5` | — | Pressed/hover tint on white | |
| `background` | `#F6F7F9` | — | The scaffold background | A card |
| `surface` | `#FAFAFA` | — | Raised neutral surface | |
| `surfaceVariant` | `#F5F5F5` | — | Input fills, skeleton base | |

Cards are `secondary` on `background` — a deliberate, low-contrast lift that
carries the whole layout without borders or shadows. Don't add a border to a card
"to make it pop"; that's what the surface step is for.

### 3.2 Text

| Token | Value | On bg | Floor | Use for |
|---|---|---|---|---|
| `textPrimary` | `#1A1A1A` | **16.24** | 4.5 ✅ | Ink. Headings, body, labels, anything a user reads. |
| `textSecondary` | `#4A4A4A` | **8.27** | 4.5 ✅ | Supporting text, field labels, subtitles. |
| `textTertiary` | `#6E6E6E` | **4.76** | 4.5 ✅ | The *lightest text that is still text*: hints, captions, timestamps, unselected nav labels, metadata. |
| `textDisabled` | `#9E9E9E` | 2.50 | exempt | Disabled control labels **only**. |

**`textTertiary` is the floor, not a decorative gray.** Its previous value
(`#8A8A8A`, 3.22:1) failed AA on 202 sites, including every input hint and the
bottom-nav label at 11px. If a piece of text feels like it wants to be lighter
than `textTertiary`, the answer is a smaller size or less prominence — **not a
lighter gray**. There is no legal text color below it.

`textDisabled` is exempt from the contrast rule because WCAG exempts inactive
controls — but exempt is not the same as invisible. It must remain legible enough
that a user can tell *what* is disabled; that's why it is `#9E9E9E` and not the
old `#C0C0C0` (1.70:1, effectively blank).

### 3.3 Borders — three roles, three weights

Borders were one token doing three jobs, so it was tuned for the softest one and
failed the strictest. Material 3 splits `outline` / `outlineVariant` for exactly
this reason; so do we.

| Token | Value | On bg | Floor | Use for |
|---|---|---|---|---|
| `divider` | `#E0E0E0` | 1.23 | exempt | **Decorative rules only** — the hairline between list rows. Carries no meaning; a screen reader ignores it; removing it loses nothing but rhythm. |
| `border` | `#D0D0D0` | 1.44 | exempt | **Container hairlines** — the edge of a card or section that isn't interactive. |
| **`borderStrong`** | `#8A8A8A` | **3.22** | 3.0 ✅ | **Mandatory on the boundary of any interactive control**: text inputs, unselected checkboxes/radios/switches, outlined chips, dropdowns. |
| `borderFocus` | `#000000` | 19.59 | 3.0 ✅ | The focus ring — **2px, with a 2px offset** so it never merges with the control's own edge. |

The rule in one line: **if the boundary is the only thing telling you a control is
there, it must be `borderStrong`.** A text input whose outline is `border` (1.44:1)
is a control the user cannot see — that was WCAG 1.4.11 failing on every form in
the app.

We deliberately did **not** darken all borders to 3:1. A card hairline is not a
control; darkening it would box the product in and lose the airy monochrome for no
accessibility gain.

**Where the line actually falls** (settled in A1, after walking all 34 bordered
interactive things): `borderStrong` goes on **form controls and selection states** —
inputs, OTP boxes, dropdowns, the custom checkbox, unselected chips and filter pills,
time-slot cells, radio-style option cards, picker rows, upload dropzones, outlined
buttons. A tappable **card** keeps the soft `border`: a stat card or an action tile is
identified by its icon and its label, not by its hairline, and 1.4.11 only demands 3:1
on the visual information *required to identify* a control.

**Disabled controls recede.** `inputDecorationTheme.disabledBorder` is the soft
`border` — deliberately *below* the enabled state. (It used to be unset, which meant a
disabled field fell through to an untokened Material default.)

### 3.4 Semantic

Status colors come from here — never `Colors.green`/`Colors.red`.

| Token | Value | On bg | As text | As icon/fill | White on it |
|---|---|---|---|---|---|
| `success` | `#2D5016` | 8.63 | ✅ | ✅ | 9.25 ✅ |
| `successLight` | `#4A7C2A` | 4.66 | ✅ | ✅ | — |
| `error` | `#8B0000` | 9.34 | ✅ | ✅ | 10.01 ✅ |
| `errorLight` | `#DC143C` | 4.66 | ✅ | ✅ | — |
| `warning` | `#6B5B00` | 6.28 | ✅ | ✅ | — |
| `warningLight` | `#FFB800` | 1.62 | ❌ | ❌ | — |
| `info` | `#1A1A2E` | 15.91 | ✅ | ✅ | ✅ |
| `infoLight` | `#2D3561` | — | ✅ | ✅ | — |

⚠️ **`warningLight` (`#FFB800`) is not a foreground color** at 1.62:1. It is a
*background tint* for warning chips (with `textPrimary` on it — 10.04:1 ✅). Using
it as a text or icon color is a contrast failure; use `warning` (`#6B5B00`).

### 3.5 Accents

| Token | Value | On bg | Use for | Never |
|---|---|---|---|---|
| `starRating` | `#FFB800` | 1.62 | The **fill of a star glyph** | Text; any control whose only cue is this color |
| `favorite` | `#E53935` | 3.94 | The **fill of a heart glyph** (3:1 ✅) | Text (fails 4.5:1) |
| `gold` | `#B8860B` | 3.04 | A **non-text accent**: the owner-chip border, the unseen-story ring (3:1 ✅, barely) | Text (fails 4.5:1) |

**Meaning never rides on hue alone** (WCAG 1.4.1). A gold star at 1.62:1 is
invisible to a low-vision user and meaningless to a color-blind one — so it is
never *the* signal:

- **Ratings always pair the glyph with the number.** The shared `AppRating`
  renders `★ 4,8 (32 avis)` — the star is decoration, the numeral is the
  information. An interactive star input encodes its state by **glyph**
  (`star_border` → `star`), not by color, so it still reads in grayscale.
- **Gold-as-state** (the owner chip, the unseen-story ring) uses `gold`, which
  clears the 3:1 non-text floor — and is *also* accompanied by a label or a
  position, never standing alone.

### 3.6 Category accents (a sanctioned exception — see §19)

| Token | Value | On bg |
|---|---|---|
| `categorySpa` | `#5B6B4F` (sage) | 5.35 ✅ |
| `categoryBarber` | `#6D5A4C` (taupe) | 6.09 ✅ |
| `categorySalon` | `#4F5B6B` (slate) | 6.44 ✅ |
| *(unknown)* | → `primary` | |

Always via **`categoryColor()`** (`core/utils/category_colors.dart`) — never
inline. Adding a category means adding a token *and* a switch arm there.

---

## 4. Type

Source: `mobile/lib/core/theme/text_styles.dart`. Pick a scale entry and
`.copyWith(color: …)`; **never write `TextStyle(fontSize: …)` in a screen.**
Line-heights are baked in — don't override them.

| Style | Size / line | Weight | Use for |
|---|---|---|---|
| `displayLarge/Medium/Small` | 57/45/36 | Bold | Marketing & splash only. Not used in-product today. |
| `headlineLarge` | 32 / 40 | 600 | Screen title (rare — hero) |
| `headlineMedium` | 28 / 36 | 600 | Screen title |
| `headlineSmall` | 24 / 32 | 600 | **AppBar title**, section hero |
| `titleLarge` | 22 / 28 | 600 | Card/section heading |
| `titleMedium` | 16 / 24 | 500 | List-row title, dialog title |
| `titleSmall` | 14 / 20 | 500 | Dense row title |
| `bodyLarge` | 16 / 24 | 400 | **Default reading text** |
| `bodyMedium` | 14 / 20 | 400 | Secondary text (the workhorse) |
| `bodySmall` | 12 / 16 | 400 | Captions, metadata |
| `labelLarge` | 14 / 20 | 500 | Button labels |
| `labelMedium` | 12 / 16 | 500 | Chips, field labels |
| `labelSmall` | 11 / 16 | 500 | **The smallest text in the product** — nav labels, badges |

**11px is the floor.** There is no 10px token and there will not be one: a 10px
French label on a low-end Android at arm's length is not readable, and adding the
token would legitimise it forever. If 11px doesn't fit, the layout is wrong.

**Never hardcode a size**, and never disable text scaling (see §13.3).

---

## 5. Spacing

An **8-pt grid** with one sanctioned half-step. Source:
`AppTheme.spacing*`.

| Token | Value | Use for |
|---|---|---|
| `spacingXS` | 4 | Icon↔label gap, tight inline pairs |
| `spacingS` | 8 | Between related elements |
| **`spacingSM`** | **12** | **The half-step.** Chip padding, dense list gaps, the gap between a title and its subtitle |
| `spacingM` | 16 | **The default.** Screen padding, card padding, between cards |
| `spacingL` | 24 | Between sections |
| `spacingXL` | 32 | Major section breaks |
| `spacingXXL` | 48 | Empty-state / hero breathing room |
| `spacingXXXL` | 64 | Rare, full-screen composition |

`spacingSM = 12` is not a loosening of the grid — it is an **admission of the
truth**: 12px appears 76 times in the codebase because 8 is too tight and 16 too
loose for dense UI, and every one of those 76 was written as a raw `SizedBox(height: 12)`
*because the token didn't exist*. Naming it converts 76 violations into 76 correct
usages and gives the next developer a legal choice instead of a literal.

Nothing else is legal. `10`, `14`, `18`, `20` are not spacing values.

---

## 6. Radius

| Token | Value | Use for |
|---|---|---|
| `radiusSmall` | 4 | Badges, tiny tags |
| `radiusMedium` | 8 | Inputs, small buttons |
| `radiusLarge` | 12 | **Default** — buttons, text fields, dialogs |
| `radiusXL` | 16 | **Cards** |
| `radiusXXL` | 24 | Bottom sheets, large surfaces |
| **`radiusPill`** | **999** | **Fully-rounded**: chips, avatars, badges, FABs, segmented controls |

`radiusPill` exists for the same reason as `spacingSM`: `999` was hand-written 21
times. A pill is a *shape*, not a number — name it.

---

## 7. Icon size

The codebase currently uses **19 distinct icon sizes**. Five is enough.

| Token | Value | Use for |
|---|---|---|
| `iconXS` | 16 | Inline with `bodySmall`/`labelMedium`; dense chips |
| `iconS` | 20 | **Inline with text** — the most common case (the leading icon in a button, a row) |
| `iconM` | 24 | **The default action icon** — AppBar, IconButton, nav. Material's own default. |
| `iconL` | 32 | Feature/avatar-scale glyphs |
| `iconXL` | 64 | The **empty-state** illustration glyph |

An icon's *size* and its *tap target* are different things: `iconM` = 24px of
glyph inside a **≥48px** touch target (§13.2). Never grow the glyph to make the
target bigger — grow the target.

---

## 8. Elevation

`AppTheme.elevation1…4` (black at 5–10% alpha). The identity is flat: **cards use
elevation 0 and rely on the surface step**; shadow is reserved for things that
genuinely float above the page (menus, sheets, the bottom nav). If you reach for
`elevation3` on a card, you're solving a contrast problem with a shadow.

---

## 9. Motion

12 distinct durations exist today, all magic numbers. The system defines five.

| Token | Value | Curve | Use for |
|---|---|---|---|
| `motionStagger` | 50ms | — | The per-item delay in a staggered list reveal |
| `motionFast` | 100ms | `easeOut` | Immediate state feedback — ripple, checkbox, toggle |
| `motionBase` | 200ms | `easeInOut` | **The default** — most transitions, cross-fades, expand/collapse |
| `motionEmphasis` | 300ms | `easeOutCubic` | Entering surfaces — sheets, dialogs, snackbars |
| `motionSlow` | 400ms | `easeInOutCubic` | Full-screen / large-surface transitions |

**Entering** decelerates (`easeOut*`), **exiting** accelerates (`easeIn*`), and
things that move *and* stay use `easeInOut`. Nothing user-initiated may take
longer than `motionSlow` — beyond ~400ms an animation stops reading as *response*
and starts reading as *lag*, especially on the reference low-end Android.

**Reduced motion:** honour `MediaQuery.disableAnimations` — when set, transitions
become instant and looping/decorative animation stops. A vestibular-sensitive user
asked the OS not to move the screen; we listen. *(Not yet implemented — §21.)*

---

## 10. Layout: breakpoints, content width, z-index

### Breakpoints (Material 3 window size classes)

| Class | Width | Surface behaviour |
|---|---|---|
| `compact` | < 600 | Phone. Single column. The consumer & pro apps' primary target. |
| `medium` | 600–839 | Large phone / small tablet. Wider gutters, capped content width. |
| `expanded` | ≥ 840 | Tablet / desktop (admin). Multi-pane; persistent nav instead of a bottom bar. |

There are **zero breakpoints in the apps today** — every screen is a phone
column. That is fine for the consumer app (its users hold phones) and wrong for
admin. Until real tablet layouts land (§22), the rule is defensive:

- **`contentMaxWidth = 720`** — text and forms never stretch past it. A 1000px-wide
  line of French body copy is unreadable, and an `ElevatedButton` whose theme says
  `minimumSize: Size(double.infinity, 48)` becomes a 1000px-wide button on a tablet.
- Buttons take their width from their **container**, not from `double.infinity`.

### z-index / layering

Flutter has no z-index — order is paint order — so the discipline is *conceptual*
and matters mostly for the web twin. The layers, lowest to highest: content →
sticky headers → the bottom nav → floating actions → drawers/sheets → dialogs →
snackbars → toasts. Nothing may be painted above a dialog except feedback.

---

## 11. Components

**Reuse before you build.** If a pattern appears twice, it becomes a shared
widget; a third inline copy is a review failure.

### 11.1 Shared (`lib/widgets/common/`)

| Component | API | Notes |
|---|---|---|
| `AppButton` | `text, onPressed, type: {primary,secondary,text}, isLoading, isFullWidth, icon, leading` | `onPressed: null` = disabled. `isLoading` swaps the label for a `BrandLoader` **without changing the button's size** (no layout jump). |
| `AppTextField` | `label, hint, errorText, controller, onChanged, keyboardType, obscureText, maxLines, maxLength, inputFormatters, enabled, prefixIcon, suffixIcon, validator` | **`errorText` is the contract for validation** — see §14. |
| `PhoneNumberField` | — | E.164 + Ivorian formatting. The only way to take a phone number. |
| `LoadingIndicator` | `size, color` | The brand loader. The **only** spinner. |
| `EmptyState` | `icon, title, description, actionText, onAction` | Icon at `iconXL`. |
| `TimedCachedImage` | network + `asset:` + caching | The **only** way to show a remote image. |
| `BrandLoader` / `BrandRefresh` | | Brand-mark loader + pull-to-refresh. |
| `CommunePickerSheet` / `CommunePill` | | Locality selection (market data — §18). |
| `SalonTimeHint` | | The "heure du salon" affordance (§18). |
| `ComingSoonScaffold` | | The V2/V3 flag-hidden placeholder. |

### 11.2 Admin (`lib/screens/admin/widgets/`)

| Component | Notes |
|---|---|
| `AdminScaffold` | Sidebar + top bar. |
| **`AdminDataTable`** | **The reference implementation of the four-state contract** (§12) — the only component in the repo that does all four properly. New async components copy its shape. |
| `StatCard` | |
| `StatusChip` | `StatusChip.forStatus(String)` → semantic kind + French label. Kind, not color, is the API. |
| `showReasonDialog` | |

### 11.3 To build (the gaps this system creates work for)

These exist as copy-pasted inline code today. They are specified here so that
when the burn-down reaches them, there is nothing left to decide:

- **`AppRating`** — `★ 4,8 (32 avis)`. Glyph + numeral, always (§3.5).
- **`AppCard`** — `secondary` on `background`, `radiusXL`, elevation 0, `spacingM` padding.
- **`AppChip`** — filled (selected) / outlined (`borderStrong`) / tinted (status). `radiusPill`.
- **`AppSnackBar`** — the single entry point for the 118 snackbar calls (§15).
- **`ConfirmDialog`** — the single destructive-confirm (§15).
- **`AppAsyncView<T>`** — takes `isLoading`/`error`/`data` and renders the four states, so a screen cannot forget one.

---

## 12. The four states

**Every screen and every async section renders four states.** A widget that only
handles the happy path is not done — this is the oldest rule in the project and
the most commonly half-kept.

| State | Requirement |
|---|---|
| **Loading** | Never a blank screen. **Skeleton** if the shape of the result is known (a list, a card) — it reduces perceived latency and prevents layout jump. **Spinner** (`LoadingIndicator`) only when the shape is *not* known, or the wait is < ~300ms. Never both. |
| **Empty** | `EmptyState` with an icon, a French title, a description that says *why* it's empty, and — wherever an action can fix it — a button. "Aucun résultat" alone is a dead end. |
| **Error** | A human French message + **a retry control**. An error state without a way out is a crash with better manners. Never show a raw exception, HTTP code or stack trace. |
| **Success** | The content. |

Plus the states that aren't about data: **offline**, **permission-denied**
(e.g. `PushBlockedBanner`), and **auth-gated** (preserve `returnTo`).

---

## 13. Accessibility

Target: **WCAG 2.1 level AA**. This section is the largest gap between what the
old standards *said* ("≥4.5:1 contrast (monochrome passes)") and what the code
does — see §21.

### 13.1 Contrast

Every rule in §3 is **executable**: `test/unit/design_contrast_test.dart` computes
real WCAG relative luminance for every token pair and asserts it against its floor,
using the same `test/support/wcag.dart` the goldens use — so the two can never
disagree about what "passes" means. A token that fails cannot be merged. Prose can
drift; a failing test cannot.

It also pins the two **usages** A1 fixed, because a value can be asserted but a usage
has to be grepped: the ink may never appear as a fill or a stroke (that is how the
brand black silently softens), and `starRating` may only ever colour a star glyph.

### 13.2 Touch targets — ≥48×48

**Every interactive element has a ≥48×48 dp touch target**, regardless of how big
its glyph is (WCAG 2.5.5 / Material's `androidTapTargetGuideline`). Padding
between the glyph and the target edge is free; the target is what the finger gets.

- `IconButton` gives you 48 by default — **don't fight it** with `constraints:` or
  `padding: EdgeInsets.zero`.
- A hand-rolled `GestureDetector`/`InkWell` gives you **nothing**. If you must
  hand-roll, wrap the child in `ConstrainedBox(minWidth: 48, minHeight: 48)` — or
  better, don't hand-roll.
- Targets that are *adjacent* need ≥8px between them, or a fat finger hits the
  wrong one.

### 13.3 Text scaling — up to 200%

The OS font-size setting is a **first-class input**, not an edge case. A user who
sets 200% has told the system they cannot read the default; a layout that clips at
150% is unusable for them.

- **Never** `MediaQuery.withNoTextScaling` or a hardcoded `textScaleFactor: 1.0`.
  Disabling scaling to "protect the layout" protects the layout by breaking the
  user.
- **A box that contains text may not have a fixed height.** `SizedBox(height: 50)`
  around a `Text` is a clip waiting to happen — use `minHeight` or let it grow.
- Text that *can* overflow gets `maxLines` + `TextOverflow.ellipsis`. Today only
  4.8% of `Text` widgets do.
- Gate: the key screens are pumped at `TextScaler.linear(2.0)` and asserted not to
  overflow.

### 13.4 Semantics (screen readers)

TalkBack and VoiceOver read the **semantics tree**, not the pixels. Today the
three apps contain **zero** `Semantics()` widgets, which means every custom
control is announced as nothing at all.

- **Icon-only controls carry a `tooltip:`** — on `IconButton` this is both the
  long-press hint *and* the screen-reader label. One property, two wins.
- **A custom gesture widget gets a `Semantics(button: true, label: …)`.** A
  `GestureDetector` is invisible to a screen reader without it.
- **An image that carries meaning gets a label**; a decorative one is
  `ExcludeSemantics`d so it isn't announced as noise.
- **Group what is read together** (`MergeSemantics`) so a card announces as one
  coherent sentence rather than six disconnected fragments.
- **Announce what changed** (`SemanticsService.announce`) when something happens
  away from focus — a booking confirmed, a filter applied.
- Gate: `meetsGuideline(androidTapTargetGuideline)`, `meetsGuideline(labeledTapTargetGuideline)`
  and `meetsGuideline(textContrastGuideline)` over the top ~10 screens. Flutter
  ships these; we simply have not been calling them.

### 13.5 Focus

Every interactive element shows a visible focus state: `borderFocus`, 2px, 2px
offset (§3.3). Dialogs and sheets take focus on open and **return it on close**.
Order follows reading order.

### 13.6 Color independence

No information is carried by color alone (§3.5): pair it with a glyph, a label, a
numeral or a position. The test is simple — **screenshot it in grayscale; if you
lose information, it's a bug.**

---

## 14. Forms & validation

**Errors belong to fields, not to toasts.**

Today, `AppTextField` exposes `errorText` and exactly **one caller in the entire
codebase passes it** — so the de-facto validation pattern is "throw a red
snackbar." That fails users in three ways: the message disappears on a timer, it
doesn't say *which* field is wrong, and a screen reader never associates it with
the input.

The rules:

1. **The message renders under the field it belongs to** (`errorText`), stays until
   fixed, and is associated with the input for assistive tech.
2. **Validate on submit; re-validate on change once a field has already errored.**
   Never validate a field the user hasn't finished typing into — the form that
   yells "email invalide" at `s@` is hostile.
3. **A snackbar is for the *outcome*** ("Connexion impossible — réessayez"), never
   for a field-level fault.
4. **Say what to do, not what happened.** "Le numéro doit comporter 10 chiffres",
   not "Format invalide".
5. **Disable submit only while submitting**, never as a way of expressing "the form
   is invalid" — a disabled button with no explanation is a dead end.
6. Required vs optional is stated, not implied by an asterisk alone.

---

## 15. Feedback & destructive actions

### Snackbars

118 `showSnackBar` calls exist; 73 are raw inline `SnackBar(...)`, only 5 go
through the shared helper, and exactly **one** in the entire product offers an
action. That is the whole feedback layer of the app, unmanaged.

The single entry point is **`AppSnackBar`**:

| Kind | Color | Duration |
|---|---|---|
| success | `success` | 3s |
| info | `textPrimary` | 3s |
| error | `error` | **6s** (an error needs time to read) |
| with action | — | **10s** (time to reach the button) |

### Destructive actions — the confirm ladder

Eleven copy-pasted `showDialog<bool>` confirmations exist. They become one
**`ConfirmDialog`**, and the friction is proportional to the damage:

| Damage | Pattern |
|---|---|
| **Reversible** (mark read, remove a favourite) | **Do it immediately, offer Undo** in the snackbar. Don't ask permission for something you can take back — a confirm dialog for a reversible action is a tax on the 99% who meant it. |
| **Hard to undo** (cancel a booking, delete a photo) | `ConfirmDialog` — name the exact thing, state the consequence, and label the button with the **verb** ("Annuler le rendez-vous"), never "OK". |
| **Irreversible + high-value** (delete an account, delete a salon) | `ConfirmDialog` + **type-to-confirm**. |

The destructive button is `error`; the cancel path is the safe default and gets
focus. Never place the destructive action where "OK" usually sits.

---

## 16. Iconography

Material Icons, **outlined** style, at the five sizes in §7. Filled variants are
reserved for the **selected/active** state (`star_border` → `star`,
`favorite_border` → `favorite`) — which is also what makes those states survive
grayscale (§13.6). One concept, one icon, product-wide.

---

## 17. Content & microcopy

- **French, everywhere** — labels, errors, empty states, buttons. Vouvoiement
  ("Réservez", "Votre rendez-vous"). Warm and plain, never cute; never
  technical.
- **FCFA, phone, duration, date** via `core/utils/` formatters — never
  hand-formatted.
- **Buttons are verbs** that name the outcome ("Réserver", "Confirmer le
  paiement"), not "OK" / "Soumettre".
- **The error formula: what happened → why → what to do.** "Paiement non confirmé
  — le justificatif n'a pas été reçu. Renvoyez la capture d'écran."
- **Never blame the user**, never show them an error code alone.
- **French is ~20% longer than English** — every label must survive expansion *and*
  200% text scale (§13.3). Design for the long string, not the demo one.

---

## 18. Market data & salon time

*(Carried forward unchanged — this rule predates the design system and outranks
it.)*

Market-specific facts — communes/localities, Mobile Money operators, currency,
timezone, phone prefixes — live **only** in their seams
(`core/constants/communes.dart`, `core/utils/mobile_money.dart`,
`core/utils/formatters.dart`, `core/utils/salon_time.dart`). Displayed times and
day boundaries are **salon time**, never the device's
([modules/multi-pays.md](../modules/multi-pays.md) §3/§9). Hardcoding a market
fact in a widget fails review **even when it works for Côte d'Ivoire** — it is
grep-pinned by `salon_time_pin_test.dart`.

---

## 19. Sanctioned exceptions

Deliberate, bounded, **not** debt:

- **Service-category accents** — color genuinely aids wayfinding on the map and the
  category chips, so the muted/earthy palette in §3.6 is an explicit exception to
  monochrome. **Always via `categoryColor()`.**
- **Story scrims** — the black→transparent gradient in `story_viewer` /
  `announcement_stories` is a neutral readability overlay; a literal alpha-black is
  acceptable there.
- **Brand black** — the logo, the `BrandLoader` and the app icon stay `#000000`
  (§1). They are brand assets, not ink.
- **`Colors.transparent`** and alpha-black/white **for scrims and overlays only**.

Everything else: no `Color(0x…)`, no named `Colors.<hue>`, no raw `fontSize:`.

---

## 20. Enforcement

Rules that aren't executed rot. Each rule in this document maps to a gate:

| Rule | Gate |
|---|---|
| Contrast (§3, §13.1) | **`test/unit/design_contrast_test.dart`** — real WCAG math per token pair, + grep-pins on the ink/brand split and gold-as-state |
| No literals (§3, §4, §5, §6) | `test/design_system_pin_test.dart` — grep-as-test with the §21 register as its allowlist, which **shrinks** with each burn-down PR |
| Tap targets + labels (§13.2, §13.4) | `meetsGuideline(androidTapTargetGuideline / labeledTapTargetGuideline / textContrastGuideline)` |
| Text scale (§13.3) | Key screens pumped at `TextScaler.linear(2.0)`, asserted not to overflow |
| Visual regression | **Goldens** — `test/golden/`, see below |
| Market data (§18) | `salon_time_pin_test.dart` |
| Everything | `flutter analyze --fatal-infos` = 0 |

The manual sweep (must not grow; ideally → 0), from `mobile/`:

```bash
grep -rn  --include='*.dart' "Color(0x" lib | grep -v lib/core/theme/
grep -rEn --include='*.dart' "Colors\.(red|green|blue|orange|grey|gray|amber|purple|teal|pink|yellow|indigo|cyan|brown)" lib | grep -v lib/core/theme/
grep -rn  --include='*.dart' "fontSize:" lib | grep -v lib/core/theme/
```

### 20.1 Goldens — the eye

`mobile/test/golden/` holds 17 goldens, and they are the **only** thing in the
repo that renders the real design system: not one of the 34 widget tests passes
`theme:`, so the whole suite would stay green while the product restyled
underneath it.

- **The token catalogue** (`tokens_*`, `components_*`) — every colour with its
  measured ratio, the whole type scale, the buttons, the text field in all five
  states, status/chips/cards/rating, and `AdminDataTable`'s four states. A token
  change lights these up immediately.
- **Real screens** (`consumer_*`, `pro_*`) — because a token can be right in the
  catalogue and still wreck a page.

**Goldens are authored on Linux, and only on Linux.** Flutter rasterizes glyphs
through CoreText on macOS and FreeType on Linux — same font, same Skia, different
pixels — so a Mac-authored golden fails in CI on every PR, forever. CI (ubuntu,
Flutter 3.38.6) therefore *is* the authority: the goldens run inside the existing
blocking `analyze-and-test` job. Everywhere else they **skip with a reason**, so
`flutter test` on a Mac says so out loud instead of failing mysteriously.

```bash
./tool/update_goldens.sh          # regenerate in the pinned Linux image (Docker)
./tool/update_goldens.sh <name>   # …just the ones matching a name
```

No Docker? Run the **“Goldens — regenerate”** workflow from the Actions tab and
download the `goldens` artifact. Either way: **review every changed PNG before
committing.** A wrong baseline is worse than none, because every later PR is then
diffed against a lie. When a golden fails in CI, the diff images are uploaded as
the `golden-failures` artifact — a golden failure is a picture, and you should
look at it.

**No fonts are vendored.** The harness loads Roboto and MaterialIcons out of the
SDK's own cache (`$FLUTTER_ROOT/bin/cache/artifacts/material_fonts/`), and CI pins
the same SDK — so the bytes are identical on both sides, nothing is committed, and
it cannot drift. Roboto is also Android's system font, our primary target.

**Two things a golden cannot pin**, both deliberate:
- **The brand loader.** `BrandLoader` is an infinitely-repeating Lottie; any
  golden of it would be a picture of an arbitrary animation frame. The loading
  state we *do* pin is `AdminDataTable`'s skeleton, which is static.
- **Anything that reads the wall clock** — see register row 23.

---

## 21. The known-violations register

**The audit, as a work list.** Every row is a real, counted defect in the code as
of 2026-07-14. Each burn-down PR drives its row to **0** and shrinks the pin
test's allowlist. This table is the honest answer to "does the product follow its
own design system?" — today, mostly not.

| # | Rule | Violations | Worst instance | Slice |
|---|---|---|---|---|
| 1 | `textTertiary` ≥ 4.5:1 (§3.2) | ~~202~~ → **0** | was 3.22:1 on every input hint and the 11px nav label; now **4.76:1** | ✅ **A1** |
| 2 | Control borders ≥ 3:1 (§3.3) | ~~every input~~ → **0** | every field was outlined at **1.44:1**; the worst was a *tappable* journal tile on `divider` at **1.24:1**. Now `borderStrong` (3.22:1) on ~30 form controls + selection states — and *not* on content-identified cards, which would have boxed the product for no gain | ✅ **A1** |
| 3 | Ink ≠ brand black (§1) | ~~130~~ → **0** | `textPrimary` is `#1A1A1A`; `primary` stays `#000000`. Exactly ONE site had the brand black wearing the ink token (a `CircleAvatar` fill) — now grep-pinned so it can't come back | ✅ **A1** |
| 3b | Gold carries state at ≥3:1 (§3.5) | ~~3~~ → **0** | the unseen-story ring was a **1.62:1** stroke — a state indicator you could not see. Gold-as-state → `gold` (3.04:1); the 12 real star glyphs keep `starRating` | ✅ **A1** |
| 4 | Spacing on-grid (§5) | ~128 `SizedBox` + ~45 `EdgeInsets` | `12` appears **76×** | **A2** |
| 5 | Radius tokens (§6) | 23 | `999` appears **21×** | **A2** |
| 6 | Type scale ≥ 11px (§4) | 9 raw `fontSize:` | six at **10px** | **A2** |
| 7 | Icon-size tokens (§7) | **19 distinct values**, 0 constants | | **A2** |
| 8 | Motion tokens (§9) | **12 distinct durations**, 0 constants | | *A9* |
| 9 | Full `ColorScheme` (§3) | **23 component themes missing** | unstyled M3 widgets fall back to **Material purple** | **A3** |
| 10 | Button min-height 48 (§13.2) | all | `textButtonTheme.minimumSize = Size(0, 40)` | **A3** |
| 11 | Buttons sized by container (§10) | all | `elevatedButtonTheme.minimumSize = Size(double.infinity, 48)` | **A3** |
| 12 | Tap targets ≥ 48 (§13.2) | **67** hand-rolled gestures, 0 constraints | photo re-order arrow = **20×20**; favourite heart = **32×32** | **A4** |
| 13 | Icon-only controls labelled (§13.4) | **26 of 40** IconButtons | the **consumer app has 0 tooltips** | **A4** |
| 14 | `Semantics` on custom controls (§13.4) | **0** in three apps | | **A4** |
| 15 | 200% text scale (§13.3) | **3 confirmed breaks** + 24 at risk | `widgets/home/category_chips.dart:25` — **the home screen** | **A5** |
| 16 | Overflow discipline (§13.3) | 46 of 963 `Text` (4.8%) | | **A5** |
| 17 | One snackbar entry point (§15) | 118 calls; 73 raw; **1** with an action | shared helper hardcodes `Colors.black87` | *A6* |
| 18 | One `ConfirmDialog` (§15) | **11** copy-pasted | | *A6* |
| 19 | Field-anchored errors (§14) | **1** caller passes `errorText` | validation = "throw a red toast" | *A8* |
| 20 | Reduced motion (§9) | **0** | | *A9* |
| 21 | Tests wrap the real theme | **0 of 34** widget tests → **17 goldens do** | a restyle can't fail a test that never loads the theme | **A3** (PR-0.5 opened the eye) |
| 22 | Deferred V2/V3 `Colors.*` | ~52 | flag-hidden `ComingSoon` screens | *allowlisted — fix if un-shelved* |
| 23 | **No clock seam** (§20.1) | pro dashboard + journal | `ProJournalProvider._selectedDate = salonToday()`; `MockProService.getDashboard()` buckets by `DateTime.now().weekday` — so those screens **cannot be golden-tested**: the image would change value with the day of the week, failing CI every morning. `package:clock` is unused. | *new — needs its own slice* |
| 24 | Disabled labels legible | all | the disabled primary button is `#5C5C5C` on `#949495` — **2.21:1**. WCAG exempts disabled controls, so this is not a violation; it is, measurably, hard to read. | *A3 (`disabledForegroundColor`)* |
| 25 | No meaning by colour alone (§13.6) | 1 | the story ring says seen/unseen with **hue and nothing else**. A1 made it legible (`gold`, 3.04:1); it still doesn't survive greyscale. Needs a second cue — weight, or a dot. | *A4* |
| 26 | Unselected segments have no boundary | 2 | both hand-rolled segmented controls draw a border on the **active** segment only (`active ? Border.all(…) : null`). A1 made that border 3:1, so the *state* is now identifiable — but the unselected segments still have no edge of their own. | *A3 (`segmentedButtonTheme`)* |

**Bold** slices are committed (the a11y tranche). *Italic* ones are specified and
scheduled for re-evaluation after it.

Rows **23–26** were not in the original audit. Each was found by *doing the work*:
23 and 24 by taking the pictures (PR-0.5), 25 and 26 by walking every bordered
control in A1. That is the register behaving as intended — it gets **more honest**
as it shrinks, not just shorter.

---

## 22. Deferred

Decided, not forgotten:

- **Dark mode.** Zero references today; 4 `*Dark` tokens with 0 usages. **But every
  token in this document is role-named** (`textTertiary`, not `gray500`) precisely
  so that a dark theme is a *value swap*, not a rewrite. Don't add a token named
  after its color.
- **A brand font** (Inter). System fonts today.
- **Real tablet/desktop layouts** for the apps (§10 is defensive, not adaptive).
- **The 52 flag-hidden V2/V3 color offenders** — allowlisted in the pin test with a
  comment, to be fixed if those screens are ever un-shelved.

---

*Supersedes `DESIGN-STANDARDS.md`. Web companion: [WEB-SYSTEM.md](WEB-SYSTEM.md).
Enforced by the `myweli-dev-guardrails` skill.*
