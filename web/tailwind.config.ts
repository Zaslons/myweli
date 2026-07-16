import type { Config } from 'tailwindcss';
import defaultTheme from 'tailwindcss/defaultTheme';
import {
  colors,
  motion,
  radius,
  screens,
  spacing,
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
      // ─── The sizing carve-out → B2c ────────────────────────────────────────
      // Tailwind's `spacing` key does not only feed padding/margin/gap — it also
      // feeds width/height/size/min-*/max-h/maxWidth/inset/translate, which are
      // SIZES, not rhythm. Closing it outright would delete 23 layout dimensions
      // (96→320px: map heights, the sidebar, avatars) that have no legal token
      // and shouldn't — the web has no sizing scale (docs/design/ covers icons
      // only, SYSTEM.md §7) — and would move pixels on 24 more.
      //
      // So `spacing` is closed as the RHYTHM scale (`p-4` is dead) and the
      // sizing keys keep the numeric scale until WEB-SYSTEM §9 gains a Sizing
      // subsection (§15 row 6b). `extend` merges INTO the resolved key, so
      // `w-60`, `w-full` and `w-m` all work while `p-4` still does not.
      width: defaultTheme.spacing,
      height: defaultTheme.spacing,
      size: defaultTheme.spacing,
      minWidth: defaultTheme.spacing,
      minHeight: defaultTheme.spacing,
      maxHeight: defaultTheme.spacing,
      maxWidth: defaultTheme.maxWidth, // a size by the same rule; nothing uses
      // `max-w-<number>` today, so this is consistency for B2c, not a live fix.
      inset: defaultTheme.spacing,
      translate: defaultTheme.spacing,
      // NOT carved out, deliberately: `spacing` also feeds `flexBasis`,
      // `borderSpacing`, `scrollMargin`, `scrollPadding` and `textIndent`, whose
      // numerics die too. Nothing uses them (verified), and none of them is a
      // "size" in the sense above — if one is ever needed, name a token rather
      // than widen this block.
    },
  },
  plugins: [],
};

export default config;
