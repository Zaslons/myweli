import type { ReactNode } from 'react';
import { SITE_CONTAINER } from '../lib/siteGrid';

/// A public page's section (docs/design/web-swiss-direction.md §6): a black rule
/// above it, and from `lg` the `<h2>` hanging in columns 1–3 beside its content.
/// `stacked` keeps the heading above, for content that needs all twelve columns.
export function SiteSection({
  title,
  titleId,
  stacked = false,
  children,
}: {
  title: string;
  titleId?: string;
  stacked?: boolean;
  children: ReactNode;
}) {
  return (
    <section aria-labelledby={titleId} className="border-t border-primary">
      <div
        className={`${SITE_CONTAINER} py-xl lg:py-xxl ${
          stacked ? '' : 'lg:grid lg:grid-cols-12 lg:gap-x-l'
        }`}
      >
        <h2
          id={titleId}
          className={`text-headlineSmall font-semibold text-textPrimary lg:text-headlineMedium ${
            stacked ? '' : 'lg:col-span-3'
          }`}
        >
          {title}
        </h2>
        <div className={stacked ? 'mt-m' : 'mt-m lg:col-span-9 lg:mt-0'}>{children}</div>
      </div>
    </section>
  );
}
