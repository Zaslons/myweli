'use client';

import { useEffect, useState } from 'react';
import { createArtistReturning, inviteMember } from '../../lib/api/pro';
import type { Artist } from '../../lib/pro/catalogue';
import {
  ROLE_SUMMARIES,
  type TeamMember,
  type TeamRoleInput,
  teamErrorCta,
  teamErrorMessage,
  validateInviteEmail,
} from '../../lib/pro/team';
import { Button } from '../Button';

const ROLE_ORDER: TeamRoleInput[] = ['manager', 'reception', 'staff'];
const ROLE_LABELS: Record<TeamRoleInput, string> = {
  manager: 'Manager',
  reception: 'Réception',
  staff: 'Collaborateur',
};

/// The 3-step invite dialog (team access R5a — docs/design/web-team-access-r5.md
/// §2.1): e-mail (validated, lowercased) → a role card → for a Collaborateur,
/// the employee fiche (existing or « Créer une fiche » inline). All error copy
/// runs through the shared R3 table so the two surfaces never drift.
export function InviteMemberDialog({
  providerId,
  artists,
  onArtistCreated,
  onClose,
  onInvited,
}: {
  providerId: string;
  artists: Artist[];
  onArtistCreated: (a: Artist) => void;
  onClose: () => void;
  onInvited: (member: TeamMember, email: string) => void;
}) {
  const [stepEmail, setStepEmail] = useState('');
  const [role, setRole] = useState<TeamRoleInput | null>(null);
  const [artistId, setArtistId] = useState<string>('');
  const [creatingFiche, setCreatingFiche] = useState(false);
  const [newFicheName, setNewFicheName] = useState('');
  const [busy, setBusy] = useState(false);
  // The machine code (not the message) — so we can render both the copy and
  // the matching CTA (offer_required/seat_limit → the picker).
  const [errorCode, setErrorCode] = useState<string | undefined>();

  useEffect(() => {
    function onKey(e: KeyboardEvent) {
      if (e.key === 'Escape') onClose();
    }
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [onClose]);

  const checked = validateInviteEmail(stepEmail);
  const cta = teamErrorCta(errorCode);

  async function createFiche() {
    const name = newFicheName.trim();
    if (!name) return;
    setBusy(true);
    setErrorCode(undefined);
    const r = await createArtistReturning(providerId, {
      name,
      specialization: null,
      imageUrl: null,
      workingHours: {},
    });
    setBusy(false);
    if (!r.ok || !r.artist) {
      setErrorCode(r.error ?? 'unknown');
      return;
    }
    onArtistCreated(r.artist);
    setArtistId(r.artist.id);
    setCreatingFiche(false);
    setNewFicheName('');
  }

  async function submit() {
    if (!role) return;
    if (role === 'staff' && !artistId) {
      setErrorCode('artist_required');
      return;
    }
    setBusy(true);
    setErrorCode(undefined);
    const r = await inviteMember({
      email: checked.email,
      role,
      artistId: role === 'staff' ? artistId : undefined,
    });
    setBusy(false);
    if (!r.ok || !r.member) {
      setErrorCode(r.error ?? 'unknown');
      return;
    }
    onInvited(r.member, checked.email);
  }

  return (
    <div
      role="dialog"
      aria-modal="true"
      aria-label="Inviter un membre"
      className="fixed inset-0 z-50 flex items-center justify-center bg-primary/40 p-m"
    >
      <div className="w-full max-w-md rounded-xl border border-border bg-secondary p-l">
        <h2 className="text-lg font-semibold text-textPrimary">
          Inviter un membre
        </h2>

        <label className="mt-m block text-sm text-textSecondary">
          Adresse e-mail
          <input
            type="email"
            inputMode="email"
            autoComplete="off"
            value={stepEmail}
            onChange={(e) => setStepEmail(e.target.value)}
            placeholder="collaborateur@exemple.com"
            className="mt-xs w-full rounded-lg border border-border bg-surface px-m py-s text-sm text-textPrimary"
          />
        </label>

        <fieldset className="mt-m">
          <legend className="text-sm text-textSecondary">Rôle</legend>
          <div className="mt-xs flex flex-col gap-s">
            {ROLE_ORDER.map((r) => (
              <button
                key={r}
                type="button"
                onClick={() => {
                  setRole(r);
                  setErrorCode(undefined);
                }}
                className={`rounded-lg border px-m py-s text-left ${
                  role === r
                    ? 'border-primary bg-surfaceVariant'
                    : 'border-border bg-surface'
                }`}
              >
                <span className="block text-sm font-medium text-textPrimary">
                  {ROLE_LABELS[r]}
                </span>
                <span className="mt-[2px] block text-xs text-textTertiary">
                  {ROLE_SUMMARIES[r]}
                </span>
              </button>
            ))}
          </div>
        </fieldset>

        {role === 'staff' ? (
          <div className="mt-m">
            <p className="text-sm text-textSecondary">Fiche employé</p>
            {creatingFiche ? (
              <div className="mt-xs flex gap-s">
                <input
                  value={newFicheName}
                  onChange={(e) => setNewFicheName(e.target.value)}
                  placeholder="Nom de l’employé"
                  className="flex-1 rounded-lg border border-border bg-surface px-m py-s text-sm text-textPrimary"
                />
                <Button
                  onClick={createFiche}
                  disabled={busy || !newFicheName.trim()}
                >
                  Créer
                </Button>
              </div>
            ) : (
              <div className="mt-xs flex gap-s">
                <select
                  value={artistId}
                  onChange={(e) => setArtistId(e.target.value)}
                  className="flex-1 rounded-lg border border-border bg-surface px-m py-s text-sm text-textPrimary"
                >
                  <option value="">Choisir une fiche…</option>
                  {artists.map((a) => (
                    <option key={a.id} value={a.id}>
                      {a.name}
                    </option>
                  ))}
                </select>
                <Button
                  variant="secondary"
                  onClick={() => setCreatingFiche(true)}
                >
                  Créer une fiche
                </Button>
              </div>
            )}
            <p className="mt-xs text-xs text-textTertiary">
              Un collaborateur ne voit que le planning de sa fiche.
            </p>
          </div>
        ) : null}

        {errorCode ? (
          <p className="mt-s text-sm text-error">
            {teamErrorMessage(errorCode, 'invite')}
          </p>
        ) : null}
        {cta ? (
          <a href={cta.href} className="mt-xs block text-sm underline">
            {cta.label}
          </a>
        ) : null}

        <div className="mt-l flex justify-end gap-s">
          <Button variant="secondary" onClick={onClose} disabled={busy}>
            Annuler
          </Button>
          <Button onClick={submit} disabled={busy || !checked.ok || !role}>
            Envoyer l’invitation
          </Button>
        </div>
      </div>
    </div>
  );
}
