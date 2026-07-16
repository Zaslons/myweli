'use client';

import Link from 'next/link';
import { usePathname } from 'next/navigation';
import { type ReactNode, useEffect, useRef, useState } from 'react';
import { useIsDesktop } from '../../lib/pro/use-is-desktop';
import { ProSidebar } from './ProSidebar';

/// The responsive chrome around the pro dashboard (WEB-SYSTEM §9).
///
/// At `lg+` this is exactly what shipped before: the persistent sidebar column
/// beside the content, no top bar. Below `lg` the sidebar becomes an off-canvas
/// DRAWER — the same `<ProSidebar>`, rendered once — opened by a hamburger in a
/// slim sticky top bar. That fixes the live bug where a 240px sidebar ate a
/// 375px phone on every `/pro` route.
///
/// It is a landmark disclosure, not a modal dialog (that sidesteps the
/// desktop/mobile `role` conflict of a single reused element), but on a phone it
/// visually overlays the page, so it behaves modally WHILE OPEN: a scrim, Escape
/// and scrim-click close it, the body scroll locks, focus moves into the drawer
/// and returns to the hamburger on close, and the content behind is `inert` so
/// focus can't wander into what's covered. B5's shared `<Modal>` can adopt this
/// later; B0 deliberately doesn't build that primitive.
export function ProShell({ children }: { children: ReactNode }) {
  const [open, setOpen] = useState(false);
  const isDesktop = useIsDesktop();
  const pathname = usePathname();
  const hamburgerRef = useRef<HTMLButtonElement>(null);
  const mainRef = useRef<HTMLElement>(null);
  const wasOpen = useRef(false);

  // Close on navigation — covers link taps AND programmatic redirects (e.g. a
  // salon switch). One mechanism instead of an onClick on every link.
  useEffect(() => setOpen(false), [pathname]);

  // Grew past `lg` (rotate / resize) while open → the drawer would strand an
  // `inert` main on the desktop layout. Reaching desktop always closes it.
  useEffect(() => {
    if (isDesktop) setOpen(false);
  }, [isDesktop]);

  // Escape closes (the codebase's one dialog-dismissal idiom).
  useEffect(() => {
    if (!open) return;
    function onKey(e: KeyboardEvent) {
      if (e.key === 'Escape') setOpen(false);
    }
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [open]);

  // While open: lock body scroll, make the covered content inert, move focus
  // into the drawer; on close, restore focus to the hamburger.
  useEffect(() => {
    const main = mainRef.current;
    if (main) main.inert = open;
    document.body.style.overflow = open ? 'hidden' : '';

    if (open) {
      const closeBtn = document.querySelector<HTMLButtonElement>(
        '#pro-sidebar-nav button[aria-label="Fermer le menu"]',
      );
      closeBtn?.focus();
    } else if (wasOpen.current) {
      hamburgerRef.current?.focus();
    }
    wasOpen.current = open;

    return () => {
      document.body.style.overflow = '';
    };
  }, [open]);

  return (
    <div className="min-h-screen lg:flex">
      {/* Mobile top bar — the only place the hamburger lives; gone at `lg+`. */}
      <header className="sticky top-0 z-sticky flex items-center gap-s border-b border-divider bg-secondary px-m py-s lg:hidden">
        <button
          ref={hamburgerRef}
          type="button"
          onClick={() => setOpen(true)}
          aria-label="Ouvrir le menu"
          aria-controls="pro-sidebar-nav"
          aria-expanded={open}
          className="rounded-lg p-xs text-textPrimary hover:bg-surfaceVariant"
        >
          <svg
            width="24"
            height="24"
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            strokeWidth="2"
            strokeLinecap="round"
            aria-hidden="true"
          >
            <line x1="4" y1="7" x2="20" y2="7" />
            <line x1="4" y1="12" x2="20" y2="12" />
            <line x1="4" y1="17" x2="20" y2="17" />
          </svg>
        </button>
        <Link
          href="/pro"
          className="text-titleLarge font-semibold text-textPrimary"
        >
          MyWeli Pro
        </Link>
      </header>

      {/* The scrim — a click target, but aria-hidden and unfocusable; Escape and
          the drawer's own ✕ are the accessible ways out. `lg:hidden` keeps it
          off the desktop layout even if `open` is momentarily stale. */}
      {open ? (
        <div
          className="fixed inset-0 z-overlay bg-primary/40 lg:hidden"
          aria-hidden="true"
          onClick={() => setOpen(false)}
        />
      ) : null}

      <ProSidebar open={open} onClose={() => setOpen(false)} />

      <main ref={mainRef} className="flex-1 p-l lg:min-w-0">
        {children}
      </main>
    </div>
  );
}
