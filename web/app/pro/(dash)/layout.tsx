import type { ReactNode } from 'react';
import { ProMembershipProvider } from '../../../components/pro/ProMembershipContext';
import { ProSidebar } from '../../../components/pro/ProSidebar';

/// Authed pro shell (sidebar + content). Applies to the dashboard routes only —
/// /pro/connexion sits outside this group and stays full-width.
/// ProMembershipProvider re-probes /api/pro/me on every navigation (team
/// access R5b: the sidebar's capability filter + the T38 revocation probe).
export default function ProDashLayout({ children }: { children: ReactNode }) {
  return (
    <ProMembershipProvider>
      <div className="flex min-h-screen">
        <ProSidebar />
        <main className="flex-1 p-l">{children}</main>
      </div>
    </ProMembershipProvider>
  );
}
