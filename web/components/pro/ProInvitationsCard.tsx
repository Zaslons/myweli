'use client';

import { useEffect, useState } from 'react';
import {
  acceptMyInvitation,
  declineMyInvitation,
  getMyInvitations,
} from '../../lib/api/pro';
import { formatDateFr } from '../../lib/format';
import { type TeamInvitation, teamErrorMessage } from '../../lib/pro/team';
import { Button } from '../Button';

/// The dashboard invitations card (team access R5a): the signed-in provider's
/// OWN pending invitations. Rendered only when there is at least one — a
/// silent no-op otherwise. Accept lands them in the salon; decline drops the
/// row. `onAccepted` lets the host refresh (a new membership may reshape the
/// session in R5b).
export function ProInvitationsCard({
  onAccepted,
}: {
  onAccepted?: () => void;
}) {
  const [invitations, setInvitations] = useState<TeamInvitation[]>([]);
  const [busyId, setBusyId] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    (async () => {
      const r = await getMyInvitations();
      if (r.status === 200) setInvitations(r.invitations);
    })();
  }, []);

  async function accept(inv: TeamInvitation) {
    setBusyId(inv.id);
    setError(null);
    const r = await acceptMyInvitation(inv.id);
    setBusyId(null);
    if (!r.ok) {
      setError(teamErrorMessage(r.error));
      return;
    }
    setInvitations((prev) => prev.filter((i) => i.id !== inv.id));
    onAccepted?.();
  }

  async function decline(inv: TeamInvitation) {
    setBusyId(inv.id);
    setError(null);
    const r = await declineMyInvitation(inv.id);
    setBusyId(null);
    if (!r.ok) {
      setError(teamErrorMessage(r.error));
      return;
    }
    setInvitations((prev) => prev.filter((i) => i.id !== inv.id));
  }

  if (invitations.length === 0) return null;

  return (
    <section className="mt-m rounded-xl border border-border bg-secondary p-l">
      <p className="font-semibold text-textPrimary">Invitations d’équipe</p>
      <ul className="mt-m space-y-s">
        {invitations.map((inv) => (
          <li
            key={inv.id}
            className="flex flex-wrap items-center justify-between gap-s rounded-lg border border-border bg-surface p-m"
          >
            <div>
              <p className="text-sm text-textPrimary">
                <span className="font-semibold">{inv.salonName}</span> vous
                invite comme {inv.roleLabel}
              </p>
              <p className="text-xs text-textTertiary">
                Expire le {formatDateFr(inv.expiresAt)}
              </p>
            </div>
            <div className="flex gap-s">
              <Button disabled={busyId === inv.id} onClick={() => accept(inv)}>
                Rejoindre
              </Button>
              <button
                type="button"
                disabled={busyId === inv.id}
                onClick={() => decline(inv)}
                className="text-sm text-textTertiary underline disabled:opacity-60"
              >
                Refuser
              </button>
            </div>
          </li>
        ))}
      </ul>
      {error ? <p className="mt-s text-sm text-error">{error}</p> : null}
    </section>
  );
}
