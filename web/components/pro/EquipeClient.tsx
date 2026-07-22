'use client';

import { useEffect, useRef, useState } from 'react';
import { Card } from '../Card';
import { DataTable } from '../DataTable';
import { StatusChip } from '../StatusChip';
import { ErrorState } from '../ErrorState';
import { useRouter } from 'next/navigation';
import {
  getMyProvider,
  getSalonSubscription,
  getTeamMembers,
  resendInvitation,
  revokeMember,
} from '../../lib/api/pro';
import { Modal } from '../Modal';
import { Toast } from '../Toast';
import { useToast } from '../../lib/useToast';
import type { Artist } from '../../lib/pro/catalogue';
import { formatDateFr } from '../../lib/format';
import {
  type SalonOffer,
} from '../../lib/pro/subscription-plans';
import {
  type TeamMember,
  type TeamRole,
  memberStatusBadge,
  seatsLabel,
} from '../../lib/pro/team';
import { Button } from '../Button';
import { SkeletonRows } from '../Skeleton';
import { ChangeRoleDialog } from './ChangeRoleDialog';
import { InviteMemberDialog } from './InviteMemberDialog';
import { TeamRoleChip } from './TeamRoleChip';

function initials(email: string): string {
  const base = email.split('@')[0] ?? email;
  const parts = base.split(/[.\-_]/).filter(Boolean);
  const chars = (parts[0]?.[0] ?? '') + (parts[1]?.[0] ?? parts[0]?.[1] ?? '');
  return chars.toUpperCase() || email.slice(0, 2).toUpperCase();
}

