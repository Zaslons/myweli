'use client';

import { useEffect, useRef, useState } from 'react';
import { Loading } from '../Loading';
import {
  type GateExitReason,
  REVOKED_LANDING,
  type TeamInvitation,
  revokedAccessMessage,
} from '../../lib/pro/team';
import { ProInvitationsCard } from './ProInvitationsCard';
import { ProLogoutButton } from './ProLogoutButton';

/// The « Invitations » page of the rejoin gate (docs/design/pro-rejoin-gate.md
/// §3): what a revoked account with a pending invitation sees INSTEAD of the
/// dashboard. ProMembershipProvider renders it in place of its children, and
/// ProShell lives in those children — so no sidebar, no drawer, no bell, no
/// profil: nothing of the lost salon is reachable from here. The only ways on
/// are « Rejoindre », « Refuser » and « Se déconnecter » — one answer at a
/// time, the way out included: while a card's answer is out the logout waits,
/// and while the logout is out the cards wait (a late « Rejoindre » must never
/// land after a sign-out).
///
/// It wears the /pro/connexion look (one column, `max-w-md`) and brings its
/// own `<main>`, since ProShell's is gone with the children. The list arrives
/// already loaded (S1: no spinner); `waiting` is the full-page wait between an
/// outcome and where it leads — S2's join on its way to the salon, S6's
/// sign-out on its way to the login — during which nothing is actionable.
export function ProRevokedInvitations({
  invitations,
  lostSalon,
  waiting,
  onJoined,
  onEmptied,
  onUnauthenticated,
  onSignedOut,
}: {
  invitations: TeamInvitation[];
  /// The salon whose access was withdrawn, when this tab knew it (a
  /// revocation seen mid-session). Empty after a login or a page load — the
  /// web keeps no membership cache — and the line is then left out rather
  /// than put « ce salon » above another salon's card.
  lostSalon: string;
  waiting: boolean;
  onJoined: (inv: TeamInvitation) => void;
  onEmptied: (reason?: GateExitReason) => void;
  onUnauthenticated: () => void;
  onSignedOut: () => void;
}) {
  const [cardBusy, setCardBusy] = useState(false);
  const [logoutBusy, setLogoutBusy] = useState(false);

  // The whole page was swapped without a navigation — and each wait swaps
  // its content again: focus goes to the heading, so a screen reader says
  // where the person now is instead of losing them on <body> with the
  // element that just went.
  const headingRef = useRef<HTMLHeadingElement>(null);
  useEffect(() => {
    headingRef.current?.focus();
  }, [waiting]);

  return (
    <main className="mx-auto max-w-md px-m py-l">
      <div className="flex flex-wrap items-center justify-between gap-s">
        <h1
          ref={headingRef}
          tabIndex={-1}
          className="text-headlineSmall font-semibold text-textPrimary"
        >
          Invitations
        </h1>
        {waiting ? null : (
          <ProLogoutButton
            redirectTo={REVOKED_LANDING}
            disabled={cardBusy}
            onBusyChange={setLogoutBusy}
            onSignedOut={onSignedOut}
          />
        )}
      </div>

      {waiting ? (
        <Loading className="mt-l" />
      ) : (
        <>
          {lostSalon ? (
            <p
              role="alert"
              className="mt-m rounded-lg border border-error/40 bg-error/10 p-m text-bodyMedium text-error"
            >
              {revokedAccessMessage(lostSalon)}
            </p>
          ) : null}
          <p className="mt-m text-bodyLarge text-textSecondary">
            Un salon vous a invité à rejoindre son équipe.
          </p>
          <ProInvitationsCard
            initial={invitations}
            onAccepted={onJoined}
            onEmptied={onEmptied}
            onUnauthenticated={onUnauthenticated}
            onBusyChange={setCardBusy}
            disabled={logoutBusy}
          />
        </>
      )}
    </main>
  );
}
