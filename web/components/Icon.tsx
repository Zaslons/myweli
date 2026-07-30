import { icon as iconSizes } from '../styles/tokens';

/// The shared icon (§15 row 7i, B6) — ONE component over a named path
/// registry, sized by §7's five-token scale, `currentColor` fill.
///
/// Before B6 the svg icons were sized through two channels (Tailwind classes
/// on two, raw width/height attrs on three) and the same Material paths were
/// copy-pasted inline in two private registries (`salon-pin.tsx` ICON_PATHS,
/// `NotificationsClient` TYPE_PATHS). This registry consolidates them.
///
/// The honest channel doctrine (web-b6-components.md):
/// - Text-character glyphs (✕ ★ ♥ ⋯) are NOT this component's job — a
///   character's size IS a font-size (WEB-SYSTEM §3); they keep `text-icon*`.
/// - The 44px `.myweli-pin` is marker/tap GEOMETRY hosting an on-scale 20px
///   <Icon>; the 22px user dot is a dot. Neither is an icon size.
/// - The hamburger stays a stroke svg in ProShell — the one stroke icon;
///   redrawing it filled would change its look for zero doctrine gain.
///
/// All paths are Material Design icons (Apache 2.0), outlined style (§16),
/// 24×24 viewBox.
export const ICON_PATHS = {
  // Notifications (the 7 per-type glyphs)
  bookingConfirmed:
    'M12 2a10 10 0 1 0 0 20 10 10 0 0 0 0-20zm-1.2 14.4L6.4 12l1.4-1.4 3 3 5.4-5.4 1.4 1.4-6.8 6.8z',
  depositReceived:
    'M21 7H5a1 1 0 0 1 0-2h14V3H5a3 3 0 0 0-3 3v12a3 3 0 0 0 3 3h16a1 1 0 0 0 1-1V8a1 1 0 0 0-1-1zm-4 7a1.5 1.5 0 1 1 0-3 1.5 1.5 0 0 1 0 3z',
  reminder:
    'M12 22a9 9 0 1 1 0-18 9 9 0 0 1 0 18zm.5-13.5h-1.5V14l4 2.4.75-1.23-3.25-1.92V8.5zM5 2 1.5 5l1.3 1.3L6.3 3.3 5 2zm14 0-1.3 1.3 3.5 3L22.5 5 19 2z',
  reschedule:
    'M12 6V3L8 7l4 4V8a4 4 0 0 1 3.9 4.9l1.5 1.1A6 6 0 0 0 12 6zm0 10a4 4 0 0 1-3.9-4.9L6.6 10A6 6 0 0 0 12 18v3l4-4-4-4v3z',
  cancellation:
    'M12 2a10 10 0 1 0 0 20 10 10 0 0 0 0-20zm4.3 12.9-1.4 1.4L12 13.4l-2.9 2.9-1.4-1.4 2.9-2.9-2.9-2.9 1.4-1.4 2.9 2.9 2.9-2.9 1.4 1.4-2.9 2.9 2.9 2.9z',
  reviewRequest:
    'M12 17.3 6.2 21l1.5-6.6L2.5 9.9l6.7-.6L12 3l2.8 6.3 6.7.6-5.2 4.5L17.8 21z',
  bell: 'M12 22a2 2 0 0 0 2-2h-4a2 2 0 0 0 2 2zm6-6v-5a6 6 0 0 0-4.5-5.8V4.5a1.5 1.5 0 0 0-3 0v.7A6 6 0 0 0 6 11v5l-2 2v1h16v-1l-2-2z',
  // Category markers (spa · content_cut · face · store_mall_directory)
  spa: 'M15.49 9.63c-.18-2.79-1.31-5.51-3.43-7.63-2.14 2.14-3.32 4.86-3.55 7.63 1.28.68 2.46 1.56 3.49 2.63 1.03-1.06 2.21-1.94 3.49-2.63zM12 15.45C9.85 12.17 6.18 10 2 10c0 5.32 3.36 9.82 8.03 11.49.63.23 1.29.4 1.97.51.68-.12 1.33-.29 1.97-.51C18.64 19.82 22 15.32 22 10c-4.18 0-7.85 2.17-10 5.45z',
  barber:
    'M9.64 7.64c.23-.5.36-1.05.36-1.64 0-2.21-1.79-4-4-4S2 3.79 2 6s1.79 4 4 4c.59 0 1.14-.13 1.64-.36L10 12l-2.36 2.36C7.14 14.13 6.59 14 6 14c-2.21 0-4 1.79-4 4s1.79 4 4 4 4-1.79 4-4c0-.59-.13-1.14-.36-1.64L12 14l7 7h3v-1L9.64 7.64zM6 8c-1.1 0-2-.9-2-2s.9-2 2-2 2 .9 2 2-.9 2-2 2zm0 12c-1.1 0-2-.9-2-2s.9-2 2-2 2 .9 2 2-.9 2-2 2zm6-7.5c-.28 0-.5-.22-.5-.5s.22-.5.5-.5.5.22.5.5-.22.5-.5.5zM19 3l-6 6 2 2 7-7V3h-3z',
  salon:
    'M9 11.75c-.69 0-1.25.56-1.25 1.25s.56 1.25 1.25 1.25 1.25-.56 1.25-1.25-.56-1.25-1.25-1.25zm6 0c-.69 0-1.25.56-1.25 1.25s.56 1.25 1.25 1.25 1.25-.56 1.25-1.25-.56-1.25-1.25-1.25zM12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm0 18c-4.41 0-8-3.59-8-8 0-.29.02-.58.05-.86 2.36-1.05 4.23-2.98 5.21-5.37C11.07 8.33 14.05 10 17.42 10c.78 0 1.53-.09 2.25-.26.21.71.33 1.47.33 2.26 0 4.41-3.59 8-8 8z',
  store:
    'M20 4H4v2h16V4zm1 10v-2l-1-5H4l-1 5v2h1v6h10v-6h4v6h2v-6h1zm-9 4H6v-4h6v4z',
  // Location pin (LocationPicker)
  place:
    'M12 2C8.13 2 5 5.13 5 9c0 5.25 7 13 7 13s7-7.75 7-13c0-3.87-3.13-7-7-7zm0 9.5c-1.38 0-2.5-1.12-2.5-2.5s1.12-2.5 2.5-2.5 2.5 1.12 2.5 2.5-1.12 2.5-2.5 2.5z',
  // EmptyState vocabulary (event · search · people · star · photo · scissors→barber)
  event:
    'M19 3h-1V1h-2v2H8V1H6v2H5a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2V5a2 2 0 0 0-2-2zm0 16H5V9h14v10zM5 7V5h14v2H5zm2 4h10v2H7v-2zm0 4h7v2H7v-2z',
  search:
    'M15.5 14h-.79l-.28-.27a6.5 6.5 0 1 0-.7.7l.27.28v.79l5 4.99L20.49 19l-4.99-5zm-6 0A4.5 4.5 0 1 1 14 9.5 4.5 4.5 0 0 1 9.5 14z',
  people:
    'M16 11c1.66 0 2.99-1.34 2.99-3S17.66 5 16 5s-3 1.34-3 3 1.34 3 3 3zm-8 0c1.66 0 2.99-1.34 2.99-3S9.66 5 8 5 5 6.34 5 8s1.34 3 3 3zm0 2c-2.33 0-7 1.17-7 3.5V19h14v-2.5c0-2.33-4.67-3.5-7-3.5zm8 0c-.29 0-.62.02-.97.05 1.16.84 1.97 1.97 1.97 3.45V19h6v-2.5c0-2.33-4.67-3.5-7-3.5z',
  star: 'M12 17.3 6.2 21l1.5-6.6L2.5 9.9l6.7-.6L12 3l2.8 6.3 6.7.6-5.2 4.5L17.8 21z',
  photo:
    'M21 19V5a2 2 0 0 0-2-2H5a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2zM8.5 13.5l2.5 3 3.5-4.5 4.5 6H5l3.5-4.5z',
} as const;

export type IconName = keyof typeof ICON_PATHS;
export type IconSize = keyof typeof iconSizes;

export function Icon({
  name,
  size = 'iconM',
  label,
  className = '',
}: {
  name: IconName;
  /** §7's five sizes — the default is `iconM` (24, "the default action icon"). */
  size?: IconSize;
  /** Accessible name. Omit for decorative icons (aria-hidden, the default). */
  label?: string;
  className?: string;
}) {
  const px = iconSizes[size];
  return (
    <svg
      viewBox="0 0 24 24"
      width={px}
      height={px}
      fill="currentColor"
      className={className || undefined}
      {...(label ? { role: 'img', 'aria-label': label } : { 'aria-hidden': true })}
    >
      <path d={ICON_PATHS[name]} />
    </svg>
  );
}
