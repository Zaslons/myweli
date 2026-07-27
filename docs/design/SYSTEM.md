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

Our surfaces, worst → best: **`surfaceVariant #F5F5F5`** (input fills,
skeletons — the darkest, so the TRUE worst case), `background #F6F7F9` (the
scaffold), `surface #FAFAFA`, `secondary #FFFFFF` (cards). **A token must clear
its floor on `surfaceVariant`** to be used anywhere. (The contrast gate long
measured only the middle three and called `background` the worst case; gold
slipped through at 2.98:1 on `surfaceVariant` — §21 row 3b. All four are
measured now.)

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
| `gold` | `#B5830A` | 3.15 | A **non-text accent**: the owner-chip border, the unseen-story ring. Clears 3:1 on ALL surfaces incl. `surfaceVariant` (3.10) — darkened from `#B8860B`, which failed there at 2.98 (§21 row 3b) | Text (fails 4.5:1 — §21 row 28) |

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

| Style | Size / line | Weight | Tracking | Use for |
|---|---|---|---|---|
| `displayLarge` | 57 / 64 | 700 | −0.25 | Marketing & splash only. Not used in-product today. |
| `displayMedium` | 45 / 52 | 700 | 0 | ″ |
| `displaySmall` | 36 / 44 | 700 | 0 | ″ |
| `headlineLarge` | 32 / 40 | 600 | 0 | Screen title (rare — hero) |
| `headlineMedium` | 28 / 36 | 600 | 0 | Screen title |
| `headlineSmall` | 24 / 32 | 600 | 0 | **AppBar title**, section hero |
| `titleLarge` | 22 / 28 | 600 | 0 | Card/section heading |
| `titleMedium` | 16 / 24 | 500 | 0.15 | List-row title, dialog title |
| `titleSmall` | 14 / 20 | 500 | 0.1 | Dense row title |
| `bodyLarge` | 16 / 24 | 400 | 0.5 | **Default reading text** |
| `bodyMedium` | 14 / 20 | 400 | 0.25 | Secondary text (the workhorse) |
| `bodySmall` | 12 / 16 | 400 | 0.4 | Captions, metadata |
| `labelLarge` | 14 / 20 | 500 | 0.1 | Button labels |
| `labelMedium` | 12 / 16 | 500 | 0.5 | Chips, field labels |
| `labelSmall` | 11 / 16 | 500 | 0.5 | **The smallest text in the product** — nav labels, badges |

**The tracking column was missing until B2b**, while `text_styles.dart` had set it on
**9 of these 15** all along — so this table did not describe the code it claims to be
sourced from. That is not cosmetic: the web mirror is built *from this table*, and
building it faithfully would have shipped the web with no tracking at all against the
app's. It would have been the **third** silent mirror drift after `gold` (WEB-SYSTEM
§15 row 4) and the missing `sm`/`xxxl` spacing — which is the case for row 19's
generator, not for more careful reading.

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

### What §5 does not govern

**Rhythm, not sizing.** This scale governs the gaps *between* things — padding,
margin, the space in a column. It does **not** govern how big a thing *is*: an
image's height, a sidebar's width, a map box, an avatar. `20` is not a legal
*spacing* value and is a perfectly ordinary *size*, and both are true at once.

That distinction was load-bearing and, until B2c, written down **nowhere a reader
would look** — it lived only in `design_system_pin_test.dart`'s doc comment and a
Tailwind config comment, while this section said "nothing else is legal" without
qualification.

**There is no sizing scale, and that is a decision.** `AppTheme` has 19 constants —
8 spacing, 6 radius, 5 icon — and nothing else. A layout dimension is a **named
constant at the call site** (`ProviderCard._imageHeight = 180`, `JournalGrid.AXIS_W
= 56`), because a map's height is not a design token: naming it `size-xl` would tell
the next reader nothing that `180` doesn't. The pin agrees by construction — its
spacing regex requires `)` immediately after the number, so a *sized container*
(`SizedBox(height: 48, width: 48, child: …)`) never matches, and the pin still calls
the firewall complete. The escape hatch (`// ds-ignore`) exists for the rare fixed
dimension that trips it anyway.

And for anything **bounding text**, the answer isn't a scale at all — it's
`AppTheme.textScaledBound` and §21/A5's rule: *prefer intrinsic; compute a bound only
under laziness; pin every computed bound with a test.*

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

Source: `AppTheme.iconXS…iconXL`. The codebase used **19 distinct icon sizes**; five
is enough — the 146 `size:` call-sites are snapped to these tokens (nearest; ties
round up) and pinned (§20).

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

Five tokens, and this table is where their values live. `AppMotion`
(`mobile/lib/core/theme/motion.dart`) and `motion` (`web/styles/tokens.ts`) both
mirror it, and `web/tests/tokens.mirror.test.ts` fails on any disagreement
between the three — editing a number in one place is a red CI job, not a drift.

| Token | Value | Curve | Use for |
|---|---|---|---|
| `motionStagger` | 50ms | — | The per-item delay in a staggered list reveal |
| `motionFast` | 100ms | `easeOut` | Immediate state feedback — ripple, checkbox, toggle |
| `motionBase` | 200ms | `easeInOut` | **The default** — most transitions, cross-fades, expand/collapse |
| `motionEmphasis` | 300ms | `easeOutCubic` | Entering surfaces — sheets, dialogs, snackbars |
| `motionSlow` | 400ms | `easeInOutCubic` | Full-screen / large-surface transitions |

Dart drops the prefix the file already carries: `AppMotion.stagger` / `.fast` /
`.base` / `.emphasis` / `.slow`, each with its `…Curve` twin. **Curves are
mobile-only** — Tailwind has no `easeOutCubic`, so the web mirrors durations and
stops. A declared divergence, and pinned as one.

**Pick by the Use column, not by nearest number.** Proximity only breaks ties
*within* a use. A8 got this wrong once and it cost a rule: a 1500ms splash fade
went to `motionSlow` because 1500 is nearest to 400, and `easeInOutCubic` still
eases *in* — so a fade-in kept violating "entering decelerates", just more
quietly than the `easeIn` it replaced. A logo appearing is an entering surface;
the answer was `motionEmphasis`.

**Entering** decelerates (`easeOut*`), **exiting** accelerates (`easeIn*`), and
things that move *and* stay use `easeInOut`. **Take the pair, not the number** —
the duration and its curve are one token. A8 found the rule already broken in the
only place prose could not catch it: the pro splash faded a logo *in* on
`easeIn`. The pairing is now pinned in the mirror test.

Nothing user-initiated may take longer than `motionSlow` — beyond ~400ms an
animation stops reading as *response* and starts reading as *lag*, especially on
the reference low-end Android.

**A content timer is not motion.** How long a story stays on screen, how long the
splash holds, how long a search waits before firing — these are measured in
reading time or network chatter, and this ladder cannot name them. They keep
their literal and carry a `// ds-ignore` saying which they are. §12's "~300ms"
spinner heuristic is the same: it collides numerically with `motionEmphasis` and
has nothing to do with it.

### 9.1 Reduced motion

When the user asks the OS to stop moving the screen, we listen — **on both
platforms**, which takes more than the one flag this section used to name.

