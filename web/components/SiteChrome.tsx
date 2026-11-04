'use client';

import { usePathname } from 'next/navigation';
import { isProRoute } from '../lib/proRoute';
import { isStoreLinkedPage } from '../lib/storeLinkedPages';
import { AppInstallBanner } from './AppInstallBanner';
import { Header } from './Header';
import { ProAuthHeader } from './pro/ProAuthHeader';

/// The Pro sign-in pages: no dashboard shell yet, so not hidden — but not the
/// client's header either (its bell and « Mon compte » are another account).
const PRO_AUTH = new Set(['/pro/connexion', '/pro/inscription']);

/// Consumer chrome (install banner + site header). Hidden on the pro
/// dashboard, which has its own sidebar shell. `/recherche` runs full width, so its
/// chrome does too: the logo starts where the list does
/// (docs/design/web-swiss-direction.md §6.2).
export function SiteChrome() {
  const pathname = usePathname() ?? '';
  if (PRO_AUTH.has(pathname)) return <ProAuthHeader />;
  if (isProRoute(pathname)) return null;
  const fullWidth = pathname === '/recherche';
  return (
    <>
      <AppInstallBanner fullWidth={fullWidth} />
      <Header fullWidth={fullWidth} salonDoor={!isStoreLinkedPage(pathname)} />
    </>
  );
}
