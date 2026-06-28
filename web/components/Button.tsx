import type { ButtonHTMLAttributes } from 'react';

type Variant = 'primary' | 'secondary';

/// Base button — token-styled (mirrors the app's AppButton). Design system:
/// docs/design/WEB-DESIGN-STANDARDS.md.
export function Button({
  variant = 'primary',
  className = '',
  ...props
}: ButtonHTMLAttributes<HTMLButtonElement> & { variant?: Variant }) {
  const base =
    'inline-flex items-center justify-center rounded-lg px-l py-s text-sm ' +
    'font-medium transition-colors disabled:opacity-50';
  const styles =
    variant === 'primary'
      ? 'bg-primary text-secondary hover:bg-primaryLight'
      : 'border border-border bg-secondary text-textPrimary hover:bg-surfaceVariant';
  return <button className={`${base} ${styles} ${className}`} {...props} />;
}
