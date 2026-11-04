'use client';

import { useEffect, useId, useRef, useState } from 'react';
import { Card } from '../Card';
import {
  acceptMyInvitation,
  declineMyInvitation,
  getMyInvitations,
} from '../../lib/api/pro';
import { formatDateFr } from '../../lib/format';
import {
  type GateExitReason,
  NO_CONNECTION_MESSAGE,
  type TeamInvitation,
  invitationActionError,
} from '../../lib/pro/team';
import { Button } from '../Button';
import { UNNAMED_SALON_AT_SENTENCE_START, salonNameOr } from '../../lib/salon-name';

type Busy = { id: string; action: 'accept' | 'decline' } | null;

/// The invitations card (team access R5a): the signed-in provider's OWN
/// pending invitations. On « Aujourd'hui » it loads its own list and renders
/// nothing when there is none. The rejoin gate (docs/design/pro-rejoin-gate.md
/// §3) reuses it with the list it already holds (`initial` — no second fetch,
/// no loading state) and needs to know when the last card goes (`onEmptied`,
/// with the server's reason when it was the server's call), when the session
/// died under it (`onUnauthenticated`), and when an answer is out
/// (`onBusyChange` — the gate's « Se déconnecter » waits for it, and
/// `disabled` holds these buttons while that one is out).
///
/// Parity with the app's ProTeamProvider: a card the server says is gone
/// (`invitation_expired`, `not_found`) is removed along with its message, and
/// no failed request — a refusal or no network at all — can leave the buttons
/// disabled. One action at a time: every button waits while one is out.
///
/// A removed card took the pressed button with it: focus moves to the card
/// now in front (the next one, or the previous when the last of the list
/// went) — its « Rejoindre », described by its own sentence, so a screen
/// reader hears where it now is. Never left on <body>.
export function ProInvitationsCard({
  initial,
  onAccepted,
  onEmptied,
  onUnauthenticated,
  onBusyChange,
  disabled = false,
}: {
  /// The host's list — skips the fetch.
  initial?: TeamInvitation[];
  /// After a successful accept (never followed by `onEmptied`).
  onAccepted?: (inv: TeamInvitation) => void;
  /// The last card was declined (no reason), or the server said it is gone.
  onEmptied?: (reason?: GateExitReason) => void;
  /// An accept/decline answered 401: the session is gone. Without it, the
  /// action's own failure sentence shows (the « Aujourd'hui » card, whose page
  /// guards own the redirect).
  onUnauthenticated?: () => void;
  /// True while an accept/decline is out, false once it answered.
  onBusyChange?: (busy: boolean) => void;
  /// The host has an answer of its own out.
  disabled?: boolean;
}) {
  const [invitations, setInvitations] = useState<TeamInvitation[]>(
    initial ?? [],
  );
  const [busy, setBusy] = useState<Busy>(null);
  const [error, setError] = useState<string | null>(null);
  const hostOwnsList = initial !== undefined;
  const uid = useId();
  const listRef = useRef<HTMLUListElement>(null);
  const joinButtons = useRef(new Map<string, HTMLButtonElement>());
  /// The card to focus once the render that removed one has landed.
  const focusNext = useRef<string | null>(null);

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

  // After a removal: the card now in front takes focus — unless the person
  // already moved it somewhere else (never steal it).
  useEffect(() => {
    const id = focusNext.current;
    if (!id) return;
    focusNext.current = null;
    const active = document.activeElement;
    const lost = !active || active === document.body;
    if (!lost && !listRef.current?.contains(active)) return;
    joinButtons.current.get(id)?.focus();
  });

  /// Drops one card; tells the host when none is left (and why, when the
  /// server decided it).
  function remove(id: string, reason?: GateExitReason) {
    const index = invitations.findIndex((i) => i.id === id);
    const rest = invitations.filter((i) => i.id !== id);
    setInvitations(rest);
    if (rest.length === 0) {
      onEmptied?.(reason);
      return;
    }
    focusNext.current = rest[Math.min(Math.max(index, 0), rest.length - 1)].id;
  }

  function start(next: Busy) {
    setBusy(next);
    setError(null);
    onBusyChange?.(true);
  }

  function done() {
    setBusy(null);
    onBusyChange?.(false);
  }

  async function accept(inv: TeamInvitation) {
    start({ id: inv.id, action: 'accept' });
    const r = await acceptMyInvitation(inv.id);
    done();
    if (!r.ok) {
      // Status 0 = no answer (the wrapper never throws —
      // docs/design/web-pro-network-failure.md §3).
      if (r.status === 0) {
        setError(NO_CONNECTION_MESSAGE);
        return;
      }
      if (r.status === 401 && onUnauthenticated) {
        onUnauthenticated();
        return;
      }
      setError(invitationActionError(r.error, 'accept'));
      if (r.error === 'invitation_expired' || r.error === 'not_found') {
        remove(inv.id, r.error);
      }
      return;
    }
    setInvitations((prev) => prev.filter((i) => i.id !== inv.id));
    onAccepted?.(inv);
  }

  async function decline(inv: TeamInvitation) {
    start({ id: inv.id, action: 'decline' });
    const r = await declineMyInvitation(inv.id);
    done();
    if (!r.ok) {
      if (r.status === 0) {
        setError(NO_CONNECTION_MESSAGE);
        return;
      }
      if (r.status === 401 && onUnauthenticated) {
        onUnauthenticated();
        return;
      }
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
        <ul ref={listRef} className="mt-m space-y-s">
          {invitations.map((inv) => {
            const sentenceId = `${uid}-${inv.id}`;
            return (
              <li
                key={inv.id}
                className="flex flex-wrap items-center justify-between gap-s rounded-lg border border-border bg-surface p-m"
              >
                <div>
                  <p id={sentenceId} className="text-bodyLarge text-textPrimary">
                    <span className="font-semibold">
                  {salonNameOr(inv.salonName, UNNAMED_SALON_AT_SENTENCE_START)}
                </span>{' '}
                vous
                    invite comme {inv.roleLabel}
                  </p>
                  <p className="text-bodySmall text-textTertiary">
                    Expire le {formatDateFr(inv.expiresAt)}
                  </p>
                </div>
                <div className="flex flex-wrap gap-s">
                  <Button
                    ref={(el) => {
                      if (el) joinButtons.current.set(inv.id, el);
                      else joinButtons.current.delete(inv.id);
                    }}
                    aria-describedby={sentenceId}
                    disabled={disabled || busy !== null}
                    isLoading={busy?.id === inv.id && busy.action === 'accept'}
                    onClick={() => accept(inv)}
                  >
                    Rejoindre
                  </Button>
                  <Button
                    variant="text"
                    aria-describedby={sentenceId}
                    disabled={disabled || busy !== null}
                    isLoading={busy?.id === inv.id && busy.action === 'decline'}
                    onClick={() => decline(inv)}
                  >
                    Refuser
                  </Button>
                </div>
              </li>
            );
          })}
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
