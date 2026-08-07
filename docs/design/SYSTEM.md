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
| `compact` | **360–599** | Phone. Single column. The consumer & pro apps' primary target. |
| `medium` | 600–839 | Large phone / small tablet. Wider gutters, capped content width. |
| `expanded` | ≥ 840 | Tablet / desktop (admin). Multi-pane; persistent nav instead of a bottom bar. |

There are **zero breakpoints in the apps today** — every screen is a phone
column. That is fine for the consumer app (its users hold phones) and wrong for
admin. Until real tablet layouts land (§22), the rule is defensive:

- **`compact` has a FLOOR: 360dp** (A11). It used to read `< 600`, unbounded
  below, and that was not a range anyone had rendered — every rendering test in
  the repo measured **one** point in it, `kGoldenPhone`'s 390. 360 is the modal
  device in Côte d'Ivoire (PRD.md: Tecno/Infinix/itel at 720×1600) and 375 is
  every small iPhone; both were broken, in eight places, and nothing could see
  it. **320dp is explicitly out of contract** — six 48dp OTP boxes cannot fit it
  under any padding. Gated by `test/a11y/layout_test.dart` across the whole
  range, not at a point.
- **`contentMaxWidth = 720`** — text and forms never stretch past it. A 1000px-wide
  line of French body copy is unreadable, and an `ElevatedButton` whose theme says
  `minimumSize: Size(double.infinity, 48)` becomes a 1000px-wide button on a tablet.
  **Implemented in A11 C6** as `AppTheme.contentMaxWidth`, applied by
  `ContentWidthCap` at each phone root's `MaterialApp.router(builder:)`, and
  mirrored to web through the `layout` token family. Until then it lived here as
  prose and in no code on either surface. Two consequences, both deliberate:
  **dialogs are capped** (a dialog is a route under the Navigator), and so are
  **SnackBars** — `ScaffoldMessenger` is only the controller; `ScaffoldState`
  renders the bar against the Scaffold's own width, and the Scaffold is under the
  builder. A bar that tracks the column is the intent, not an accident.
- **The admin console is excluded**, and the exclusion is held by a test rather
  than by this sentence. §10 gives the reason two paragraphs up — *"wrong for
  admin"* — and the arithmetic gives the rest: `AdminScaffold` is a top-level
  `Row` with a 240dp sidebar, and seven `AdminDataTable` call sites divide their
  width with `Expanded` columns and no horizontal scroll, so 720 would leave
  ~431dp for a five-column table and truncate it.
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
| **`LabelValueRow`** | `LabelValueRow({required label, required value, labelStyle, valueStyle})` | a label and its value — « Total » · « 25 000 FCFA ». **A `Wrap`, not a `Row(spaceBetween)`**: eleven call sites across six files, nine of which shipped with neither child flexed, so each took its full intrinsic width and the row overflowed by up to ~150dp at 360×2× — on the deposit screens and the bar that is always visible while a booking is built. While both fit they sit at opposite ends exactly as the Row put them; when they stop fitting the VALUE drops to its own line. The `SizedBox(width: double.infinity)` is load-bearing, as in `SectionHeading` (A12) |
| **`SectionHeading`** | `SectionHeading({required title, style, action, onTap})` | a section title with an optional action beside it. **A `Wrap`, not a `Row`** — at 200% « Derniers rendez-vous » + « Voir tout » wants 564dp and a 360dp phone gives 328, so the action drops to its own line and the title takes the full width. Carries §13.2's `minHeight: 48` when the header is tappable. A11 C5 found the pattern three times, already drifted (`spaceBetween` vs `Spacer`, `titleLarge` vs `titleMedium`, and only one of the three with the touch-target guard) |

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
| **Error** | A human French message + **a way out**. An error state without one is a crash with better manners. Never show a raw exception, HTTP code or stack trace. **The way out is a retry only when retrying can succeed.** This was written as « a retry control » flatly, and A14 found the flat version wrong twice: a booking past the salon's horizon is not full and not broken, so « Réessayer » invites the user to retry a date that can never be accepted (`mobile-a14-pickers.md` §24, register rows 48 and 76); and a salon that is not published or was suspended will refuse identically for as long as it stays that way (row 82). Both offer a way out that *leads somewhere* instead — the salon's own next bookable day, or another salon — and both are gated on it: `bookingErrorCta` returns `null` for every code whose answer really is « try again here », in `mobile/lib/core/utils/booking_error_cta.dart` and `web/lib/booking/window.ts`, with the two halves pinned against each other. A retry control that cannot succeed is not a way out; it is the dead end with a button on it. |
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
- **`leadingWidth: 48` on the app bar is legal, and free** (A15) precisely
    because of the first bullet: a `BackButton` lays out at exactly 48 under
    `MaterialTapTargetSize.padded`, so the theme is asking for the floor rather
    than shaving it, and nothing was ever painted in the other 8. **`titleSpacing:
    0` is a different question and the answer is no** — that gap applies whether
    or not a leading exists, so zeroing it puts a *root* bar's title at x = 0
    against a body that keeps its 16dp gutter. One screen, two gutters.

### 13.3 Text scaling — up to 200%

The OS font-size setting is a **first-class input**, not an edge case. A user who
sets 200% has told the system they cannot read the default; a layout that clips at
150% is unusable for them.

- **Never** `MediaQuery.withNoTextScaling` or a hardcoded `textScaleFactor: 1.0`.
  Disabling scaling to "protect the layout" protects the layout by breaking the
  user.
- **A box that contains text may not have a fixed height.** `SizedBox(height: 50)`
  around a `Text` is a clip waiting to happen — use `minHeight` or let it grow.
- **…and it may not have a fixed width either. Divide the row; don't dimension
  the boxes.** (A11 C3 — this bullet's absence is why `Container(width: 50)`
  around a `TextField` survived every gate this document has. Every rule in
  §13.3 was vertical, so the horizontal twin was true, unwritten and unenforced.)
  `N` items across a row are `N` `Expanded`s under a `Row(spacing: …)` — the gaps
  belong to the parent, **not** as a `margin` on the child, which is spent
  *inside* its own flex slot and silently shrinks the middle items while leaving
  the ends alone. The width then falls out as `(W − 2×padding − (N−1)×gap)/N`,
  which is a property of the layout rather than a coincidence, and cannot
  overflow at any width. Precedents: `otp_code_row.dart`,
  `pro_journal_screen.dart`'s 7 day pills.
- **A `TabBar` whose labels do not fit must not divide the width** — the same
  rule seen from the other side, and the app's worst case of it (A11 C4). A
  non-scrollable bar wraps every tab in `Expanded` (`tabs.dart:1977`) so each
  gets `W/n`, and a `Tab`'s label is `softWrap: false, overflow: fade`
  (`tabs.dart:183`) — hard-coded, no override. **A label too long for its share
  is faded away without throwing**: no overflow, no exception, French copy cut
  off in the product. A10 photographed « Aujourd'hui » truncated on the pro
  earnings screen and 777 tests were silent about it.
  - The fix is **`isScrollable: true` + `tabAlignment: TabAlignment.center`**.
    `center` is the only alignment legal in **both** modes
    (`tabs.dart:1809-1821`), and it degrades correctly — genuinely centred while
    the labels fit, start-anchored and scrolling once they do not.
  - **Never take the M3 default.** For a scrollable bar it is
    `TabAlignment.startOffset` (`tabs.dart:2727`), which spends 52dp on an empty
    leading gutter — 14% of a 360dp screen — and is not accounted for in the
    scroll-centring math (`tabs.dart:1669-1683`), so the selected tab lands 52dp
    off-centre.
  - **`tabAlignment` never goes in `tabBarTheme`.** The assert is evaluated
    per-bar against that bar's own `isScrollable`, so a theme value throws on
    every non-scrollable bar in the app.
  - A bar whose labels **do** fit may keep `fill` — `« Calendrier »/« Liste »`
    does — but that is a measurement, not a default. The width gate is what
    keeps it true.
- **A value the user reads as one token, and a control's label, may not break
  INSIDE a word** (A11 C8). Flutter breaks mid-word whenever the box is narrower
  than the word, and **nothing else in this document or in the gates forbids it**:
  the truncation walk permits wrapping *deliberately* — a heading that wraps to
  two lines is the correct fix — and no overflow ever fires, because wrapping is
  how the layout succeeds. So a date rendered « 13/03/20 » / « 26 » and a call
  button reading « Appel » / « er » both passed 846 tests, and were found by
  looking at the first 200% pictures (§20.1, §21 row 62).
  - **May not break**: a date, a time, a price, a phone number, a reference — and
    **any control's label**, because a button is read as one thing.
  - **May**: a heading, a sentence. **A salon's NAME may not** (A13) — this
    line used to permit it, on the grounds that « Salon Ex/cellence » is "ugly,
    not a defect". A13 decides otherwise and the reason is that a salon's name
    is not decoration: it is what identifies the business a user is about to
    book, and « Salon Ex / cellence » does not identify anything. The same
    reasoning promotes any proper noun that names a thing the user is choosing
    between.
  - And note what the story cards taught (§21 row 62): a title that *looks* like
    a heading may be a **control's label**. `announcement_stories.dart` wraps
    each card in `Semantics(button: true)` + `InkWell`, so the title IS the
    control's accessible name and the first clause above already covered it.
    Ask what the string DOES, not what it looks like.
  - The fix is always **more width**, never a smaller font: a one-word label
    cannot wrap its way out, so the row wraps (`Wrap`) or the bar stacks. A
    text-scale branch is legitimate here and is not a §10 breakpoint — what
    changed is how much room a word needs, not how much room the screen has.
  - Gate: `expectNoMidWordBreak` (`test/a11y/_a11y.dart`) — a paragraph breaks
    inside a word **iff** its box is narrower than its widest word. Applied **by
    name**, because a sweep would red on the headings this rule allows.
- **A flexed label may not be squeezed below a readable prefix** (A12). The
  truncating twin of the mid-word rule: a `Text` inside `Expanded`/`Flexible`
  beside an unflexed sibling spends its **declared** ellipsis on a squeeze it did
  not choose, and a declared ellipsis is exactly what `expectNoUndeclaredTruncation`
  skips. `CompactAppointmentTile` rendered a salon's name as **nothing but an
  ellipsis** — 0 characters in 26.8dp — on two screens that had been width-gate
  subjects since C5, with every assertion green.
  - The floor is **8 characters**, and it is measured rather than chosen: see
    §21 row 69 for the table and the one-character margin it sits in.
  - The fix is more width — flex the sibling, or `Wrap` the row — never a
    smaller font.
  - Gate: `expectNoLegibilityCrush`, applied as a **sweep**, unlike
    `expectNoMidWordBreak`. §13.3 gives that one a role exception (a date may
    not break, a heading may); legibility has none — three characters is
    illegible in a heading too.
- **The fixed-height rule above is now enforced** (A12), and it had been prose
  since A5. `expectNoVerticalClip` asks the framework's own arithmetic —
  `getMaxIntrinsicHeight(size.width) > size.height` — in one pump. **Vertical
  only**: the horizontal twin is true of almost every sentence on a 360dp phone,
  because wrapping is how the layout succeeds. `childAspectRatio` is separately
  **prohibited** by a source pin, because it freezes tile HEIGHT as a multiple of
  tile WIDTH and width does not move with the font.
- **A constant that gates a text-dependent branch has to move with the text**
  (A12, found on a device *after* the fix it undermined had shipped). It is the
  fixed-box rule one level up: not a fixed size around text, but a fixed
  **threshold** deciding which layout the text gets. `ProviderCard` chose its
  compact design with `maxH < 260` while A12's own `gridHeight` was
  `142 + 68 × scale` — the two cross at **≈1.74×**, above which the card drew
  the full-size image inside a box measured for the compact one and overflowed
  by 55dp on a real phone at ≈1.95×.
  - The fix is to test against **the other layout's own height** rather than a
    number that approximates it, so the two cannot disagree by construction.
  - **A threshold that is a proxy for the rule cannot gate the rule.** The
    repo already had a test for this exact class, and it asserted
    `carouselHeight >= 260` — it guarded the bound dipping *below* the number
    and said nothing about a smaller bound crossing it going *up*. Assert the
    thing itself: which branch the widget actually took.
  - Where the threshold is about **width** (can this cell still name a salon?),
    do not express it as a text scale: the crossing moves with the screen, so a
    scale constant is wrong at some of §10's widths and right at others.
    `ProviderCard.minGridCellWidth` is the shape.
- Text that *can* overflow gets `maxLines` + `TextOverflow.ellipsis`. Today only
  4.8% of `Text` widgets do.
- **An `AppBar` title is the one place in the product that cannot reflow, so it
  is the one place with a length rule** (A15, §21 row 79). Material gives the
  title one line, a fixed height and an ellipsis it never announces — every
  other rule above says "the fix is more width", and a bar has none to give. The
  A14 device run photographed « Dat… », « Tableau de b… » and « Nouveau
  rendez… » on a phone while the whole suite was green.
  - **Budget: 280dp**, which is 360 minus a 48dp leading and 16dp of
    `titleSpacing` on each side (`app_theme.dart` — see §13.2). Material clamps the
    title's own scaling to **1.34×** (`app_bar.dart:44`, applied at `:1092`), so
    the title is measured at 1.34 and not at 2.0.
  - **An action is NOT clamped**, and that is the half the rule almost missed: a
    `TextButton` action label scales by the full system scaler, so « Réinitialiser »
    costs ~182dp at 2× and leaves a four-letter title unable to fit. **On a bar
    with a text action the title is never the defect** — convert the action to
    `IconButton` + `tooltip:` (§13.4 already blesses this, and a tooltip has the
    whole screen, so it can be *clearer* than the label was).
  - **A title may not interpolate data.** « {Salon} — votre planning » has no
    width it can promise: « Salon Excellence » fits and « Institut de Beauté
    Cocody Riviera » does not. Move the datum one line down into the body, where
    it can wrap.
  - The way out, when a title genuinely cannot shorten, is a **declaration**:
    `// clip-ok: <why>` in the ten lines above the bar. Same word, same window
    and same "a reason, always" rule as the web (below) — a marker that governs
    no title is itself an offence.
- Gate: the key screens are pumped at `TextScaler.linear(2.0)` and asserted not to
  overflow — **and across §10's whole compact range**, not at one width
  (`test/a11y/layout_test.dart`). Those subjects are **route-pushed**, because a
  screen pumped as `home:` draws no back button and is measured on a bar 72dp
  wider than the one the product renders. Titles additionally get a corpus run
  over every literal in `lib/` (`test/a11y/a15_titles_test.dart`).

