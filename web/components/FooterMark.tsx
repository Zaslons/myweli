'use client';

import Image from 'next/image';
import { usePathname } from 'next/navigation';
import type { ReactNode } from 'react';
import { isProRoute } from '../lib/proRoute';

/// The footer's logo, the one thing in it that depends on the page: a poster-size
/// wordmark under an agenda is wrong, so `/pro/*` gets the lockup
/// (docs/design/web-swiss-direction.md §7.9). A leaf, so that `SiteFooter` stays a
/// server component, and `SiteChrome` already ships `usePathname` on every page. The
/// wordmark arrives as a prop, so its paths stay out of the client bundle. The lockup
/// is decorative here too: the header already names the page.
export function FooterMark({ wordmark }: { wordmark: ReactNode }) {
  if (isProRoute(usePathname() ?? '')) {
    return (
      <Image
        src="/brand/myweli_lockup_horizontal_black.svg"
        alt=""
        width={126}
        height={50}
        unoptimized
        className="h-8 w-auto"
      />
    );
  }
  return wordmark;
}
