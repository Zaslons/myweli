import Link from 'next/link';
import type { ReactNode } from 'react';
import { type ButtonVariant, buttonClasses } from './Button';

/// A link that looks like a `Button` — for an action that NAVIGATES (WEB-SYSTEM
/// §4: a link goes somewhere, a button does something). Same classes as
/// `Button`, from one definition.
export function ButtonLink({
  href,
  variant = 'primary',
  className = '',
  children,
}: {
  href: string;
  variant?: ButtonVariant;
  className?: string;
  children: ReactNode;
}) {
  return (
    <Link href={href} className={`${buttonClasses(variant)} ${className}`}>
      {children}
    </Link>
  );
}
