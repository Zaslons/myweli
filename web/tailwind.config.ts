import type { Config } from 'tailwindcss';
import defaultTheme from 'tailwindcss/defaultTheme';
import {
  colors,
  icon,
  motion,
  radius,
  screens,
  spacing,
  type,
  zIndex,
} from './styles/tokens';

const config: Config = {
  content: ['./app/**/*.{ts,tsx}', './components/**/*.{ts,tsx}'],
  theme: {
    // ─── CLOSED (WEB-SYSTEM.md §2) ───────────────────────────────────────────
    // These are `theme`, not `theme.extend`: `extend` ADDS to Tailwind's default
    // scales, so `bg-red-500` and `rounded-2xl` kept working and the token
    // discipline was a convention rather than a constraint. Replacing the key
    // means a non-token utility simply does not exist.
    //
    // The hazard this creates — and why the gate is lint, not review:
    // **Tailwind does not error on an unknown utility, it emits nothing.**
    // `className="bg-red-500"` is not a build failure here; it is an element
    // with no background, shipped. `tailwindcss/no-custom-classname`
    // (.eslintrc.js) is what actually holds this, and
    // `tests/tokens.theme-pin.test.ts` covers what lint cannot see (classes in
    // bare `const` strings).
    colors: { transparent: 'transparent', ...colors },
    borderRadius: radius, // no DEFAULT: bare `rounded` is dead on purpose (§15 row 6)
    spacing,
    zIndex,
    screens,
    transitionDuration: motion,
    // B2b. `text-sm` and friends no longer exist — a class now says what the text
    // IS (`text-bodyMedium`), not how big it happens to be. Tailwind's 18/20/30px
    // steps have no counterpart in a Material 11/12/14/16/22/24/28/32 scale, which
    // is exactly how the same role ended up at three: of 42 `<h2>` on main, 23 were
    // 18px, 15 were 20px and 4 carried no size at all — the drift a closed scale
    // exists to kill. (Those 4 still carry no type token; see §15.)
    // B2c adds §7's icon scale beside the type roles: every icon on the web is a
    // text character, so its size IS a font-size. `text-iconM` says "a 24px
    // icon"; `text-titleLarge` on a ✕ said "a card/section heading".
    fontSize: { ...type, ...icon },

    // ─── maxWidth: CLOSED, and a real leak fixed (B2c) ──────────────────────
    // Tailwind's own `maxWidth` spreads `theme('spacing')` FIRST and then lays
    // its named rem steps on top. With `spacing` closed to the rhythm tokens
    // that produced a live landmine: `max-w-s`=8px, `max-w-m`=16px,
    // `max-w-l`=24px, `max-w-xxl`=48px, `max-w-xxxl`=64px — rhythm tokens acting
    // as max-widths — while `max-w-sm`=24rem and `max-w-xl`=36rem, because
    // Tailwind's names win wherever they collide. So `max-w-l` (24px) and
    // `max-w-xl` (576px) sat adjacent in one naming scheme, 24× apart, and an
    // author reading `max-w-sm` as "the sm token" was wrong by 32×.
    //
    // Written out rather than spread from the default, so the `spacing` leak
    // cannot come back. The 7 steps in use are byte-identical (verified).
    // NOTE the function form: Tailwind's default also spreads
    // `breakpoints(theme('screens'))` to give `max-w-screen-sm…2xl`. A static
    // object drops those five silently — which is precisely the trap the ⚠️ below
    // warns about for width/height, and I walked into it one block earlier.
    // Nothing uses them today, but keeping the spread means `maxWidth` still
    // tracks `screens` when a breakpoint changes.
    maxWidth: ({ breakpoints, theme }) => ({
      ...breakpoints(theme('screens')),
      none: 'none',
      xs: '20rem',
      sm: '24rem',
      md: '28rem',
      lg: '32rem',
      xl: '36rem',
      '2xl': '42rem',
      '3xl': '48rem',
      '4xl': '56rem',
      '5xl': '64rem',
      '6xl': '72rem',
      '7xl': '80rem',
      full: '100%',
      min: 'min-content',
      max: 'max-content',
      fit: 'fit-content',
      prose: '65ch',
      // SYSTEM.md §10's `contentMaxWidth = 720` — the ONE non-icon dimension the
      // design system names, and it had never been implemented on either surface
      // (it lives in §10 as prose, and in no code). Naming it here is a
      // convergence, not an invention. §10: "text and forms never stretch past
      // it — a 1000px-wide line of French body copy is unreadable." Applying it
      // to the pages that need it is a layout decision, not a token one (§15).
      content: '720px',
    }),

    // These derive from `colors`, whose palette we just replaced. Tailwind's own
    // defaults use the *fallback* form — `theme('colors.gray.200', 'currentColor')`,
    // `theme('colors.blue.500', '#3b82f6')` — so with `gray`/`blue` gone they do
    // NOT break; they quietly land on the fallback. That is the problem: measured,
    // unpinned resolves `borderColor.DEFAULT` and `divideColor.DEFAULT` to
    // `currentColor` (main had `#e5e7eb`), so every un-coloured border would
    // silently start following the text ink, and `ringColor.DEFAULT` would stay
    // the off-palette `#3b82f6`. Pinning keeps them on-token.
    borderColor: ({ theme }) => ({ ...theme('colors'), DEFAULT: colors.divider }),
    divideColor: ({ theme }) => theme('borderColor'),
    ringColor: ({ theme }) => ({ ...theme('colors'), DEFAULT: colors.primary }),
    ringOffsetColor: ({ theme }) => ({
      ...theme('colors'),
      DEFAULT: colors.secondary,
    }),

    extend: {
      // ─── Sizing stays open. That is the decision, not a deferral (B2c) ─────
      // B2a carved these out "until the web gets a sizing scale". B2c checked
      // that premise and it does not hold: **sizing is not a token class in this
      // design system.** `AppTheme` has exactly 19 constants — 8 spacing, 6
      // radius, 5 icon — and nothing else. Mobile sizes every box with a raw
      // number (`ProviderCard._imageHeight = 180`, `JournalGrid.AXIS_W = 56`),
      // its pin deliberately cannot see them (the spacing regex requires `)`
      // straight after the number, so a *sized container* never matches), and
      // that pin calls its firewall "complete" regardless. SYSTEM.md §5 governs
      // grid gaps, not overlay sizing.
      //
      // So a web-only sizing scale would be a FOURTH mirror divergence — after
      // `gold`, `sm`/`xxxl` and §4's tracking — with no upstream for B3's
      // generator to track. `w-60` is a layout dimension, and the system's
      // answer to those is a named constant at the call site (and, for anything
      // bounding text, `AppTheme.textScaledBound` + A5's "prefer intrinsic").
      //
      // ⚠️ IF YOU EVER DO CLOSE THESE, READ THIS FIRST. Each key's literals —
      // `w-full` (58 uses!), `h-auto`, `w-1/2`, `left-1/2`, `-translate-x-1/2`,
      // `h-screen`, `min-h-screen` — do NOT come from `spacing`. They live in the
      // key's OWN default block. Writing `theme.width = {…}` deletes all of them,
      // silently: 112 of the 250 sizing usages, 45%. Preserve the function form
      // and re-include the literals, or measure the emitted CSS and watch half
      // the layout vanish with a green build.
      width: defaultTheme.spacing,
      height: defaultTheme.spacing,
      minWidth: defaultTheme.spacing,
      minHeight: defaultTheme.spacing,
      maxHeight: defaultTheme.spacing,
      inset: defaultTheme.spacing,
      translate: defaultTheme.spacing,
      // `size` is NOT here: `size-*` has 74 keys and zero uses — all 17 square
      // elements spell `h-N w-N`. The carve-out was dead weight.
      //
      // Also not here, and dead for the same reason as `p-4`: `spacing` feeds
      // `flexBasis`, `borderSpacing`, `scrollMargin`, `scrollPadding` and
      // `textIndent` too. Nothing uses them — if one is ever needed, name a
      // token rather than widen this block.
    },
  },
  plugins: [],
};

export default config;
