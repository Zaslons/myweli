'use client';

import { useRouter } from 'next/navigation';
import { useState } from 'react';
import type { ProProfile } from '../../lib/api/pro';
import {
  deleteProAccount,
  getEarnings,
  listClients,
  listProAppointments,
} from '../../lib/api/pro';
import { buildProviderDataExport } from '../../lib/pro/export';
import { Button } from '../Button';
import { TextField } from '../TextField';

/// « Compte » danger zone on /pro/profil (audit 11.5 — AUTH-004/005 for
/// pros): the data export (client-side assembly, like the consumer page) and
/// the type-SUPPRIMER deletion. Design:
/// docs/design/pro-account-deletion-export.md.
/// Team access R5b: `exportEnabled=false` = the MEMBER variant — deletion
/// parity for everyone, but the salon-data export stays with profile.manage
/// (a member deletes their own account, not the salon).
export function CompteDangerSection({
  profile,
  exportEnabled = true,
}: {
  profile: ProProfile;
  exportEnabled?: boolean;
}) {
  const router = useRouter();
  const [exporting, setExporting] = useState(false);
  const [copied, setCopied] = useState(false);
  const [confirmDelete, setConfirmDelete] = useState(false);
  const [deleteText, setDeleteText] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function assembleJson(): Promise<string> {
    const providerId = profile.provider.id;
    const [appts, clients, earnings] = await Promise.all([
      listProAppointments(),
      listClients(providerId),
      getEarnings(providerId, null),
    ]);
    return JSON.stringify(
      buildProviderDataExport({
        profile,
        appointments: appts.items,
        clients: clients.list?.items ?? [],
        earnings: earnings.earnings ?? null,
      }),
      null,
      2,
    );
  }

  async function download() {
    setExporting(true);
    const json = await assembleJson();
    setExporting(false);
    const blob = new Blob([json], { type: 'application/json' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = 'myweli-salon-donnees.json';
    a.click();
    URL.revokeObjectURL(url);
  }

  async function copy() {
    setExporting(true);
    const json = await assembleJson();
    setExporting(false);
    await navigator.clipboard.writeText(json);
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  }

  async function remove() {
    setBusy(true);
    setError(null);
    const r = await deleteProAccount();
    setBusy(false);
    if (!r.ok) {
      setError(
        r.error === 'future_bookings'
          ? 'Terminez ou annulez vos rendez-vous à venir avant de supprimer votre compte.'
          : 'La suppression a échoué. Réessayez.',
      );
      return;
    }
    router.replace('/pro/connexion');
  }

  return (
    <section className="mt-l rounded-xl border border-border bg-secondary p-m">
      <h2 className="text-titleLarge font-semibold text-textPrimary">Compte</h2>

      {exportEnabled ? (
        <div className="mt-s flex items-center justify-between gap-m">
          <p className="text-bodyMedium text-textSecondary">
            Recevoir une copie des données de votre salon (compte, fiche,
            catalogue, rendez-vous, fichier clients, revenus).
          </p>
          <div className="flex shrink-0 gap-s">
            <Button variant="secondary" disabled={exporting} onClick={download}>
              {exporting ? 'Préparation…' : 'Exporter (JSON)'}
            </Button>
            <Button variant="secondary" disabled={exporting} onClick={copy}>
              {copied ? 'Copié ✓' : 'Copier'}
            </Button>
            <span role="status" className="sr-only">
              {copied ? 'Données copiées.' : ''}
            </span>
          </div>
        </div>
      ) : null}

      <div
        className={
          exportEnabled ? 'mt-m border-t border-divider pt-m' : 'mt-s'
        }
      >
        {!confirmDelete ? (
          <button
            type="button"
            onClick={() => {
              setConfirmDelete(true);
              setDeleteText('');
              setError(null);
            }}
            className="text-bodyMedium text-error underline"
          >
            Supprimer mon compte
          </button>
        ) : (
          <div className="rounded-lg bg-surface p-m">
            <p className="text-bodyMedium text-textSecondary">
              {exportEnabled
                ? 'Cette action est définitive. Votre salon sera retiré de MyWeli. Pensez à exporter vos données avant. Tapez SUPPRIMER pour confirmer.'
                : 'Cette action est définitive. Votre compte MyWeli Pro sera supprimé. Tapez SUPPRIMER pour confirmer.'}
            </p>
            <TextField
              className="mt-s"
              label="Confirmation de suppression"
              hideLabel
              value={deleteText}
              onChange={(e) => setDeleteText(e.target.value)}
              placeholder="SUPPRIMER"
            />
            {error ? <p role="alert" className="mt-s text-bodyMedium text-error">{error}</p> : null}
            <div className="mt-s flex gap-s">
              <Button
                variant="secondary"
                onClick={() => setConfirmDelete(false)}
              >
                Annuler
              </Button>
              <Button
                disabled={busy || deleteText.trim() !== 'SUPPRIMER'}
                onClick={remove}
              >
                Supprimer définitivement
              </Button>
            </div>
          </div>
        )}
      </div>
    </section>
  );
}
