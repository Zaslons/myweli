'use client';

import { useEffect, useState } from 'react';
import { changeMemberRole, createArtistReturning } from '../../lib/api/pro';
import type { Artist } from '../../lib/pro/catalogue';
import {
  ROLE_SUMMARIES,
  type TeamMember,
  type TeamRoleInput,
  teamErrorMessage,
} from '../../lib/pro/team';
import { Button } from '../Button';

const ROLE_ORDER: TeamRoleInput[] = ['manager', 'reception', 'staff'];
const ROLE_LABELS: Record<TeamRoleInput, string> = {
  manager: 'Manager',
  reception: 'Réception',
  staff: 'Collaborateur',
};

/// Change a member's role (team access R5a). Reuses the invite role cards;
/// a Collaborateur must carry an employee fiche.
export function ChangeRoleDialog({
  member,
  providerId,
  artists,
  onArtistCreated,
  onClose,
  onChanged,
}: {
  member: TeamMember;
  providerId: string;
  artists: Artist[];
  onArtistCreated: (a: Artist) => void;
  onClose: () => void;
  onChanged: (member: TeamMember) => void;
}) {
  const initialRole =
    member.role === 'owner' ? 'manager' : (member.role as TeamRoleInput);
  const [role, setRole] = useState<TeamRoleInput>(initialRole);
  const [artistId, setArtistId] = useState<string>(member.artistId ?? '');
  const [creatingFiche, setCreatingFiche] = useState(false);
  const [newFicheName, setNewFicheName] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | undefined>();

  useEffect(() => {
    function onKey(e: KeyboardEvent) {
      if (e.key === 'Escape') onClose();
    }
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [onClose]);

  async function createFiche() {
    const name = newFicheName.trim();
    if (!name) return;
    setBusy(true);
    setError(undefined);
    const r = await createArtistReturning(providerId, {
      name,
      specialization: null,
      imageUrl: null,
      workingHours: {},
    });
    setBusy(false);
    if (!r.ok || !r.artist) {
      setError(teamErrorMessage(r.error));
      return;
    }
    onArtistCreated(r.artist);
    setArtistId(r.artist.id);
    setCreatingFiche(false);
    setNewFicheName('');
  }

  async function submit() {
    if (role === 'staff' && !artistId) {
      setError(teamErrorMessage('artist_required'));
      return;
    }
    setBusy(true);
    setError(undefined);
    const r = await changeMemberRole(member.id, {
      role,
      artistId: role === 'staff' ? artistId : undefined,
    });
    setBusy(false);
    if (!r.ok || !r.member) {
      setError(teamErrorMessage(r.error));
      return;
    }
    onChanged(r.member);
  }

  return (
    <div
      role="dialog"
      aria-modal="true"
      aria-label="Changer le rôle"
      className="fixed inset-0 z-50 flex items-center justify-center bg-primary/40 p-m"
    >
      <div className="w-full max-w-md rounded-xl border border-border bg-secondary p-l">
        <h2 className="text-lg font-semibold text-textPrimary">
          Changer le rôle
        </h2>
        <p className="mt-xs text-sm text-textTertiary">{member.email}</p>

        <div className="mt-m flex flex-col gap-s">
          {ROLE_ORDER.map((r) => (
            <button
              key={r}
              type="button"
              onClick={() => {
                setRole(r);
                setError(undefined);
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
          </div>
        ) : null}

        {error ? <p className="mt-s text-sm text-error">{error}</p> : null}

        <div className="mt-l flex justify-end gap-s">
          <Button variant="secondary" onClick={onClose} disabled={busy}>
            Annuler
          </Button>
          <Button onClick={submit} disabled={busy}>
            Enregistrer
          </Button>
        </div>
      </div>
    </div>
  );
}
