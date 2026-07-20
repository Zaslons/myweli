'use client';

import type { ReactNode, RefObject } from 'react';
import { useEffect, useId, useRef } from 'react';

/// The shared dialog (§8, §10) — the web twin of SYSTEM §15's `ConfirmDialog`
/// doctrine, generalized. Before B5 the app had six hand-rolled modals with
/// **zero** focus traps, zero focus restores, zero scroll locks, Escape on two,
/// and three different scrim patterns (web-b5-feedback.md).
///
/// Deliberately hand-rolled, NOT the native `<dialog>`: jsdom has no
/// `showModal()` (the unit suite renders dialogs directly), and the z-stack is
/// token-asserted by `z-layers.spec.ts` — the top layer would sidestep both.
///
/// Structure is B4's blessed pattern: an **aria-hidden scrim sibling** carries
/// the dismiss click (decoration to AT — jsx-a11y strict would rightly flag a
/// click handler on the dialog wrapper), and the panel is a RELATIVE sibling
/// above it, so it needs no stopPropagation.
///
/// Behavior — ProShell's drawer idioms (B0), generalized:
/// - focus moves in on open (`initialFocusRef` first — SYSTEM §15 wants the
///   CANCEL path focused on destructive confirms — else the first focusable,
///   else the panel itself);
/// - Tab/Shift+Tab cycle INSIDE the panel (a keydown trap: `inert` siblings
///   can't work for an in-tree modal — inert-ing an ancestor inerts the modal);
/// - Escape closes; body scroll locks;
/// - focus returns to the opener on close (guarded — the opener may have
///   unmounted, e.g. a row's ⋯ menu whose row was just deleted).
export function Modal({
  title,
  label,
  onClose,
  initialFocusRef,
  returnFocusRef,
  panelClassName = 'w-full max-w-md rounded-xl border border-border bg-secondary p-l',
  scrimClassName = 'bg-primary/40',
  children,
}: {
  /** The visible dialog title — rendered as the panel's <h2> and wired via
   *  aria-labelledby. Pass `label` instead for a title-less dialog. */
  title?: string;
  /** Accessible name when the dialog has no visible title (the Lightbox). */
  label?: string;
  onClose: () => void;
  /** Focused on open. SYSTEM §15: on a destructive confirm, point this at the
   *  CANCEL button — the safe default gets focus. */
  initialFocusRef?: RefObject<HTMLElement | null>;
  /** Focused on close INSTEAD of the captured opener. For dialogs opened from
   *  an element that unmounts in the same commit (a row's ⋯ menu item —
   *  the menu closes as the dialog opens), point this at a stable ancestor
   *  trigger (the ⋯ button) or the restore silently drops to <body>. */
  returnFocusRef?: RefObject<HTMLElement | null>;
  panelClassName?: string;
  scrimClassName?: string;
  children: ReactNode;
}) {
  const titleId = useId();
  const panelRef = useRef<HTMLDivElement>(null);
  // Latest-prop mirror: the unmount cleanup below closes over mount-time
  // values, but the RIGHT restore target is the one from the LAST render.
  const returnRef = useRef(returnFocusRef);
  returnRef.current = returnFocusRef;

  // Focus in on mount, restore on unmount (returnFocusRef, else the opener).
  useEffect(() => {
    const opener = document.activeElement as HTMLElement | null;
    const panel = panelRef.current;
    const target =
      initialFocusRef?.current ?? (panel ? firstFocusable(panel) : null) ?? panel;
    target?.focus();
    return () => {
      const ret = returnRef.current?.current;
      if (ret && ret.isConnected) ret.focus();
      else if (opener && opener.isConnected) opener.focus();
    };
    // A ref is stable, so this still runs exactly once per open.
  }, [initialFocusRef]);

  // Escape closes; Tab cycles inside the panel (§8's trap).
  useEffect(() => {
    function onKey(e: KeyboardEvent) {
      // An Escape (or any key) during IME composition belongs to the IME —
      // closing the dialog would discard the user's half-composed input.
      if (e.isComposing) return;
      if (e.key === 'Escape') {
        e.stopPropagation(); // a modal above the pro drawer must not close both
        onClose();
        return;
      }
      if (e.key !== 'Tab') return;
      const panel = panelRef.current;
      if (!panel) return;
      const focusables = allFocusable(panel);
      if (focusables.length === 0) {
        e.preventDefault();
        panel.focus();
        return;
      }
      const first = focusables[0];
      const last = focusables[focusables.length - 1];
      const active = document.activeElement;
      // Leaving the edge (or the panel entirely) wraps to the other edge.
      if (e.shiftKey && (active === first || !panel.contains(active))) {
        e.preventDefault();
        last.focus();
      } else if (!e.shiftKey && (active === last || !panel.contains(active))) {
        e.preventDefault();
        first.focus();
      }
    }
    document.addEventListener('keydown', onKey, true);
    return () => document.removeEventListener('keydown', onKey, true);
  }, [onClose]);

  // Background scroll locks while open (the ProShell idiom).
  useEffect(() => {
    const prev = document.body.style.overflow;
    document.body.style.overflow = 'hidden';
    return () => {
      document.body.style.overflow = prev;
    };
  }, []);

  return (
    <div
      role="dialog"
      aria-modal="true"
      aria-labelledby={title ? titleId : undefined}
      aria-label={title ? undefined : label}
      className="fixed inset-0 z-modal flex items-center justify-center p-m"
    >
      <div
        aria-hidden="true"
        className={`absolute inset-0 ${scrimClassName}`}
        onClick={onClose}
      />
      <div ref={panelRef} tabIndex={-1} className={`relative ${panelClassName}`}>
        {title ? (
          <h2
            id={titleId}
            className="text-titleLarge font-semibold text-textPrimary"
          >
            {title}
          </h2>
        ) : null}
        {children}
      </div>
    </div>
  );
}

const FOCUSABLE =
  'a[href], button:not([disabled]), input:not([disabled]), select:not([disabled]), textarea:not([disabled]), [tabindex]:not([tabindex="-1"])';

function allFocusable(root: HTMLElement): HTMLElement[] {
  // No offsetParent visibility filter: jsdom has no layout (it is always
  // null there), and sr-only elements — a focusable file input — ARE real
  // tab stops that the trap must include.
  return Array.from(root.querySelectorAll<HTMLElement>(FOCUSABLE));
}

function firstFocusable(root: HTMLElement): HTMLElement | null {
  return allFocusable(root)[0] ?? null;
}
