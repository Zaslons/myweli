import type { LocalityTree, MomoOperator } from './api/localities';

/// Mobile-Money helpers (multi-pays MP3 — the web mirror of the app's
/// core/utils/mobile_money.dart). Operator identity comes from the country
/// catalogs in GET /localities; payment deep links are built ONLY from the
/// closed `deepLinkKind` vocabulary — never from a payload URL (threat T56).

/// Find an operator across the catalogs — by wire id first, then by label
/// (legacy policies stored display labels).
export function findOperator(
  tree: LocalityTree,
  value: string | null | undefined,
): MomoOperator | null {
  if (!value) return null;
  for (const country of tree.countries) {
    const byId = country.operators.find((o) => o.id === value);
    if (byId) return byId;
  }
  for (const country of tree.countries) {
    const byLabel = country.operators.find((o) => o.label === value);
    if (byLabel) return byLabel;
  }
  return null;
}

/// Display label for a stored operator value; unknown values render as-is.
export function operatorLabel(
  tree: LocalityTree,
  value: string | null | undefined,
): string {
  return findOperator(tree, value)?.label ?? value ?? '';
}

/// Whether an operator supports a pre-filled deep link — only Wave today.
export function deepLinkKindIsWave(kind?: string | null): boolean {
  return kind === 'wave';
}

/// A Wave link pre-filling recipient + amount (the client only confirms with
/// their PIN). NOTE: confirm the exact format against Wave's live docs before
/// launch — the copyable number + amount stays the guaranteed fallback.
export function waveDeepLink(number: string, amount: number): string | null {
  const digits = number.replace(/\D/g, '');
  if (!digits) return null;
  return `https://pay.wave.com/?recipient=${digits}&amount=${Math.round(amount)}`;
}
