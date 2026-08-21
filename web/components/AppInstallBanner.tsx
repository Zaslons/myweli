'use client';

import { useEffect, useState } from 'react';
import { appStoreUrl } from '../lib/appStore';

const dismissKey = 'myweli_install_dismissed';

/// Dismissible "download the app" nudge (WEB-DESIGN-STANDARDS §7) — one per
/// session, remembers dismissal, never blocks content. Store link from env.
export function AppInstallBanner() {
  const [visible, setVisible] = useState(false);

  useEffect(() => {
    if (window.localStorage.getItem(dismissKey) !== '1') setVisible(true);
  }, []);

  if (!visible) return null;

  // **No store URL means no banner at all**, not a banner with its button
  // removed. Hiding only the link left « téléchargez l'app MyWeli » above a
  // dismiss button and nothing to download — an offer a visitor cannot take.
  // An `<a href="#">` was the previous version of the same mistake.
  const href = appStoreUrl();
  if (!href) return null;

  function dismiss() {
    window.localStorage.setItem(dismissKey, '1');
    setVisible(false);
  }

  return (
    <aside
      aria-label="Installer l’application"
      className="flex items-center justify-between gap-m bg-primary px-m py-s text-secondary"
    >
      <p className="text-bodyMedium">Réservez plus vite — téléchargez l’app MyWeli.</p>
      <div className="flex items-center gap-s">
        {href ? (
          <a
            href={href}
            className="inline-flex min-h-12 items-center rounded-md bg-secondary px-m text-labelLarge font-medium text-primary"
          >
            Télécharger
          </a>
        ) : null}
        <button
          type="button"
          aria-label="Fermer"
          onClick={dismiss}
          className="-my-sm -mr-sm flex min-h-12 min-w-12 items-center justify-center text-iconXS text-secondary"
        >
          ✕
        </button>
      </div>
    </aside>
  );
}
