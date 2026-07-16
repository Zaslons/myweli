// Shared design tokens — the web mirror of the Flutter `AppColors`
// (mobile/lib/core/theme/colors.dart). Kept hand-synced with it and with
// docs/design/SYSTEM.md §3; the values, ratios and usage rules live there.
// (A Flutter→web generator + a CI drift gate is slice B3; until then, hand-synced.)
// `tests/tokens.contrast.test.ts` asserts every floor below is met.

export const colors = {
  // Brand vs ink (SYSTEM.md §1): `primary` is the thing you look AT (fills, the
  // logo, the focus ring); `textPrimary` is the ink you read THROUGH. Text is
  // never `primary`; nothing on web fills or strokes with `textPrimary`.
  primary: '#000000', // brand — never body text
  primaryHover: '#333333', // the hover/pressed step off primary
  secondary: '#FFFFFF', // card background
  secondaryVariant: '#F5F5F5',
  background: '#F6F7F9', // the scaffold
  surface: '#FAFAFA', // page background
  surfaceVariant: '#F5F5F5',
  // Text — the ink. textTertiary is the lightest legal text (4.76:1); there is
  // nothing below it. textDisabled is exempt, but legible-inert, not blank.
  textPrimary: '#1A1A1A', // 16.24:1 — AAA
  textSecondary: '#4A4A4A', // 8.27:1
  textTertiary: '#6E6E6E', // 4.76:1 — the AA floor
  textDisabled: '#9E9E9E', // 2.50:1 — disabled controls only
  // Borders — three roles (SYSTEM.md §3.3). `divider`/`border` are decorative and
  // exempt; `borderStrong` is the mandatory boundary of an interactive control.
  divider: '#E0E0E0', // decorative rules
  border: '#D0D0D0', // container hairlines
  borderStrong: '#8A8A8A', // 3.22:1 — interactive control boundaries (WCAG 1.4.11)
  // Semantic (status only)
  success: '#2D5016',
  successLight: '#4A7C2A',
  error: '#8B0000',
  errorLight: '#DC143C',
  warning: '#6B5B00',
  info: '#1A1A2E',
  // Accents. `gold` (3.04:1) is gold-as-STATE. `starRating` (1.62:1) is the fill
  // of a rating-star glyph and nothing else — currently unused on web, which
  // renders `★` in ink/neutral (an amber-star parity pass would revive it).
  gold: '#B8860B', // 3.04:1 — the owner chip, unseen-story ring, etc.
  starRating: '#FFB800',
  favorite: '#E53935',
  // Category accents (a sanctioned exception to monochrome), via markerColor().
  categorySpa: '#5B6B4F',
  categoryBarber: '#6D5A4C',
  categorySalon: '#4F5B6B',
} as const;

export const radius = {
  sm: '4px',
  md: '8px',
  lg: '12px',
  xl: '16px',
  xxl: '24px',
  // Fully-rounded. `pill` is a *shape*, not a number — chips, avatars, badges
  // (SYSTEM.md §6, mirroring `AppTheme.radiusPill`). It replaces `rounded-full`,
  // which was Tailwind's default key and dies with the closed theme (§2).
  pill: '999px',
} as const;

// The RHYTHM scale — padding, margin, gap (SYSTEM.md §5's 8pt grid).
//
// Tailwind's `spacing` key also feeds `w-`/`h-`/`size-`/`min-*`/`max-h-`/`inset-`/
// `translate-`, which are SIZES, not rhythm — and the web has no sizing scale yet
// (docs/design/ covers icons only, SYSTEM.md §7). So `tailwind.config.ts` closes
// this scale for rhythm and carves the sizing keys out until B2c. See §2.
export const spacing = {
  0: '0px', // inset-0 / top-0 / min-w-0 — 38 uses, and not a "spacing value"
  xs: '4px',
  s: '8px',
  // The sanctioned half-step (SYSTEM.md §5): 8 too tight, 16 too loose for dense
  // UI. Mobile named it `spacingSM`; the web mirror had silently dropped it.
  sm: '12px',
  m: '16px',
  l: '24px',
  xl: '32px',
  xxl: '48px',
  xxxl: '64px', // mirrors `AppTheme.spacingXXXL` — the second mirror drift (see §15 row 19)
} as const;

// Layering (WEB-SYSTEM.md §9). The scale is the LAYER, named — never a number.
// Ties are resolved by DOM order, so if two things at the same layer can coexist,
// one of them is at the wrong layer.
export const zIndex = {
  base: '0', // content
  sticky: '10', // sticky headers, the map's floating controls
  dropdown: '20', // menus, popovers, in-page panels
  overlay: '30', // scrims
  modal: '40', // dialogs, sheets, the mobile drawer
  toast: '50', // feedback — always on top
  // Load-bearing, not redundant: at `lg:` the pro sidebar is a FLEX ITEM, and
  // z-index applies to flex items whatever their `position`. `base` (0) is NOT a
  // substitute — 0 creates a stacking context and would trap the salon-switcher
  // dropdown inside the aside; `auto` does not.
  auto: 'auto',
} as const;

// Motion (SYSTEM.md §9). Durations only — the easing curves have no Tailwind
// equivalent and land with the motion slice (A9).
export const motion = {
  // Load-bearing: every bare `transition`/`transition-colors` reads
  // `transitionDuration.DEFAULT`. Drop it and they all become INSTANT — silently.
  //
  // It is also the slice's one deliberate rendering change: Tailwind's stock
  // DEFAULT is 150ms, SYSTEM.md §9's `motionBase` is 200. The three sites with a
  // bare `transition*` and no `duration-` sibling get 33% slower: `Button.tsx`
  // (its shared `base` string — i.e. EVERY button hover) and the two
  // notifications toggles. Imperceptible, but real, and now on the record.
  DEFAULT: '200ms', // = base, SYSTEM.md §9's "the default"
  stagger: '50ms',
  fast: '100ms', // immediate state feedback
  base: '200ms', // most transitions
  emphasis: '300ms', // entering surfaces
  slow: '400ms', // large surfaces
} as const;

// Breakpoints (WEB-SYSTEM.md §9) — Tailwind's own values, pinned so a sixth
// cannot appear. `xl`/`2xl` are unused today and stay anyway: §9 says their
// ABSENCE is the bug (the pro dashboard is a stretched phone column), so the
// desktop work needs them.
export const screens = {
  sm: '640px',
  md: '768px',
  lg: '1024px',
  xl: '1280px',
  '2xl': '1536px',
} as const;
