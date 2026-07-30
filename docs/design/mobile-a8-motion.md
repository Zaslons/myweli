# mobile-a8-motion — five tokens, and the app finally listens when the OS says stop (A8)

**Status:** ✅ Shipped (2026-07-26). **Surface:** `mobile/` — every animation,
plus a `web/` constraint. **Design system:**
[SYSTEM.md §9](SYSTEM.md#9-motion) · [§13](SYSTEM.md#13-accessibility) ·
[§20/§20.1](SYSTEM.md#20-enforcement) ·
[§21](SYSTEM.md#21-the-known-violations-register) rows 8 & 20. **Twin:** the web
shipped the same five tokens in **B2a** (`web/styles/tokens.ts:215`) and its
`motion-reduce:` guards in **B6**. **Roadmap:** design-system programme, mobile
A-series slice A8.

## Goal & the debt

§21 row 8 (motion tokens) and row 20 (reduced motion) are the last coherent
design-system subsystem with nothing built. §9 already specifies the answer in
full — five tokens, exact values, exact curves — so the token half is a **port**,
not a design. The reduced-motion half is not: it is the only §9 clause the
framework will not do for us.

## ⚠️ The census disproved row 8 — and the correction changes what the slice does

| Row 8's claim | Measured at base (`31ce0e8`) |
|---|---|
| "**12 distinct durations**" | The 12 is the count of distinct `Duration(milliseconds:)` literals **app-wide, blind to category**. Only **6 are motion**; the method also missed a 7th (`Duration(seconds: 6)`) by reading only the `milliseconds:` constructor. **Real: 7 distinct animation durations across 9 sites.** |
| "**0 constants**" | **False.** Nine named `Duration` constants exist, one of them motion (`_storyDuration`). The defensible claim is *"0 motion tokens in `AppTheme`"* — and that one is exactly right: `app_theme.dart` holds zero `Duration`, `Curve` or `Interval`. |
| Row 20, "**0**" | **Confirmed**, genuinely zero. |

**And the rows are nearly disjoint: closing row 8 does not move row 20.** The
vestibular exposure is two `repeat: true` Lotties, three indeterminate spinners
and a 6-site involuntary 350 ms scroll — **none of which is one of the counted
numbers**. The register points at expand/collapse tweens; the harm is elsewhere.
That is why this slice does reduced motion **first**.

## A live bug, shipping today

`story_viewer.dart:56` drives a **6-second content dwell** on a
default-behaviour `AnimationController`, advanced with `.forward()`. Verified in
the SDK: `forward()` → `_animateToInternal` → `animation_controller.dart:651`,
which scales `AnimationBehavior.normal` controllers to **0.05** when
`SemanticsBinding.instance.disableAnimations` is true.

By that reading, Android's "Remove animations" should collapse each story to
300 ms and finish a five-story reel in 1.5 s. The 6 s is a *reading time*, not
motion — the case the SDK's own `AnimationBehavior.preserve` doc describes.

**⚠️ Not confirmed, therefore not fixed — and it shipped that way.** Two
attempts to gate it both refused to go red: a controller built with `preserve`
tests the SDK rather than us, and pumping the real `StoryViewer` and counting
`onViewed` calls is **green at base** — so either the scale is not reached on
this path, or `onViewed` does not fire per advance. The SDK reading is sound and
the risk is real, but a gate that will not fail is not a gate, and fixing an
unreproduced bug ships a change nobody can justify.

**The open question, stated for whoever picks it up.** Reproduce it on a device
with *Remove animations* on: if a five-story reel finishes in ~1.5 s, the fix is
one argument (`AnimationBehavior.preserve` on `_progress`) and §9.1 already
carries the rule. What A8 *did* fix on that screen is the page **advance** — a
full-screen slide the user did not ask for — which is a different animation on
the same widget.

## Why the SDK does not do this for us

Measured, not assumed:

| Thing | Auto-honoured? |
|---|---|
| Route transitions, `Hero`, every implicit `AnimatedX` | **Yes** — plain controllers, so they hit the 0.05 scale |
| `SnackBar` entrance/exit | Yes — but its **dismiss timeout is a `Timer`**, untouched. A6's boundary, mechanically confirmed |
| **`repeat()`** | **No.** It calls `_startSimulation` directly and never reaches the scale |
| Lottie's own ticker, `CircularProgressIndicator`'s internal repeat | **No** |

**So §9's first clause is nearly free, and its second clause — "looping/decorative
animation stops" — is 100 % manual.** That second clause is this slice.

## §9's rule is an iOS no-op, as written

`FlutterViewController.mm:2159` maps iOS "Reduce Motion" to `kReduceMotion`.
`kDisableAnimations` does not appear in any Darwin embedder, and
`grep -rn "reduceMotion" packages/flutter/lib/` returns **zero** — the framework
reads it nowhere. Only Android sets `disableAnimations`, and only when
*Transition animation scale* is **exactly 0**.

A8 therefore honours **both** flags and amends §9 to say so. The iOS half needs a
`WidgetsBindingObserver`, because `PlatformDispatcher.accessibilityFeatures` is
not an `InheritedWidget` and will not rebuild on change.

## The web is ahead, and it constrains this PR

`web/styles/tokens.ts:215` already ships §9's five tokens, closed in the Tailwind
theme since **B2a**, plus **7 `motion-reduce:` guards** (B6). Mobile has 0 and 0.
Curves are explicitly **mobile-first** — `tokens.ts:214` defers them to "the
motion slice", which is this one.

Two hard constraints follow:

- **A new `lib/core/theme/motion.dart` fails the web's blocking vitest job.**
  `dart-tokens.mjs:200` pins the theme directory's file manifest *deliberately*,
  to force this decision rather than let a token source go unread. Either the
  constants live in `app_theme.dart`, or the file is added **and**
  `dart-tokens.mjs` taught in the same PR — never two sources.
- **§9's markdown table is machine-parsed.** Heading exactly `## 9. Motion`;
  cells `` `motionX` | Nms | `` with backticks, no bold, no space before `ms`. A
  bolded or re-spaced cell silently vanishes from the mirror and the row-count
  check throws.

## What this slice will NOT do, and why

- **No test-suite simplification.** Making the loader static does *not* let
  `pumpAndSettle` replace the 18 hand-rolled `settle()` ladders: a pending
  `Future.delayed` schedules no frame, so `pumpAndSettle` would return **early**
  with the screen still loading. It converts a loud timeout into a silent
  wrong-state pass. The ladders stay.
- **No global flag.** `accessibilityFeaturesTestValue` is process-global — set it
  per-test in the helper, never in a `flutter_test_config.dart`. Same argument
  `golden.dart:56` already makes for fonts.
- **A6's snackbar 3/6/10 s stay out of scope** (§15 owns them). The
  argument-position pin cannot reach them anyway — they are positional enum
  arguments — which is the right answer for the right reason.
- **§12's "~300 ms" spinner heuristic is not a motion token**, despite colliding
  numerically with `motionEmphasis`. Stated here so nobody tokenises it.

## What shipped, and what each gate cost

The working rule held: **no sweep commit landed before the gate commit that
proved it.** Reds measured and quoted in every message.

| Commit | Gate → red | Sweep |
|---|---|---|
| ① | loader animates (control) · stops under the flag · says « Chargement… » · a still frame | — |
| ①b | the **iOS flag alone** · the flag raised **mid-session** · every root installs the observer · correct with **no scope** | — |
| ①c | a `Semantics` label in **both** modes · **exactly one** node says it | — |
| ② | — | the accessor + observer · `BrandLoader` · the splash · 3 spinners · 2 involuntary movements. **9 mutations** |
| ③ | `Duration(milliseconds:` **10** · `Curves.` **7** | — |
| ④ | — | 7 sites → `AppMotion` · the three-legged mirror. **4 web mutations** |
| ⑥ | the reel throws · the splash is blank · the caption overflows — **+12 −3** | — |
| ⑦ | — | `jumpToPage` · `AlwaysStoppedAnimation(1)` · a measured caption bound. **9 mutations, one of which changed the gate** |
| ⑧ | — | the pin holes: hand-rolled curves, seconds, `core/router/`, and the doc's Curve column. **6 mutations** |

### Five things this slice got wrong first, and how each was caught

1. **The planned pin design did not survive its own sweep.** Argument-position
   (`duration:` + `Duration(` on one line) measured 8/8 before ② and **5/8**
   after — ② had turned three hits into ternaries. It would have gated only the
   code A8 did not touch. Caught by re-measuring instead of trusting the number
   in the plan.
2. **①c could not have gone green.** `addTearDown(handle.dispose)` runs *after*
   `_endOfTestVerifications`, so the semantics tests would have failed on a live
   handle whatever they found. Its red was real; its green was unreachable.
3. **`animate: false` renders nothing.** Frame 0 of a draw-on loader is an empty
   canvas, so "freeze the mark" froze a blank box with a caption under it. The
   property assertion passed. **The golden is what caught it** — and the fix is
   the still brand mark the animation draws towards (`myweli_mark_black.svg`).
4. **`// ds-ignore` silently stopped applying.** `dart format` reflowed two
   trailing escapes into a block body, where the pin does not look. The escape
   has to sit on the offending line; two of the three now name their value so
   the formatter cannot move it.
5. **The golden diff the plan predicted did not happen.** Six durations changed
   and not one baseline byte moved: a golden photographs the end state, not the
   tween. Recorded in §20.1 as a limit — no golden can catch a duration
   regression.

### ⑥–⑧ — the adversarial review, and the three defects it found in A8's own work

**Writing the gate before the sweep was necessary and not sufficient.** ①–①c
were four gate commits, and every assertion in all four pumped `BrandLoader`.
Six `reduceMotionOf` call sites shipped; five were asserted by nothing. All
three defects below lived in those five.

| Defect | Why no gate saw it | Evidence |
|---|---|---|
| **The story reel threw** on its first advance under the flag | nothing pumped `StoryViewer` | `assert(duration > Duration.zero)`, `scroll_activity.dart:705`. `Duration.zero` is a jump for `Scrollable.ensureVisible` (`scroll_position.dart:872` special-cases it) and a crash for `PageController`. I read one API and generalised to the other |
| **The splash rendered a blank screen for 3800 ms** | nothing pumped `SplashScreen` | the bug ⑤ had just documented fixing in `BrandLoader`, shipped one file over. All six glyph layers of `myweli_loader_mixed.json` open at opacity 0 and `redraw` is not in-point until frame 54. **Confirmed by rendering it** before believing the JSON |
| **The caption overflowed a 60px avatar by 44px** | the gates pumped an unbounded box | `LoadingIndicator` never passes `fast`, so ~50 sites took the caption branch. The review estimated ~20px; measured, it is 44 |

Two more findings were about the gates rather than the code, and both were real:

- **"a bare MaterialApp still honours the flag" was vacuous.** It set *both*
  flags, so `MediaQuery` answered at the accessor's first line and the no-scope
  fallback the test exists to check was never evaluated — replacing that whole
  fallback with `?? false` kept the entire suite green.
- **The mirror's Curve column was pinned against itself.** `parseMdTable` reads
  the name and the milliseconds and stops; `dartMotionCurves` was compared to a
  **hardcoded literal in the test file**. Editing §9's curve cell was a green CI
  job — while ④'s commit message claimed the mirror covered "including the curve
  pairing".

**And one gate had to be strengthened mid-fix.** "the reel advances instead of
throwing" passed when the reel ignored the flag *entirely*: it only proved
non-crashiness. It measures `PageController.page` now and has a motion-ON leg,
so both "jumps for nobody" and "jumps for everybody" go red. The fix was correct
and the gate was not — which is the whole reason to run the mutations.

`expectHonoursReducedMotion` was deleted in the same round: 48 lines carrying
this slice's most emphatic doctrine, zero call sites, exactly the shape A7's fix
commit deleted `unvalidatedKeys` for. A generic geometry probe would have passed
the reel that jumped for everybody — the abstraction fit none of its intended
callers, and that is why it had none.

### Also weaker than it reads, and left as written

"…and STOPS under reduced motion" is satisfied by `repeat: false` alone: a
non-repeating Lottie runs a plain controller, so the framework's 5 % scale
finishes it inside the 400 ms pump. The iOS-alone, mid-session and
no-Lottie assertions each catch what it misses, so the *suite* is sound — but the
assertion does not prove what its name claims, and saying so is cheaper than
pretending otherwise.

## What this slice did NOT do, and why

- **The story-dwell fix** — unreproduced; see above.
- **The framework's iOS blindness** — `_animateToInternal` reads
  `disableAnimations`, which no Darwin embedder sets. Our own animations honour
  both flags; route transitions and implicit `AnimatedX` still do not, on iOS.
  There is no supported override. **§21 row 33.**
- **No test-suite simplification.** A static loader does *not* let
  `pumpAndSettle` replace the 18 hand-rolled `settle()` ladders: a pending
  `Future.delayed` schedules no frame, so `pumpAndSettle` returns **early** with
  the screen still loading — a loud timeout traded for a silent wrong-state pass.
- **A6's snackbar 3/6/10 s stay out of scope** (§15 owns them).
- **§12's "~300 ms" spinner heuristic is not a motion token**, despite colliding
  numerically with `motionEmphasis`.

## The lesson, stated plainly

The slice's whole premise was *gate first, then sweep* — and it still shipped a
crash, a blank splash and a 44px overflow. The premise was not wrong; it was
incomplete. **Four gate commits all pointed at the same widget.** Gate-first
guarantees the rule is executable; it guarantees nothing about coverage. The
question a gate commit has to answer is not "did I write a test before the fix"
but *"which call sites does this test not reach"* — and A8 could have answered
it at any point with one grep, because `reduceMotionOf` had six callers and the
tests named one.

## Definition of done — met

Rows 8 & 20 → **0** with the counts corrected rather than restated · both pins
green, reds recorded · reduced motion honoured on **both** platforms, with the
residue recorded as row 33 · the loader static, labelled and now **goldened** ·
the splash frozen with its 3800 ms intact · §9 rewritten + §9.1 added · §13
cross-referenced · §20 gains a motion row · §20.1's loader caveat halved · web
vitest green (485) · mobile **734** · `analyze` 0 · ROADMAP (French) · an
adversarial review run, its three code findings fixed and gated, its two gate
findings fixed, and the one claim it disproved (the curve mirror) corrected in
the doc that made it.
