import type { ButtonHTMLAttributes } from 'react';

type Variant = 'primary' | 'secondary';

/// Base button — token-styled (mirrors the app's AppButton). Design system:
/// docs/design/WEB-SYSTEM.md.
export function Button({
  variant = 'primary',
  className = '',
  ...props
}: ButtonHTMLAttributes<HTMLButtonElement> & { variant?: Variant }) {
  // labelLarge, not bodyMedium: §4 gives labelLarge (14/20, 500) as "Button
  // labels" — same size and line as bodyMedium, tighter tracking (0.1 vs 0.25).
  // The `font-medium` below is the role signal, and it is split across the two
  // concatenated literals, so a line-wise migration reads this as unweighted.
  const base =
    'inline-flex items-center justify-center rounded-lg px-l py-s text-labelLarge ' +
    'font-medium transition-colors disabled:opacity-50';
  const styles =
    variant === 'primary'
      ? 'bg-primary text-secondary hover:bg-primaryHover'
      : // The outline IS the control here (WCAG 1.4.11) → borderStrong, not the
        // 1.44:1 `border`. One edit covers every secondary button.
        'border border-borderStrong bg-secondary text-textPrimary hover:bg-surfaceVariant';
  return <button className={`${base} ${styles} ${className}`} {...props} />;
}
