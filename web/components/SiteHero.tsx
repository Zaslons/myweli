import type { ReactNode } from 'react';
import { SITE_CONTAINER } from '../lib/siteGrid';
import { WovenBandRow, WovenPanel } from './brand/Weave';

/// The hero of `/` and `/professionnels` (docs/design/web-swiss-direction.md §7.1,
/// §7.2): the band above on a phone; from `lg`, the `<h1>` at the top of columns 1–7,
/// `children` on the panel's bottom line, and the panel in columns 8–12.
export function SiteHero({ title, children }: { title: ReactNode; children: ReactNode }) {
  return (
    <section>
      <WovenBandRow className="lg:hidden" />
      <div className={`${SITE_CONTAINER} lg:grid lg:grid-cols-12 lg:gap-x-l`}>
        <div className="flex flex-col py-l lg:col-span-7 lg:min-h-hero lg:justify-between lg:py-xl">
          <h1 className="text-balance break-words text-displaySmall font-semibold tracking-tight text-textPrimary sm:text-displayMedium lg:text-displayLarge xl:text-displayPoster">
            {title}
          </h1>
          <div className="mt-m lg:mt-xl">{children}</div>
        </div>
        <div
          data-weave-panel
          className="relative hidden border-l border-primary lg:col-span-5 lg:block"
        >
          <WovenPanel />
        </div>
      </div>
    </section>
  );
}
