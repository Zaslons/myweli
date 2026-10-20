'use client';

import { usePathname } from 'next/navigation';
import { AppInstallBanner } from './AppInstallBanner';
import { Header } from './Header';
import { ProAuthHeader } from './pro/ProAuthHeader';

/// The Pro sign-in pages: no dashboard shell yet, so not hidden — but not the
/// client's header either (its bell and « Mon compte » are another account).
const PRO_AUTH = new Set(['/pro/connexion', '/pro/inscription']);

/// Consumer chrome (install banner + site header). Hidden on the pro
/// dashboard, which has its own sidebar shell. **`/pro` or `/pro/…` exactly**
/// — the prefix test this used to be (`startsWith('/pro')`) also hid the
/// header of `/professionnels`, the public page for salons
/// (docs/design/web-pro-access.md §1.3).
export function SiteChrome() {
  const pathname = usePathname() ?? '';
  if (PRO_AUTH.has(pathname)) return <ProAuthHeader />;
  if (pathname === '/pro' || pathname.startsWith('/pro/')) return null;
  return (
    <>
      <AppInstallBanner />
      <Header />
    </>
  );
}
