'use client';

import { useEffect, useRef } from 'react';
import { revokedAccessMessage, teamErrorMessage } from '../../lib/pro/team';
import { ProLogoutButton } from './ProLogoutButton';

/// A revoked sign-out whose logout call did not come back OK
/// (docs/design/pro-rejoin-gate.md §2 « échouer fermé », §10). The session —
/// salon-less — still lives in its httpOnly cookies, and only the logout
/// response can clear them; so the login page, which looks signed out, is NOT
/// shown over it. What is shown instead: nothing of a salon (like the gate,
/// it stands in for the dashboard), why the person is leaving, why they have
/// not left yet, and the way out — which retries.
///
/// Every sentence is an existing one: « Espace Pro » (the login's heading),
/// the revoked banner, « Pas de connexion. Réessayez. » or the generic one.
export function ProSignOutRetry({
  lostSalon,
  error,
  redirectTo,
  onSignedOut,
}: {
  /// The salon whose access was withdrawn, when this tab knew it.
  lostSalon: string;
  /// Why the first sign-out did not happen.
  error: string;
  /// The landing the sign-out was headed for (its banner, its reason).
  redirectTo: string;
  onSignedOut: () => void;
}) {
  // The page was swapped without a navigation: say where the person is.
  const headingRef = useRef<HTMLHeadingElement>(null);
  useEffect(() => {
    headingRef.current?.focus();
  }, []);

  return (
    <main className="mx-auto max-w-md px-m py-l">
      <h1
        ref={headingRef}
        tabIndex={-1}
        className="text-headlineSmall font-semibold text-textPrimary"
      >
        Espace Pro
      </h1>
      <p className="mt-m rounded-lg border border-error/40 bg-error/10 p-m text-bodyMedium text-error">
        {lostSalon
          ? revokedAccessMessage(lostSalon)
          : teamErrorMessage('not_a_member')}
      </p>
      <div className="mt-m">
        <ProLogoutButton
          redirectTo={redirectTo}
          initialError={error}
          onSignedOut={onSignedOut}
        />
      </div>
    </main>
  );
}