**On the web, the same rule has a different unit and a different number**
([WEB-SYSTEM §9 — Text scale & reflow](WEB-SYSTEM.md#text-scale--reflow-wcag-1410)).
A browser has two independent inputs where the OS has one: a **font-size
preference**, which moves text only, and **page zoom**, which scales the CSS
pixel and therefore the viewport too. So the web standard is **WCAG 1.4.10
Reflow** and it is stated as a width — **320 CSS px** — rather than as a
multiplier, because a multiplier cannot describe zoom. Three differences worth
knowing before porting a rule across:

- **`overflow: visible` does not clip.** A web box paints its excess *outside*
  itself, so the vertical-clip predicate is `overflow-y: hidden|clip`, not
  "content taller than box". Porting this section's twin literally would fire on
  every long page.
- **Declared truncation is still a loss.** Flutter's ellipsis and CSS's are the
  same decision, and 1.4.10 does not care that it was intentional — so the web
  requires a written reason per site (`// clip-ok:`) rather than treating an
  ellipsis as an opt-out. **A15 makes this a convergence rather than a
  divergence**: mobile app-bar titles now use the same marker, the same
  ten-line window and the same orphan rule, because they are the one mobile
  surface where an ellipsis is also unavoidable-by-construction. The rest of
  mobile still treats a declared ellipsis as an opt-out, which is the remaining
  half of the difference.
- **There is no golden harness on the web.** §20.1's "look at the 2× pictures" —
  which is how rows 62 and 69 were found — has no web equivalent; every web
  finding comes from computed geometry.

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
| Plural (A13) | « 1 prestation » · « 2 prestations » — `Formatters.count` | « 1 prestation(s) » |

**The plural rule passes this section's own test**, which is why it is here and
not in a style guide: A9 added the two rules above because *the app contradicted
itself*, and explicitly declined to invent conventions that were merely absent.
`(s)` is the first kind — the app rendered it in **7** places against **17**
correct plurals. And it is not a preference: the parenthetical is an English
habit that French does not use.

`Formatters.count(n, one, other)` asks CLDR through `Intl.plural`, which matters
for one value: **French puts 0 in the SINGULAR.** That is the only place the four
idioms the app had grown — `== 1`, `<= 1`, `> 1`, and a hard-coded plural —
disagree, which is exactly why they coexisted unnoticed. The helper passes
`locale: kAppLocale` explicitly, because `Intl.getCurrentLocale()` falls back to
`en_US` and English differs from French **only at n = 0**.

**`invité(e)` is deliberately not covered.** It is gender, not count; a French
administrative habit rather than an English one; and a live test asserts it. It
is the guillemets case — absent-not-contradictory — and is left as its own
decision.

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

**The seam list above is closed and enumerated: an unlisted seam is itself a §18
violation.** A10 added the eighth, and the gap it filled is worth naming, because
the rule read for two years as though it were already covered. §18 governs which
**zone** a time renders in. It never owned which **instant** "now" is — and an
unfreezable "now" on a render path is a screen that cannot be photographed
(§20.1). So:

- **`core/utils/app_clock.dart` is the only legal source of the current
  instant.** `AppClock.now()`; for anything a user sees, prefer the
  `salon_time.dart` helper that wraps it. A direct `DateTime.now()` in `lib/`
  fails `salon_time_pin_test.dart` unless it is on the declared exemption list,
  and each exemption is a claim — *this read never reaches a pixel* — that has to
  survive review.
- **Day, week and month boundaries come from `salonDayBoundsUtc()` /
  `salonWallClockToUtc()`, never from `DateTime(y, m, d)`.** Local midnight is
  the device's, and it is invisible in Abidjan — UTC+0 makes the two agree — and
  wrong in every other wave. A10 found five of these in one function.
- **A test that freezes the clock builds its fixtures from the frozen instant.**
  Mixing a freeze with a wall-clock fixture decouples two clocks that used to
  agree, and the symptom is a wrong *number* — « 12 jours » where the trial says
  14 — not a crash. Pinned; `test/support/frozen_clock.dart` is the entry point,
  and it re-seeds `MockData` so a freeze cannot be half-applied.

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
| No literals (§4, §5, §6, §7) | **`test/unit/design_system_pin_test.dart`** — sweep-as-test: no raw spacing (§5), radius (§6), type (§4), or icon-size (§7) literal survives. Excludes `core/theme/` (token defs) + the flag-hidden `features/` (§22); a `// ds-ignore` line is a declared fixed-dimension exception. **A11 C3 added the sixth rule and withdrew the word "complete"**: the sweep scanned `SizedBox(…)` and `EdgeInsets.*` and had never looked at **`spacing:`/`runSpacing:`** — which `Wrap` has always had and `Flex` gained in 3.27 — so a gap written that way was invisible. It went red at **21** across 11 files; nineteen were already the token's value, and two were `spacing: 10` (booking hub) and `spacing: 6` (appointment card), both off the 8pt grid §5 declares mandatory. Two known limits, recorded rather than papered over: ~~the sweep reads comments as code~~ — **fixed in C5** after it happened twice in three commits (a docstring quoting §13.3's example, then one naming the literal it had just deleted): a line that is *entirely* a comment is now skipped. An end-of-line `// …` is deliberately not, because truncating at the first `//` would also cut a line containing a URL, and a *sized container* is deliberately out of scope, which is exactly how `Container(width: 50, height: 64)` survived — that one is now §13.3's job, not the pin's |
| Tap targets + labels (§13.2, §13.4) | **`test/a11y/`** — **complete**: `meetsGuideline(androidTapTargetGuideline)` (A4a) + `labeledTapTargetGuideline` (A4b) + `textContrastGuideline` (A4c), all live over the key components |
| Text scale (§13.3) | **`test/a11y/text_scale_test.dart`** — the key components pumped at `TextScaler.linear(2.0)`. **Three** assertions, because each of the first two passed against a real bug: `takeException()` is null (nothing *overflows*); **and** `expectGrowsWithTextScale` (the height actually grew — a fixed bound doesn't overflow, it **clips silently**); **and**, for any *computed* bound, that it still covers the widget's real content at **0.82× → 2×** and doesn't over-provision. Pump the widget **as it ships** — bounded, and in the variant that breaks: unbounded, nothing can overflow and the gate is vacuous |
| **Forms & validation (§14)** | **`test/unit/field_errors_test.dart`** (rule 2's state machine, incl. the merge case web's review had to fix) + **`test/unit/validators_test.dart`** (one rule per concept) + **`test/a11y/field_error_test.dart`** (unclipped at 200 %, grows its field, reachable in the field's semantics) + two pins in `design_system_pin_test.dart` — no `validator:`, one e-mail definition. **The rule a regex cannot express — "a field fault is never a bar" — is held behaviourally on SIX named funnels**, each asserting: submit invalid → the message renders *under the field* · **no `SnackBar` in the tree** · the flow does not advance · fixing it clears the message without a second submit. Those funnels are `login_screen` · `pro_register_screen` · `pro_salon_profile_screen` · `deposit_settings_screen` · `client_list_screen`'s add-client sheet · `invite_member_sheet` (gated since A6-era A7④a) — chosen because each is a defect A7 actually shipped. **A seventh, `client_detail_screen`'s tag sheet, is held to the same shape but sits OUTSIDE this arithmetic**: it has no validator map at all (a bare `String? _tagError`), so it is not one of the 17 — see row 32. Two of them are **lockout regressions**: load the stored value and save without editing, which is the assertion that catches "the app cannot save data it just loaded". Every one was mutation-proven red before it was trusted. **Coverage is 6 of the 17 screens on `FieldErrors` — see §21 row 32 for the remainder.** A7 first claimed this row when one such test existed; the count is now named rather than implied. |
| **Motion (§9, §9.1)** | **5 pins** in `design_system_pin_test.dart` — no `Duration(milliseconds:` and no `Curves.` under `screens/`+`widgets/` (red at **10 · 7**), plus a guard that the scan sees >100 files so an empty sweep can't read as a clean one — **and** `test/a11y/motion_test.dart`: the loader animates with motion on (the control), stops under the flag, stops on the **iOS flag alone**, stops when the flag is raised **mid-session**, stops with **no scope above it**, carries a `Semantics` label in both modes with exactly ONE node saying it, shows the **static mark** rather than a blank frozen Lottie, and unregisters its binding observer on dispose. Every app root is source-pinned to install `ReduceMotionObserver` (globbed, not listed). Three more pins close holes the review found rather than defects it saw, and are at **zero** with no measured red: no hand-rolled easing shape (`Cubic`, `SawTooth`, `Threshold`, `FlippedCurve`, `CatmullRom`, `Elastic*Curve` — `Curves.` is the idiom, not the language), no `duration:` in **seconds**, and `core/router/` in scope because that is where a full-screen transition belongs even though none lives there today. Values are pinned three ways — §9's table ↔ `AppMotion` ↔ `tokens.ts` — by `web/tests/tokens.mirror.test.ts`, **including the Curve column**, which the first version compared against a literal in the test file and therefore pinned against itself. **17 assertions, 20 mutations each watched fail.** The gates that matter most are the ones added *after* the review: the story reel's page position (two-legged — "jumps for nobody" and "jumps for everybody" both go red), the splash's pinned frame **and its 3800ms hold**, and the caption's bound in both directions at 2× text. **What is NOT gated: the story reel's 6 s dwell** — two attempts to reproduce it both came back green, so it is an open question, not a fix (see `mobile-a8-motion.md`). |
| **Language & typography (§17, §17.1)** | **§17's first gate**, and the reason it drifted: it was the only substantive section with none. `test/unit/french_test.dart` — the app resolves French localizations on **three independent mechanisms** (`GlobalMaterialLocalizations`, `GlobalCupertinoLocalizations`, `Intl.defaultLocale`), each asserted separately because any one can be right while the others are broken; a typed date reads as `dd/MM/yyyy`; the calendar starts Monday; the time picker gives a 24h dial with the device toggle off; every `MaterialApp` in `lib/` **and `test/support/`** declares the delegates (globbed, not listed). `test/unit/status_labels_test.dart` — no status renders English on any surface, `NO_SHOW`/`noShow`/`no-show` normalise to one label, an unknown status renders « — » and never the wire value, and no screen keeps its own vocabulary. Plus **3** pins in `design_system_pin_test.dart` for §17.1 (`…`, `’`, and A13's `(s)` — the parenthetical plural) — the escaped apostrophe scanned at **line** level because a literal parser cannot see inside an interpolation, which is a hole a failing test found while the pin was green. |
| **Width (§10) — the compact RANGE** | **`test/a11y/layout_test.dart`** (A11 C2) — §10 *used to* define `compact` as everything **under 600dp with no floor** — C6 gave it the 360 floor it now carries — and every rendering test in the repo measured one point in it: `kGoldenPhone`, 390. The gate pumps **9 subjects × {360, 375, 390} × {1×, 2×}** — 360 being the modal Android device in CI, 375 every small iPhone — and asserts three things, because the first two each pass against a real defect: `takeException()` is null (nothing **overflows**); **and** `expectNoUndeclaredTruncation` (no text is **clipped** — a `Tab` is `softWrap: false, overflow: fade`, so it truncates French copy without throwing, which is why A10's earnings photograph showed a cut-off « Aujourd'hui » that 777 tests were silent about); **and** that the screen rendered its **content** — two subjects reach an empty state by default and would measure the padding around « Aucun rendez-vous ». **Two harness rules are load-bearing and were each verified rather than reasoned.** ① The width loop must sit **outside** `testWidgets`: `_overflowReportNeeded` latches once per render object, and the collapsed shape reports the OTP overflow at 360 and **nothing at 375 while it is still broken**. ② The suite must `loadRealFonts()` — with none loaded, `flutter_test` draws every glyph as a square of the font size, and the gate's first run condemned « Semaine », « À venir » and « Annulés » as clipped, all three measuring **98.7dp to a tenth of a pixel** against Roboto's 55.3 / 44.1 / 51.4. `pumpAtWidth` now pins the font and refuses to run without it. Plus **`test/a11y/content_width_test.dart`** (C6) for §10's other half — the 720 cap measured at 1024, 720 and 390, its gutters, its effect on a SnackBar, and **two source pins**: every phone root installs `ContentWidthCap`, and `main_admin.dart` does not. Those pins exist because **no test in this repo renders an app root**, so the cap is invisible to every other assertion. **GREEN at 55 of 55** as of C5 — 27 red after C2, then C3 closed the OTP row (8), C4 the tab bars (15), and C5 the headings. C5 also added a ninth subject (`ProviderDetailScreen`) and three assertions the walk could not make, which took the count 4 → 7 before it went to 0; see `mobile-a11-width.md` §3.1 for the measurement table |
| Visual regression | **Goldens** — `test/golden/`, see below |
| Market data (§18) | `salon_time_pin_test.dart` |
| **The clock (§18, §20.1)** | **`test/unit/salon_time_pin_test.dart`**, three pins in the same file as §18's firewall because they are the same rule — the zone half and the instant half. No `DateTime.now()` in `lib/` outside `core/utils/app_clock.dart`, with **seven** declared exemptions each carrying its argument for why that read never reaches a pixel; none under `test/golden/`, because a golden built from the wall clock is a picture of the day it was taken; and **no file that both freezes the clock and reads the wall clock** — the one that matters, because a blanket ban across `test/` would have hit 38 legitimate relative fixtures while the actual hazard is the *mix*: 12 subscription fixtures compared against a `SalonSubscription` that now reads the seam, decoupling silently the day one of them gains a freeze, and reporting « 12 jours » where the trial says 14. A fourth assertion guards against a **vacuous sweep** — `listSync` throws on a missing root but not on one that yields nothing, and the first draft of that guard was itself red, having asserted 300 files where there are 292. Plus **`test/unit/clock_test.dart`**: the seam defaults to the wall clock (the control, without which every other assertion would pass on a seam returning a constant), it freezes and restores, the journal strip renders the frozen week and a *different* frozen week gives a different one, and `getDashboardStats` buckets by the frozen month. **4 mutations, each watched fail.** |
| Everything | `flutter analyze --fatal-infos` = 0 |

The manual sweep (must not grow; ideally → 0), from `mobile/`:

```bash
grep -rn  --include='*.dart' "Color(0x" lib | grep -v lib/core/theme/
grep -rEn --include='*.dart' "Colors\.(red|green|blue|orange|grey|gray|amber|purple|teal|pink|yellow|indigo|cyan|brown)" lib | grep -v lib/core/theme/
grep -rn  --include='*.dart' "fontSize:" lib | grep -v lib/core/theme/
```

### 20.1 Goldens — the eye

`mobile/test/golden/` holds **34** goldens, and they are the **only** thing in the
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
- **A rendering CONDITION** (`*_w360`, `*_w360_x2`) — seven baselines: five
  added by A11 C7, a sixth (`pro_login_w360_x2`) by C8, and a seventh
  (`pro_dashboard_w360_x2`) by A12 — added precisely because regenerating every
  baseline after the dashboard fixes moved **nothing**. The first whose reason for
  existing is not their subject but the
  **surface they are rendered on**. Everything else here is 390 × 1×, which is
  one point in §10's `compact` range and the OS default. The floor is 360, and
  200% text is a first-class input (§13.3) — so a picture at 390 × 1× is blind
  to an entire class of defect **by construction**. Concretely: four of A11's
  fixes are the identity at 1×, and `tabAlignment` reddens *nothing* in
  `flutter test`. Not a survey of widths; the floor, once. Suffix them `_w360`
  and `_w360_x2` — the first *condition* suffixes in a set of content ones
  (`_all`, `_day`, `_success`), which is an honest signal that they differ in
  kind.

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

**One thing a golden cannot pin** — **half a thing, since A8 and A10 closed the
rest**:
- **The brand loader, animating.** With motion on, `BrandLoader` is an
  infinitely-repeating Lottie and any golden of it is a picture of an arbitrary
  frame. **Its reduced-motion state is now pinned** (`components_loader_reduced_motion`)
  because it is a still brand mark by design — and taking that picture is what
  found the bug: the first version froze the Lottie with `animate: false`, which
  stops the ticker and renders **frame 0**, an empty canvas. The property
  assertion passed; the pixels were blank. The other static loading state we pin
  is `AdminDataTable`'s skeleton.
~~**Anything that reads the wall clock.**~~ **Closed by A10.**
`core/utils/app_clock.dart` is a function pointer every render-path clock read
goes through, so a test can freeze it and the picture stops being "a photograph
of the day it was taken". **Four** baselines that could not exist now do —
`pro_dashboard`, `pro_journal`, `pro_journal_day`, `pro_earnings` — and the two
consumer screens that were stable **by luck** are now frozen too.

*(The first version of this passage said "six baselines that could not exist",
counting two that have existed since PR-0.5, and called the consumer pair
"stable by construction" when `consumer_screens_golden_test.dart` did not call
`freezeClock` at all. That made the two-instant proof **vacuous** for them — a
file that never reads `kFixedNow` cannot change when `kFixedNow` moves, so their
byte-identity proved nothing, which is the exact failure this section warns about
one paragraph later. Both golden files now freeze **before** their services are
constructed: several mocks seed clock-relative data in instance-field
initialisers, and the locator's fields are `late final`, assignable once, so a
later `setUp` cannot replace them.)*

**The proof is a re-run, not an argument.** Every baseline was generated twice,
under two frozen instants eighteen months apart (11 Mar 2026 and 22 Sep 2027).
**23 of 26 are byte-identical**, and C7's five were put through the same two instants: `pro_reviews_w360` identical (its `Review` fixtures carry absolute dates), the other four **differ**, in the appointment dates they print from `AppClock.now()` seeds — where identity would have been the bug, which is what proves no hidden wall-clock read
leaks in. The three that differ — `pro_journal`, `pro_journal_day`, `pro_team` —
differ *only* in rendered dates and in a roster ordered by `invitedAt`, and an
identical result there would have been the bug: it would mean the screen ignored
the freeze. Regenerate a clock-bearing golden and you must be able to name which
of the two it is.

**And identity is only half a proof.** `pro_dashboard` was byte-identical across
both of those instants because both sit mid-month — an *unfrozen* dashboard shot
twice the same afternoon would have matched too. A third run frozen on a month
edge (30 Sep 2027) moves it: « Ce mois » goes 5 000 FCFA → 0, which is exactly
the flake row 23 named. So: identity proves absence of leakage only for a screen
that renders nothing clock-derived; for one that does, **sensitivity must be
shown by a freeze that changes the value.**

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
| 15 | 200% text scale (§13.3) | ~~3~~ → ~~0 (A5, wrongly)~~ → **0** | the count under-read it (as row 4 did): **9** boxes bounded *text* with a constant and clipped it — `category_chips` (the named worst, 50), the home's two card carousels (280) + its tile strip (92), provider-detail's tile strip (100), the journal's artist chips (48) + day pill (32), the client tag strip (44), admin's search field (38). **Two of them clipped at 1×** — the tile strips were shipping a bug at the *default* font size (the strip gives 92/100; the tile measures 96/120), so this row was never only an a11y row. Three fixes, chosen by what the box actually is: short scroller → `SingleChildScrollView` + `Row`, **intrinsic**, no bound at all (the default — no arithmetic can rot); long/lazy scroller, which *must* have a bound → the widget exposes it (`ProviderCard.carouselHeight`) via `AppTheme.textScaledBound`; plain box → delete the constant. Boxes bounding an image/logo/divider are correctly fixed and were left alone — see the "wrong target" note below **⚠️ Corrected by A11 C5 — this row claimed 0 and was wrong.** Every one of its nine boxes was a *height*, and A5's gate rendered a single width (390) with the home screen **signed out**, where both of the headings below are hidden behind `isAuthenticated`. So the class was never closed: C5 found `home_screen`'s two heading rows (236/221/206dp and 89/74/59dp), `search_bar`'s unflexed placeholder (75/60/45dp) **and** its own `height: 48` around text, `provider_detail`'s `expandedHeight: 160` clipping the salon header by 92dp, three of its contact rows, `review_tile`'s verified badge, and `reviews_screen`'s fixed-width bar. Nine more boxes, all at 200%, all invisible to a one-width gate. The lesson is the row's own: **a count is only as closed as the gate that measured it** | ✅ **A5**, reopened and re-closed by **A11 C5** |
| 16 | Overflow discipline (§13.3) | ~~46 of 963~~ → ~~0 (A5, wrongly)~~ → **0** | the "4.8% have `maxLines`" figure was a **proxy** — most `Text` sits in a `Flexible`/`Wrap` and never overflows, so the count measured the wrong thing. The real check is executable: pumped at **2×**, a `Text` that can't fit throws. That found **one** genuine break the proxy never would have ranked: `compact_appointment_tile`'s hint `Row` overflowed by **217px** at 200% — a `Row` hands its children infinite width, so an unflexed `Text` never wraps, it just runs off the tile. `Flexible` fixes it. The rest of the audited `Text` already ellipsises correctly **⚠️ Corrected by A11 C5 — same reason as row 15.** "The rest of the audited `Text` already ellipsises correctly" generalised from **one** measured break at **one** width. Eight more width breaks were waiting at 360–390 × 2×, and the audit could not have seen them: it rendered 390 only, and the two worst were behind `isAuthenticated` | ✅ **A5**, reopened and re-closed by **A11 C5** |
| 17 | One snackbar entry point (§15) | ~~118 calls; 73 raw; 1 with an action~~ → **0** | the counts were RIGHT — the first rows a census hasn't disproven — but they hid the defects. `.showSnackBar(` 116 → **1** and `SnackBar(` 111 → **2**, both inside `AppSnackBar`, whose kind IS the API. Fixed with them: the tone (only 7 of 31 successes were green, 30 of 61 errors weren't red), the durations (2s ×15 · 1s ×4 · Material's 4s ×99 — §15's 3/6/10 appeared NOWHERE, including on the one action-bearing bar), the two local re-inventions (`_toast`, `_showError`) and `Helpers.showSnackBar` itself. **Six sites were feeding a modal-blocked bar** — pruned by `BlockSemantics`, painted under the scrim — and now raise `InlineFeedback` inside the sheet that owns the failure. **The worst-instance note here was stale** (A3 had already removed `Colors.black87`) and the a11y claim inverted: see row 14. Gated by 2 pin rules + `test/a11y/feedback_test.dart` | ✅ **A6** |
| 18 | One `ConfirmDialog` (§15) | ~~11 copy-pasted~~ → **0** | 11 was right for `showDialog<bool>`, but `AlertDialog(` counted **13** — the admin's `showReasonDialog` (9 call sites) and the caption prompt were never counted. All 13 → one component; `showReasonDialog` survives as a 6-line delegation so the admin didn't change a line. The ladder is now real: the 2 title-only deletes state their consequence, « Oui, annuler » became « Annuler le rendez-vous », the **pro** salon delete gained the type-to-confirm its consumer twin always had, and destructive is a stated classification (red where something is destroyed; explicitly NOT for logout / report-a-review / no-show, so the red keeps its meaning). **Cancel-takes-focus was 0/11** (§15 AND §13.5) — the component does it for all. Its 4 missing `mounted` guards and 3 leaked controllers died with the copies. Gated by 2 pin rules + `test/widget/confirm_dialog_test.dart` | ✅ **A6** |
| 19 | Field-anchored errors (§14) | ~~**1** caller passes `errorText`~~ → **0** | **both halves of this row were wrong, and the correction is the slice.** The one `errorText` caller was **dead code** — `invite_member_sheet:191` could only be reached through a button gated on the value already being valid, so the product had **zero** working field-anchored errors, not one. And validation was **not** "a red toast": only **4** validation snackbars fired on a live screen (4 more were dead code shadowed by their own disabled button), while the real pattern was the **silent disabled button ×22** and **10 hand-rolled red `Text` blocks**. A slice built on this row's framing would have hunted toasts that mostly weren't there. It was also not greenfield: **5 live screens already ran Flutter's `Form`/`validator`** with 13 validators, so two mechanisms shipped — and they collide, because a `validator` result silently overwrites `decoration.errorText`. Now **one**: `FieldErrors` (validate on submit · re-validate once errored · **merge**, never replace · `set()` for server faults) feeding `errorText`, with `GlobalKey<FormState>` and `Form(` both at **0** and the `validator` param deleted. Fixed with it, because "where the error renders" was hiding "whether the rule is right": **5 e-mail regexes → 1** (two definitions of valid e-mail shipped in one app) · the **OTP gate accepted 4 digits** on a « Code à 6 chiffres » field, on 3 live screens · the **Mobile Money number had no validation at all** — `"abc"` saved, rendered to the client, and went into the Wave deep link · 2 `PhoneNumberField`s with no rule of their own — **and A7's stated reason for that was false**: it claimed the package's validator "could never run" without a `Form` ancestor. Measured afterwards, `IntlPhoneField` defaults to `onUserInteraction`, needs no `Form`, and was judging from the first keystroke while *overwriting* the app's message. Silenced with `autovalidateMode: disabled` · a tag sheet whose 3 rules were **silent no-ops** with the button enabled · « Ce numéro existe déjà. » raised on the **list screen after the sheet had popped**, one frame before navigating away. Gated by 2 pins (red measured at 13 · 5) + `field_errors_test` + `validators_test` + `a11y/field_error_test` | ✅ **A7** |
| 20 | Reduced motion (§9) | ~~0~~ → **0 honoured** | the count was right and the framing was not: rows 8 and 20 are **nearly disjoint**, so closing row 8 would have moved none of this. The register points at expand/collapse tweens; the harm was two `repeat: true` Lotties, an indeterminate spinner, a 6-call-site involuntary scroll and an auto-advancing story reel — **not one of them a counted number**. Two more things the row could not have known. §9 named `MediaQuery.disableAnimations`, which is **Android-only**: iOS reports `reduceMotion` and the framework reads it nowhere, so the rule as written was an iOS no-op (§9.1 now names both flags; `ReduceMotionObserver` makes the iOS half reactive, because `MediaQueryData` has no field for it and nothing rebuilds when it changes). And the framework already does the *other* half for free — plain controllers scale to 5 %, so route transitions and every implicit `AnimatedX` were never the work; `repeat()` bypasses that scale entirely and was 100 % of it. Found on the way past: **`BrandLoader` had no `Semantics` at all**, at 68 call sites — the app's most common transient state was silent to a screen reader in *both* modes. **And the first pass shipped three defects of its own, all found by the adversarial review, all in reduced-motion paths the gates never pumped** — ①–①c wrote four gate commits and every one of them pumped `BrandLoader`: six `reduceMotionOf` call sites shipped and five were asserted by nothing. The story reel **threw** on its first advance (`Duration.zero` is a jump for `ensureVisible` and `assert(duration > Duration.zero)` for `PageController`); the splash rendered a **blank screen for 3800ms** (`animate: false` parks at frame 0, which in that composition is an empty canvas — the exact bug the slice had just documented fixing in `BrandLoader`); and the caption **overflowed a 60px avatar by 44px**, because `LoadingIndicator` never passes `fast` and ~50 sites took the caption branch. Writing gates before sweeps is necessary and not sufficient — gates that all point at one widget are one widget's coverage. Gated by `test/a11y/motion_test.dart` (17 assertions, 20 mutations each watched fail) | ✅ **A8** |
| 21 | Tests wrap the real theme | ~~0 of 34~~ → **34 of 34** | all 34 widget tests migrated to `wrapApp`/`pumpApp` (`test/support/pump_app.dart`) — they render `AppTheme.lightTheme`, so a restyle that breaks a screen's layout now fails a test. `pump_app_test.dart` asserts the harness injects the real theme. | ✅ **A3b** |
| 22 | Deferred V2/V3 `Colors.*` | ~52 | flag-hidden `ComingSoon` screens | *allowlisted — fix if un-shelved* |
| 23 | **No clock seam** (§18, §20.1) | ~~2 screens unphotographable~~ → **0** | **⚠️ This row was copied verbatim from a code comment, and two of its three specifics were wrong.** There is no `MockProService.getDashboard()` — it is `getDashboardStats(String providerId)`. `weekday` reaches exactly one value, `weekRevenue`, and **no screen renders it**: the "weekly stat cards" the row blames do not exist. And the journal does **not** print today's date into its header — on the default path `isToday` is always true, so it stably reads « Aujourd'hui »; the flake was the **week strip**, seven pills printing `${d.day}`, all moving daily. The dashboard's real flake was monthly and rare: an appointment seeded at `now + 2d` falls into the next month on the last two days of one, and `monthRevenue` drops to zero. A slice that trusted this row would have gated a card that does not exist. **The row was also a large undercount** — `earnings_screen` is the screen its description actually fits, and `appointment_list`, `appointment_calendar_view`, `pro_manual_booking`, `availability` and `pro_subscription` all read the clock on a render path too. `DateTime.now()` in `lib/` measured **106**, and that grep is the wrong instrument: **19 render-path sites carry no token at all**, calling `salonToday()`/`salonNow()` with `now:` omitted. True total: **38 sites across 16 files**. Closed by `core/utils/app_clock.dart` — a function pointer, **not `package:clock`**, which was the first decision and was measured wrong: `flutter_test` already overrides the ambient clock with FakeAsync seeded off the real wall clock, `fake_async` captures a timer's zone at *creation* so the mocks' 300 ms delay escapes any body-level `withClock`, `MockData.appointments` is `static final` and memoised in whatever zone touched it first, and the import trips `depend_on_referenced_packages` → CI red under `--fatal-infos`. **The leverage was four reads inside `salon_time.dart`**, which made 19 of the 38 deterministic with zero call-site churn | ✅ **A10** |
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
| 38 | Five **device-local** day boundaries in one function (§18) | ~~5~~ → **0** | `MockProService.getDashboardStats` built its today/week/month buckets with `DateTime(today.year, today.month, today.day)` and `today.weekday` — local midnight and the *device's* weekday, which §18 forbids outright. Invisible in Abidjan, where UTC+0 makes device and salon agree, and wrong in every other wave: a salon and its owner on opposite sides of midnight bucketed into different weeks. `salonDayBoundsUtc()` had existed since MP2 with **no caller here**. **The first fix was itself incomplete** — it routed all five through the salon-time helpers and omitted `tz:` on every one, so they fell back to `kSalonTz` and reproduced the exact property the violation had: right in Abidjan, wrong in every other wave. The salon's real timezone now comes from `MockData.providers`, the lookup this same file already used in `getJournalDay`. Neither this nor row 39 was caught by `salon_time_pin_test.dart`, which swept `.toLocal(`, `DateFormat(` and `'Africa/Abidjan'` — never the clock. **And CI could not have caught it either:** `ci.yml` sets `TZ: UTC` at the workflow level, precisely so date-boundary seeds are deterministic — which makes the runner's local midnight identical to Abidjan's, so every one of these five reads was correct on every CI run it ever made. The env var stays as hygiene; it was never the mechanism, and for the life of that workflow it was masking this row | ✅ **A10** |
| 39 | `pro_team.png` was pinned against the wrong half (§20.1) | ~~order on the wall clock~~ → **stable** | `_FixedRoster` has guarded this golden since it was written, overriding `expiresAt` so the printed expiry could not flip daily. It never touched the **row order** — and the roster sorts on `invitedAt` (`pro_team_provider.dart:223`), where **two of six members carry clock-relative values and four are absolute** (`mock_data.dart:695,730` vs `:675,685,708,718`). The picture would have reordered itself on **3, 10, 12, 17, 19 and 24 June 2026** — the dates on which `now − 2d` and `now − 9d` each cross the three June absolutes — **six** silent reorderings nobody would have traced to a clock. *(The first version of this row listed 1, 10 and 15 June: those are the absolutes' own values, not the dates the crossings happen. It also named three line numbers for four absolute seeds — `:675`'s owner was missing. A row whose whole point is "measured, not restated" had the arithmetic backwards.)* **A partial fix that made the golden look pinned**, which is the more dangerous failure: a golden with a guard reads as reviewed. The freeze makes it deterministic; the seed's mixed shape stays, because "invited 2 days ago, still pending" and "invited 9 days ago, now expired" are *inherently* relative and freezing them absolute would freeze the semantics too | ✅ **A10** |
| 40 | `earnings_screen` — a clipped tab label, an untokenised card, a bare empty state, and a first load that lied (§4, §12, §13) | ~~3~~ → **0** | invisible until A10 photographed the screen for the first time, and all four turned out to be one screen's worth of the same neglect. **① The `TabBar` was not `isScrollable`**, so each of four tabs got `W/4` and « Aujourd'hui » — 72.2dp of label in a 58.0dp share at 360, and 65.5 even at the 390 the golden was taken at — was **faded away without throwing** (`Tab` is `softWrap: false, overflow: fade`, `tabs.dart:183`). Now `isScrollable: true` + `TabAlignment.center`; §13.3 carries the rule. **② The total card** was a bare `Container(color: secondary)` — no radius, no elevation, no margin — reading as an unstyled band welded to the tab bar; it is a surface and now has surface tokens. **③ The empty state** was `Center(Text('Aucune transaction'))`: no icon, no title, no explanation, the four-states contract met in name only — now the shared `EmptyState`, and it matters far more than it did, because of ④. **④ The first load passed NO date bounds** while every tab tap passed them, so the screen opened on « Aujourd'hui » listing **every transaction the salon had ever taken** and only told the truth once the user touched a tab. A10's golden photographed precisely that — « dimanche 1 mars 2026 » under a tab labelled today, clock frozen to 11 March — and it read as data, not as a bug. `initState` now delegates to `_loadEarningsForTab(_tabController.index)`, so there is one definition of each bucket and it cannot drift from `onTap` again. Fixing ④ is what made ③ urgent: « Aujourd'hui » is correctly empty for most salons most of the time. **Two goldens now**, `pro_earnings` (what a salon sees on opening) and `pro_earnings_all` (tapped into takings) — the `pro_journal_day` argument, that one picture of an empty state is not a photograph of a screen | ✅ **A11 C4** |
| 41 | « 1 prestation(s) » — the parenthetical plural (§17) | ~~1 confirmed, unswept~~ → **12 defects · 2 goldens** | the journal's timeline row printed `1 prestation(s)`, and the mock's client name rendered as the literal « Client ». The `(s)` form is an English habit French does not use. **A13 swept it and the count was twelve, not one** — 7 literal `(s)`, 4 hard-coded plurals, and an n = 0 bug — plus a latent `== 1` and a gender `(e)`; and **two** committed goldens photographed them, not one. **Everything turns on n = 0**: French puts zero in the SINGULAR, and that is the only value where the four idioms the app had grown (`== 1`, `<= 1`, `> 1`, hard-coded) disagree — which is precisely why they coexisted unnoticed. `provider_list_screen.dart` was the only site in `lib/` that had it right; web has **zero** defects because every web site already uses `> 1` (the same parity asymmetry row 34 records). Now one `Formatters.count`/`Formatters.plural` over `Intl.plural` with an **explicit `locale: kAppLocale`** — load-bearing, because `Intl.getCurrentLocale()` falls back to `en_US` and English differs from French only at n = 0, so an unlocalised call is right at every value a casual test checks and wrong at the one this row is about. Pinned as §17.1's third rule; `invité(e)` named as an exception (gender, not count). **And the « Client » half was a real shipping defect, not a mock gap** — see row 74 | ✅ **A13** |
| 42 | `earnings_screen` queried with the **account** id, not the salon (R6, §18-adjacent) | ~~1~~ → **0** | `loadEarnings(authProvider.provider!.id)` at `:33` and `:79`. `ProAuthProvider.activeSalonId` documents the rule at its own declaration — *"screens use THIS (never `provider.id` — an account id is not a salon id)"* — and every other pro screen follows it (`pro_journal_screen:34`, `client_list_screen:43`, `appointment_list_screen:46,63,90,97,109`). So `getEarnings` filtered on an account id, matched nothing, and the screen showed **« 0 FCFA » and « Aucune transaction » for a salon with takings** — and a multi-salon owner's switch never reached it, because the account id does not change. **Found by the adversarial review of A10, from the golden A10 had just taken**: the picture showed the empty state, and `golden.dart`'s own warning is that *"a golden cannot tell you it photographed the wrong thing — it quietly becomes the new truth instead."* Fixed rather than recorded, because leaving it would have pinned it. The corrected baseline shows 5 000 FCFA and a real transaction row | ✅ **A10** |
| 43 | Frozen ids collide — six generators keyed on the clock (§18) | **6, latent** | the sweep routed six id generators through the seam: `'manual_${AppClock.now().millisecondsSinceEpoch}'` and five siblings in `mock_pro_service.dart:232,553,605`, `mock_pro_team_service.dart:112`, `mock_auth_service.dart` ×6, `mock_messaging_service.dart:55`. Under the live clock they advance between calls; **under a freeze they are constant**, so a frozen test that creates two manual bookings gets two appointments with the same id and `indexWhere((a) => a.id == …)` always resolves the first — accept/decline/arrive then act on the **wrong row**, silently. No test does this today, which is exactly why it is recorded: §18's new clause actively pushes future tests toward `freezeClock`. A counter or a seeded generator would close it; that is a mock-realism slice, not a clock one | *new — needs its own slice* |
| 44 | The app told users they accepted documents that did not exist (§17) | ~~3 dead sentences · 0 on pro~~ → **0** | `login_screen.dart:188-198`, `phone_login_screen.dart:109-121` and `booking_confirmation_screen.dart:418-434` rendered « En continuant, vous acceptez nos conditions d'utilisation » as a plain `Text` — **no link, no route** — pointing at documents that existed in **no surface of the product**, and never naming privacy at all. **Pro registration had no consent copy whatsoever**, which is the sharper half: that funnel precedes a KYC identity upload and a public business listing. Three design specs (`app-auth-social.md:46`, `auth-social-email.md:313`, `web-auth-social.md:52`) describe a "CGU line" on these screens as though it were built; it was built as static text. Closed by `legal_consent_text.dart` — a `Wrap` of real buttons, **not** a `TextSpan` + `TapGestureRecognizer`, because a recognizer span has no semantics node and no box and would fail §13.2 and `tap_target_test` correctly | ✅ **L1** |
| 45 | « À propos » rendered a chevron it did not honour (§4, §12) | ~~1 inert row · 3 copies of the version~~ → **0** | `profile_screen.dart:130-134` had **no `onTap` at all** since PR-0 — a row that looks tappable and is not, on the screen where a store reviewer goes looking for a privacy policy — and printed « Version 1.0.0 » as a literal beside `AppConstants.appVersion`, with `pubspec.yaml` holding a third copy. **`ProfileScreen` had never had a widget test or a golden**, which is most of why. Now `/a-propos` in both routers, `SettingsTile` promoted out of the file, the version read once, and the screen's first test — pumped **signed out**, because a reviewer never signs in | ✅ **L1** |
| 46 | The deletion dialog promised an erasure the backend does not perform (§17) | ~~1~~ → **0** | « Vos rendez-vous, favoris et **avis seront supprimés** » was false before L1 and would have stayed false after it: the booking survives stripped of name/phone/notes because the salon needs it to reconcile takings, and the review survives without its author because the rating is an aggregate the salon earned. One transcription now spans three surfaces — the dialog, `openapi.yaml`'s `/me` `delete:`, and `/suppression-compte`. `components_feedback_a6_golden_test` reproduces the copy verbatim and moved in lockstep | ✅ **L1** |
| 47 | Raw `url_launcher` call sites, five behaviours, no seam | **9 across 5 files** | L1 collapsed the two that were genuinely duplicates — the byte-identical `wa.me` blocks in `profile_screen.dart` and `pro_subscription_screen.dart`, down to their duplicated failure copy — into `core/utils/external_link.dart`. **⚠️ The first version of this row said 8, and said `pro_subscription_screen` had been converted when it had not** — the file was not in the diff at all. Found by the adversarial review; the conversion is now real and the count measured (`grep -ro 'launchUrl(' lib/`). The other eight are **five different behaviours**: a navigation-app chooser that probes five map apps with `canLaunchUrl` and shows a picker (`helpers.dart:37-124`), `tel:`↔`wa.me` contact fallbacks (×3), and Mobile Money operator deep links (×2). One wrapper swallowing all five would erase the differences that matter. Three of them also omit `LaunchMode.externalApplication` (`provider_detail_screen.dart:626,667,992`), so they get a Custom Tab on Android while every other site gets the browser | *new — a seam slice, not a store-submission one* |
| 48 | The consumer erasure had no future-bookings gate; the provider one did | ~~1~~ → **0** | `ProviderAccountService` refuses to delete while pending or confirmed future bookings exist (T53) — *« nous ne voulons pas annuler d'office les réservations de vos clients »*. `UserErasureService` applies no such gate and cancels nothing, so a client with a confirmed slot tomorrow can delete: the row survives as `confirmed` with a NULL name and phone, `booking_notifier` resolves no recipient and the reminder silently no-ops, and `appointments_slot_unique` keeps the slot blocked. **Not a privacy leak — a salon-facing one**, and an asymmetry neither side documented. Found by L1's adversarial review. Cancelling on a user's behalf was a product decision, and the owner answered it: **the consumer is blocked too, and must cancel first**. `UserErasureService` now runs the same gate before its first step, so a refusal is never a half-erasure, and the route maps it to **409 `future_bookings`** exactly as `/me/provider` does. Both clients say what to do rather than « la suppression a échoué » — advice that was wrong, because retrying fails identically until the booking is cancelled. The mock refuses the same way, so the app behaves identically off-network. Gated on four cases: a confirmed booking tomorrow blocks, a **pending** one blocks, a **past or cancelled** one does not (a naive `status != cancelled` check would lock every account that ever booked), and a **bystander's** future booking does not | ✅ **L2** |
| 49 | `LegalConsentText` and `AboutScreen` are justified by a11y and asserted by none | **2 widgets** | `legal_consent_text.dart` rejects `TapGestureRecognizer` in its own docstring because a recognizer span has no semantics node and no 48px box — and `grep -rn LegalConsentText mobile/test` returned **nothing** until A11 put it in the width gate. `tap_target_test.dart` and `label_test.dart` are hand-maintained component inventories and neither gained an entry, so the counterfactual is argued against a test that would not have measured the widget either way. Two specific properties go unverified: that a screen reader receives **two separately-activatable link nodes** rather than one merged sentence (`Semantics(container: true)` leaves `explicitChildNodes` at `false`), and that the `Wrap` does not clip at 200% text on 375px — where `pro_register_screen` now adds a third instance inside a dense form. **A11 C2 answered the second of the two**: the widget is in `layout_test.dart`'s inventory and is **green at all six** width×scale configurations, 360 through 390 at 1× and 2× — the `Wrap` does what a `Wrap` is for. Recorded because a measured green is a result; the row stood open on an unmeasured suspicion, and the suspicion was wrong. **The semantics half is still unasserted** — nothing yet checks that a screen reader gets two separately-activatable link nodes rather than one merged sentence | ~~2~~ → **1 widget** — *the clip half is measured; add the semantics half to the a11y inventories* |
| 50 | Phone sign-in created a user it never registered | ~~1~~ → **0** | `MockAuthService.verifyOtp`'s `orElse` built a `User` and returned it **without `MockData.users.add`** — unlike the e-mail and social paths twenty lines below, which both do. So a phone sign-in on an unknown number produced a live session for an account that was not in the mock database: `deleteAccount`'s `removeWhere` was a no-op on it, and anything reading the user list could not see them. **Found by L2's gate asserting that a REFUSED deletion leaves the account intact** — it could not, because the account had never been there. A three-line orElse, wrong since the mock was written | ✅ **L2** |
| 51 | A gap written as `spacing:` was invisible to the literal firewall (§5) | ~~21~~ → **0** | the sweep scanned `SizedBox(…)` and `EdgeInsets.*` and §20 called it *complete*. `Wrap` has always had `spacing`/`runSpacing` and Flutter 3.27 put `spacing` on `Flex`, and neither was ever looked at — **21 raw literals across 11 files**. Nineteen were already the token's value (8, and one 4): invisible rather than wrong, and their conversion moved nothing. Two were not — `spacing: 10` on the booking hub's slot chips and `spacing: 6` on the appointment card's service pills — both off the 8pt grid §5's own header outlaws by name (*"10, 14, 18, 20 are not spacing values"*). Both to `spacingS`, because 8 is what the other nine wraps already used and because widening a chip grid is the wrong direction in a slice about a 360dp screen. Zero goldens moved *at the time*: neither changed site was inside any of the 26 pictures then — C7 has since photographed `appointment_card`'s wrap inside `consumer_my_bookings_w360_x2.png`, so the 6→8 value is **baselined, not verified against the old one**. Pinned by a sixth rule in `design_system_pin_test.dart` | ✅ **A11 C3a** |
| 52 | The OTP box clipped its own digits, on every device, at 1× | ~~2dp~~ → **0** | `Container(width: 50, height: 64)` around a `headlineMedium` `TextField`. §13.3 forbids a fixed height around text in writing — and this was not a clip *waiting* to happen: measured at the moment the height came off, the field wants **66.0dp at 1×** and had 64, and **99.0dp at 2×**. So ~2dp of every digit was cut, always, and 825 tests and 26 goldens were silent, because a fixed bound does not overflow — it clips. The **width** had no written rule to break at all, which is why it survived every gate: every bullet in §13.3 was vertical. §13.3 now carries the horizontal twin, and `OtpCodeRow` is in the `tap_target` and `text_scale` inventories | ✅ **A11 C3c** |
| 53 | `phone_login_screen` pushes a route the router does not declare | **1** | `phone_login_screen.dart:57` does `context.push('/verify-otp?phone=…')`, and neither `app_router.dart` nor `pro_router.dart` declares that path — it resolves to go_router's error page. **Doubly dead today**: `PhoneLoginScreen` is itself referenced nowhere in `lib/`, and both OTP screens are deliberately dormant (`app_router.dart:32-34`, `pro_router.dart:61-63` — kept for the phone-OTP revival, which the SMS decision puts behind WhatsApp + an African aggregator). So it cannot fire, and it is a live 404 the day it can. Found by A11 C3's census and **recorded rather than fixed**: wiring a dormant auth flow is a product decision, not a width fix | *new — decide with the phone-OTP revival* |
| 54 | Web's tab strips have mobile's defect and web's gate was standing on one of them | **5 strips · 1 live** | mobile's three clipping `TabBar`s are mirrored on web as five hand-rolled `<button>` strips, all **byte-identical** `flex gap-s border-b border-divider` with no `flex-wrap` and no `overflow-x`, so a `<button>` flex item's `min-width: auto` pushes the page sideways rather than clipping — the exact inversion of mobile, which clips silently. The census found two by reading; `grep -rn "flex gap-s border-b border-divider" web/components` returns all five in one line (C8d's correction). **This row's stated REASON was also wrong, and B9 measured it:** `type-overflow.spec.ts` did not run `PUBLIC_ROUTES` only — it already logged in, and one of its two authed tests stood on **`/pro/rendez-vous`, the page carrying the first strip, asserting a computed `line-height` and nothing else.** The gate existed and looked away. Measured in a browser rather than computed at 375: only strip #2 is live, **340px of 327** — 13px, not the ≈41 the arithmetic predicted — and the other four are latent. The « two surfaces, two answers » divergence is overstated too: `RevenusClient.tsx` is a `ChipButton` pill row, not this control. **Closed by B9** — one shared `<Tabs>` that WRAPS (a desktop has no swipe affordance, and A11 C4 recorded its scrollable strip putting « Tous » off-screen at 200%), plain buttons in a named `role="group"` rather than ARIA tabs, `min-h-12` for the 48px floor all five missed, and the authed routes promoted to matrix entries with `setup` steps. The web register carries the detail: WEB-SYSTEM §15 row 28. Full account: `web-b9-tabs.md` | ✅ **B9** |
| 55 | A `Tab`'s box is 46dp, under §13.2's floor — and the guideline passes | **0** | `_kTabHeight` is **46.0** (`tabs.dart:30`), a framework constant with no override short of `Tab(height:)` at every call site, and every tab in the app measures exactly that. A11 C4 put the first `TabBar` any a11y inventory has ever held into `tap_target_test` expecting a red, and `androidTapTargetGuideline` **passes in both scrollable and fixed mode** — it evaluates semantics nodes, not that box. Recorded because the arithmetic says it should fail and the measurement says it does not: the fix for a number that is already correct is nothing. Related, and still a genuine platform limit: a `Tab` cannot grow with the text scale, so `titleSmall` at 2× is 40dp inside 46 — it survives §13.3's 200% by 6dp and clips above ≈2.3× | ✅ **A11 C4** — *measured green* |
| 56 | `AppSearchBar` — two §13.3 defects in a widget no row had named | ~~2~~ → **0** | the home screen's third overflow, and the one nobody was looking for. `Text('Rechercher un salon…')` had no `Expanded`, no `maxLines`, no `overflow` — it wanted **277dp** at 200% and had 202, and ran off the side of the pill (75/60/45dp at 360/375/390). And `height: 48` was a fixed height around text, §13.3's *written* rule, with `bodyMedium` at 2× measuring 40dp inside 46 of usable box: it survives 200% by 6dp and clips above ≈2.3×. Now `Expanded` + a **declared** ellipsis — placeholder copy in a fixed-shape pill is the one place in A11 where an ellipsis is the right answer rather than the false fix — and `minHeight` | ✅ **A11 C5** |
| 57 | The text-scale gate measured a font and a width that do not ship | ~~2~~ → **0** | `text_scale_test` pumped `CompactAppointmentTile` at `SizedBox(width: 340)`, **wider than every width the tile is ever given** — home computes `(w × 0.86).clamp(280, 360)` → 309.6 at the floor, the salon page `(w × 0.75).clamp(260, 340)` → 270. Green about a configuration that does not exist: the same vacuity class §20 names, one level subtler than "unbounded". Narrowing it to 270 produced a 58dp overflow that **Roboto does not produce** — because the file also loaded no font, so it was measuring the placeholder square glyph C2 banned, in a second file nobody had checked. Both fixed together: `pumpAtTextScale` now pins the family and **refuses to run** unless `loadRealFonts()` has been called, so the fallback cannot return silently | ✅ **A11 C5** |
| 58 | A `Wrap` with `spaceBetween` shrink-wraps, and the gate cannot see it | ~~1~~ → **0** | `SectionHeading`'s first version rendered « Voir tout » snug against the title instead of at the right edge: a `Wrap` sizes to its content under loose constraints, so `spaceBetween` had no free space to distribute, where the `Row` it replaced defaulted to `mainAxisSize: max`. **The layout was correct and only the alignment was wrong**, so nothing in 838 tests objected — it was caught by looking at the regenerated `consumer_provider_detail.png`, which is the whole argument for §20.1's "look at every changed PNG" rule. Fixed with `SizedBox(width: double.infinity)` | ✅ **A11 C5** — *caught by the eye, not the gate* |
| 59 | `contentMaxWidth` was named in §10 and implemented on neither surface | ~~2 surfaces~~ → **0** | §10 has said *"text and forms never stretch past it"* since it was written. Mobile had **nothing** — 19 `static const double`s in `AppTheme`, all spacing/radius/icon. Web had `content: '720px'` hard-coded in `tailwind.config.ts`, under a comment admitting it stood in for §10. So the one dimension the design system names was prose on one surface and a literal on the other, agreeing by luck. C6 gave it an upstream: a fourth token family (`LAYOUT_KEYS`), `AppTheme.contentMaxWidth`, `ContentWidthCap` at the two phone roots, and the web config reading the generated value. Note what made the order forced — `tokens.mirror.test.ts` refuses any `AppTheme` scalar no family claims, so **the Dart constant could not exist until the web family did** | ✅ **A11 C6** |
| 60 | No test renders an app root, so anything wired there is unmeasurable | **1 structural gap** | `grep MyweliApp mobile/test/` returns only the docstring that quotes this grep. Every golden builds its own `MaterialApp` (`golden.dart`), every widget test goes through `wrapApp`, and **neither has a `builder:`** — so `MaterialApp.builder`, `ReduceMotionObserver`'s placement, and now `ContentWidthCap` are all invisible to the suite. It is why the spec's *"the unchanged golden suite is the no-regression proof"* was true and **vacuous** for C6: zero baselines moved because the cap is in no tree any of them photographs. Held today by source pins (the `motion_test` idiom) plus component tests, which is a proxy, not coverage. The real fix is a shell that renders at a device width — `test/a11y/` currently inherits `flutter_test`'s 800×600, wider than anything this product ships on — and that is its own slice, already filed in `mobile-a11-width.md` §8 | *new — the shell should pin a real width* ✅ **Closed by A12.** `pumpForA11y` now pins 360×1600, which converted `contrast`, `label` and `tap_target` in one edit; `feedback` and `motion` took per-test pins. **6 of 11 → 11 of 11.** It found three reds and **not one was a product bug**: `tap_target` pumped a four-label `TabBar` with `isScrollable: false` — a bar `lib/` has not had since C4, and one that overflows at 360 — and `motion` tapped `Offset(700, 400)` for "the right 65 %" of an 800dp surface, which at 360 is off-screen, so two assertions read 0.0 pages. A guideline asserted against a layout that cannot render is not a measurement. |
| 61 | A slice fixed fourteen defects and moved three pictures | ~~14 fixes / 3 baselines~~ → **5 new baselines** | the coverage arithmetic nobody had done. A11 closed fourteen layout defects and the entire golden suite moved **three** files *(the C7 figure; the slice finished at **eight**, six of them moved by one shared button label)* — and `consumer_home.png` moved **zero bytes** while C5 was rewriting two of its sections, because the golden pumps it **signed out** and both headings sit behind `isAuthenticated`. Five fixes were photographed by nothing at all; four more are the identity at 1×, so no picture in the repo could see them at any width. C7 added five baselines at the **360 floor**, three of them the repo's first at **200% text**. The lesson generalises past A11: **a suite of 26 pictures all taken at one width and one text scale is not coverage of a design system that defines a range and calls 200% a first-class input** | ✅ **A11 C7** |
| 62 | At 200% text, several labels break mid-word — and the gate permits it | ~~4 measured~~ → **4 fixed** | found by looking at C7's first 2× pictures, which is the whole argument for §20.1's review rule. « Salon Ex/cellence » · « Prom/o W… » · « Appel/er » · and a DATE broken as « 13/03/20 » / « 26 ». **C8 fixed the two that were unarguable** — a date and a control's label — and left the two « headings » to the slice that would decide whether a heading may break. **A13 closes them, and the row had one of them misfiled.** The story card is not a heading: `announcement_stories.dart` wraps it in `Semantics(button: true)` + `InkWell`, so its title IS the control's accessible name and §13.3's *"any control's label"* already forbade it. Only the salon header was ever the heading question, and §13.3 is amended: a salon's NAME may not break either, because it identifies the business a user is choosing. **Measured against the SDK's own Roboto, and the number that reframes the fix is 1.20×, not 2×**: the 64dp title box loses « Week‑End » just past 1.20×, « Nouveau » at 1.38× and « Dernière » at 1.43×. So all three titles break — swapping the U+2011 (a NON-BREAKING hyphen, which is why « Week‑End » is one token) for a breaking one fixes **one of three** — and a 1.3× branch, this file's own idiom, would arrive **late**. The card's width and height track the scale instead (`textScaledBound`, returning exactly 92.0 and 126.0 at 1×, so the 1× golden is byte-identical). `ringWidth` became an argument on the way: `Container` applies `decoration.padding` on top of the explicit `Padding`, so the ring was inset twice and **the title's width depended on whether the story had been seen** (64dp unseen, 72dp seen). The salon header **stacks above 1.6×** — shrinking the 72×72 logo cannot reach the contract point (measured at 56/48/40dp it still breaks, and deleting it outright only just clears), and `maxLines: 3` moves the assertion by zero while adding 72dp to a header with **zero slack at 2×**. Full account: `mobile-a13-copy-and-breaks.md` | ✅ **A11 C8** for two · ✅ **A13** for two |
| 63 | **Nothing had ever run this app on a device.** Eleven design slices, 881 tests, 33 pictures — and the first `adb install` was C8 | **3 defects, first run** | A11's whole thesis is that one measured point is not a range. C8 tested the thesis against itself: a 360dp Android emulator (720×1600 @ 320dpi, xhdpi — the Tecno/Infinix class the PRD names) at 1× and 200% text found **three** overflows the suite could not, in about ten minutes. All three are `RenderFlex` overflows, and the striped « RIGHT OVERFLOWED BY » banner is **debug-only** — in the release build a user installs, the content is cut off at the edge and nothing is reported anywhere. The generalisation is row 61's, one level up: a golden is a picture of a tree the test built, and a device is the only instrument that renders the tree the product builds. `mobile-a11-width.md` §6.3 records the run as a numbered note, the convention `DEPLOYMENT.md` uses — no prior slice had one to copy | ✅ **A11 C8** |
| 64 | A shared control's label could not shrink, so it pushed the control off the screen | **2 labels, every button in both apps** | `AppButton` put its label in a `Row` as a **non-flex** child, and a Row lays those out with an unbounded main-axis constraint — so the `Text` measured its full intrinsic width and the Row overflowed rather than the label shrinking. At 360dp × 200%: « + Nouveau rendez-vous » **32px** past the edge, « Voir toutes les communes » **65px**. Both are `EmptyState` actions, i.e. the one control on an otherwise empty screen. Invisible to `expectNoUndeclaredTruncation`, which walks paragraphs: this paragraph is not truncated, it is drawn in full past its parent. The label is `Flexible` now, so it wraps between words — §13.3 permits that for a control and forbids a mid-word break, and `app_button_test.dart` measures both over every `actionText` in `lib/`. The one call site that then needed a bound (`InvitationCard`'s « Refuser », beside an `Expanded`) took six tests down instantly, which is why the assertion is left loud rather than absorbed by a `LayoutBuilder` — that cannot answer intrinsic queries, and `IntrinsicHeight` is used twice in `lib/` | ✅ **A11 C8** |
| 65 | The screens people **sign in on** were measured at no width | **2 screens × 3 widths** | `layout_test.dart` has nine subjects and neither login is among them; the goldens held a `consumer_login.png` and **nothing for the pro app at any width**. So the pro login's « Pas encore de compte ? » + « S'inscrire » — a centred `Row` holding a sentence and a `TextButton`, neither able to give way — ran **149px** past a 360dp screen at 200% text (134 at 375, 119 at 390). The overflow barely moves with the width, which is the signature of content with a fixed intrinsic width: not a layout that adapts badly, one that does not adapt. It is the last line of the first screen a pro ever sees and the only route from it to registration; `pro_register_screen.dart` held a byte-identical copy. Both are one `AuthSwitchPrompt` now — a `Wrap`, the same fix §13.3 already takes for headings, with the same load-bearing `SizedBox` (a Wrap shrink-wraps, so centring inside one centres nothing). `auth_layout_test.dart` measures three screens × {360,375,390} × {1×,2×} | ✅ **A11 C8** |
| 66 | A form dropdown is as wide as its longest option, whatever the screen is | **3 of 3 phone forms** | `DropdownButtonFormField` sizes its button to its **widest item's** intrinsic width unless told otherwise, so « Institut de manucure » pushed the « Type d'entreprise » field **79px** off a 360dp screen at 200% text — and every other phone dropdown in the app had the same latent defect, none of them setting `isExpanded`. Fixed at all three; held by a **discovered-not-listed** source pin in `design_system_pin_test.dart`, so the fourth dropdown written is the one it exists for. The admin console's bare `DropdownButton` is excluded on purpose and by the same reasoning as row 51's cap exclusion — §10 leaves that surface uncapped, and stretching a filter would fill the filter bar | ✅ **A11 C8** ⚠️ **Row 68 re-opened this widget and the two rows disagreed (A12).** Resolved here: row 66 is right about the DROPDOWN — §10 leaves admin uncapped and stretching a filter would fill the bar — and row 68 was right that something is wrong there, but named the wrong thing. Its « bare `DropdownButton` in an unbounded `Row` » is **bounded**: `admin_scaffold.dart:98` is a `Container(height: 64)` whose Row holds a `Spacer()`, which cannot exist under an unbounded main axis. The real defect is that **fixed `height: 64`** around a `headlineSmall` title — 64.0dp of line box at 2×, exactly at the boundary — and it is a §13.3 fixed-box case on a surface §10 excludes, so it stays open as admin work rather than phone work. |
| 67 | The adversarial review found **two regressions the slice itself introduced**, and six gates that could not fail | **2 + 6, all after green** | run once `flutter analyze` was 0 and 881 tests passed, which is the only time it is worth running. **`ContentWidthCap` made `MediaQuery` lie** — `MaterialApp` publishes the WINDOW size, the cap narrowed the tree, and nothing reconciled them: on a 1200dp window a screen under the cap read `size.width == 1200` inside a 720dp box. `story_viewer.dart` splits its prev/next zones at `size.width * 0.35` against a LOCAL tap x, so the back zone became **58%** of the visible story and a tap left of centre went backwards; `_FullScreenGallery` sized its image from `size` and overflowed its own dialog. **`SectionHeading` dropped 8dp on six headings** — the `_SectionCard` it replaced padded `vertical: spacingXS` *unconditionally*, outside its `InkWell`, and the extraction moved it inside the `onTap != null` branch; only 1 of 7 salon sections is tappable. C5 regenerated `consumer_provider_detail.png` in the same commit, so the loss was written into the baseline **as truth** — §20.1's named failure mode, caught by reading the diff rather than by any assertion. Six gates were vacuous: the cap's root pin read raw bytes and both roots carry the string in a comment as well as in code; `button.right <= 360` cannot fail because `EmptyState` centres in 296dp; the gutters test asserted about its own fixture; `didExceedMaxLines` is false whenever `maxLines` is null, so it passed the ellipsis fix it forbids; 18 auth tests had no assertion that the screen rendered; and `openEarningsAll` passed on the error branch, where a golden photographs immediately after | ✅ **A11 C8d** |
| 68 | Twelve screens still break at 360 × 200%, and one harness is why | ~~12 screens, 0 gated~~ → **20 swept, 18 fixed, 7 refuted** | the census `layout_test.dart` and `auth_layout_test.dart` do **not** cover — twelve subjects × the same shapes this slice has now fixed four times. The systemic cause is one line: **`pumpAtTextScale` never pinned a surface**, so every component test that claims 200% coverage ran on `flutter_test`'s **800×600** — wider than any phone sold. The repo therefore had 360dp coverage and 2× coverage that *never intersected* outside the gate's twelve subjects. Fixed in C8d (it now pins 360, and all 160 a11y tests still pass — strictly stricter, at no cost), which is what makes the twelve findable. Ranked by how early a user meets them: **booking confirmation**'s three money rows, unflexed, ~190px over on the screen immediately before payment · **`provider_list`**'s `CommunePill` + `Spacer` + count · the **pro dashboard**'s `_StatCard` header (« Aujourd'hui » needs 165dp of a 126dp tile) and its `childAspectRatio: 1.1` action grid, whose tile height is frozen at 144dp forever · the **reschedule** time picker's hard `80×48` box around `« 14:30 »`, which needs 80.4dp at 2× and **clips silently** · **service list**, **deposit settings**, the **booking hub**'s pinned « Total » bar, the legacy **service picker**, **availability**, and `NotificationTile`, whose `Expanded` title is crushed to ~30dp by an unflexed timestamp — a legibility defect no assertion in this repo can see, because the truncation *is* declared. Plus the **admin audit filter**, a bare `DropdownButton` in an unbounded `Row` inside a fixed 64dp bar, where `isExpanded` would assert rather than help. **Recorded, not fixed:** these are twelve screens outside A11's stated subjects, and thinning them into the end of this slice would be the hollow pass the full-depth rule forbids | *next — its own slice* ⚠️ **C8f — no longer a prediction.** The iOS run (`iPhone 13 mini`, a true 360×780pt surface) reproduced finding #3 **at the contract point**: at `accessibility-large`, which Flutter maps to **≈1.95×**, the pro dashboard shows Flutter's striped banner on three of its four `_StatCard`s — « Aujourd'hui » + calendar **16px** over, « En attente » + dot **2.6px**, « Aujourd'hui » + `$` **16px**; at ≈3.12× the same cards run **91px** and **31px**. The census derived that statically (« Aujourd'hui » wants ~165dp of a 126dp tile) and the device agrees. **And a thirteenth, which a horizontal census could not find:** `EmptyState` overflows **vertically by 3px** at 1.95× when its description wraps far enough — a shared component on every empty screen in both apps. Recorded, still not fixed, for the reason above. ✅ **A12 closes it, and corrects it.** The row was assembled by READING `lib/`, not sweeping it, and a balanced-paren sweep found **20** of the unflexed-row shape where this named 9, and **16** fixed boxes where it named 2. Four of its figures were also wrong, every one re-derived against `layout_test.dart`'s recorded 72.2dp and the device's 16px/2.6px: the `_StatCard` label wants **~141dp** not 165 (computed at the wrong font size — `bodySmall` is 12), booking confirmation is **~123px** over not ~190, `NotificationTile`'s title keeps **~86dp** not 30, and the 80×48 slot box **fits at 2×** (~72dp) and bites at ≈2.2×. The admin entry contradicted row 66 and its « unbounded Row » is bounded — see row 66. Final triage: 13 defects fixed from the sweep and **7 of shape 1's hits refuted** (rating rows, and blocks the matcher mis-attributed) — **the two do not sum to 20**, and the first draft said they did: two of the 13 hold a single `Text` and are shape-4 hits reassigned into shape 1's triage, which is this row's own error class committed inside its correction. Five more defects arrived after the sweep closed — two the device found in the salon grid (row 72), three the adversarial review found (`AppointmentCard`, `NotificationTile`, the booking-confirmation service row) — for **18 fixed**, and every one needed an instrument the sweep did not have. Full account: `mobile-a12-census.md` |
| 69 | Two defect classes no assertion in this repo could see | **2 rules, 2 primitives** | §13.3 said *"a box that contains text may not have a fixed height"* since A5 and nothing enforced it; and a FLEXED label starved by unflexed siblings spends its declared ellipsis on a squeeze it did not choose, which `expectNoUndeclaredTruncation` skips **by design**. So `NotificationTile`'s title was unreadable and the dashboard's `childAspectRatio` tile was frozen at 143.6dp at every text scale, both green. A12 adds **`expectNoLegibilityCrush`** — flexed **and** `didExceedMaxLines`, the second precondition being the whole design, since without it every framing fires on `CommunePill`'s correctly-narrow « Cocody » — and **`expectNoVerticalClip`**, one pump of `getMaxIntrinsicHeight(size.width) > size.height`, vertical only because the horizontal twin is true of nearly every sentence on a phone. Plus a `childAspectRatio` prohibition pin, red at 2. `kMinLegibleChars = 8` was **measured, not chosen**: report-only first, then set strictly between the worst defect (7 chars, the salon app bar) and the best legitimate (9, a review tile) — a **one-character margin**, recorded rather than smoothed over | ✅ **A12** |
| 70 | The gates had no gates | **6 self-tests** | every assertion in `_a11y.dart` runs across the width matrix, where green is the right answer and a useless one — a helper that cannot fail is indistinguishable from one that passes, and row 67 records six shipped in a single slice. A12's two primitives were **wrong three times between them** before `primitives_test.dart` existed: `_prefixWidth` measured a single line and called a `maxLines: 2` header a crush; `_isPainted` needed three attempts because `tester.allRenderObjects` walks everything LAID OUT and `DropdownButton` builds every item into an `IndexedStack` — `RenderIndexedStack` is not the marker, `RenderObject.paintsChild` is not overridden by `_RenderVisibility`, and the answer is both plus an **element** walk. Each false positive is now a permanent subject | ✅ **A12** |
| 71 | The §5 spacing pin cannot see a compound name | **6 swept · 4 converted** | the sweep's regex was `\b(?:run)?[Ss]pacing: \d`, and `\b` cannot fire inside `crossAxisSpacing` — so a grid's gaps were invisible to a sweep §20 calls complete. A12 converted the dashboard's two in passing. **A13 closes it, and the obvious widening was a trap worth recording**: `[A-Za-z]*[Ss]pacing:` reds on **seven `letterSpacing:` lines** in this very corpus — the exact false positive the original `\b` existed to prevent, so that widening would "close" the gap by reintroducing the bug. The pattern names the compounds explicitly instead: `(?:\b(?:run)?|(?:cross|main)Axis)[Ss]pacing:\s*\d`, with `\s*` closing a wrapped-argument hole nothing exploits today. Red at **4**, all `10` — not on the scale at all — in `pro_photos_screen.dart` and `mock_image_picker_sheet.dart`, converted to `spacingSM`. **This row's own attribution was also wrong:** all four `10`s are in the corpus, and the `features/` pair are `12`, not `10`. And the sweep had **no non-empty corpus guard of its own** — it was borrowing the credibility of the `childAspectRatio` and animation pins from the same `group`, which is §21 row 67's failure mode; it has one now | ✅ **A13** |
| 72 | A fix that no test could execute, and the threshold that undid it | **1 screen, 2 defects, 55px** | A12 fixed the salon grid — `childAspectRatio: 0.75` → `ProviderCard.gridHeight` — and the device then showed « BOTTOM OVERFLOWED BY 55 PIXELS » on both cards at ≈1.95×, *after* the fix. **No test in the repo could have seen it**: `_isGrid` starts `false`, so `layout_test`'s salon-list subject and every other test measured the LIST branch, and the grid fix was never once executed by an assertion — the vacuity class §20 names, reached through a toggle rather than an empty state. The cause is two formulas in one file that disagreed: `gridHeight` is `142 + 68 × scale` (from the COMPACT image floor) while `_buildGridCard` decided compact with `maxH < 260`, a raw dp number; they cross at **≈1.74×**, above which the card drew the 180dp roomy image inside a box measured for the 110dp one. `compact` is now `maxH < carouselHeight(context)` — the roomy layout's own height — and the compact image takes what is LEFT after the text rather than `maxH × 0.56`. Fixing the height exposed a **second real defect** underneath, which the device had also shown and `expectNoLegibilityCrush` then reproduced: a 360dp two-column cell gives the salon's NAME 140dp, which holds 8 characters only to **1.90×** — under the ≈1.95× contract point, hence « Salon … » where a name should be. The crossing moves with the WIDTH (375dp holds to 2.00×, 390dp past it), so the rule is about the cell: `minGridCellWidth`, one column below it. **And the third instrument that was wrong first:** `text_scale_test` already guarded this class with `carouselHeight >= 260`, a proxy — which is exactly what let it through. See §13.3's new rule | ✅ **A12** |
| 73 | **Flutter's own date picker cannot show a date at 200% text** | **5 screens** | found on a device during A12's run, on the consumer booking flow: at `accessibility-large` (≈1.95×) on a 360×780pt iPhone, Material's `showDatePicker` calendar renders **20, 22, 23, 24, 25, 26 as a single digit** — « 2 21 2 2 2 2 2 ». Only 21 survives, because « 1 » is narrow. The user cannot tell one day from another on the screen where they choose their appointment. **It is not our widget and not our theme** — `AppTheme.datePickerTheme` sets colours, shape and elevation only, and never a `dayStyle` or a size. It is arithmetic: Material caps the dialog near 328dp, seven columns of ~46dp, and a two-digit day at ≈1.95× does not fit its cell. **More width is not available**, which is the fix §13.3 mandates everywhere else, so this needs a product decision rather than a layout change — an input-mode fallback above a text scale, or our own picker. Reachable from `booking_hub`, `pro_manual_booking`, `pro_journal` (×2) and `availability`. — **A14a closes it, and the row was accurate**, which is rare enough here to say: the day list, the theme's exoneration and all five call sites check out. Two things it did not contain, both measured by the gate before anything was built: the defect is **1.5dp** — « 20 » had **35.4dp and needed 36.9** — and it is **360-only at 2×**, since 375 and 390 both pass, so *"Material caps the dialog near 328dp"* reads as universal arithmetic when the dialog is also screen-relative. **The fix is not the full-screen route**, which buys ~0.9dp: it is owning the cell. `_WeekStrip`'s pill needs `max(32, scaledLine + spacingS)` = **48dp at 2×** against 46.9dp of column *because a circle must stay square*, so the day cell is a **rounded rectangle** that takes the column's full width and grows only downwards. Recorded rather than hidden, and the same trade `_WeekStrip` and WEB-SYSTEM row 7h already took: **seven 48dp targets need 336dp plus padding, which no 360dp phone has**, so §13.2's floor is unreachable horizontally for any month grid — height floored at 48, width grid-bound, the whole cell tappable. Gated by `expectTokensWhole` (shipped by A14a as `expectDayNumbersWhole`; A14b renamed it when the time picker needed the same predicate, and every reference here follows the symbol that exists), which exists because none of the three near-miss helpers could see this (the crush gate's 8-character floor is above a two-digit day; `expectNoMidWordBreak` skips the `maxLines: 1` paragraphs a day number is) and which is **proven falsifiable in three directions** per row 67. The first picker golden in the repo, at 1× and 2×. **Re-verified on the hardware that found it** — same iPhone 13 mini at `accessibility-large`: « 20 21 22 23 24 25 26 » | ✅ **A14a** |
| 74 | **Every app-originated booking showed the pro « Client » instead of a name** | **1 field · 3 screens · every booking** | found by row 41's own golden, and it is not a mock gap. `booking_service.dart:123` writes `'clientName': null` for **every** booking made through the consumer app — only the pro's manual-booking route supplies a name — so a salon saw the placeholder for the majority of its book. **The erasure pre-check came first and cleared**: `eraseUser` hard-deletes the identity row and there is no foreign key from `appointments.user_id`, so nothing resolves and no name can be resurrected. **But the fix is neither a `users` join nor `clientName`.** `appointment_card.dart:265` gates the « Réservé par votre salon » badge on `clientName != null`, so filling that field would have fired the badge on every booking and overloaded one field with two meanings; and `salon_clients.display_name` already holds the real name, written at booking time and already anonymised by erasure. So a **new `clientDisplayName`**, surfaced through the one hook both pro reads funnel through. **The erasure test then taught us the safety is THREEfold**: a draft asserting the field equals the anonymous label went red, because `anonymizeUser` also nulls `salon_clients.user_id` — so after erasure the booking cannot resolve to the client row at all. It **joins the off-day mask** (BACKEND.md T40/R4a): a name is contact data of a different kind but the same purpose, and an own-scope Collaborateur browsing days they do not work would otherwise rebuild the client base one date at a time. T40 now STATES that rule rather than leaving it inferred — before A13 there was no name to mask, so the mask's scope had never been decided, only observed | ✅ **A13** |
| 75 | **`table_calendar` is text-scale-blind, and one of its rows clips at 1×** | **3 call sites · 2 live** | found by A14a while deciding whether to reuse it. The package contains **zero** `MediaQuery`, `textScaler`, `maxLines` or `FittedBox` anywhere in its `lib/`: `rowHeight` is a fixed `52.0` and `daysOfWeekHeight` a fixed `16.0`, and `table_calendar_base.dart` sums them into a `SizedBox(height:)` — the exact fixed-box-around-text shape §13.3 forbids and row 69 built a gate for. `CalendarBuilders.prioritizedBuilder` **cannot save it**: the builder's result is inserted as the *child* of `SizedBox(height: rowHeight)`, and a child cannot make a `SizedBox` taller. Its cell is also **~39dp** after `cellMargin: EdgeInsets.all(6.0)` — **narrower than the ~46dp Material was already failing at**, so the row 73 defect is reproduced inside it. **And the weekday row clips at 1×, today**: `daysOfWeekHeight: 16.0` around a ~20dp line, on `date_time_selection_screen` (consumer funnel) and `appointment_calendar_view` (pro). Nothing has ever measured it — no golden, no a11y subject. The third site, `booking_journal_screen`, is `FeatureFlags`-dead. Not folded into A14a: replacing it reaches two more flows with their own states and event markers | ✅ **A14c** — all three converted, `table_calendar` gone from `pubspec.yaml`, and the weekday clip **measured at last**: « lun. » needed 20.0dp in a 16.0dp box, at **1×**, on all six configurations. The reason it escaped for so long is one line — Calendrier is `TabController` index 0, and both instruments aimed at the screen called `openProList(tester)` as their second statement, whose whole job is to tap away from it. Converting found three more the clip did not: the page had **no room for an honest calendar** (`rowHeight: 52.0` cannot overflow), the 40dp was **width** from triple-counted chrome (37.7dp a column against the 44.9 A14a requires, so « 15 » wrapped), and **pull-to-refresh was dead on quiet days** because `BrandRefresh`'s only scrollable was a `ListView` the empty branch replaced. Plus a salon with nothing booked **could not open its calendar at all** |
| 76 | **Nothing decides how far ahead — or how soon — a salon accepts bookings** | **the consumer funnel · both ends of the window** | *(body rewritten by A14d; the original framed it as « **2 screens**: `booking_hub_screen` over **365 days**; `date_time_selection_screen` over **90** », and **A14c deleted `date_time_selection_screen`** — `booking_horizons.dart:7` records « its 90 died with it » — so that half is moot. The row stayed open on its other half, which is the slice.)* **There is no server-side bookable-horizon rule at all** — re-verified 2026-07-31: a grep of `backend/` for `bookingHorizon|horizonDays|maxAdvance|advanceBooking|leadTime` returns nothing, and `slot_service.dart` holds no `Duration(days:)` bound anywhere, so **a client may request slots for any date in any year and the server will compute them**. A14a named the constants rather than reconciling them, because reconciliation is a product question and not a refactor. **Scoping the answer found the near end has the same defect**: `slot_service.dart:101-105` enforces a minimum notice as a bare `60`, with no constant, no setting and **no test**, duplicated independently in `mock_appointment_service.dart:358-361` as `Duration(hours: 1)` — so mobile's mock and the API agree only by coincidence. The window is unspecified at **both** ends, which is why A14d ships both | ✅ **A14d** — `bookingHorizonDays` (1..730, default 365) + `minimumNoticeMinutes` (0..10080, default 60) on `Availability`, enforced in `SlotService.availableSlots` for **client paths only**: the salon's own manual booking and its own reschedules stay exempt, because the salon owns its calendar. Both defaults preserve the previous behaviour exactly, so **no salon's calendar changed on the day it shipped** — the feature is the ability to change them. **The near end forced a restructure**: the rule was « for today, only starts ≥1h from now », computed as minutes past salon midnight and null on every other day — structurally incapable of a notice longer than a day, since a 48-hour salon must exclude tomorrow. One absolute instant says both, and the old 1h behaviour (which had no test in its life) is pinned first. **Four traps, each watched red**: the server's `replaceAvailability` allow-list and mobile's `toJson` both silently erase an unlisted field (proven — written 30/120, read back 365/60); `invalid_state` does **not** map to 409 on the booking route, so `beyond_horizon` would have shipped as a 400; and `SlotPicker.horizon` had existed since A14c with the docstring « A14d makes this per-salon » while **neither call site passed it** — a defaulted parameter no behavioural test can see, now pinned at the source. **An empty day gained four reasons** where it had one: beyond the horizon names the last bookable date, inside the notice names the delay, a full day says so, a past day says it has passed — each with a one-tap jump, none with a « Réessayer » that could never succeed. Web needed its missing FOURTH state first (`fetchSlots` collapsed every failure into `[]`, the same defect A14c fixed on mobile) and six French sentences stopped claiming someone had taken a slot that was never taken. Along the way: blocked dates were stored as the **UTC** calendar day of a salon-midnight instant, so a UTC+1 salon blocking the 15th closed the 14th — fixed ahead of A14e in its own PR, and the availability screen got its first golden and first layout subject |
| 77 | **Flutter's time picker does not clip — it refuses to scale, and no gate here can fail on it** | **6 call sites · 8 (site, route) pairs over 5 routes** | found by A14b while scoping the time half of A14, and it is a *different* defect from row 73 rather than its twin — borrowing row 73's framing would have been false. Four mechanisms, each verified against Flutter 3.38.6: (1) **`time_picker.dart:387` passes `textScaler: TextScaler.noScaling` to the hour and the minute as a LITERAL** — in dial mode those are `displayLarge`, 57sp on a 64dp line, inside a hard-coded 80dp box, so the dialog's largest text is byte-for-byte the same size at 100% and at 200%. **That is worse than a clip, because a clip is visible.** :528 does it to the separator and :2263 wraps input mode in `MediaQuery.withNoTextScaling`. (2) it **caps its own container at 1.1×** (`:2544-2552`, with Flutter's own comment admitting why), and to height only — portrait width stays the literal `310`. (3) its dial numbers *do* scale, to 2×, on rings a fixed **28dp** apart (`_kTimePickerInnerDialOffset`), and `dialTextStyle` is `bodyLarge` — **our** `bodyLarge`, wired at `app_theme.dart:212` — so 2× puts a **48dp line box on 28dp of radial gap**. Labels are painted centred on the ring (`:1082`), so the two boxes overlap by 20dp **at 12 and 6 o'clock**, where the radius is vertical — two earlier drafts said *"at every clock position"* (which treats a radial constant as vertical everywhere; at 3 and 9 the governing dimension is glyph width and the boxes do not meet) and estimated *"~4dp of painted ink"* (which read a 32sp font size as 32dp of ink — cap height is ≈0.71 em). **Whether the glyphs touch was never measured.** What is derivable is enough: the dial reserves 28dp of radial room for text occupying 48. (4) **no assertion in this repo can fail on any of it** — the dial is a `CustomPaint` inside `ExcludeSemantics` with `excludeFromSemantics: true`, and every helper in `_a11y.dart` walks `RenderParagraph`s, of which it has zero. And the theme cannot reach it: `hourMinuteSize` and `dialSize` are abstract getters on the private `_TimePickerDefaults` and appear **zero** times in `time_picker_theme.dart`, so unlike row 73's `dayStyle` this is not even *"reachable by doing the forbidden thing"* — the font is the only lever and it does nothing. — **A14b closes it.** Three house controls (leaf, range, combined), all six sites converted, **two** shipped error states deleted because the constraint became expressible: `weekly_hours_editor.dart:75`'s **bare silent `return`** (two modals, then the row simply did not change — indistinguishable from a cancel) and `availability_screen.dart:670-678`'s snackbar. A third, `pro_manual_booking`'s « … à venir. », is **kept and demoted to a drift backstop** — the spec claimed it would die and that was wrong, because the wall clock moves while the form is open. Gated by a new subject at {360,375,390}×{1×,2×} on all three controls (watched red against a fixed 24dp row) plus a source pin forbidding `TextScaler.noScaling` in `lib/` (watched red by planting one). Six goldens, and the pictures found two defects the gate could not: a date broken **mid-token** — « 11/03/2 » / « 026 » — and mismatched chip heights, both fixed with a `Wrap`. The adversarial review then found **five more the goldens could not**: an `hour: 24` from ceiling a minute component and carrying (silent — `TimeOfDay` has no assert, so « Confirmer » stayed live and `salonDateTime` rolled the booking to the next day), two closed-form `hourEnabled` predicates that marked an hour selectable when none of its minutes were, an off-grid start clamp, and an unsnapped lift in manual booking — plus a per-token vacuity hole that let the gate measure one paragraph while claiming two columns | ✅ **A14b** |
| 78 | **Blocking a week costs a week of round trips, and the destructive half is the unguarded one** | **1 screen · 2 write paths** | found while scoping A14e, and the register had no row for it because nobody had costed the gesture. `_showAddBlockedDateDialog` opens the picker, confirms, and writes — **once per day**. « Bloquer les fêtes » is fourteen full round trips, and each one is a `DELETE` of the salon's ENTIRE availability followed by a re-insert of four tables; « tous les dimanches d'août » is five, and a date RANGE cannot express it at all. Toggle is the only single mode that expresses both real jobs, and the only one that maps onto the model that exists — `blockedDates` is a list of days, not a rule. **The confirmation was on the wrong half**: adding always confirmed (A14a restored it deliberately, because the picker pops on first tap and the write is immediate and un-undoable) while removing wrote **immediately, with no dialog** — and unblocking is the direction that produces an unwanted booking. **The trap that made this a register row rather than a chore**: the picker's `firstDate` is the salon's today, so `_enabled` refuses every earlier day — a past blocked date **cannot** be in a selection. A multi-select returning the full set would therefore **delete every blocked date before today**, on the first save, with no error, and irrecoverably, because the server replaces the whole set. Invisible from the UI: past days never render in the picker, so nobody would see them go. So the picker returns a **delta**, and erasure stops being something to remember and becomes something the shape cannot express | ✅ **A14e** — `showMyweliMultiDatePicker` returning `({added, removed})`, one composer (`applyBlockedDaysDelta`) shared by the multi-select AND the per-card delete so they cannot drift, and **one confirm named by direction** — « Bloquer » / « Débloquer » / « Enregistrer » for a mixed change, with `isDestructive: false` on pure removal because opening your calendar destroys nothing. The erasure gate is watched red twice: once as a unit (`return fresh` reddens 4 of 6) and once end-to-end on what the SERVICE receives. A second mutation proves the pair is not one assertion wearing two hats — dropping the `removed` filter reddens a different test while the erasure one stays green. The save button is gated on the **delta**, never on `_selected.isEmpty`, which is the naive rule that makes « tout débloquer » unreachable |
| 79 | **An `AppBar` title ellipsizes, and at 200% text the bar has nothing left to give it** | **3 screens found in one session; the class is every title long enough to lose against its residual bar width** | found by the A14 device run (`mobile-a14-pickers.md` §35.3) on the `A11 360dp` simulator at `accessibility-large` ≈1.95×. « Dates à bloquer » renders « **Dat…** » the moment A14e's « Réinitialiser » action appears — which is precisely while the pro is mid-edit; « Tableau de bord » renders « **Tableau de b…** » beside its two icon actions; and « Nouveau rendez-vous » renders « **Nouveau rendez…** » with **no actions at all**. That third one is why this is a row and not a one-line fix: crowding is only half of it, and « move the action into the body » repairs one instance while leaving the other two. The scope is a **length** question rather than a structural one — « Disponibilité » and « Rendez-vous », on the same tap chain in the same session, fit at the same scale — so a rule has to say *which* titles are allowed to lose, not « app bars are broken ». Measured: the multi-picker's full title is **237dp** at 1.95×, its leading `IconButton` takes **69dp** including `titleSpacing`, and a `TextButton` reading « Réinitialiser » takes ~**150dp** — 456 into 360. §13.3 says text reflows rather than truncates and an `AppBar` title is the one place in the product that structurally cannot: Material wraps the title in a `DefaultTextStyle(softWrap: false, overflow: TextOverflow.ellipsis)` (`app_bar.dart` — it never sets `maxLines`, and a `softWrap: false` paragraph is single-line regardless) and the bar's height is fixed. The decision this needs is what the house rule *is* — a two-line bar at large scale, a `FittedBox`, shorter titles, or an accepted exception with a gate that pins which titles may clip. Nothing computes today: A11's §10 width gate walks `RenderParagraph`s for **overflow**, and an ellipsis is not overflow — the paragraph fits, having thrown the text away first. B11's web half already built the analogous **truncation** gate (`web-b11-reflow.md`), so the shape exists on the other surface | ✅ **A15** — [mobile-a15-appbar-titles.md](mobile-a15-appbar-titles.md). The rule is in §13.3: **280dp at the 1.34× clamp**, which is 360 minus a `leadingWidth: 48` — exactly what a `BackButton` occupies, so the 8dp it recovers were never painted in — and Material's 16dp of `titleSpacing` on each side. **`titleSpacing: 0` was built, photographed and rejected**: it buys 32dp and every title fits, but the gap applies whether or not a leading exists, so on a ROOT bar the title lands at x = 0 against a body that keeps its 16dp gutter — one screen with two gutters, on all 57 bars. And the 32dp were not comfort: at 312 the widest survivor cleared by **2.7dp**. **The scope estimate in this row was wrong in both directions and the corpus is now read out of `lib/` rather than counted by hand**: 56 title literals, not 63 — and the four that reach a bar through a picker's `helpText:` were missing from the hand count, including « Dates à bloquer », *this row's own headline example*. At the shipped budget **6 titles lost**, not 14: « Détails du rendez-vous » → « Détails », « Reporter le rendez-vous » → « Reporter », « Préférences de notification » → « Préférences », « Nouveau rendez-vous » → « Réservation », « Configurer mon profil » → « Configuration », « Horaires - {jour} » → the bare day name. **Three of those go the OTHER way on the row that opens them** — a `SettingsTile` or a button has the width to say « Préférences de notification » or « Nouvelle réservation », and a 280dp bar does not, so the long phrase moved to where the width is rather than being deleted. **The other half was never a length problem.** An action's label is scaled by the FULL system scaler while the title is clamped to 1.34× (`app_bar.dart:44`/`:1092`), so on an action-bearing bar the title is never the defect — « Réinitialiser » alone costs ~182dp of 280. Three text actions became `IconButton` + `tooltip:` (« Tout lire » ×2 → « Tout marquer comme lu », « Réinitialiser »), and the two titles this row photographed as crowded — « Dates à bloquer », « Tableau de bord » — **kept their copy**. **And one bar lost its action entirely**: « Salons & Barbiers » is 257dp and one icon action leaves 232, so the grid/list toggle moved into the results row — a control over the results belongs there anyway. It could not go in the commune row, which is already full: an `IconButton` there squeezed « Toutes les communes » to 110.8dp and reddened A12's own 8-character floor. That is the width gates catching the fix for the width gates. **A third species: a title that interpolates data promises a width it cannot keep.** The journal's « {Salon} — votre planning » fit for « Salon Excellence » and not for « Institut de Beauté Cocody Riviera », so the name moved into `_Header`'s Column and the bar says « Votre planning »; `availability_screen.dart`'s « Horaires - {jour} » became the bare day name (and took an ASCII hyphen with it — §17.1 would want « — », which is *wider*, so that repair alone would have made it worse). **Both were invisible to the corpus scan by construction** — the literal regex refuses `$`, so interpolation was the way out of every measurement in the slice. That is now its own pin. Gates: `expectAppBarTitleWhole` as a *scope* of `expectNoUndeclaredTruncation`'s predicate rather than a second one; the 15 matrix subjects are now **route-pushed** (`pumpPushedAtWidth`) because `home:` draws no leading and measured a bar 72dp wider than the product's; a corpus run over every title in `lib/`; and a `// clip-ok:` declaration with an orphan rule and a four-case fixture through the shipping scan, non-vacuous on a day when nothing declares one. New baseline `pro_journal_own_mode.png` — the T40 boundary had never been photographed. **And the device run found the gate's own blind spot, which is why row 79 could not have been closed without one.** The corpus ran every title on the widest bar it can get (pushed, action-less, 280dp) and read « Tableau de bord » (231.1dp) and « Dates à bloquer » (226.3dp) GREEN — while a phone at `accessibility-large` still rendered « Tableau de b… » and « Dates à bloqu… ». Two causes, both now closed: **the matrix gated only the 13 PUSHED subjects**, so the dashboard — a `go`-only root — was unpushed *and* ungated; and **a bar with a leading and one icon action has 232dp, not 280**, which nothing measured. The corpus now runs a **second pass beside a real icon action** for every title whose own `AppBar(` declares `actions:`, and the three root subjects are gated too. Four more titles fell out: « Tableau de bord » → « Accueil » (`/pro/profile` is reachable from that bar and nowhere else, so the action could not give), « Dates à bloquer » → « Jours bloqués » (which also stops naming one direction on a screen A14e made bidirectional), « Nouveau créneau » → « Nouveau », « Modifier le créneau » → « Modifier ». **Measured limit, stated rather than hidden**: rendering runs ~5% wide of a bare `TextPainter` — « Dates à bloquer » computes 226.3dp and paints ≈237 — so a margin under ~5% is a coincidence, not a pass; and the second pass renders ONE action, so two-action bars are held only by the matrix. Re-verified on the phone: all six bars whole. |
| 80 | **One screen hand-rolls the empty state the house already owns, and loses two of the three things it does** | **1 screen · one import away** | found by the A14 device run on the pro **Calendrier** tab at ≈1.95×. `appointment_calendar_view.dart`'s `_emptyDay()` is a bare `Center(child: Column(...))` where `widgets/common/empty_state.dart` gives `EdgeInsets.all(spacingXL)` and `textAlign: TextAlign.center`. Both losses are visible together: « Aucun rendez-vous » wraps and line two (« vous ») sits **left-aligned under line one**, because a `Column`'s cross-axis centring centres the paragraph *box* and not its lines; and « pour vendredi 31 juillet 2026 » runs **edge to edge with ~3dp of inset** at 360dp, where a slightly longer date (« pour mercredi 30 septembre 2026 » is two glyphs more) would wrap against the bezel. **The third defect is NOT the shared widget's to fix**, and the first draft of this row wrongly implied it was: because the branch is a `SliverFillRemaining(hasScrollBody: false)` with no bottom padding, its last line is the **bottom of the scroll extent** and cannot be scrolled clear of the extended FAB — a FAB reserves ~56dp plus its 16dp margin that this scroll view never adds, and `EmptyState` has no FAB inset either. So the repair is two moves, not one, and the second has no stated contract behind it: §13 does not say what a scroll view owes a floating action button. Related: row 81 is the same screen's FAB | *new* |
| 81 | **The pro journal offers one action twice, and at 200% text the two controls merge** | **2 tabs of 1 screen** | found by the A14 device run at ≈1.95×. « Ma journée » and the **Calendrier** tab both render an empty state whose CTA pushes the new-appointment route **under** a `FloatingActionButton.extended` that pushes the same route. At default text scale they are far apart and the redundancy merely reads as generous; at 1.95× the empty state grows downwards and the FAB's top edge lands ~**3dp inside** the CTA's rectangle, so two `primary`-filled surfaces abut with no gap and read as a single broken control. The fix is to drop one, and which one is a product call: the FAB is the persistent affordance and the CTA is the discoverable one, they cannot both be right, and A11's rule about a phone at 200% does not decide it. Recorded with row 80, which is the same screen's other half | *new — needs a product decision* |
| 82 | **A salon that is not yet online fails with « Une erreur est survenue. » — on both sides** | **2 write paths · every newly registered salon** | found by the A14 device run, and it is the state **every** salon starts in. A salon created through registration is `status: 'draft'`; `BookingService.book` and the pro's own `POST /providers/{id}/appointments` both refuse it with `provider_suspended` (409), which is correct. Neither surface has a sentence for that code, so both fall through to the generic snackbar: the consumer reaching a draft or suspended salon through a stale link or a favourite gets nothing to act on, and — worse — the pro filling in their **first ever** manual booking is told only that an error occurred, on a dashboard whose go-live card is meanwhile inviting them to « Complétez les étapes pour aller en ligne ». Two things need deciding together, which is why this is a row: the **copy** (« Votre salon n'est pas encore en ligne. » is not the same sentence a *suspended* salon should see), and the **code**, because `provider_suspended` currently names both a never-published draft and a banned salon and no client can tell them apart. A14d's `beyond_horizon`/`too_soon` mapping in `routes/appointments/index.dart` is the precedent for adding an explicit case rather than letting it fall to the default | *new — copy + a code split* 🟢 **Closed for the copy; the read stays open — [salon-state-and-refusals.md](salon-state-and-refusals.md).** **PR2 shipped the sentences on all four surfaces**, plus the way out: `conflictMessage` gained an `audience` discriminator (a closed two-value axis — which is *not* the thing its docstring argues against centralising), both mobile mappers gained the codes, and `bookingErrorCta` — twinned line-for-line on web and mobile — offers « Découvrir des salons » for these two refusals and **`null` for every other**, which is the guard that stops §12's « way out » becoming a button on every error. Shipped alongside, because they sat in the same switch and made the PR's own claim false otherwise: the pro's missing `slot_unavailable` (its likeliest refusal, whose screen comment already asserted what the copy denied) and mobile finally learning A14d's `beyond_horizon`/`too_soon`. §12 itself is amended — it demanded « a retry control » flatly, which this copy correctly disobeys. **Still open:** Decision C, the public read. **Shipped:** a draft salon now **owns its calendar** — `bookManual` refuses `suspended` only, so this row's worst case (the pro's first ever manual booking) **stops happening** rather than getting better copy; and the code **splits**, `draft` → `provider_not_published`, because `mobile/lib/models/provider.dart` has no `status` field and the client structurally cannot disambiguate. Four gates, two watched red, two mutations proving the pair is not one assertion twice. T51's mitigation is amended: it *was* the conflation (« booking refuses them like suspended ») and it contradicted T54's promise that a billing unpublish leaves the journal working. **PR1b cleared the first blocker on the public read:** the claim that closing it was safe had been **false** — four mobile pro surfaces, including the owner's pre-publish preview, read their own salon through the unauthenticated route while web read all four correctly; they now use `GET /me/provider`, pinned by `pro_reads_own_salon_test.dart`. That pin went red on three of four and **green on the worst one**, because the preview's public fetch lived inside the *shared* consumer screen and so named no forbidden token — a directory-scoped source pin is blind to a defect that crosses its boundary, and the preview is held behaviourally instead. **PR1c answered the product question and built it.** The relationship lives on the server, so the server hydrates it: a consumer's own appointment now carries the salon's identity, contact, address, deposit coordinates, artist/service names, booking window and **`providerStatus`**, and `/me/favorites` returns hydrated salons — both deliberately UNFILTERED on status, because those endpoints are authenticated and own the relationship, so they can serve a hidden salon's facts without giving an anonymous caller an enumeration oracle. That deleted web's per-salon fan-out, the favourites fan-out, `fetchBookingWindow` and its proxy route, and **six** provider reads from mobile's appointment detail — taking three live defects with them: « Numéro indisponible. » blaming a phone number for a salon-state problem, a deposit sheet opening with **no Mobile Money handle to pay to**, and a calendar export writing « Rendez-vous — le salon » at zero duration **while reporting success**. Three things the slice found that the plan had not: the pro « Avis » surfaces read the salon's own reviews through the *public* route (PR1b's miss one file over, invisible to its pin because the leak crossed a service rather than a directory — now `GET /me/provider/reviews`); that route has **no provider read at all**, so an unknown id returns `200 {items:[]}` and gating only the hidden case would make 404 mean « exists but hidden », the exact oracle T51 forbids; and `canReschedule` was quietly answering « is upcoming » at two other call sites, so folding the salon state into it would have taken the calendar entry away from a client whose salon shut down (split into `isUpcoming`). **PR1d closed the doors, and row 82 with them.** All four public reads serve `active` only through one primitive; **hidden and unknown answer identically**, which on the reviews route meant moving the UNKNOWN id to 404 as well — it returned `200 {items:[]}`, so a 404 covering only the hidden case would have meant « exists but hidden », the oracle T51 exists to prevent. Who is told WHICH state is the same anonymous-vs-relationship split PR1c drew: `/availability` flattens both into `provider_not_found` because it answers to anyone and takes an arbitrary id in a query string; the consumer reschedule names the state (409) because the caller owns the booking. That last one made a shipped comment TRUE — `appointment_detail_screen.dart` already claimed « the server refuses the move … hiding is a courtesy OVER the server gate, never instead of one », and there was no server gate. **Decision A is finally enforced on both salon-owned write paths:** `rescheduleByProvider` keeps working for a draft salon and now refuses a SUSPENDED one, which it never checked at all — the written rule (« a salon that has not published owns its calendar; a suspended one does not ») had been half true since PR1. Two client defects the closure would otherwise have manufactured are fixed in the same slice rather than recorded: mobile's funnel rendered **« Une erreur est survenue. »** beside a « Réessayer » that could never succeed — row 82's headline sentence, back, inside the funnel — and web's blamed the connection. **Residual, stated rather than hidden:** closed on the API, **≤5 min on the public page cache** (`revalidate` 3600 → 300; the funnel is `force-dynamic`, so only the marketing page lags). 🟢 |
| 83 | **A salon that authored its own opening hours stopped taking bookings, silently — in both engines** | **every salon that is not a fixture · every service · every open day** | found by the A14 device run (`mobile-a14-pickers.md` §35.1), and it is the defect that justifies driving a live round trip on hardware. `SlotService._openMinutes` enumerated each `weeklySchedule` entry's `startTime` and **discarded its `endTime`** — correct only when the template holds one entry per 30-minute step, which is what `seedProviders`' `_defaultWeeklySchedule` builds. But `draftSalonDocument` gives a fresh registration an **empty** `weeklySchedule`, so every salon authors its own hours — in the pro app's day editor **or the web dashboard's « Disponibilités »** (`web/lib/pro/availability.ts`'s `toApi`) — and both store one entry per range the owner enters, so « 09:00 – 18:00 » is *one*. Nothing forbids eighteen entries (the editor appends without a cap; the server checks only `start.isBefore(end)`), but nothing authors them, and outside the fixtures the shape never existed. Measured against the engine: one `09:00–18:00` entry → **1 slot** for a 30-minute service and **0** for a 60-minute one; a split day `09:00–12:00` + `14:00–18:00` — the most ordinary schedule there is — → **2** and **0**; eighteen half-hour entries → **18** and **17**, unchanged by the fix. The user-visible failure is « Aucun créneau ce jour-là » on every open day, forever, with no error on either side. **And it was in two engines**: `mock_appointment_service.dart` read the template the same way, invisible for the same reason (`MockData._generateTimeSlots` emits one entry per step) | ✅ **Closed by the A14 device run.** Both engines enumerate `[start, end)` in steps — strictly a superset, so a one-step entry still contributes exactly its own start and the fixtures' eighteen stay eighteen. Two red-first gates, each paired with a guard that was green throughout and stops the fix becoming « every day is open all day »: `slot_service_test.dart` (**red at `[540]`**) and `mock_open_hours_test.dart` (**red at `[540]`**, and `[540, 840]` on the split day). The app half was found not by the device but by the **adversarial review of the write-up** — the server fix alone would have made this row's ✅ true of one surface and false of the product |
| 84 | **One fact, three fallbacks — and an export that reports success while writing nothing** | **3 surfaces · every booking whose salon does not resolve** | found while deleting the fetches in row 82's PR1c. A booking's salon name had three different last-resort spellings depending on which file rendered it: « Salon » (`AppointmentCard.tsx:19`, `AppointmentDetailClient.tsx:196`), « MyWeli » (`web/lib/account/calendar.ts:20-22`) and « le salon » (`appointment_detail_screen.dart:399`). Nobody chose three; each was chosen once, locally, by someone who could not see the other two. Worse, the mobile calendar export built its event from a failed fetch — title « Rendez-vous — le salon », **zero duration**, no address — and then called `AppSnackBar.outcomeOn(..., success: 'Rendez-vous ajouté à votre calendrier')`. The user was told it worked. **The fallbacks are now unreachable** (the server sends the name), which is a fix by removal rather than by agreement: the three literals still sit in three files, and the next fact that degrades will acquire its own third spelling the same way. The rule this suggests, not yet written into §12: **a fallback is copy, and copy has one home** | *new — recorded, not fixed* 🟡 the paths are dead as of PR1c; the pattern that produced them is not |
| 85 | **`null` meant both « not asked » and « asked and failed » — so three screens flashed the ERROR state on frame 1, and one had no error state at all** | **3 consumer screens · every cold open** | found while writing row 82's landing states. The salon detail, the booking hub and the booking confirmation all schedule their fetch in a post-frame callback — they must, because the notifier notifies before its first await and notifying during build throws — so **build #1 saw `isLoading == false, selectedProvider == null` and rendered the failure**. One frame of a red error icon on every cold open of three screens, invisible in every test because none of them pumped a single frame without settling. The state machine had two values for three states. **Worse, on one of them there was no error state at all:** `booking_confirmation_screen.dart` mapped `p == null` unconditionally to a spinner, so a failed load span forever — on the screen immediately *before payment*, with `provider.error` and `provider.errorCode` both populated and both ignored. Same class as A14c's SlotPicker miss: a fourth state that was never written because nothing forced it. Fixed by a synchronous non-notifying `beginProviderLoad()` and a shared `SalonUnavailableView`; held by an assertion on the very first `pump()`, which is the only frame that can see it | *new — fixed in PR1d* 🟢 |
| 86 | **Two French words break mid-word at 200%, and `expectNoMidWordBreak` is applied BY NAME so neither was ever named** | **2 surfaces · the class is every unnamed label the helper does not cover** | found by the A15 device run on the `A11 360dp` simulator at `accessibility-large` ≈1.95×, walking the surfaces row 79 named. (a) `availability_screen.dart`'s **pause-hours rows** render « **Mard/i** », « **Merc/redi** », « **Jeud/i** », « **Vend/redi** », « **Sam/edi** » — five of seven day names split across two lines, in a row whose right half (« 13:00 – 14:00 » + a switch) is unflexed and takes its intrinsic width, so the day name is the only child that can give. (b) `MyweliMultiDatePicker`'s **discard dialog** titles « **Abandonne/r les modifi/cations ?** » — an `AlertDialog` title is a heading, and §13.3 lets a heading wrap, but never inside a word. **Why the suite is green about both**: §13.3 gives `expectNoMidWordBreak` a role exception — a date may not break, a heading may — so it is applied per named string rather than as a sweep, and nobody named a weekday or a dialog title. That is the same shape as row 79's own defect (a rule with no gate over its whole population), one level down: the helper exists, the corpus does not. A day name is a proper noun the pro is choosing between, which A13 already promoted into the « may not break » list — so (a) is a rule the document already contains and the code already violates. The fix for (a) is more width (flex the day name, or stack the row); for (b) it is `Wrap`-friendly copy or a shorter title — « Abandonner ? » is 13 glyphs and says the same thing | *new — found by the A15 device run, filed rather than absorbed: different rule, different gate* |
| 87 | **The same control wore three appearances depending on which screen you reached it from — and the brand mark was on one provider but not the other** | **3 screens × 2 platforms · every sign-in and sign-up surface** | raised by the owner, not by a gate, because no gate can see it: the two social buttons live on the consumer login, the pro login and the pro register screen, and **nothing has ever rendered them next to each other**. So Google was always an outlined white `AppButton` carrying the official « G », while Apple carried **no mark at all** on either platform and appeared black on the two login screens and **white** (`secondary`) on pro registration. On web they were not even the same kind of object — Google an iframe painted by Google's script at 320 × 40, Apple our `Button` at full container width. Three things the fix surfaced that the report did not ask about, each worse than the asymmetry. **(a) The Apple button had never rendered in any build.** `FeatureFlags.appleSignIn` was `bool.fromEnvironment('APPLE_SIGN_IN')` — default **false** — and `APPLE_SIGN_IN` was passed **nowhere**: not CI, not `DEPLOYMENT.md`, not a build script. App Store rule **4.8** requires Sign in with Apple wherever another third-party provider ships, so every iOS submission would have been rejectable, with the code present and correct the whole time. **(b) `pro_register_screen.dart:357` was a dead stub** — `onPressed: () {}` — so the button was visible, tappable, and silent, while the backend's register route had accepted an Apple identity since the slice landed. **(c) Web read « Se connecter avec Google » beside « Continuer avec Apple »**, because two of the three `renderButton` calls omitted `text` and GIS defaults to `signin_with`; a third omitted `locale: 'fr'`. Nothing failed — the copy was merely wrong, which is why it survived. **Why the suite was green about all of it:** `_showApple` requires `defaultTargetPlatform == TargetPlatform.iOS`, and `flutter test` hard-wires **android**, so no widget test and **no golden** could ever draw an Apple button; and the `components_buttons` golden's social specimen was `icon: Icons.g_mobiledata`, a Material glyph no screen uses — the sheet depicted a button that did not exist while the real one went unwatched | ✅ **Closed.** One control, two fills: same height, width, radius and icon gap, Google `secondary` (white), Apple `primary` (black), each carrying the vendor's own vector — `GoogleGLogo`, and Apple's via `AppleLogoPainter`, which `sign_in_with_apple` exports, so no trademark is redrawn and no asset is bundled. Both `ExcludeSemantics` (§13.4 — the label already names the provider). Two details that only a rendered pixel catches, both found in review before shipping: `AppleLogoPainter` **scales its path to the `Size` it is handed**, so a square box visibly fattens the apple (drawn at 25:31, matching the plugin's own button); and a `leading:` widget — unlike `icon:` — is **not** tinted by `foregroundColor`, so a hardcoded white mark would have vanished against the disabled `surfaceVariant` fill. It reads `IconTheme` instead, which `ButtonStyleButton` populates with the state-aware foreground. On **web the relationship inverts**: Google's button cannot be restyled and is the only source of the ID token the backend verifies, so **its preset is chosen first and Apple is built to match** — and matching means 40px, against `Button`'s pinned 48px floor. Resolved as the tap-target rule itself prescribes, **grow the target not the glyph**: a 48px `<button>` around a 40 × 320 painted `<span>`, so neither the floor nor its test is weakened. **Gates, where none existed:** `login_screen_test.dart` overrides the platform to iOS — the first time anything in this repo has rendered the Apple button — and asserts the two buttons are **the same size**, so a divergence in type or padding cannot quietly return; `social-buttons.test.ts` pins the shared GIS object and that **`text` is the only key allowed to vary**; and the golden's fake specimen is replaced by the real pair, enabled **and disabled**, which is the only artefact that can show a mark going invisible. 🟢 |

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
