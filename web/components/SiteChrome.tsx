'use client';

import { usePathname } from 'next/navigation';
import { AppInstallBanner } from './AppInstallBanner';
import { Header } from './Header';

/// Consumer chrome (install banner + site header). Hidden on the pro dashboard,
/// which has its own sidebar shell.
export function SiteChrome() {
  const pathname = usePathname();
  if (pathname?.startsWith('/pro')) return null;
  return (
    <>
      <AppInstallBanner />
      <Header />
    </>
  );
}
