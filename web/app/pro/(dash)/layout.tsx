import type { ReactNode } from 'react';
import { ProSidebar } from '../../../components/pro/ProSidebar';

/// Authed pro shell (sidebar + content). Applies to the dashboard routes only —
/// /pro/connexion sits outside this group and stays full-width.
export default function ProDashLayout({ children }: { children: ReactNode }) {
  return (
    <div className="flex min-h-screen">
      <ProSidebar />
      <main className="flex-1 p-l">{children}</main>
    </div>
  );
}
