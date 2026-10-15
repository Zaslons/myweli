'use client';

import { useEffect, useRef } from 'react';
import { Loading } from '../Loading';
import { type TeamInvitation, revokedAccessMessage } from '../../lib/pro/team';
import { ProInvitationsCard } from './ProInvitationsCard';
import { ProLogoutButton } from './ProLogoutButton';

/// The « Invitations » page of the rejoin gate (docs/design/pro-rejoin-gate.md
/// §3): what a revoked account with a pending invitation sees INSTEAD of the
/// dashboard. ProMembershipProvider renders it in place of its children, and
/// ProShell lives in those children — so no sidebar, no drawer, no bell, no
/// profil: nothing of the lost salon is reachable from here. The only ways on
/// are « Rejoindre », « Refuser » and « Se déconnecter ».
///
/// It wears the /pro/connexion look (one column, `max-w-md`) and brings its
/// own `<main>`, since ProShell's is gone with the children. The list arrives
/// already loaded (S1: no spinner); `joining` is S2's wait between a
/// successful accept and the joined salon's dashboard.
export function ProRevokedInvitations({
  invitations,
  lostSalon,
  joining,
  onJoined,
  onEmptied,
}: {
  invitations: TeamInvitation[];
  /// The salon whose access was withdrawn, when this session knew it (a
  /// revocation mid-session). Empty after a fresh login: the line is then
  /// left out rather than put « ce salon » above another salon's card.
  lostSalon: string;
  joining: boolean;
  onJoined: (inv: TeamInvitation) => void;
  onEmptied: () => void;
}) {
  // The whole page was swapped without a navigation: move focus to its
  // heading so a screen reader says where the person now is, instead of
  // leaving focus on an element that no longer exists.
  const headingRef = useRef<HTMLHeadingElement>(null);
  useEffect(() => {
    headingRef.current?.focus();
  }, []);

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
        {joining ? null : (
          <ProLogoutButton redirectTo="/pro/connexion?motif=acces-retire" />
        )}
      </div>

      {joining ? (
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
          />
        </>
      )}
    </main>
  );
}
