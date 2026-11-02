import Image from 'next/image';
import Link from 'next/link';
import { SITE_CONTAINER } from '../../lib/siteGrid';

/// The Pro sign-in and sign-up pages' header (docs/design/web-pro-access.md
/// P4). They used to have none — `SiteChrome` hid everything under `/pro` —
/// so a salon on `/pro/connexion` had no logo and no way back to the site.
/// The brand lockup goes home (the convention every site keeps), and the page
/// says where the visitor is; the client's bell and « Mon compte » stay off
/// (a different account).
export function ProAuthHeader() {
  return (
    <header className="border-b border-primary">
      <div className={`${SITE_CONTAINER} flex items-center gap-m py-s`}>
        <Link href="/" aria-label="MyWeli — accueil" className="-my-s flex min-h-12 items-center">
          <Image
            src="/brand/myweli_lockup_horizontal_black.svg"
            alt="MyWeli"
            width={126}
            height={50}
            priority
            unoptimized
            className="h-8 w-auto"
          />
        </Link>
        <span className="text-labelLarge font-medium text-textSecondary">Espace pro</span>
      </div>
    </header>
  );
}
