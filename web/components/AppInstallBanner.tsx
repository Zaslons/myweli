'use client';

import { useEffect, useState } from 'react';

const dismissKey = 'myweli_install_dismissed';

/// Dismissible "download the app" nudge (WEB-DESIGN-STANDARDS §7) — one per
/// session, remembers dismissal, never blocks content. Store link from env.
export function AppInstallBanner() {
  const [visible, setVisible] = useState(false);

  useEffect(() => {
    if (window.localStorage.getItem(dismissKey) !== '1') setVisible(true);
  }, []);

  if (!visible) return null;

  const href =
    process.env.NEXT_PUBLIC_ANDROID_APP_URL ??
    process.env.NEXT_PUBLIC_IOS_APP_URL ??
    '#';

  function dismiss() {
    window.localStorage.setItem(dismissKey, '1');
    setVisible(false);
  }

  return (
    <div className="flex items-center justify-between gap-m bg-primary px-m py-s text-secondary">
      <p className="text-bodyMedium">Réservez plus vite — téléchargez l’app MyWeli.</p>
      <div className="flex items-center gap-s">
        <a
          href={href}
          className="rounded-md bg-secondary px-m py-xs text-labelLarge font-medium text-primary"
        >
          Télécharger
        </a>
        <button
          type="button"
          aria-label="Fermer"
          onClick={dismiss}
          className="px-xs text-secondary"
        >
          ✕
        </button>
      </div>
    </div>
  );
}
