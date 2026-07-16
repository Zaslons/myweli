'use client';

import { useEffect, useState } from 'react';
import { useRouter } from 'next/navigation';
import {
  getMyProvider,
  getSalonSubscription,
  getTeamMembers,
  resendInvitation,
  revokeMember,
} from '../../lib/api/pro';
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
  const [error, setError] = useState(false);
  const [inviteOpen, setInviteOpen] = useState(false);
  const [roleTarget, setRoleTarget] = useState<TeamMember | null>(null);
  const [revokeTarget, setRevokeTarget] = useState<TeamMember | null>(null);
  const [menuFor, setMenuFor] = useState<string | null>(null);
  const [busyId, setBusyId] = useState<string | null>(null);
  const [toast, setToast] = useState<string | null>(null);

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
  }, [router]);

  function showToast(msg: string) {
    setToast(msg);
    setTimeout(() => setToast(null), 4000);
  }

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
      showToast(
        r.status === 429
          ? 'Budget de renvois épuisé pour cette invitation.'
          : 'Renvoi impossible. Réessayez.',
      );
      return;
    }
    upsert(r.member);
    showToast(`Invitation renvoyée à ${m.email}.`);
  }

  async function doRevoke() {
    const m = revokeTarget;
    if (!m) return;
    setBusyId(m.id);
    const r = await revokeMember(m.id);
    setBusyId(null);
    setRevokeTarget(null);
    if (!r.ok || !r.member) {
      showToast('Révocation impossible. Réessayez.');
      return;
    }
    upsert(r.member);
    showToast(`Accès de ${m.email} révoqué.`);
  }

  if (loading) return <p className="text-textSecondary">Chargement…</p>;
  if (error) {
    return <p className="text-error">Une erreur est survenue. Réessayez.</p>;
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
        <div className="mt-l rounded-xl border border-border bg-secondary p-l">
          <p className="text-titleMedium font-medium text-textPrimary">
            Invitez votre équipe
          </p>
          <p className="mt-xs text-bodyMedium text-textSecondary">
            Chaque membre a son propre accès. Les collaborateurs ne voient que
            leur propre planning.
          </p>
        </div>
      ) : null}

      {/* The owner is always pinned at the top of the roster, even alone. */}
      <div className="mt-l overflow-x-auto rounded-xl border border-border">
        <table
          // ds-ignore: the roster's minimum column budget before the wrapper scrolls — a
          // table-specific measure, not a shared size.
          // eslint-disable-next-line tailwindcss/no-arbitrary-value
          className="w-full min-w-[640px] border-collapse text-bodyMedium"
        >
            <thead>
              <tr className="border-b border-divider text-left text-textTertiary">
                <th className="px-m py-s font-medium">Membre</th>
                <th className="px-m py-s font-medium">Rôle</th>
                <th className="px-m py-s font-medium">Employé</th>
                <th className="px-m py-s font-medium">Statut</th>
                <th className="px-m py-s font-medium" />
              </tr>
            </thead>
            <tbody>
              {rows.map((m) => {
                const badge = memberStatusBadge(m, formatDateFr);
                const isOwner = m.role === 'owner';
                const isInvited = m.status === 'invited';
                const isRevoked = m.status === 'revoked';
                return (
                  <tr
                    key={m.id}
                    className="border-b border-divider last:border-0"
                  >
                    <td className="px-m py-s">
                      <div className="flex items-center gap-s">
                        <span className="flex h-8 w-8 items-center justify-center rounded-pill bg-surfaceVariant text-labelMedium font-medium text-textSecondary">
                          {initials(m.email)}
                        </span>
                        <span className="text-textPrimary">{m.email}</span>
                      </div>
                    </td>
                    <td className="px-m py-s">
                      <TeamRoleChip role={m.role as TeamRole} />
                    </td>
                    <td className="px-m py-s text-textSecondary">
                      {m.role === 'staff' ? (m.artistName ?? '—') : '—'}
                    </td>
                    <td className="px-m py-s">
                      {badge ? (
                        <span
                          className={
                            badge.tone === 'error'
                              ? 'text-error'
                              : 'text-textTertiary'
                          }
                        >
                          {badge.label}
                        </span>
                      ) : (
                        <span className="text-textTertiary">Actif</span>
                      )}
                    </td>
                    <td className="px-m py-s text-right">
                      {isOwner || isRevoked ? (
                        <span className="text-bodySmall text-textDisabled">—</span>
                      ) : (
                        <div className="relative inline-block">
                          <button
                            type="button"
                            aria-label={`Actions pour ${m.email}`}
                            disabled={busyId === m.id}
                            onClick={() =>
                              setMenuFor(menuFor === m.id ? null : m.id)
                            }
                            className="-mx-s -my-sm flex min-h-12 min-w-12 items-center justify-center rounded-lg text-iconXS text-textSecondary hover:bg-surfaceVariant"
                          >
                            ⋯
                          </button>
                          {menuFor === m.id ? (
                            <div className="absolute right-0 z-dropdown mt-xs w-56 rounded-lg border border-border bg-secondary py-xs shadow-lg">
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
                      )}
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>

      {toast ? (
        <div
          role="status"
          className="fixed bottom-l left-1/2 -translate-x-1/2 rounded-lg bg-primary px-l py-s text-bodyMedium text-secondary shadow-lg"
        >
          {toast}
        </div>
      ) : null}

      {inviteOpen && providerId ? (
        <InviteMemberDialog
          providerId={providerId}
          artists={artists}
          onArtistCreated={(a) => setArtists((prev) => [...prev, a])}
          onClose={() => setInviteOpen(false)}
          onInvited={(member, email) => {
            upsert(member);
            setInviteOpen(false);
            showToast(`Invitation envoyée à ${email}.`);
          }}
        />
      ) : null}

      {roleTarget && providerId ? (
        <ChangeRoleDialog
          member={roleTarget}
          providerId={providerId}
          artists={artists}
          onArtistCreated={(a) => setArtists((prev) => [...prev, a])}
          onClose={() => setRoleTarget(null)}
          onChanged={(member) => {
            upsert(member);
            setRoleTarget(null);
            showToast('Rôle mis à jour.');
          }}
        />
      ) : null}

      {revokeTarget ? (
        <div
          role="dialog"
          aria-modal="true"
          aria-label="Révoquer l’accès"
          className="fixed inset-0 z-modal flex items-center justify-center bg-primary/40 p-m"
        >
          <div className="w-full max-w-md rounded-xl border border-border bg-secondary p-l">
            <h2 className="text-titleLarge font-semibold text-textPrimary">
              Révoquer l’accès
            </h2>
            <p className="mt-m text-bodyMedium text-textSecondary">
              {revokeTarget.email} perdra immédiatement l’accès à {salonName}.
              Son compte MyWeli n’est pas supprimé.
            </p>
            <div className="mt-l flex justify-end gap-s">
              <Button
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
          </div>
        </div>
      ) : null}
    </div>
  );
}
