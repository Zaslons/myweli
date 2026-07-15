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
} as const;

export const spacing = {
  xs: '4px',
  s: '8px',
  m: '16px',
  l: '24px',
  xl: '32px',
  xxl: '48px',
} as const;