- **Android** sets `disableAnimations` (and only when *Transition animation
  scale* is exactly 0). It rides `MediaQueryData`, so reading it rebuilds for
  free.
- **iOS** sets `reduceMotion`, and **the framework reads it nowhere** —
  `grep -rn "reduceMotion" packages/flutter/lib/` returns 0, and
  `kDisableAnimations` appears in no Darwin embedder. It is also not an
  `InheritedWidget`, so nothing rebuilds when it changes.

`reduceMotionOf(context)` (`mobile/lib/core/a11y/reduce_motion.dart`) reads both;
`ReduceMotionObserver`, installed at every app root, makes the iOS half reactive.
The accessor falls back to reading the dispatcher directly when no scope is above
it: a missing observer costs a rebuild, never the behaviour.

**Do not hand-wire what the framework already does.** Route transitions, `Hero`
and every implicit `AnimatedX` run plain controllers and collapse to 5 % on their
own (`animation_controller.dart:651`). Reach for the accessor only where that
scale cannot arrive:

- **`repeat()`**, which calls `_startSimulation` directly and never sees it —
  Lottie's ticker, an indeterminate `CircularProgressIndicator`;
- **involuntary movement**, where the app moves the page rather than the user —
  `Scrollable.ensureVisible`, an auto-advancing `PageController`.

**What replaces the motion matters as much as stopping it.** A frozen logo and a
broken screen look identical, so `BrandLoader` holds a still frame *and* says
« Chargement… ». Branding, colour, layout and timing stay exactly as they are for
everyone else: the user asked for less movement, not a different app.

**A content timer must not be collapsed.** `AnimationController` scales a
`normal` controller to 5 % under the flag, which is right for a transition and
wrong for a reading time — a 6-second story would flash past in 300ms. A
controller driving *dwell* rather than *movement* takes
`AnimationBehavior.preserve`.

### 9.1.1 Two ways of "not animating" that do not work

Both were written, shipped in a slice, and caught by the review that followed.
Neither is obvious from the API, and neither fails loudly.

- **`Duration.zero` is not "instant" everywhere.** `Scrollable.ensureVisible`
  special-cases it and jumps (`scroll_position.dart:872`). `PageController` does
  not: `animateToPage` reaches `DrivenScrollActivity`, whose constructor asserts
  `duration > Duration.zero` (`scroll_activity.dart:705`). Use **`jumpToPage`**.
  Read the API you are calling, not the one next to it.
- **Stopping a Lottie is not the same as showing one.** `animate: false` stops
  the ticker and parks progress at **frame 0** — and frame 0 of a draw-on
  animation is an empty canvas. Either render the static asset the animation
  draws towards (`BrandLoader`) or pin the progress to the end frame with
  `AlwaysStoppedAnimation` (the splash). A frozen blank screen is not a
  reduced-motion state.

**And a reduced-motion layout is a different layout.** Replacing motion with
text adds height that the surrounding box may not have — `BrandLoader`'s caption
overflowed a 60px avatar placeholder by 44px. The widget measures its incoming
constraints; §13.3's arithmetic rules apply, including checking 2×.

⚠️ **The remaining gap is the framework's, and it is iOS-only** — see §21 row 33.

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
| `AppTextField` | `label, hint, errorText, controller, focusNode, onChanged, keyboardType, obscureText, maxLines, maxLength, inputFormatters, enabled, prefixIcon, suffixIcon` | **`errorText` is the contract for validation** — see §14. A7 **removed `validator`**: it cannot express rule 2, and its result silently overwrites `errorText`. |
| `InlineFeedback` | `message, kind` | The form / in-modal outcome slot (§14, §15). `null` renders nothing. |
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
when the burn-down reaches them, there is nothing left to decide.

