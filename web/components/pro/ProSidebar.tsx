'use client';

import Link from 'next/link';
import { navForMembership } from '../../lib/pro/nav';
import { type TeamRole } from '../../lib/pro/team';
import { ProLogoutButton } from './ProLogoutButton';
import { TeamRoleChip } from './TeamRoleChip';
import { useProMembership } from './ProMembershipContext';

/// Sidebar nav — capability-filtered per role (team access R5b). The width
/// is constant (w-60) and loading shows skeleton rows, so the filter never
/// shifts layout. Members (non-owners) get an identity block: who they are,
/// as which role, in which salon.
export function ProSidebar() {
  const { loading, membership, role, salonName, email } = useProMembership();
  const entries = navForMembership(membership);

  return (
    <aside className="w-60 shrink-0 border-r border-divider bg-secondary p-m">
      <p className="px-s text-lg font-semibold text-textPrimary">MyWeli Pro</p>
      {loading ? (
        <div className="mt-l space-y-xs" aria-hidden="true">
          {Array.from({ length: 6 }).map((_, i) => (
            <div
              key={i}
              className="mx-s h-8 rounded-lg bg-surfaceVariant"
            />
          ))}
        </div>
      ) : (
        <>
          <nav className="mt-l space-y-xs">
            {entries.map((item) => (
              <Link
                key={item.label}
                href={item.href}
                className="block rounded-lg px-s py-s text-sm text-textPrimary hover:bg-surfaceVariant"
              >
                {item.label}
              </Link>
            ))}
          </nav>
          {membership && role && role !== 'owner' ? (
            <div className="mt-l space-y-xs rounded-lg border border-border bg-surface p-s">
              {email ? (
                <p className="break-all text-xs text-textSecondary">{email}</p>
              ) : null}
              <TeamRoleChip role={role as TeamRole} />
              {salonName ? (
                <p className="text-xs text-textTertiary">{salonName}</p>
              ) : null}
            </div>
          ) : null}
        </>
      )}
      <div className="mt-l px-s">
        <ProLogoutButton />
      </div>
    </aside>
  );
}
