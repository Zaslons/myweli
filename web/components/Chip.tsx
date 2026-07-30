import type { ButtonHTMLAttributes, ReactNode } from 'react';

/// The shared chip (§11.3's AppChip, B6) — filled (selected) / outlined /
/// tinted (status), `rounded-pill`, `labelMedium`.
///
/// Before B6: ~24 hand-rolled pill renderings across 13 files, and NONE used
/// `borderStrong` on the outlined variant — §16 names "outlined chips"
/// explicitly in the mandatory-boundary rule. TeamRoleChip's own ds-ignore
/// promised its 2px padding to this component; both die here.
///
/// Two natures, one look:
/// - `<Chip>` — a STATIC badge (status pill, tag). Compact `px-s py-xs`; no
///   fake tap target on a non-control.
/// - `<ChipButton>` — an INTERACTIVE chip (selection, filter, toggle):
///   `min-h-12` (§13.2) and the button semantics; selection is `filled`.
///
/// Variants:
/// - `filled` — the selected state: `bg-primary text-secondary`.
/// - `outlined` — the default resting chip: **`border-borderStrong`** (§16).
/// - `tinted` — status by KIND (`bg-{kind}/10 text-{kind}`): pass `tint`.
/// - `gold` — the privileged owner treatment (TeamRoleChip's).
/// - `neutral` — the quiet single-tint badge (`bg-surface`, textSecondary):
///   the appointment-status pills' existing look, kept until B7's
///   StatusChip.forStatus maps kinds product-wide.
type ChipVariant = 'filled' | 'outlined' | 'tinted' | 'gold' | 'neutral';

const TINTS: Record<string, string> = {
  error: 'bg-error/10 text-error',
  success: 'bg-success/10 text-success',
  info: 'bg-info/10 text-info',
  warning: 'bg-warningLight/20 text-warning',
};

function chipClasses(variant: ChipVariant, tint?: string): string {
  switch (variant) {
    case 'filled':
      return 'bg-primary text-secondary';
    case 'outlined':
      return 'border border-borderStrong bg-surface text-textPrimary';
    case 'tinted':
      return TINTS[tint ?? 'info'] ?? TINTS.info;
    case 'gold':
      return 'border border-gold/40 bg-gold/15 text-textPrimary';
    case 'neutral':
      return 'bg-surface text-textSecondary';
  }
}

export function Chip({
  variant = 'neutral',
  tint,
  dense = false,
  className = '',
  children,
}: {
  variant?: ChipVariant;
  /** Semantic kind for `tinted` (error/success/info/warning). */
  tint?: string;
  /** The list-row micro-badge tier (labelSmall, px-xs) — dense tables only. */
  dense?: boolean;
  className?: string;
  children: ReactNode;
}) {
  return (
    <span
      className={`inline-flex items-center rounded-pill font-medium ${
        dense ? 'px-xs text-labelSmall' : 'px-s py-xs text-labelMedium'
      } ${chipClasses(variant, tint)} ${className}`}
    >
      {children}
    </span>
  );
}

/** The interactive-chip classes for ANCHOR chips (category/filter links —
 *  most selection chips navigate). Same look as <ChipButton>, §13.2 floor
 *  included; selection = filled. */
export function chipLinkClasses(selected: boolean): string {
  return `inline-flex min-h-12 items-center rounded-pill px-m text-bodyMedium ${
    selected
      ? 'border border-primary bg-primary text-secondary'
      : 'border border-borderStrong bg-surface text-textPrimary hover:bg-surfaceVariant'
  }`;
}

export function ChipButton({
  selected = false,
  className = '',
  children,
  ...props
}: ButtonHTMLAttributes<HTMLButtonElement> & {
  selected?: boolean;
  children: ReactNode;
}) {
  return (
    <button
      type="button"
      {...props}
      className={`inline-flex min-h-12 items-center rounded-pill px-m text-bodyMedium ${
        selected
          ? 'border border-primary bg-primary text-secondary'
          : 'border border-borderStrong bg-surface text-textPrimary hover:bg-surfaceVariant'
      } ${className}`}
    >
      {children}
    </button>
  );
}
