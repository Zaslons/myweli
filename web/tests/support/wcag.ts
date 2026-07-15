// WCAG 2.1 contrast math — the TS twin of mobile/test/support/wcag.dart, so the
// two surfaces agree on what "passes" means (docs/design/SYSTEM.md §2).

/// WCAG 2.1 relative luminance of a `#RRGGBB` hex.
export function relativeLuminance(hex: string): number {
  const h = hex.replace('#', '');
  const channel = (v: number) => {
    const c = v / 255;
    return c <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4;
  };
  const r = channel(parseInt(h.slice(0, 2), 16));
  const g = channel(parseInt(h.slice(2, 4), 16));
  const b = channel(parseInt(h.slice(4, 6), 16));
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

/// The contrast ratio between two opaque hexes, 1.0 → 21.0.
export function contrastRatio(a: string, b: string): number {
  const la = relativeLuminance(a);
  const lb = relativeLuminance(b);
  const hi = Math.max(la, lb);
  const lo = Math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

/// The WCAG AA floors.
export const FLOOR_TEXT = 4.5; // normal text (1.4.3)
export const FLOOR_NON_TEXT = 3.0; // icons, control borders, focus (1.4.11)

export const ratioLabel = (r: number) => r.toFixed(2);
