# Myweli — design & UX standards (canonical)

The single reference for how Myweli UI looks and behaves. **Consult this — and the
part's design spec — before designing or building any UI.** Nothing in a screen
should invent a color, size, or pattern that isn't here. Source of truth for
tokens is the theme code; this doc explains how to use it + the UX rules.

> **Standing rule (also in the `myweli-dev-guardrails` skill):** before any
> UI/design work — _check this doc, the relevant `docs/design/<part>.md` spec,
> and the existing components_ first. Plan the UX and get sign-off, then build.
> After building, run the consistency sweep (§6). No hardcoded colors/sizes.

## 1. Identity
**Minimalist monochrome.** Black/white/gray dominate; **color is reserved for
status and the single primary action**, never decoration. Generous spacing,
rounded corners, semibold headlines. The admin console reuses the same identity,
adapted to a data-dense desktop tool ([admin-console-ui.md](admin-console-ui.md)).

## 2. Tokens — always use these, never literals
Defined in `mobile/lib/core/theme/`: `colors.dart`, `text_styles.dart`, `app_theme.dart`.

- **Colors → `AppColors`.** Surfaces (`surface`, `secondary`, `surfaceVariant`, `background`), text (`textPrimary/Secondary/Tertiary`), `border`/`divider`, and **semantic** (`success`/`error`/`warning`/`info` + `*Light`). **Status colors come from here** — `AppColors.success`, not `Colors.green`. Tints via `.withValues(alpha: …)`.
- **Type → `AppTextStyles`.** `headline*` (32/28/24, semibold), `title*` (22/16/14, medium), `body*` (16/14/12), `label*`. **No inline `fontSize:` / `TextStyle(...)`** — pick a scale entry and `.copyWith(color: …)` if needed.
- **Spacing → `AppTheme.spacing{XS,S,M,L,XL,XXL}`** = 4/8/16/24/32/48. **Radius → `AppTheme.radius{Small,Medium,Large,XL,XXL}`** = 4/8/12/16/24 (default cards = `radiusLarge`).
- **Only `Colors.transparent` / `Colors.black|white` (for scrims/overlays) are acceptable literals.** No `Color(0xFF…)` and no named `Colors.<hue>` in screens/widgets.

## 3. Components — reuse before you build
- **Common** (`lib/widgets/common/`): `AppButton` (primary/secondary/text; `isLoading`), `AppTextField`, `LoadingIndicator`, `EmptyState` (icon/title/description/action), `TimedCachedImage` (network + `asset:` + caching).
- **Admin** (`lib/screens/admin/widgets/`): `AdminScaffold` (sidebar + top bar), `AdminDataTable` (rows + loading/empty/error), `StatCard`, `StatusChip` (`StatusChip.forStatus(...)`), `showReasonDialog`.
- Need something new? Add it as a **shared widget**, don't one-off it inline.

## 4. UX rules (non-negotiable)
1. **Four states on every screen:** loading · empty · error (+ retry) · success. Happy-path-only is not done.
2. **French copy** everywhere (labels, errors, empty states); **FCFA / phone / duration** via `core/utils/` formatters; Ivorian taxonomy (PRD Appendix A).
3. **Reuse the pattern** of the surrounding code (interface+mock, Provider, go_router, DI) — don't invent a new shape.
4. **Plan the UX + get sign-off first** for user-facing work (goal, flow, all states, edge cases, interaction, copy, fit) — see the skill's "UX first" section.
5. **Accessibility:** ≥4.5:1 contrast (monochrome passes), tooltips on icon-only controls, dialog focus.
6. **Performance:** `const` where possible, paginate, lazy/cached images, low-end Android budget (ROADMAP Part 6).
7. **Market data & salon time:** market-specific facts — communes, Mobile Money operators, currency, timezone, phone prefixes — live **only** in their seams (`core/constants/communes.dart`, `core/utils/mobile_money.dart`, `core/utils/formatters.dart`, `core/utils/salon_time.dart` once built); displayed times and day boundaries are **salon time**, never the device's ([modules/multi-pays.md](../modules/multi-pays.md) §3/§9). Hardcoding a market fact elsewhere fails review, even when it works for CI.

## 5. Pre-build checklist (UI)
- [ ] Read this doc + the part's `docs/design/<part>.md` spec.
- [ ] UX planned (states + copy) and **signed off** (user-facing work).
- [ ] Tokens only (no literal colors/sizes); reuse existing components.
- [ ] Four states; French; formatters; CI locale fit.
- [ ] After: `flutter analyze` 0; the §6 sweep is clean for new/changed files.

## 6. Consistency sweep (run after UI work)
From `mobile/`, these must not grow (ideally → 0) in screens/widgets:
```
grep -rn --include='*.dart' "Color(0x" lib | grep -v lib/core/theme/
grep -rEn --include='*.dart' "Colors\.(red|green|blue|orange|grey|gray|amber|purple|teal|pink|yellow|indigo|cyan|brown)" lib | grep -v lib/core/theme/
grep -rn --include='*.dart' "fontSize:" lib | grep -v lib/core/theme/
```

## 7. Known deviations (tech debt — track + burn down)
Baseline `flutter analyze` = 0; **admin UI = 0 violations**.

**Fixed (UI-consistency cleanup, 2026-06-26):** the **semantic** color drift in live
screens — appointment **status** colors now go through `appointmentStatusColor()`
(`core/utils/status_colors.dart`) reused by the pro list/calendar/detail; the pro
**dashboard** stat accents → `AppColors.warning/success/info`; **star** ratings →
`AppColors.starRating`; **favorite** hearts → `AppColors.favorite`; the snackbar
error → `AppColors.error`. (~37 live `Colors.<named>` → tokens.)

**Sanctioned exceptions (deliberate, bounded — not debt; decided 2026-06-26):**
- **Service-category accents** — color *does* aid wayfinding on the map + category
  chips, so a small **muted/earthy** palette is allowed as an explicit exception to
  monochrome: `AppColors.categorySpa` (sage `#5B6B4F`), `categoryBarber` (taupe
  `#6D5A4C`), `categorySalon` (slate `#4F5B6B`), unknown → `primary`. **Always via
  `categoryColor()`** (`core/utils/category_colors.dart`) — never an inline hex; one
  source, used by `map_screen` + `highlight_stories`. Adding a category = add a token
  + a switch arm here.
- **"Unseen" story ring** — single warm gold `AppColors.starRating` (seen → neutral
  `AppColors.border`); the old gold→pink gradient is retired.
- **Map-marker semantics** — now tokens: rating star → `starRating`, favorite →
  `favorite`, "you are here" dot → `info` (white outline kept for contrast).
- **Story scrims** (`story_viewer` / `announcement_stories` black→transparent
  gradient) — neutral readability overlays; **acceptable** literal (alpha black).

**Remaining (separate follow-ups):**
- **~39 in deferred V2/V3 `screens/provider/features/*`** (flag-hidden `ComingSoon`) — fix if/when un-shelved.
- A few inline `fontSize:` / `TextStyle(` (OTP digit fields, `provider_detail`) — minor; fold into the next pass.
