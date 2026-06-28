// Shared design tokens — mirror of the Flutter theme (mobile/lib/core/theme).
// One source of truth for the web; keep in sync with WEB-DESIGN-STANDARDS.md.
// (Automating the Flutter→web export is a later nicety; values are mirrored here.)

export const colors = {
  primary: '#000000',
  primaryLight: '#1A1A1A',
  secondary: '#FFFFFF', // card background
  secondaryVariant: '#F5F5F5',
  background: '#F6F7F9',
  surface: '#FAFAFA', // page background
  surfaceVariant: '#F5F5F5',
  textPrimary: '#000000',
  textSecondary: '#4A4A4A',
  textTertiary: '#8A8A8A',
  textDisabled: '#C0C0C0',
  divider: '#E0E0E0',
  border: '#D0D0D0',
  success: '#2D5016',
  successLight: '#4A7C2A',
  error: '#8B0000',
  errorLight: '#DC143C',
  warning: '#6B5B00',
  info: '#1A1A2E',
  starRating: '#FFB800',
  favorite: '#E53935',
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
