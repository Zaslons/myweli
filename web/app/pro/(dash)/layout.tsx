import type { ReactNode } from 'react';
import { ProMembershipProvider } from '../../../components/pro/ProMembershipContext';
import { ProShell } from '../../../components/pro/ProShell';

/// Authed pro shell. Applies to the dashboard routes only — /pro/connexion sits
/// outside this group and stays full-width. ProMembershipProvider re-probes
/// /api/pro/me on every navigation (team access R5b: the sidebar's capability
/// filter + the T38 revocation probe). ProShell is the responsive chrome:
/// persistent sidebar at `lg+`, off-canvas drawer below (WEB-SYSTEM §9).
export default function ProDashLayout({ children }: { children: ReactNode }) {
  return (
    <ProMembershipProvider>
      <ProShell>{children}</ProShell>
    </ProMembershipProvider>
  );
}
