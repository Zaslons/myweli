import type { ButtonHTMLAttributes } from 'react';
import { forwardRef } from 'react';

type Variant = 'primary' | 'secondary' | 'text';

/// Base button — token-styled, the parity of the app's `AppButton`
/// (docs/design/web-b4-controls.md; WEB-SYSTEM §10).
///
/// `min-h-12` is §13.2's 48px floor, mirroring mobile A3's
/// `minimumSize: Size(0, 48)` — a HEIGHT floor, width from the container (the
/// `double.infinity` form is the documented anti-pattern). Before B4 every
/// button in the app measured 36px; the only 48px box in the codebase was a
/// non-interactive avatar (§15 row 7h).
///
/// `text` is the app's third variant, previously missing (parity drift, §10).
/// Its foreground is deliberately `textPrimary` INK, not mobile's `primary`
/// foreground — on web, §1's ink/brand split reserves `primary` for fills.
///
/// `isLoading` swaps the label for a spinner WITHOUT changing the button's size
/// (SYSTEM §11.1 — no layout jump): the children stay in flow but painted
/// transparent (`text-transparent`, NOT `invisible` — visibility:hidden would
/// strip the accessible name), and the spinner centers absolutely on top.
/// Loading implies disabled (§14 rule 5: disable only WHILE submitting).
/// CONSTRAINT: `text-transparent` sets `color` on the button, so a child that
/// carries its own `text-*` color class would stay visible through the
/// spinner. Pass plain (uncolored) children to a button that can load — every
/// current caller passes a bare string.
/// forwardRef (B5): `Modal`'s `initialFocusRef` needs to point at a Button —
/// SYSTEM §15 focuses the CANCEL path on destructive confirms.
export const Button = forwardRef<
  HTMLButtonElement,
  ButtonHTMLAttributes<HTMLButtonElement> & {
    variant?: Variant;
    isLoading?: boolean;
  }
>(function Button(
  {
    variant = 'primary',
    isLoading = false,
    className = '',
    disabled,
    children,
    ...props
  },
  ref,
) {
  // labelLarge, not bodyMedium: §4 gives labelLarge (14/20, 500) as "Button
  // labels" — same size and line as bodyMedium, tighter tracking (0.1 vs 0.25).
  const base =
    'relative inline-flex min-h-12 items-center justify-center rounded-lg px-l py-s ' +
    'text-labelLarge font-medium transition-colors disabled:opacity-50';
  const styles =
    variant === 'primary'
      ? 'bg-primary text-secondary hover:bg-primaryHover'
      : variant === 'secondary'
        ? // The outline IS the control here (WCAG 1.4.11) → borderStrong, not
          // the 1.44:1 `border`. One edit covers every secondary button.
          'border border-borderStrong bg-secondary text-textPrimary hover:bg-surfaceVariant'
        : 'px-m text-textPrimary hover:bg-surfaceVariant';
  return (
    <button
      ref={ref}
      className={`${base} ${styles} ${className}`}
      disabled={disabled || isLoading}
      aria-busy={isLoading || undefined}
      {...props}
    >
      {isLoading ? (
        <>
          <span className="text-transparent">{children}</span>
          <span
            aria-hidden="true"
            className="absolute inline-flex h-5 w-5 animate-spin rounded-pill border-2 border-current border-t-transparent"
          />
        </>
      ) : (
        children
      )}
    </button>
  );
});
