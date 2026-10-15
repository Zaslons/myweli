'use client';

import { useEffect, useState } from 'react';
import { Card } from '../Card';
import {
  acceptMyInvitation,
  declineMyInvitation,
  getMyInvitations,
} from '../../lib/api/pro';
import { formatDateFr } from '../../lib/format';
import {
  NO_CONNECTION_MESSAGE,
  type TeamInvitation,
  invitationActionError,
} from '../../lib/pro/team';
import { Button } from '../Button';

type Busy = { id: string; action: 'accept' | 'decline' } | null;

/// The invitations card (team access R5a): the signed-in provider's OWN
/// pending invitations. On « Aujourd'hui » it loads its own list and renders
/// nothing when there is none. The rejoin gate (docs/design/pro-rejoin-gate.md
/// §3) reuses it with the list it already holds (`initial` — no second fetch,
/// no loading state) and needs to know when the last card goes (`onEmptied`).
///
/// Parity with the app's ProTeamProvider: a card the server says is gone
/// (`invitation_expired`, `not_found`) is removed along with its message, and
/// no failed request — a refusal or no network at all — can leave the buttons
/// disabled. One action at a time: every button waits while one is out.
export function ProInvitationsCard({
  initial,
  onAccepted,
  onEmptied,
}: {
  /// The host's list — skips the fetch.
  initial?: TeamInvitation[];
  /// After a successful accept (never followed by `onEmptied`).
  onAccepted?: (inv: TeamInvitation) => void;
  /// The last card was declined, or the server said it is gone.
  onEmptied?: () => void;
}) {
  const [invitations, setInvitations] = useState<TeamInvitation[]>(
    initial ?? [],
  );
  const [busy, setBusy] = useState<Busy>(null);
  const [error, setError] = useState<string | null>(null);
  const hostOwnsList = initial !== undefined;

  useEffect(() => {
    if (hostOwnsList) return;
    let active = true;
    (async () => {
      // Silent on failure, as the app's loadMyInvitations: the card simply
      // does not show.
      const r = await getMyInvitations().catch(() => null);
      if (active && r?.status === 200) setInvitations(r.invitations);
    })();
    return () => {
      active = false;
    };
  }, [hostOwnsList]);

  /// Drops one card; tells the host when none is left.
  function remove(id: string) {
    const rest = invitations.filter((i) => i.id !== id);
    setInvitations(rest);
    if (rest.length === 0) onEmptied?.();
  }

  async function accept(inv: TeamInvitation) {
    setBusy({ id: inv.id, action: 'accept' });
    setError(null);
    let r: Awaited<ReturnType<typeof acceptMyInvitation>>;
    try {
      r = await acceptMyInvitation(inv.id);
    } catch {
      setError(NO_CONNECTION_MESSAGE);
      return;
    } finally {
      setBusy(null);
    }
    if (!r.ok) {
      setError(invitationActionError(r.error, 'accept'));
      if (r.error === 'invitation_expired' || r.error === 'not_found') {
        remove(inv.id);
      }
      return;
    }
    setInvitations((prev) => prev.filter((i) => i.id !== inv.id));
    onAccepted?.(inv);
  }

  async function decline(inv: TeamInvitation) {
    setBusy({ id: inv.id, action: 'decline' });
    setError(null);
    let r: Awaited<ReturnType<typeof declineMyInvitation>>;
    try {
      r = await declineMyInvitation(inv.id);
    } catch {
      setError(NO_CONNECTION_MESSAGE);
      return;
    } finally {
      setBusy(null);
    }
    if (!r.ok) {
      setError(invitationActionError(r.error, 'decline'));
      return;
    }
    remove(inv.id);
  }

  // A card removed with a message keeps the message on screen.
  if (invitations.length === 0 && !error) return null;

  return (
    <Card as="section" className="mt-m">
      <p className="font-semibold text-textPrimary">Invitations d’équipe</p>
      {invitations.length > 0 ? (
        <ul className="mt-m space-y-s">
          {invitations.map((inv) => (
            <li
              key={inv.id}
              className="flex flex-wrap items-center justify-between gap-s rounded-lg border border-border bg-surface p-m"
            >
              <div>
                <p className="text-bodyLarge text-textPrimary">
                  <span className="font-semibold">{inv.salonName}</span> vous
                  invite comme {inv.roleLabel}
                </p>
                <p className="text-bodySmall text-textTertiary">
                  Expire le {formatDateFr(inv.expiresAt)}
                </p>
              </div>
              <div className="flex flex-wrap gap-s">
                <Button
                  disabled={busy !== null}
                  isLoading={busy?.id === inv.id && busy.action === 'accept'}
                  onClick={() => accept(inv)}
                >
                  Rejoindre
                </Button>
                <Button
                  variant="text"
                  disabled={busy !== null}
                  isLoading={busy?.id === inv.id && busy.action === 'decline'}
                  onClick={() => decline(inv)}
                >
                  Refuser
                </Button>
              </div>
            </li>
          ))}
        </ul>
      ) : null}
      {error ? (
        <p role="alert" className="mt-s text-bodyMedium text-error">
          {error}
        </p>
      ) : null}
    </Card>
  );
}
