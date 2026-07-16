'use client';

import Link from 'next/link';
import { usePathname } from 'next/navigation';
import { useEffect, useRef, useState } from 'react';
import { navForMembership } from '../../lib/pro/nav';
import { ROLE_LABELS, type TeamRole } from '../../lib/pro/team';
import { useIsDesktop } from '../../lib/pro/use-is-desktop';
import { ProLogoutButton } from './ProLogoutButton';
import { TeamRoleChip } from './TeamRoleChip';
import { useProMembership } from './ProMembershipContext';

/// Whether the nav's active-route highlight should light up for [href].
/// « Aujourd'hui » (/pro) matches exactly; every other entry also stays active
/// on its detail routes (/pro/rendez-vous → …/[id]).
function isActive(pathname: string | null, href: string): boolean {
  if (!pathname) return false;
  if (href === '/pro') return pathname === '/pro';
  return pathname === href || pathname.startsWith(`${href}/`);
}

/// The pro dashboard's navigation (team access R5b — capability-filtered per
/// role). At `lg+` it is a persistent sidebar; below `lg` it is the off-canvas
/// drawer that `ProShell` opens (WEB-SYSTEM §9) — ONE instance either way, so the
/// e2e/RTL selectors never see a duplicate. R6 multi-salons: the salon block at
/// the top is the « Mes salons » SWITCHER for every role; « Ajouter un salon »
/// appears when the server-computed gate is open. Members keep their identity
/// block (email + role chip).
///
/// [open] drives the drawer slide (ignored at `lg+`); [onClose] is provided only
/// in drawer mode and renders the mobile close button.
export function ProSidebar({
  open = false,
  onClose,
}: {
  open?: boolean;
  onClose?: () => void;
}) {
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
  const pathname = usePathname();
  const isDesktop = useIsDesktop();
  const entries = navForMembership(membership);
  const [menuOpen, setMenuOpen] = useState(false);
  const [switching, setSwitching] = useState<string | null>(null);
  const [switchError, setSwitchError] = useState(false);

  const switchable = salons.length > 1 || canAddSalon;

  // Keep the CLOSED drawer out of the tab order on a phone (it's translated
  // off-screen, but still focusable without this). Set via a ref, not a JSX
  // prop, because React 18 doesn't recognise `inert`. Guarded on `isDesktop` so
  // the desktop column — and jsdom, where `isDesktop` stays true — is never
  // inert, which is what keeps the existing RTL test able to find these buttons.
  const asideRef = useRef<HTMLElement>(null);
  useEffect(() => {
    const el = asideRef.current;
    if (el) el.inert = !open && !isDesktop;
  }, [open, isDesktop]);

  async function pick(salonId: string, active: boolean) {
    if (active) {
      setMenuOpen(false);
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
    setMenuOpen(false);
  }

  return (
    <aside
      ref={asideRef}
      id="pro-sidebar-nav"
      aria-label="Navigation du salon"
      className={`fixed inset-y-0 left-0 z-modal w-60 overflow-y-auto border-r border-divider bg-secondary p-m transition-transform duration-base motion-reduce:transition-none lg:static lg:z-auto lg:shrink-0 lg:translate-x-0 lg:overflow-visible lg:transition-none ${
        open ? 'translate-x-0 shadow-xl lg:shadow-none' : '-translate-x-full'
      }`}
    >
      <div className="flex items-center justify-between px-s">
        <p className="text-titleLarge font-semibold text-textPrimary">MyWeli Pro</p>
        {onClose ? (
          <button
            type="button"
            onClick={onClose}
            aria-label="Fermer le menu"
            className="-m-sm flex min-h-12 min-w-12 items-center justify-center rounded-lg text-iconXS text-textTertiary hover:bg-surfaceVariant lg:hidden"
          >
            <span aria-hidden="true">✕</span>
          </button>
        ) : null}
      </div>
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
                  aria-expanded={menuOpen}
                  onClick={() => {
                    setMenuOpen((o) => !o);
                    setSwitchError(false);
                  }}
                  className="flex min-h-12 w-full items-center justify-between gap-xs rounded-lg border border-borderStrong bg-surface px-s text-left text-bodyMedium text-textPrimary hover:bg-surfaceVariant"
                >
                  <span className="truncate">{salonName}</span>
                  <span aria-hidden="true" className="text-textTertiary">
                    ▾
                  </span>
                </button>
              ) : (
                <p className="truncate rounded-lg border border-border bg-surface px-s py-xs text-bodyMedium text-textSecondary">
                  {salonName}
                </p>
              )}
              {menuOpen ? (
                <div className="absolute inset-x-s z-dropdown mt-xs rounded-lg border border-border bg-secondary py-xs shadow-lg">
                  {salons.map((s) => {
                    const active = s.salonId === providerId;
                    return (
                      <button
                        key={s.salonId}
                        type="button"
                        disabled={switching !== null}
                        onClick={() => pick(s.salonId, active)}
                        className="flex min-h-12 w-full items-center justify-between gap-xs px-s text-left text-bodyMedium text-textPrimary hover:bg-surfaceVariant disabled:opacity-60"
                      >
                        <span className="min-w-0">
                          <span className="block truncate">{s.salonName}</span>
                          <span className="block text-bodySmall text-textTertiary">
                            {ROLE_LABELS[s.role as TeamRole]}
                            {s.salonStatus === 'draft' ? ' · Brouillon' : ''}
                          </span>
                        </span>
                        {active ? (
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
                        onClick={() => setMenuOpen(false)}
                        className="block px-s py-s text-bodyMedium text-textPrimary underline hover:bg-surfaceVariant"
                      >
                        Ajouter un salon
                      </Link>
                    </>
                  ) : null}
                </div>
              ) : null}
              {switchError ? (
                <p className="mt-xs text-bodySmall text-error">
                  Changement impossible — votre accès à ce salon a peut-être
                  été retiré.
                </p>
              ) : null}
            </div>
          ) : null}
          <nav className="mt-l space-y-xs">
            {entries.map((item) => {
              const active = isActive(pathname, item.href);
              return (
                <Link
                  key={item.label}
                  href={item.href}
                  aria-current={active ? 'page' : undefined}
                  className={`flex min-h-12 items-center rounded-lg px-s text-bodyMedium hover:bg-surfaceVariant ${
                    active
                      ? 'bg-surfaceVariant font-medium text-textPrimary'
                      : 'text-textPrimary'
                  }`}
                >
                  {item.label}
                </Link>
              );
            })}
          </nav>
          {membership && role && role !== 'owner' ? (
            <div className="mt-l space-y-xs rounded-lg border border-border bg-surface p-s">
              {email ? (
                <p className="break-all text-bodySmall text-textSecondary">{email}</p>
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
