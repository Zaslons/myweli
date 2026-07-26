# mobile-a8-motion — five tokens, and the app finally listens when the OS says stop (A8)

**Status:** In progress (2026-07-26). **Surface:** `mobile/` — every animation,
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

So with Android's "Remove animations" on, **each story shows for 300 ms and a
five-story reel is over in 1.5 seconds.** The 6 s is a *reading time*, not
motion — precisely the case the SDK's own `AnimationBehavior.preserve` doc
describes. Fixed here, and it is the slice's best proof-red for row 20.

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

## Tests & gates — written first, watched fail, then swept

The working rule for this slice: **no sweep commit lands before the gate commit
that proves it.** Reds measured at `31ce0e8`.

- **The pins** — argument-position, measured **8/8 precision, 0 false positives**:
  `duration:`/`transitionDuration:` + `Duration(` = **8**, `Curves.` = **7**. Two
  holes stated rather than papered over: `_storyDuration` (a named const, no
  literal) and the splash's `Future.delayed` dwell.
- **The reduced-motion gate must be TWO-LEGGED or it is vacuous.** The motion-ON
  leg proves the widget actually animates; the motion-OFF leg proves one 60 fps
  frame already lands at the end state. **16 ms is the discriminator**: 5 % of
  200 ms is 10 ms, so 16 ms ≫ 10 ms (settled with motion off) and 16 ms ≪ 200 ms
  (clearly mid-flight with motion on).
- **The loader** — `expect(tester.binding.hasScheduledFrame, isFalse)` after
  pumping under the flag. Red today: the Lottie schedules a frame forever.
- A `Duration.zero` property assertion is **not** a gate — the framework runs at
  5 %, not 0, deliberately (`animation_controller.dart:646`). Asserting what we
  *asked for* is the mistake `app_snack_bar_test.dart:52` already names.

## Definition of done

Rows 8 & 20 → **0** with both pins green and their reds recorded · the corrected
count in the register · reduced motion honoured on **both** platforms · the
loader static + labelled, the splash frozen with its timing intact, the story
dwell preserved · §9 amended (both flags, the loader's replacement, the
`preserve` rule for content timers) · §13 cross-referenced · §20 gains a motion
row **after** the gates exist · §20.1's loader caveat halved by the new static
golden · web vitest green · full battery · adversarial review · ROADMAP (French).
