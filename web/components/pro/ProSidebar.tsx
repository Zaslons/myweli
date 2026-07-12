'use client';

import Link from 'next/link';
import { useState } from 'react';
import { navForMembership } from '../../lib/pro/nav';
import { ROLE_LABELS, type TeamRole } from '../../lib/pro/team';
import { ProLogoutButton } from './ProLogoutButton';
import { TeamRoleChip } from './TeamRoleChip';
import { useProMembership } from './ProMembershipContext';

/// Sidebar nav — capability-filtered per role (team access R5b). The width
/// is constant (w-60) and loading shows skeleton rows, so the filter never
/// shifts layout. R6 multi-salons: the salon block at the top is the
/// « Mes salons » SWITCHER for every role (a member can belong to several
/// salons too); « Ajouter un salon » appears when the server-computed gate
/// is open. Members keep their identity block (email + role chip).
export function ProSidebar() {
  const {
    loading,
    membership,
    role,
    salonName,
    providerId,
    email,
    salons,
    canAddSalon,
    switchSalon,
  } = useProMembership();
  const entries = navForMembership(membership);
  const [open, setOpen] = useState(false);
  const [switching, setSwitching] = useState<string | null>(null);
  const [switchError, setSwitchError] = useState(false);

  const switchable = salons.length > 1 || canAddSalon;

  async function pick(salonId: string, isActive: boolean) {
    if (isActive) {
      setOpen(false);
      return;
    }
    setSwitching(salonId);
    setSwitchError(false);
    const ok = await switchSalon(salonId);
    setSwitching(null);
    if (!ok) {
      setSwitchError(true);
      return;
    }
    setOpen(false);
  }

  return (
    <aside className="w-60 shrink-0 border-r border-divider bg-secondary p-m">
      <p className="px-s text-lg font-semibold text-textPrimary">MyWeli Pro</p>
      {loading ? (
        <div className="mt-l space-y-xs" aria-hidden="true">
          {Array.from({ length: 6 }).map((_, i) => (
            <div key={i} className="mx-s h-8 rounded-lg bg-surfaceVariant" />
          ))}
        </div>
      ) : (
        <>
          {/* The « Mes salons » switcher (R6) — the active salon, and the
              door to the rest of the fleet. */}
          {salonName ? (
            <div className="relative mt-s px-s">
              {switchable ? (
                <button
                  type="button"
                  aria-label="Changer de salon"
                  aria-expanded={open}
                  onClick={() => {
                    setOpen((o) => !o);
                    setSwitchError(false);
                  }}
                  className="flex w-full items-center justify-between gap-xs rounded-lg border border-border bg-surface px-s py-xs text-left text-sm text-textPrimary hover:bg-surfaceVariant"
                >
                  <span className="truncate">{salonName}</span>
                  <span aria-hidden="true" className="text-textTertiary">
                    ▾
                  </span>
                </button>
              ) : (
                <p className="truncate rounded-lg border border-border bg-surface px-s py-xs text-sm text-textSecondary">
                  {salonName}
                </p>
              )}
              {open ? (
                <div className="absolute inset-x-s z-20 mt-xs rounded-lg border border-border bg-secondary py-xs shadow-lg">
                  {salons.map((s) => {
                    const isActive = s.salonId === providerId;
                    return (
                      <button
                        key={s.salonId}
                        type="button"
                        disabled={switching !== null}
                        onClick={() => pick(s.salonId, isActive)}
                        className="flex w-full items-center justify-between gap-xs px-s py-s text-left text-sm text-textPrimary hover:bg-surfaceVariant disabled:opacity-60"
                      >
                        <span className="min-w-0">
                          <span className="block truncate">{s.salonName}</span>
                          <span className="block text-xs text-textTertiary">
                            {ROLE_LABELS[s.role as TeamRole]}
                            {s.salonStatus === 'draft' ? ' · Brouillon' : ''}
                          </span>
                        </span>
                        {isActive ? (
                          <span aria-hidden="true" className="shrink-0">
                            ✓
                          </span>
                        ) : null}
                      </button>
                    );
                  })}
                  {canAddSalon ? (
                    <>
                      <div className="my-xs border-t border-divider" />
                      <Link
                        href="/pro/salons/nouveau"
                        onClick={() => setOpen(false)}
                        className="block px-s py-s text-sm text-textPrimary underline hover:bg-surfaceVariant"
                      >
                        Ajouter un salon
                      </Link>
                    </>
                  ) : null}
                </div>
              ) : null}
              {switchError ? (
                <p className="mt-xs text-xs text-error">
                  Changement impossible — votre accès à ce salon a peut-être
                  été retiré.
                </p>
              ) : null}
            </div>
          ) : null}
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
