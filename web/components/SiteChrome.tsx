'use client';

import { usePathname } from 'next/navigation';
import { isProRoute } from '../lib/proRoute';
import { isStoreLinkedPage } from '../lib/storeLinkedPages';
import { AppInstallBanner } from './AppInstallBanner';
import { Header } from './Header';
import { ProAuthHeader } from './pro/ProAuthHeader';

/// The Pro sign-in pages: no dashboard shell yet, so not hidden — but not the
/// client's header either (its bell and « Mon compte » are another account).
///
/// `/pro/suppression-compte` (B0.19) is read signed out too, and **its entry is
/// required, not cosmetic**: `isProRoute` is true for it, so without it this
/// renders no header at all (docs/design/web-pro-account-deletion.md §7). Like
/// the sign-in, it gets no install banner — a person leaving is not pushed to
/// install (WEB-SYSTEM §13).
const PRO_AUTH = new Set(['/pro/connexion', '/pro/inscription', '/pro/suppression-compte']);

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
