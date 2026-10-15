'use client';

import { useRouter } from 'next/navigation';
import { useEffect, useRef, useState } from 'react';
import { logoutPro } from '../../lib/api/pro';
import { logoutErrorMessage } from '../../lib/pro/team';
import { Button } from '../Button';

/// « Se déconnecter » — the sidebar's, the rejoin gate's, and the locked page
/// a failed revoked sign-out leaves (docs/design/pro-rejoin-gate.md S8, §10).
/// `redirectTo` lets a host land somewhere other than the bare login — the
/// gate signs out onto the « accès retiré » banner.
///
/// The session is two httpOnly cookies that only the logout RESPONSE can
/// clear, so the login page — which looks signed out — is shown only once that
/// response came back OK. A failed call stays here, says so (« Pas de
/// connexion. Réessayez. », or the generic sentence for an error status) and
/// gives the button back for a retry: on a shared salon computer, a
/// signed-out-looking screen over a live 30-day session is the next person's
/// way into it.
///
/// `disabled` + `onBusyChange` let the gate hold one answer at a time — the
/// way out included (a late « Rejoindre » must not land after a sign-out).
export function ProLogoutButton({
  redirectTo = '/pro/connexion',
  disabled = false,
  onBusyChange,
  onSignedOut,
  initialError = null,
}: {
  redirectTo?: string;
  disabled?: boolean;
  /// True while the logout call is out, false when it failed.
  onBusyChange?: (busy: boolean) => void;
  /// The cookies are cleared — called just before the navigation.
  onSignedOut?: () => void;
  /// A host that already tried (the locked page) opens with its message.
  initialError?: string | null;
}) {
  const router = useRouter();
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(initialError);
  const buttonRef = useRef<HTMLButtonElement>(null);

  // The button was disabled while the call was out, which can drop focus to
  // <body>: put it back on the retry, never steal it from elsewhere.
  useEffect(() => {
    if (!error) return;
    const active = document.activeElement;
    if (!active || active === document.body) buttonRef.current?.focus();
  }, [error]);

  async function signOut() {
    setBusy(true);
    setError(null);
    onBusyChange?.(true);
    const outcome = await logoutPro();
    if (outcome === 'ok') {
      // Busy until the page goes: the login replaces this one.
      onSignedOut?.();
      router.replace(redirectTo);
      return;
    }
    setError(logoutErrorMessage(outcome));
    setBusy(false);
    onBusyChange?.(false);
  }

  return (
    <div>
      <Button
        ref={buttonRef}
        variant="secondary"
        disabled={disabled}
        isLoading={busy}
        onClick={signOut}
      >
        Se déconnecter
      </Button>
      {error ? (
        <p role="alert" className="mt-xs text-bodySmall text-error">
          {error}
        </p>
      ) : null}
    </div>
  );
}
