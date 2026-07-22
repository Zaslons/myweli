import type { ReactNode } from 'react';

/// The shared card (§11.3's AppCard, B7): `secondary` on `background`,
/// `radiusXL`, elevation 0, **`spacingM` padding** — the spec's density. The
/// pro pages hand-rolled this box with `p-l` (24px); Card conversions tighten
/// to 16px, which IS "the pro/admin density work" (web-b7-desktop.md records
/// the deliberate change).
export function Card({
  as: Tag = 'div',
  className = '',
  children,
}: {
  as?: 'div' | 'section' | 'article' | 'li';
  className?: string;
  children: ReactNode;
}) {
  return (
    <Tag
      className={`rounded-xl border border-border bg-secondary p-m ${className}`}
    >
      {children}
    </Tag>
  );
}