*(`AppSnackBar` and `ConfirmDialog` were on this list until **A6** built them;
`FieldErrors` + `Validators` joined §11.1's roster in **A7**.)*

- **`AppRating`** — `★ 4,8 (32 avis)`. Glyph + numeral, always (§3.5).
- **`AppCard`** — `secondary` on `background`, `radiusXL`, elevation 0, `spacingM` padding.
- **`AppChip`** — filled (selected) / outlined (`borderStrong`) / tinted (status). `radiusPill`.
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

**Reduced motion lives in [§9.1](#91-reduced-motion), and it belongs here too.**
WCAG 2.3.3 is an accessibility criterion, not a styling preference: vestibular
disorders make involuntary movement genuinely nauseating. It is written up with
the motion tokens because that is where the mechanism is, and cross-referenced
here because this is where anyone auditing accessibility will look.

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

*Until A7, `AppTextField` exposed `errorText` and exactly **one caller passed
it** — and that caller was unreachable, so the product had **zero** working
field-anchored errors. The de-facto pattern was not, as this section long
claimed, "throw a red snackbar": it was the **silent disabled button** (22
sites), then hand-rolled red `Text` (10), then a toast (4 live, 4 dead). All
three fail the same way — the message doesn't say which field is wrong, and it
disappears, or never appears at all.*

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

**Rule 5's one exception is §15's destructive ladder.** `ConfirmDialog` holds
its confirm disabled until the reason is typed or the confirm word matches —
that is deliberate friction on an irreversible action, not a form judging its
input, and §15 specifies it. A rate limit is the other legitimate disable (a
resend cooldown, an OTP lockout), and it must label itself: « Renvoyer dans
0:24 » says when it reopens. Nothing else may be disabled to mean "invalid".

**Focus follows the first error.** §13.5 covers focus on open and on close and
says nothing about submit — but once rule 5 makes every button tappable, a press
can produce a message the user never sees. A failed submit scrolls the first
errored field into view and focuses it, in the form's **reading order**
(`focusFirstError`, `core/forms/field_errors.dart`).

**Three slots, and only three** (A7; the modal half is A6's finding):

| Slot | Widget | Owns |
|---|---|---|
| field fault | `AppTextField.errorText` | "this input is wrong" — persists until fixed |
| form / in-modal outcome | `InlineFeedback` | « Connexion impossible » · anything inside a sheet, where a snackbar is pruned by `ModalBarrier` (§15) |
| screen outcome | `AppSnackBar` | rule 3 — the outcome, never a field fault |

**Flutter has no `aria-describedby`, and the spec should not pretend otherwise.**
Measured in A7: `errorText` is **not** folded into the field's semantics label —
it renders as a **child node** of the field's node, so a screen reader reaches it
immediately *after* the input rather than hearing it *with* the input.
`MergeSemantics` cannot change that (a `TextField`'s node is a semantics
boundary; wrapping one produces a byte-identical tree). So rule 1's "associated"
means **structurally associated and reachable** on this platform — which is what
`test/a11y/field_error_test.dart` holds. Do **not** reach for `SemanticsService`
to close the gap: `supportsAnnounce` is false on Android, where a direct
announcement clears TalkBack's queue (§15, A6).

---

## 15. Feedback & destructive actions

### Snackbars

~~118 `showSnackBar` calls exist; 73 are raw inline `SnackBar(...)`~~ — **A6
closed this**: every snackbar in the product goes through **`AppSnackBar`**,
and the kind is the API (a call site never picks a colour or a duration).

| Kind | Color | Glyph | Duration |
|---|---|---|---|
| success | `success` | `check_circle_outline` | 3s |
| info | `textPrimary` | `info_outline` | 3s |
| error | `error` | `error_outline` | **6s** (an error needs time to read) |
| with action | — | — | **10s** — *when the snackbar is the only route back* |

**The glyph is not decoration (§13.6).** `success` (#2D5016) and `error`
(#8B0000) have relative luminances of 0.072 and 0.062 — screenshot them in
greyscale and the outcome is gone. Colour + glyph is two cues, the same fix
A4b made on the story ring. *(A6 amendment.)*

**The 10s rule is scoped.** §15 originally gave every action-bearing snackbar
10s. But when the SCREEN itself is the undo — the favourite heart is one tap —
ten seconds of occlusion on a routine action is a cost with no benefit. 10s is
for when the bar is the only way back (a deleted photo); otherwise the kind
keeps its own duration. `SnackAction.isOnlyRouteBack` says which.
*(A6 amendment.)*

**Feedback raised while a dialog or sheet is open is NOT a snackbar.**
`ModalBarrier` renders `BlockSemantics(ExcludeSemantics(…))`, so the bar is
pruned from the semantics tree — a screen reader never hears it — and it paints
*under* the scrim (§10). It belongs inside the modal that raised it:
**`InlineFeedback`**, which borrows the same `SnackKind` so feedback speaks one
vocabulary wherever it lands. *(A6 amendment; the mirror of web B5's
`aria-modal` finding.)*

**Announcements: the `SnackBar` is already a live region** (Flutter wraps every
one in `Semantics(liveRegion: true)`), which is the mechanism both platforms
support — and the ONLY one on Android, where `supportsAnnounce` is false and a
direct announcement clears TalkBack's queue. **Do not add `SemanticsService`
beside a snackbar**; A6 deleted the six sites that did. `Helpers.announce`
remains right for genuinely off-focus events that are *not* snackbars (the map
sheet's favourite, pull-to-refresh). *(A6 correction — the pre-A6 register
claimed the opposite.)*

### Destructive actions — the confirm ladder

~~Eleven copy-pasted `showDialog<bool>` confirmations exist.~~ — **A6 closed
this** (13 `AlertDialog`s, once the admin's `showReasonDialog` and the caption
prompt were counted). One **`ConfirmDialog`** serves them all, and the friction
is proportional to the damage:

| Damage | Pattern |
|---|---|
| **Reversible** (mark read, remove a favourite) | **Do it immediately, offer Undo** in the snackbar. Don't ask permission for something you can take back — a confirm dialog for a reversible action is a tax on the 99% who meant it. |
| **Hard to undo** (cancel a booking, delete a photo) | `ConfirmDialog` — name the exact thing, state the consequence, and label the button with the **verb** ("Annuler le rendez-vous"), never "OK". |
| **Irreversible + high-value** (delete an account, delete a salon) | `ConfirmDialog` + **type-to-confirm**. |

The destructive button is `error`; the cancel path is the safe default and gets
focus. Never place the destructive action where "OK" usually sits.

**Undo undoes ONE action — it never restores a snapshot.** A6's review caught
the trap: when the service takes a whole collection, the obvious undo is to
capture the list before the delete and PUT it back. That is not undo, it is a
rewind — and everything the user did during the 10-second window is destroyed
by the button whose entire promise is that nothing was lost (a reorder
reverted, a photo uploaded in the meantime deleted for good). Re-insert the one
removed item into the **current** collection instead. And an undo that fails
must say so: the restore's result is feedback, never a discarded `Future`.

**A dialog `scrollable: true`.** A consequence sentence plus a type-to-confirm
field overflows its own box at 200 % text (§13.1) — measured at 4px on a
400×700 surface — and paints the message over the buttons; a keyboard rising
under a field does the same.

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

### 17.1 Typography — one spelling per character

Added in **A9**, because until then this section had **no typography rule at
all** and §20 had no row for §17 — the only substantive section with neither,
which is exactly why the copy drifted into two spellings of the same word.

| Rule | Write | Never |
|---|---|---|
| Ellipsis | `…` (U+2026) | `...` |
| Apostrophe | `’` (U+2019) | `'` (U+0027) |

Measured at A9's base: `…` 10 sites vs `...` 5, and `’` 56 lines vs `\'` 90 —
including `Chargement...` in `availability_screen` beside `Chargement…` in
`BrandLoader`. **The same word, two spellings, one app.** Pinned in §20.

**What is deliberately NOT a rule here**, so nobody adds it later as an
oversight-correction: **guillemets « »** and the **narrow no-break space** before
`! ? : ;`. Both are correct French typography and both are *absent* rather than
inconsistent — 0 NBSP in 85 eligible sites, and guillemets in ~5 strings against
138 in doc comments. A9 fixed what the app contradicted itself about; inventing a
convention across 85 invisible characters is a different decision, and should be
taken as one.

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
| No literals (§4, §5, §6, §7) | **`test/unit/design_system_pin_test.dart`** — sweep-as-test, **complete**: no raw spacing (§5), radius (§6), type (§4), or icon-size (§7) literal survives. Excludes `core/theme/` (token defs) + the flag-hidden `features/` (§22); a `// ds-ignore` line is a declared fixed-dimension exception |
| Tap targets + labels (§13.2, §13.4) | **`test/a11y/`** — **complete**: `meetsGuideline(androidTapTargetGuideline)` (A4a) + `labeledTapTargetGuideline` (A4b) + `textContrastGuideline` (A4c), all live over the key components |
| Text scale (§13.3) | **`test/a11y/text_scale_test.dart`** — the key components pumped at `TextScaler.linear(2.0)`. **Three** assertions, because each of the first two passed against a real bug: `takeException()` is null (nothing *overflows*); **and** `expectGrowsWithTextScale` (the height actually grew — a fixed bound doesn't overflow, it **clips silently**); **and**, for any *computed* bound, that it still covers the widget's real content at **0.82× → 2×** and doesn't over-provision. Pump the widget **as it ships** — bounded, and in the variant that breaks: unbounded, nothing can overflow and the gate is vacuous |
| **Forms & validation (§14)** | **`test/unit/field_errors_test.dart`** (rule 2's state machine, incl. the merge case web's review had to fix) + **`test/unit/validators_test.dart`** (one rule per concept) + **`test/a11y/field_error_test.dart`** (unclipped at 200 %, grows its field, reachable in the field's semantics) + two pins in `design_system_pin_test.dart` — no `validator:`, one e-mail definition. **The rule a regex cannot express — "a field fault is never a bar" — is held behaviourally on SIX named funnels**, each asserting: submit invalid → the message renders *under the field* · **no `SnackBar` in the tree** · the flow does not advance · fixing it clears the message without a second submit. Those funnels are `login_screen` · `pro_register_screen` · `pro_salon_profile_screen` · `deposit_settings_screen` · `client_list_screen`'s add-client sheet · `invite_member_sheet` (gated since A6-era A7④a) — chosen because each is a defect A7 actually shipped. **A seventh, `client_detail_screen`'s tag sheet, is held to the same shape but sits OUTSIDE this arithmetic**: it has no validator map at all (a bare `String? _tagError`), so it is not one of the 17 — see row 32. Two of them are **lockout regressions**: load the stored value and save without editing, which is the assertion that catches "the app cannot save data it just loaded". Every one was mutation-proven red before it was trusted. **Coverage is 6 of the 17 screens on `FieldErrors` — see §21 row 32 for the remainder.** A7 first claimed this row when one such test existed; the count is now named rather than implied. |
| **Motion (§9, §9.1)** | **5 pins** in `design_system_pin_test.dart` — no `Duration(milliseconds:` and no `Curves.` under `screens/`+`widgets/` (red at **10 · 7**), plus a guard that the scan sees >100 files so an empty sweep can't read as a clean one — **and** `test/a11y/motion_test.dart`: the loader animates with motion on (the control), stops under the flag, stops on the **iOS flag alone**, stops when the flag is raised **mid-session**, stops with **no scope above it**, carries a `Semantics` label in both modes with exactly ONE node saying it, shows the **static mark** rather than a blank frozen Lottie, and unregisters its binding observer on dispose. Every app root is source-pinned to install `ReduceMotionObserver` (globbed, not listed). Three more pins close holes the review found rather than defects it saw, and are at **zero** with no measured red: no hand-rolled easing shape (`Cubic`, `SawTooth`, `Threshold`, `FlippedCurve`, `CatmullRom`, `Elastic*Curve` — `Curves.` is the idiom, not the language), no `duration:` in **seconds**, and `core/router/` in scope because that is where a full-screen transition belongs even though none lives there today. Values are pinned three ways — §9's table ↔ `AppMotion` ↔ `tokens.ts` — by `web/tests/tokens.mirror.test.ts`, **including the Curve column**, which the first version compared against a literal in the test file and therefore pinned against itself. **17 assertions, 20 mutations each watched fail.** The gates that matter most are the ones added *after* the review: the story reel's page position (two-legged — "jumps for nobody" and "jumps for everybody" both go red), the splash's pinned frame **and its 3800ms hold**, and the caption's bound in both directions at 2× text. **What is NOT gated: the story reel's 6 s dwell** — two attempts to reproduce it both came back green, so it is an open question, not a fix (see `mobile-a8-motion.md`). |
| **Language & typography (§17, §17.1)** | **§17's first gate**, and the reason it drifted: it was the only substantive section with none. `test/unit/french_test.dart` — the app resolves French localizations on **three independent mechanisms** (`GlobalMaterialLocalizations`, `GlobalCupertinoLocalizations`, `Intl.defaultLocale`), each asserted separately because any one can be right while the others are broken; a typed date reads as `dd/MM/yyyy`; the calendar starts Monday; the time picker gives a 24h dial with the device toggle off; every `MaterialApp` in `lib/` **and `test/support/`** declares the delegates (globbed, not listed). `test/unit/status_labels_test.dart` — no status renders English on any surface, `NO_SHOW`/`noShow`/`no-show` normalise to one label, an unknown status renders « — » and never the wire value, and no screen keeps its own vocabulary. Plus 2 pins in `design_system_pin_test.dart` for §17.1 (`…`, `’`) — the escaped apostrophe scanned at **line** level because a literal parser cannot see inside an interpolation, which is a hole a failing test found while the pin was green. |
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

`mobile/test/golden/` holds 19 goldens, and they are the **only** thing in the
repo that renders the real design system: not one of the 34 widget tests passes
`theme:`, so the whole suite would stay green while the product restyled
underneath it (until the `pumpApp()` migration, A3b).

- **The token catalogue** (`tokens_*`, `components_*`) — every colour with its
  measured ratio, the whole type scale, the buttons, the text field in all five
  states, status/chips/cards/rating, `AdminDataTable`'s four states, and the
  **themed Material components** (`components_material` / `components_dialog` — the
  proof A3 de-purpled the chips/switch/checkbox/slider/tabs/icons and the dialog).
  A token or theme change lights these up immediately.
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

**Two things a golden cannot pin** — **one and a half, since A8**:
- **The brand loader, animating.** With motion on, `BrandLoader` is an
  infinitely-repeating Lottie and any golden of it is a picture of an arbitrary
  frame. **Its reduced-motion state is now pinned** (`components_loader_reduced_motion`)
  because it is a still brand mark by design — and taking that picture is what
  found the bug: the first version froze the Lottie with `animate: false`, which
  stops the ticker and renders **frame 0**, an empty canvas. The property
  assertion passed; the pixels were blank. The other static loading state we pin
  is `AdminDataTable`'s skeleton.
- **Anything that reads the wall clock** — see register row 23.

**A golden photographs the end state, not the tween.** A8 changed six animation
durations and expected `consumer_booking_hub` and `consumer_provider_detail` to
move; **not one byte changed**. Worth knowing before a future slice budgets time
for a golden review it does not need — and worth knowing as a limit: no golden
can catch a duration regression.

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
| 3b | Gold carries state at ≥3:1 (§3.5) | ~~3~~ → **0** | the unseen-story ring was a **1.62:1** stroke — a state indicator you could not see. Gold-as-state → `gold`; the 12 real star glyphs keep `starRating`. **A1 measured only 3 surfaces** (its contrast test wrongly called `background` the worst case) and gold slipped through at **2.98:1 on `surfaceVariant`** — the darker 4th surface; caught web-side (WEB-SYSTEM §15 row 23), fixed here: `#B8860B`→**`#B5830A`** clears 3:1 on all four (worst is surfaceVariant, 3.10), and the test now measures surfaceVariant too. The register got more honest, not just shorter | ✅ **A1** (+ surfaceVariant follow-through) |
| 4 | Spacing on-grid (§5) | ~~128~~ → **0** | the register **under-counted**: it missed the pixel-identical on-grid literals, so the true in-scope set was **~488** raw spacing literals. `12`×76 → the new `spacingSM`; ~90 off-grid (`2/6/10/14/20/28/…`) resolved to the nearest token (tie → up); the rest are exact-value swaps. One fixed clearance keeps its literal under `// ds-ignore`. Pinned by `design_system_pin_test.dart` | ✅ **A2** |
| 5 | Radius tokens (§6) | ~~23~~ → **0** | `999`×21 → `radiusPill`; `16`/`24` → `radiusXL`/`radiusXXL`; `7`/`2` → nearest. Pinned | ✅ **A2** |
| 6 | Type scale ≥ 11px (§4) | ~~9~~ → **0** | the six `fontSize: 10` labels → `labelSmall` (11, the floor); the photo counter → `bodyMedium`; the two OTP boxes drop the magic `26` → `headlineMedium`. Pinned | ✅ **A2b** |
| 7 | Icon-size tokens (§7) | ~~19 distinct values~~ → **0** | 146 `size:` sites snapped to the 5 `AppTheme.icon*` (nearest; ties → up — `18`→20, `48`→64 = the empty-state glyph, §7). Pinned | ✅ **A2b** |
| 8 | Motion tokens (§9) | ~~12 distinct durations, 0 constants~~ → **0** | **both figures were wrong, and in opposite directions.** The 12 counted `Duration(milliseconds:)` literals **app-wide, blind to category** — mock latency, OTP cooldowns and a search debounce among them — while missing motion written any other way. "0 constants" was simply false: nine named `Duration` constants existed. Measured in scope (`screens/` + `widgets/`): **7 motion sites, 6 distinct values** — 350 · 240 · 220 · 200 ×2 · 180 · **1500**. All → `AppMotion` (§9's five), nearest token, ties faster. The 1500 was a pro-splash logo fade sitting 3.75× over §9's own ceiling; it also faded a logo **in** on `Curves.easeIn`, an inversion of the rule §9 states in prose — which is why the curve pairing is now pinned in the mirror test, not just written down. Three literals stay with a `// ds-ignore` and a reason: two content timers and a debounce, none of which §9's 50–400ms ladder could name. **The pin design the plan called for had to be thrown away**: argument-position (`duration:` + `Duration(` on one line) measured 8/8 before A8's reduced-motion sweep and 5/8 after it, because the sweep turned three of them into ternaries — it would have gated the code A8 did not touch. The shipped pin matches the literal and pays for it with a directory scope. The mapping rule needed narrowing too: "nearest token, ties faster" sent the splash to `motionSlow`, whose `easeInOutCubic` still eases **in** on a fade-in — one §9 violation swapped for a quieter one. §9's **Use column decides**; proximity only breaks ties within a use. Gated by 5 pins (red at **11 · 7** at the slice's base `31ce0e8`, quoted as 10 · 7 in ③ because ② had already merged two of them; the other three are guard rails at zero, proven by throwaway mutation and labelled as such) + the three-legged mirror (doc ↔ Dart ↔ web) — whose **Curve column was read by nothing** until the review, so `dartMotionCurves` was compared to a hardcoded literal in the test that asserted it | ✅ **A8** |
| 9 | Full `ColorScheme` + component themes (§3) | ~~23 missing~~ → **0** | the scheme set 8 of ~30 slots, so unthemed M3 widgets (pickers, snackbars, chips, tabs, icons, sheets) fell back to **Material purple**. Now the full scheme + a component theme for every component the app renders — verified by the `components_material` golden | ✅ **A3** |
| 10 | Button min-height 48 (§13.2) | ~~all~~ → **0** | `textButtonTheme.minimumSize` `Size(0, 40)` → `Size(0, 48)` — raw TextButtons and `AppButton.text` alike | ✅ **A3** |
| 11 | Buttons sized by container (§10) | ~~all~~ → **0** | `elevated`/`outlinedButtonTheme` `Size(double.infinity, 48)` → `Size(0, 48)` — width comes from the container, not a forced full-width bar | ✅ **A3** |
| 12 | Tap targets ≥ 48 (§13.2) | ~~67~~ → **0** | **26** of the 67 rendered <48 (favourite hearts, photo arrows, close/remove ×, contact + text-link rows, pills, segments) + 3 adjacency (<8px) + `review_tile`'s `shrinkWrap` 32px button. Icon-glyphs → 48 transparent hit area (glyph unmoved, anchor compensated); rows/pills → `ConstrainedBox(minHeight: 48)` (grows with text scale). New **`test/a11y/`** gate — `meetsGuideline(androidTapTargetGuideline)` on 5 components — went **red** before the fixes | ✅ **A4a** |
| 13 | Icon-only controls labelled (§13.4) | ~~26 of 40~~ → **0** | `tooltip:` (= the SR label on IconButton) on the 21 unlabelled buttons + the 3 FABs, state-dependent for toggles ("Ajouter/Retirer des favoris", "Noter N étoiles"); `Semantics(label:)` on the gesture-icons (hearts, remove-×). Pinned by `labeledTapTargetGuideline` | ✅ **A4b** |
| 14 | `Semantics` on custom controls (§13.4) | ~~0~~ → **0** | **A4b** — roles + states: `Semantics(button/checked/selected/expanded/slider+value)` on the hand-rolled controls (services checkbox / artist radio rows, accordion, date row, before/after slider + thumbnails, segments, pill, hearts). **A4c** — the reading experience: `TimedCachedImage` gains a `semanticLabel` (decorative by default, so images stop being announced as noise); `MergeSemantics` done right (whole-tile on the sub-button-less tappable tiles, content-only on `InvitationCard`; tappable cards with sub-buttons keep tap-aggregation); `SemanticsService.announce` at the snackbar helper + the off-focus events (favourite, review published, pull-to-refresh). | ✅ **A4b + A4c** **A6 correction**: the announcement half of this row was WRONG. Flutter wraps every `SnackBar` in `Semantics(liveRegion: true)` (snack_bar.dart:831) — the mechanism both platforms support, and the ONLY one on Android, where `supportsAnnounce` is false and a direct announcement clears TalkBack's queue. So the 6 sites that ALSO called `SemanticsService` were the anomaly (double-speaking on iOS), not the 111 that didn't. A6 deleted them and gates the live region instead; `Helpers.announce` stays for genuinely off-focus non-snackbar events. |
| 15 | 200% text scale (§13.3) | ~~3~~ → **0** | the count under-read it (as row 4 did): **9** boxes bounded *text* with a constant and clipped it — `category_chips` (the named worst, 50), the home's two card carousels (280) + its tile strip (92), provider-detail's tile strip (100), the journal's artist chips (48) + day pill (32), the client tag strip (44), admin's search field (38). **Two of them clipped at 1×** — the tile strips were shipping a bug at the *default* font size (the strip gives 92/100; the tile measures 96/120), so this row was never only an a11y row. Three fixes, chosen by what the box actually is: short scroller → `SingleChildScrollView` + `Row`, **intrinsic**, no bound at all (the default — no arithmetic can rot); long/lazy scroller, which *must* have a bound → the widget exposes it (`ProviderCard.carouselHeight`) via `AppTheme.textScaledBound`; plain box → delete the constant. Boxes bounding an image/logo/divider are correctly fixed and were left alone — see the "wrong target" note below | ✅ **A5** |
| 16 | Overflow discipline (§13.3) | ~~46 of 963~~ → **0** | the "4.8% have `maxLines`" figure was a **proxy** — most `Text` sits in a `Flexible`/`Wrap` and never overflows, so the count measured the wrong thing. The real check is executable: pumped at **2×**, a `Text` that can't fit throws. That found **one** genuine break the proxy never would have ranked: `compact_appointment_tile`'s hint `Row` overflowed by **217px** at 200% — a `Row` hands its children infinite width, so an unflexed `Text` never wraps, it just runs off the tile. `Flexible` fixes it. The rest of the audited `Text` already ellipsises correctly | ✅ **A5** |
| 17 | One snackbar entry point (§15) | ~~118 calls; 73 raw; 1 with an action~~ → **0** | the counts were RIGHT — the first rows a census hasn't disproven — but they hid the defects. `.showSnackBar(` 116 → **1** and `SnackBar(` 111 → **2**, both inside `AppSnackBar`, whose kind IS the API. Fixed with them: the tone (only 7 of 31 successes were green, 30 of 61 errors weren't red), the durations (2s ×15 · 1s ×4 · Material's 4s ×99 — §15's 3/6/10 appeared NOWHERE, including on the one action-bearing bar), the two local re-inventions (`_toast`, `_showError`) and `Helpers.showSnackBar` itself. **Six sites were feeding a modal-blocked bar** — pruned by `BlockSemantics`, painted under the scrim — and now raise `InlineFeedback` inside the sheet that owns the failure. **The worst-instance note here was stale** (A3 had already removed `Colors.black87`) and the a11y claim inverted: see row 14. Gated by 2 pin rules + `test/a11y/feedback_test.dart` | ✅ **A6** |
| 18 | One `ConfirmDialog` (§15) | ~~11 copy-pasted~~ → **0** | 11 was right for `showDialog<bool>`, but `AlertDialog(` counted **13** — the admin's `showReasonDialog` (9 call sites) and the caption prompt were never counted. All 13 → one component; `showReasonDialog` survives as a 6-line delegation so the admin didn't change a line. The ladder is now real: the 2 title-only deletes state their consequence, « Oui, annuler » became « Annuler le rendez-vous », the **pro** salon delete gained the type-to-confirm its consumer twin always had, and destructive is a stated classification (red where something is destroyed; explicitly NOT for logout / report-a-review / no-show, so the red keeps its meaning). **Cancel-takes-focus was 0/11** (§15 AND §13.5) — the component does it for all. Its 4 missing `mounted` guards and 3 leaked controllers died with the copies. Gated by 2 pin rules + `test/widget/confirm_dialog_test.dart` | ✅ **A6** |
| 19 | Field-anchored errors (§14) | ~~**1** caller passes `errorText`~~ → **0** | **both halves of this row were wrong, and the correction is the slice.** The one `errorText` caller was **dead code** — `invite_member_sheet:191` could only be reached through a button gated on the value already being valid, so the product had **zero** working field-anchored errors, not one. And validation was **not** "a red toast": only **4** validation snackbars fired on a live screen (4 more were dead code shadowed by their own disabled button), while the real pattern was the **silent disabled button ×22** and **10 hand-rolled red `Text` blocks**. A slice built on this row's framing would have hunted toasts that mostly weren't there. It was also not greenfield: **5 live screens already ran Flutter's `Form`/`validator`** with 13 validators, so two mechanisms shipped — and they collide, because a `validator` result silently overwrites `decoration.errorText`. Now **one**: `FieldErrors` (validate on submit · re-validate once errored · **merge**, never replace · `set()` for server faults) feeding `errorText`, with `GlobalKey<FormState>` and `Form(` both at **0** and the `validator` param deleted. Fixed with it, because "where the error renders" was hiding "whether the rule is right": **5 e-mail regexes → 1** (two definitions of valid e-mail shipped in one app) · the **OTP gate accepted 4 digits** on a « Code à 6 chiffres » field, on 3 live screens · the **Mobile Money number had no validation at all** — `"abc"` saved, rendered to the client, and went into the Wave deep link · 2 `PhoneNumberField`s with no rule of their own — **and A7's stated reason for that was false**: it claimed the package's validator "could never run" without a `Form` ancestor. Measured afterwards, `IntlPhoneField` defaults to `onUserInteraction`, needs no `Form`, and was judging from the first keystroke while *overwriting* the app's message. Silenced with `autovalidateMode: disabled` · a tag sheet whose 3 rules were **silent no-ops** with the button enabled · « Ce numéro existe déjà. » raised on the **list screen after the sheet had popped**, one frame before navigating away. Gated by 2 pins (red measured at 13 · 5) + `field_errors_test` + `validators_test` + `a11y/field_error_test` | ✅ **A7** |
| 20 | Reduced motion (§9) | ~~0~~ → **0 honoured** | the count was right and the framing was not: rows 8 and 20 are **nearly disjoint**, so closing row 8 would have moved none of this. The register points at expand/collapse tweens; the harm was two `repeat: true` Lotties, an indeterminate spinner, a 6-call-site involuntary scroll and an auto-advancing story reel — **not one of them a counted number**. Two more things the row could not have known. §9 named `MediaQuery.disableAnimations`, which is **Android-only**: iOS reports `reduceMotion` and the framework reads it nowhere, so the rule as written was an iOS no-op (§9.1 now names both flags; `ReduceMotionObserver` makes the iOS half reactive, because `MediaQueryData` has no field for it and nothing rebuilds when it changes). And the framework already does the *other* half for free — plain controllers scale to 5 %, so route transitions and every implicit `AnimatedX` were never the work; `repeat()` bypasses that scale entirely and was 100 % of it. Found on the way past: **`BrandLoader` had no `Semantics` at all**, at 68 call sites — the app's most common transient state was silent to a screen reader in *both* modes. **And the first pass shipped three defects of its own, all found by the adversarial review, all in reduced-motion paths the gates never pumped** — ①–①c wrote four gate commits and every one of them pumped `BrandLoader`: six `reduceMotionOf` call sites shipped and five were asserted by nothing. The story reel **threw** on its first advance (`Duration.zero` is a jump for `ensureVisible` and `assert(duration > Duration.zero)` for `PageController`); the splash rendered a **blank screen for 3800ms** (`animate: false` parks at frame 0, which in that composition is an empty canvas — the exact bug the slice had just documented fixing in `BrandLoader`); and the caption **overflowed a 60px avatar by 44px**, because `LoadingIndicator` never passes `fast` and ~50 sites took the caption branch. Writing gates before sweeps is necessary and not sufficient — gates that all point at one widget are one widget's coverage. Gated by `test/a11y/motion_test.dart` (17 assertions, 20 mutations each watched fail) | ✅ **A8** |
| 21 | Tests wrap the real theme | ~~0 of 34~~ → **34 of 34** | all 34 widget tests migrated to `wrapApp`/`pumpApp` (`test/support/pump_app.dart`) — they render `AppTheme.lightTheme`, so a restyle that breaks a screen's layout now fails a test. `pump_app_test.dart` asserts the harness injects the real theme. | ✅ **A3b** |
| 22 | Deferred V2/V3 `Colors.*` | ~52 | flag-hidden `ComingSoon` screens | *allowlisted — fix if un-shelved* |
| 23 | **No clock seam** (§20.1) | pro dashboard + journal | `ProJournalProvider._selectedDate = salonToday()`; `MockProService.getDashboard()` buckets by `DateTime.now().weekday` — so those screens **cannot be golden-tested**: the image would change value with the day of the week, failing CI every morning. `package:clock` is unused. | *new — needs its own slice* |
| 24 | Disabled labels legible | ~~all~~ → **0** | was `#5C5C5C` on `#949495` (2.21:1). Now a legible-inert pair (`surfaceVariant` / `textDisabled`) in the button themes + `AppButton`. WCAG exempts disabled, but it now reads as *disabled*, not blank. | ✅ **A3** |
| 25 | No meaning by colour alone (§13.6) | ~~1~~ → **0** | the story ring now carries **two greyscale-surviving cues**: unseen = a thick (3px) gold ring + a bold title; seen = a thin (1px) neutral ring + regular title — width and weight, not just hue. Folded into the ring's `Semantics` label ("nouvelle"/"déjà vue"). | ✅ **A4b** |
| 26 | Unselected segments have no boundary | 2 | both **hand-rolled** segmented controls (not Material `SegmentedButton`) draw a border on the active segment only — so `segmentedButtonTheme` can't fix them; it's a widget change, not a ThemeData one. | *a widget cleanup, not A3* |
| 27 | Reading paragraphs read one step small (§4) | ~~2 paragraph roles~~ → **0** | §4 declares `bodyLarge` "Default reading text", yet the salon description (`provider_detail_screen.dart`) and the empty-state body (`empty_state.dart`) rendered **`bodyMedium` (14)** — one step below the app's own doctrine. Raised from the OUTSIDE by web B8's census (which disproved "the app reads at 16px"). Both → `bodyLarge`; no density mode to split across (unlike web's HYBRID). Spec: [mobile-gold-reading.md](mobile-gold-reading.md) | ✅ **mobile A-series** |
| 28 | `gold` used as TEXT below the 4.5:1 floor | **1** | found darkening gold for row 23: `TeamRoleChip`'s « Propriétaire » renders `gold` as *text* (labelSmall, 11px) on a 12%-gold tint — **~3:1**, below the 4.5:1 text floor even at `#B5830A`. Row 3b closed gold as *state* (3:1, "not text") and the a11y contrast guideline covers 6 widgets but not this chip, so it slipped both. Fix: a darker gold-text token, or ink on the tint | *needs its own slice* |
| 29 | Every Material default string is ENGLISH (§17) | ~~the whole app~~ → **0** | **the row called this a screen-reader footnote — *"the barrier a screen reader announces is not ours to word"* — and that was the smallest part of it.** Measured: a French user typing `07/01/2026` in the booking date picker **booked 1 July**. `DefaultMaterialLocalizations.parseCompactDate` carries the comment *"Assumes US mm/dd/yyyy format"*, reads `inputParts[0]` as the month, is **not overridable by any parameter**, and is reachable from `booking_hub_screen.dart:743` — the consumer funnel. Silent, no error, hint reading `mm/dd/yyyy`. Also visible and unrecorded: **51 reachable `AppBar`s** saying "Back" (the highest-frequency English string in the product), the picker headline « Wed, Sep 27 », the month toggle « January 2026 », a weekday row reading **S M T W T F S starting Sunday** (structural, not a string), and the selection toolbar on **50** fields. **Two mechanisms the delegates do not reach.** iOS takes the toolbar from `CupertinoLocalizations` (`adaptive_text_selection_toolbar.dart:211`), so the Material delegate alone leaves Cut/Copy/Paste English on every iPhone — in an app importing zero Cupertino widgets; and `table_calendar` reads **`Intl.defaultLocale`**, never set anywhere, so the consumer booking calendar rendered « July 2026 » / « Mon Tue Wed » one widget below a French screen. Fixed by a seam (`core/utils/app_locale.dart`) the three roots **and `wrapApp`** call, because a line in `main()` is invisible to every test — which is how `goldenApp` passed `locale: fr_FR` for the entire life of the golden baseline while resolving to **`en_US`**. Two things measured rather than assumed: the plural `GlobalMaterialLocalizations.delegates` is mandatory (the singular pairing turns **8 of 11** assertions red, because `MaterialApp` always appends an English-only Cupertino delegate), and 24h time needed **no code** — French locale data forces it regardless of the device. Gated by `french_test.dart` (11 assertions, 6 mutations) | ✅ **A9** |
| 30 | Undo stops at the client boundary (§15) | **the server-backed destructions** | A6 shipped the product's first undo where the client owns the whole list (photos, before/afters, favourites — restoring the snapshot IS the same call that removed it). Cancelling a booking, revoking access and deleting an account cannot be undone without new service methods, so they keep the confirm-only rung. §15's reversible row is satisfied where it can be and honestly unmet where it can't | *needs backend work* |
| 31 | An error's association is weaker than the web's (§14) | **the platform** | measured in A7: Flutter does **not** fold `errorText` into the field's semantics label — it is a **child node**, so a screen reader reaches it *after* the input, not *with* it. `MergeSemantics` cannot merge it (a `TextField`'s node is a semantics boundary — the tree comes back byte-identical). There is no `aria-describedby` equivalent, and `SemanticsService` is the wrong tool (A6: `supportsAnnounce` is false on Android). §14 now states the limit rather than implying parity with the web | *platform limit — recorded, not fixable here* |
| 32 | Per-funnel §14 coverage is 6 of 17 (§20) | **11 screens** | A7 claimed §20's behavioural row when exactly ONE such test existed, and the class of defect it was supposed to catch shipped four times in the same slice. Six of the 17 are genuinely covered and mutation-proven — the ones where a miss was dangerous. The other **11 rely on the unit + pin layer only**, and one of them is a trap worth naming: `client_detail_screen` is in the 17 because of `_NotesSection`'s rule, which has **no test** — the branch's two tag-sheet tests cover a different widget in the same file, so counting that screen as covered would have been arithmetic rather than coverage. (An earlier draft of this row did exactly that, and its totals came out right only because a second error cancelled the first.) **Also structurally uncoverable by any `FieldErrors`-based mechanism: the hand-rolled `errorText`** (`_TagSheet` holds a bare `String? _tagError` with no validator map), which is the exact shape that shipped dead in `invite_member_sheet` for months and again in A7 | *the honest remainder — extend per funnel as they are next touched* |
| 33 | The framework ignores iOS Reduce Motion (§9.1) | **every framework-driven animation, on iOS only** | A8 made **our** code honour both flags, and it cannot make the framework do the same. `_animateToInternal`'s 5 % scale reads `SemanticsBinding.instance.disableAnimations`, which is fed by `kDisableAnimations` — a flag **no Darwin embedder sets**. `grep -rn "reduceMotion" packages/flutter/lib/` returns **0**. So on iOS, route transitions, `Hero` and every implicit `AnimatedX` still run at full speed for a user who asked their OS to stop movement, while the `repeat()`-driven and involuntary motion A8 owns correctly stops. There is no supported override: `disableAnimations` has no setter and `debugSemanticsDisableAnimations` is debug-only. The honest scope of §9.1 today is *"everything we animate ourselves, on both platforms; everything the framework animates, on Android"* | *platform limit — upstream, recorded not fixable here* |
| 34 | Eight status vocabularies, one of them English (§17, §18) | ~~8 maps · 3 spellings~~ → **0** | found while fixing row 29 and **recorded by neither register**. `admin/widgets/status_chip.dart` routed `confirmed`/`cancelled`/`noshow` through its *kind* switch — so the pill was the right colour — and fell through its label switch to `raw ?? '—'`, printing the **English enum** beside it; `pending` also rendered lowercase there against « En attente » everywhere else. Across the app `noShow` read three ways: « Absent » ×6, « Non présenté » ×2, the raw enum ×1. `web/components/StatusChip.tsx:55` documents the normalisation fix as one it mirrored **from** mobile — mobile never received it, a parity regression only web's own code recorded. Now one `core/utils/status_labels.dart` (§18: a domain fact lives in `core/`), with web's vocabulary since web had already settled it across all three surfaces. A mutation proved the gate incomplete on the way: restoring the `?? raw` fallback kept every assertion green, because they all test statuses the map knows — an unknown status now asserts « — » | ✅ **A9** |
| 35 | §17 had no typography rules, and no gate (§17.1, §20) | ~~no rule to break~~ → **0** | §17 was the only substantive section with **neither a typography rule nor a §20 row**, and the copy drifted exactly as that predicts: `Chargement...` in `availability_screen` beside `Chargement…` in `BrandLoader` — the same word, two spellings, one app. §17.1 now states two rules (`…`, `’`) and §20 gates them. Swept: **3** ellipsis sites, **89** escaped apostrophes across 37 files, **32** double-quoted strings that `dart analyze` then revealed had been double-quoted *only* to dodge the escape, and 33 test assertions in lockstep. **Guillemets « » and the narrow no-break space are deliberately NOT rules** — 0 NBSP across 85 eligible sites and guillemets in ~5 strings against 138 in doc comments, so both are *absent* rather than inconsistent. A9 fixed what the app contradicted itself about; inventing a convention across 85 invisible characters is a separate decision | ✅ **A9** |
| 36 | Strings are not externalized (PRD NFR-I18N-001) | **2540 literals, 0 externalized** | the PRD requires *"all user-facing strings externalized (even though V1 is French-only) to enable English/Nouchi later"*. Nothing in `docs/` has ever described how, and there is no `l10n.yaml`, no `.arb`, no `AppLocalizations`. **A9 deliberately did not close it**: FR-L10N-002 (English + Nouchi) is **V3**, externalising 2540 literals buys nothing until a second language is committed, and V1-scope discipline says do not build V3 speculatively. Recorded so the NFR is visibly unmet rather than quietly assumed | *deferred to the V3 language work — scope decision, not an oversight* |
| 37 | APK size was never measured, and no job checked it (ROADMAP Part 6, NFR-PERF-002) | ~~no number, no gate~~ → **22.68 MB / 30 MB** | NFR-PERF-002 sets **<30 MB** and PR-0 shipped it with **no measured number anywhere and no CI job checking it** — unfalsifiable since the day it was written. **⚠️ And this row was wrong twice before it was right.** A9 first recorded it as *"the Android release build produces no APK"*, on the evidence that `flutter build apk --release` ran Gradle to completion and then failed with *"failed to produce an .apk file"* — reproduced twice in CI, with and without `--analyze-size`. The release build was never broken: **this project has product flavors** (`consumer`, `pro` — `android/app/build.gradle.kts:49-61`), so Gradle correctly emits `app-consumer-release.apk` and `app-pro-release.apk`, while a flavourless `flutter build apk` looks for `app-release.apk`, which will never exist here. The command was wrong, not the build. Found by installing the Android SDK and reproducing locally — CI had shown the same message twice and I read it as a broken build rather than a wrong invocation. Now measured: **22.68 MB** (arm64, consumer, release), **7.3 MB under budget**, and gated in CI at 30 MB. Before/after, built from the same machine: **22.31 MB at `d8b5230`** → **22.68 MB at A9's head — the whole slice cost 0.37 MB**, which corrects one more A9 claim: the spec warned that `supportedLocales` does not tree-shake `flutter_localizations` and to expect "roughly the compiled equivalent of 2.3 MB of Dart". True of the source; the AOT compiler drops most of it, and dropping the dead `flutter_datetime_picker_plus` paid for part of the rest | ✅ **A9-fix** |

**Bold** slices are committed (the a11y tranche). *Italic* ones are specified and
scheduled for re-evaluation after it.

Rows **23–31** were not in the original audit. Each was found by *doing the work*:
23 and 24 by taking the pictures (PR-0.5), 25 and 26 by walking every bordered
control in A1, **27 from the outside** (web B8's reading-text census disproved
"the app reads at 16px"), **28 while fixing 3b's surfaceVariant gap** (the darkened gold exposed that the
owner chip uses it as *text*, not state), **29–30 while building A6's two
components** (the dialog's barrier speaks English; undo runs out of road where
the server owns the state), and **31 by writing A7's a11y gate against an
assumption instead of a measurement** — the error was supposed to be in the
field's semantics label, and it is a child node. Row **19's was wrong twice over** — its "1 caller" was dead code (the real number
of *working* field-anchored errors was **0**) and its "validation = a red toast"
described 4 live sites while missing the 22 silent disabled buttons that were the
actual pattern. Row **4's count was wrong** — the audit said ~128, but migrating it
found **~488** (it had never counted the pixel-identical on-grid literals). Row **15's
was wrong too** (3 → **9**), and row **16's counted the wrong thing entirely** — "4.8%
of `Text` have `maxLines`" measures a *proxy*; the executable check (pump at 2×) found
the real set. That is the register behaving as intended — it gets **more honest** as it
shrinks, not just shorter. A count is a hypothesis; the burn-down is the measurement,
and a rule you can run beats a number you counted once.

### The wrong fix for a fixed bound (A5)

Worth writing down, because it was wrong at **five of five** sites and every one of
them looked right — and because the failure mode is the burn-down's own: a *plausible*
fix that no gate contradicts.

The tempting one-liner for a bound that must track the font is
`height: MediaQuery.textScalerOf(context).scale(N)`. It is almost always wrong:

- **Only the text's share scales.** A 280px provider card is 180 image + 32 padding +
  68 text. `scale(280)` gives **560** at 200% for 332 of content — 41% dead space, and
  it drags the *image's* share up too. Scale the text share, add the constant back:
  `AppTheme.textScaledBound(constant:, text:)`.
- **It must not shrink.** Rows are `max(icon, line)` and **icons do not scale**, so the
  card's text block needs 60.4 at 0.85× — not `68 × 0.85 = 57.8`. A proportional bound
  under-provisions at *small* scales. Worse, `scale(280)` = 238 at Android "Small",
  under `provider_card`'s own `maxH < 260` compact threshold — so **reducing** your font
  size silently changed the card design. A fix that reaches across a file boundary into
  another widget's magic number is a fix you cannot see. Hence the `max`: 1× is a floor.
- **Growth can be super-linear.** `CompactAppointmentTile` goes 96 → **176** (2.25×) at
  200%, because the title wraps. *No* linear formula is safe there — which is why an
  intrinsic strip is the default and a computed bound is the exception, taken only when
  the list is long enough to need laziness, and always pinned by a test.
- **Check the box actually bounds text.** Three sites were *wrong targets*: a story tile
  (an image — scaling its height collapsed the artwork from 92:126 to 92:252), a
  highlight strip (an `Expanded` gradient already absorbed the growth; the label was
  never clipped), and a skeleton row (no text at all — the "fix" measured 52 at both 1×
  and 2×, i.e. a no-op). Row 15's tell — *same height at 1× and 2×* — has a
  false-positive mode: it also means "bounds no text."

The rule: **prefer intrinsic; compute a bound only under laziness; pin every computed
bound with a test that measures the real widget at 0.82× → 2×.** A measured constant
with a gate is fine. A measured constant without one rots the day someone adds a row.

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