/// /pro/equipe (team access R5a — docs/design/web-team-access-r5.md §2.1).
/// The salon roster as a desktop table: owner pinned + inert, invite dialog,
/// role change, resend, revoke-with-confirm; a seats header from the offer.
export function EquipeClient() {
  const router = useRouter();
  const [providerId, setProviderId] = useState<string | null>(null);
  const [salonName, setSalonName] = useState('ce salon');
  const [artists, setArtists] = useState<Artist[]>([]);
  const [members, setMembers] = useState<TeamMember[]>([]);
  const [offer, setOffer] = useState<SalonOffer | null>(null);
  const [loading, setLoading] = useState(true);
  const [reloadKey, setReloadKey] = useState(0);
  const [error, setError] = useState(false);
  const [inviteOpen, setInviteOpen] = useState(false);
  const [roleTarget, setRoleTarget] = useState<TeamMember | null>(null);
  const [revokeTarget, setRevokeTarget] = useState<TeamMember | null>(null);
  const [menuFor, setMenuFor] = useState<string | null>(null);
  const [busyId, setBusyId] = useState<string | null>(null);
  const { toast, show } = useToast();
  const revokeCancelRef = useRef<HTMLButtonElement>(null);
  // The ⋯ trigger per member — the dialogs' restore target: their true opener
  // (the menu ITEM) unmounts in the same commit the dialog mounts, so Modal's
  // captured activeElement is already gone by close time.
  const dotsRefs = useRef<Record<string, HTMLButtonElement | null>>({});
  const dotsRefFor = (id: string) => ({ current: dotsRefs.current[id] ?? null });

  useEffect(() => {
    (async () => {
      const me = await getMyProvider();
      if (me.status === 401) {
        router.replace('/pro/connexion');
        return;
      }
      if (me.status !== 200 || !me.profile) {
        setError(true);
        setLoading(false);
        return;
      }
      const pid = me.profile.provider.id;
      setProviderId(pid);
      setSalonName(me.profile.provider.name || 'ce salon');
      setArtists(me.profile.provider.artists ?? []);
      const [roster, sub] = await Promise.all([
        getTeamMembers(),
        getSalonSubscription(pid),
      ]);
      if (roster.status === 401) {
        router.replace('/pro/connexion');
        return;
      }
      if (roster.status !== 200) {
        setError(true);
        setLoading(false);
        return;
      }
      setMembers(roster.items);
      if (sub.status === 200 && sub.offer) setOffer(sub.offer);
      setLoading(false);
    })();
  }, [router, reloadKey]);


  function upsert(member: TeamMember) {
    setMembers((prev) => {
      const i = prev.findIndex((m) => m.id === member.id);
      if (i === -1) return [...prev, member];
      const next = [...prev];
      next[i] = member;
      return next;
    });
  }

  async function doResend(m: TeamMember) {
    setBusyId(m.id);
    setMenuFor(null);
    const r = await resendInvitation(m.id);
    setBusyId(null);
    if (!r.ok || !r.member) {
      show(
        r.status === 429
          ? 'Budget de renvois épuisé pour cette invitation.'
          : 'Renvoi impossible. Réessayez.',
      
        'error',
      );
      return;
    }
    upsert(r.member);
    show(`Invitation renvoyée à ${m.email}.`, 'success');
  }

  async function doRevoke() {
    const m = revokeTarget;
    if (!m) return;
    setBusyId(m.id);
    const r = await revokeMember(m.id);
    setBusyId(null);
    setRevokeTarget(null);
    if (!r.ok || !r.member) {
      show('Révocation impossible. Réessayez.', 'error');
      return;
    }
    upsert(r.member);
    show(`Accès de ${m.email} révoqué.`, 'success');
  }

  if (loading) return <SkeletonRows count={4} className="mt-l" />;
  if (error) {
    return <ErrorState title="Équipe" onRetry={() => { setError(false); setLoading(true); setReloadKey((k) => k + 1); }} />;
  }

  const nonOwner = members.filter((m) => m.role !== 'owner');
  const owner = members.find((m) => m.role === 'owner');
  const rows = owner ? [owner, ...nonOwner] : members;

  return (
    <div>
      <div className="flex items-center justify-between gap-m">
        <h1 className="text-headlineSmall font-semibold text-textPrimary">Équipe</h1>
        <Button onClick={() => setInviteOpen(true)}>+ Inviter un membre</Button>
      </div>

      {offer ? (
        <div className="mt-m max-w-sm">
          <p className="text-bodyMedium text-textSecondary">
            {seatsLabel(offer.seats)}
          </p>
          <div className="mt-xs h-2 overflow-hidden rounded-pill bg-surfaceVariant">
            <div
              className="h-full rounded-pill bg-primary"
              style={{
                width: `${Math.min(
                  100,
                  offer.seats.cap === 0
                    ? 0
                    : (offer.seats.used / offer.seats.cap) * 100,
                )}%`,
              }}
            />
          </div>
        </div>
      ) : (
        <p className="mt-m text-bodyMedium text-textSecondary">
          Choisissez votre offre pour inviter votre équipe.{' '}
          <a href="/pro/abonnement" className="underline">
            Choisir mon offre
          </a>
        </p>
      )}

      {nonOwner.length === 0 ? (
        <Card className="mt-l">
          <p className="text-titleMedium font-medium text-textPrimary">
            Invitez votre équipe
          </p>
          <p className="mt-xs text-bodyMedium text-textSecondary">
            Chaque membre a son propre accès. Les collaborateurs ne voient que
            leur propre planning.
          </p>
        </Card>
      ) : null}

      {/* The owner is always pinned at the top of the roster, even alone.
          B7: the hand-rolled <table> re-based on <DataTable> (the reference
          conversion). The ⋯ Actions cell is interactive, so rows carry NO
          onClick (the DataTable contract); the z-dropdown menu keeps the same
          overflow box it always lived in. */}
      <div className="mt-l">
        <DataTable
          columns={[
            { label: 'Membre', flex: 3 },
            { label: 'Rôle', flex: 2 },
            { label: 'Employé', flex: 2 },
            { label: 'Statut', flex: 3 },
            { label: 'Actions', flex: 1, align: 'right' },
          ]}
          emptyTitle="Aucun membre"
          rows={rows.map((m) => {
            const badge = memberStatusBadge(m, formatDateFr);
            const isOwner = m.role === 'owner';
            const isInvited = m.status === 'invited';
            const isRevoked = m.status === 'revoked';
            return {
              key: m.id,
              cells: [
                <div key="who" className="flex items-center gap-s">
                  <span className="flex h-8 w-8 shrink-0 items-center justify-center rounded-pill bg-surfaceVariant text-labelMedium font-medium text-textSecondary">
                    {initials(m.email)}
                  </span>
                  <span className="truncate text-textPrimary">{m.email}</span>
                </div>,
                <TeamRoleChip key="role" role={m.role as TeamRole} />,
                <span key="artist" className="text-textSecondary">
                  {m.role === 'staff' ? (m.artistName ?? '—') : '—'}
                </span>,
                <StatusChip
                  key="status"
                  status={
                    isRevoked
                      ? 'revoked'
                      : isInvited
                        ? m.expired
                          ? 'expired'
                          : 'invited'
                        : 'active'
                  }
                  label={badge?.label ?? 'Actif'}
                  dense
                />,
                isOwner || isRevoked ? (
                  <span key="none" className="text-bodySmall text-textDisabled">
                    —
                  </span>
                ) : (
                  <div key="actions" className="relative inline-block">
                    <button
                      type="button"
                      ref={(el) => {
                        dotsRefs.current[m.id] = el;
                      }}
                      aria-label={`Actions pour ${m.email}`}
                      disabled={busyId === m.id}
                      onClick={() => setMenuFor(menuFor === m.id ? null : m.id)}
                      className="-my-sm flex min-h-12 min-w-12 items-center justify-center rounded-lg text-iconXS text-textSecondary hover:bg-surfaceVariant"
                    >
                      ⋯
                    </button>
                    {menuFor === m.id ? (
                      <div className="absolute right-0 z-dropdown mt-xs w-56 rounded-lg border border-border bg-secondary py-xs text-left shadow-lg">
                        <button
                          type="button"
                          onClick={() => {
                            setMenuFor(null);
                            setRoleTarget(m);
                          }}
                          className="block w-full px-m py-s text-left text-bodyMedium text-textPrimary hover:bg-surfaceVariant"
                        >
                          Changer le rôle
                        </button>
                        {isInvited ? (
                          <button
                            type="button"
                            onClick={() => doResend(m)}
                            className="block w-full px-m py-s text-left text-bodyMedium text-textPrimary hover:bg-surfaceVariant"
                          >
                            Renvoyer l’invitation
                            {typeof m.resendsLeft === 'number'
                              ? ` (${m.resendsLeft} restants)`
                              : ''}
                          </button>
                        ) : null}
                        <button
                          type="button"
                          onClick={() => {
                            setMenuFor(null);
                            setRevokeTarget(m);
                          }}
                          className="block w-full px-m py-s text-left text-bodyMedium text-error hover:bg-surfaceVariant"
                        >
                          Révoquer l’accès
                        </button>
                      </div>
                    ) : null}
                  </div>
                ),
              ],
            };
          })}
        />
      </div>

      <Toast toast={toast} />

      {inviteOpen && providerId ? (
        <InviteMemberDialog
          providerId={providerId}
          artists={artists}
          onArtistCreated={(a) => setArtists((prev) => [...prev, a])}
          onClose={() => setInviteOpen(false)}
          onInvited={(member, email) => {
            upsert(member);
            setInviteOpen(false);
            show(`Invitation envoyée à ${email}.`, 'success');
          }}
        />
      ) : null}

      {roleTarget && providerId ? (
        <ChangeRoleDialog
          returnFocusRef={dotsRefFor(roleTarget.id)}
          member={roleTarget}
          providerId={providerId}
          artists={artists}
          onArtistCreated={(a) => setArtists((prev) => [...prev, a])}
          onClose={() => setRoleTarget(null)}
          onChanged={(member) => {
            upsert(member);
            setRoleTarget(null);
            show('Rôle mis à jour.', 'success');
          }}
        />
      ) : null}

      {revokeTarget ? (
        <Modal
          title="Révoquer l’accès"
          onClose={() => setRevokeTarget(null)}
          returnFocusRef={dotsRefFor(revokeTarget.id)}
          // SYSTEM §15: the cancel path is the safe default and gets focus.
          initialFocusRef={revokeCancelRef}
        >
          <p className="mt-m text-bodyMedium text-textSecondary">
            {revokeTarget.email} perdra immédiatement l’accès à {salonName}.
            Son compte MyWeli n’est pas supprimé.
          </p>
          <div className="mt-l flex justify-end gap-s">
            <Button
              ref={revokeCancelRef}
              variant="secondary"
              onClick={() => setRevokeTarget(null)}
              disabled={busyId === revokeTarget.id}
            >
              Annuler
            </Button>
            <Button
              onClick={doRevoke}
              disabled={busyId === revokeTarget.id}
              className="!bg-error hover:!bg-error"
            >
              Révoquer
            </Button>
          </div>
        </Modal>
      ) : null}
    </div>
  );
}
