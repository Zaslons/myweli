'use client';

import { useEffect, useState } from 'react';

/// `true` at and above the `lg` breakpoint (1024px) — the point at which the pro
/// dashboard's nav is a persistent sidebar rather than an off-canvas drawer
/// (WEB-SYSTEM §9).
///
/// SSR-safe by construction: it returns `true` on the server and on the first
/// client render, then corrects on mount. The LAYOUT never reads this — the
/// column-vs-drawer switch is pure CSS (`lg:`), so there is no hydration flash.
/// This governs only the non-visual bits CSS can't express: closing the drawer
/// when the viewport grows past `lg`, and marking the off-screen drawer `inert`
/// on a phone.
///
/// The `matchMedia` guard means jsdom (which doesn't implement it) stays on the
/// `true` branch, so the existing RTL tests render the sidebar as a desktop
/// column and keep passing untouched.
export function useIsDesktop(): boolean {
  const [isDesktop, setIsDesktop] = useState(true);

  useEffect(() => {
    if (typeof window.matchMedia !== 'function') return;
    const mq = window.matchMedia('(min-width: 1024px)');
    const update = () => setIsDesktop(mq.matches);
    update();
    mq.addEventListener('change', update);
    return () => mq.removeEventListener('change', update);
  }, []);

  return isDesktop;
}
