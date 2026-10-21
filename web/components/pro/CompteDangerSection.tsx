'use client';

import { useRouter } from 'next/navigation';
import { useState } from 'react';
import type { ProProfile } from '../../lib/api/pro';
import {
  deleteProAccount,
  getEarnings,
  listAllClients,
  listProAppointments,
} from '../../lib/api/pro';
import {
  EXPORT_COPY_FAILED,
  type ExportSection,
  buildProviderDataExport,
  exportFailureMessage,
} from '../../lib/pro/export';
import { EXPORT_BUILD_FAILED } from '../../lib/account/export';
import { DEMO_ACCOUNT_LOCKED_MESSAGE } from '../../lib/pro/team';
import { Button } from '../Button';
import { TextField } from '../TextField';

/// A refused deletion, by machine code. The two refusals a user can be told
/// about each get their sentence; anything else is the generic failure.
function deleteErrorMessage(code: string | undefined): string {
  switch (code) {
    case 'future_bookings':
      return 'Terminez ou annulez vos rendez-vous à venir avant de supprimer votre compte.';
    case 'demo_account_locked':
      return DEMO_ACCOUNT_LOCKED_MESSAGE;
    default:
      return 'La suppression a échoué. Réessayez.';
  }
}

function settledValue<T>(r: PromiseSettledResult<T>): T | null {
  return r.status === 'fulfilled' ? r.value : null;
}

/// « Compte » danger zone on /pro/profil (audit 11.5 — AUTH-004/005 for
/// pros): the data export (client-side assembly, like the consumer page) and
/// the type-SUPPRIMER deletion. Design:
/// docs/design/pro-account-deletion-export.md.
/// Team access R5b: `exportEnabled=false` = every member who is not the
/// owner — deletion parity for everyone, but the salon-data export is the
/// owner's (`salon.publish`, the app's gate; T39). A member deletes their
/// own account, not the salon.
///
/// The export is whole or it is not made: a read that fails names the
/// missing data and makes no file (docs/design/web-pro-export-completeness.md).
///
/// The shared store-review demo account cannot delete itself: the entry
/// stays visible for it, the server answers 403 `demo_account_locked` after
/// the SUPPRIMER confirmation, and the page and the session stay. Design:
/// docs/design/demo-account-deletion-lock.md §7.2.
export function CompteDangerSection({
  profile,
  exportEnabled = true,
}: {
  profile: ProProfile;
  exportEnabled?: boolean;
}) {
  const router = useRouter();
  const [exporting, setExporting] = useState(false);
  const [exportError, setExportError] = useState<string | null>(null);
  const [copied, setCopied] = useState(false);
  const [confirmDelete, setConfirmDelete] = useState(false);
  const [deleteText, setDeleteText] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  /// The export document, or null when it cannot be made whole — the alert
  /// or the sign-in redirect is already under way then. A section is never
  /// filled with « nothing » because its read failed: a salon owner reads
  /// `[]` as « no clients », not as « the read failed » (spec §3).
  async function assembleJson(): Promise<string | null> {
    const providerId = profile.provider.id;
    // allSettled, not all: a fetch that throws is one failed section, not a
    // rejection that leaves the buttons disabled.
    const [ra, rc, re] = await Promise.allSettled([
      listProAppointments(),
      listAllClients(providerId),
      getEarnings(providerId, null),
    ]);
    const a = settledValue(ra);
    const c = settledValue(rc);
    const e = settledValue(re);
    if ([a, c, e].some((r) => r?.status === 401)) {
      router.replace('/pro/connexion');
      return null;
    }
    const appointments = a?.status === 200 ? a.items : null;
    const clients = c?.items ?? null;
    const earnings = e?.earnings ?? null;
    if (!appointments || !clients || !earnings) {
      const failed: ExportSection[] = [];
      if (!appointments) failed.push('appointments');
      if (!clients) failed.push('clients');
      if (!earnings) failed.push('earnings');
      setExportError(exportFailureMessage(failed));
      return null;
    }
    return JSON.stringify(
      buildProviderDataExport({ profile, appointments, clients, earnings }),
      null,
      2,
    );
  }

  /// One attempt: the alert from the last one clears, and the buttons come
  /// back whatever happens — they are the retry.
  ///
  /// A throw while the file is assembled is a refusal too, never a silent
  /// no-file (docs/design/export-unreadable-200.md §2.3): the reads are
  /// checked for their lists, but the file is still built from what crossed
  /// the network, and the button used to just come back with nothing said.
  /// It says so in its own words: it used to name all three reads, which had
  /// answered (docs/design/web-client-polish.md §2.3).
  async function prepare(): Promise<string | null> {
    setExporting(true);
    setExportError(null);
    try {
      return await assembleJson();
    } catch {
      setExportError(EXPORT_BUILD_FAILED);
      return null;
    } finally {
      setExporting(false);
    }
  }

  async function download() {
    const json = await prepare();
    if (json === null) return;
    const blob = new Blob([json], { type: 'application/json' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = 'myweli-salon-donnees.json';
    a.click();
    URL.revokeObjectURL(url);
  }

  async function copy() {
    const json = await prepare();
    if (json === null) return;
    try {
      await navigator.clipboard.writeText(json);
    } catch {
      // Permission, an unfocused page, or no clipboard at all (an insecure
      // origin) — the download needs none of them.
      setExportError(EXPORT_COPY_FAILED);
      return;
    }
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  }

  async function remove() {
    setBusy(true);
    setError(null);
    const r = await deleteProAccount();
    setBusy(false);
    if (!r.ok) {
      setError(deleteErrorMessage(r.error));
      return;
    }
    router.replace('/pro/connexion');
  }

  return (
    <section className="mt-l rounded-xl border border-border bg-secondary p-m">
      <h2 className="text-titleLarge font-semibold text-textPrimary">Compte</h2>

      {exportEnabled ? (
        <div className="mt-s">
          <div className="flex items-center justify-between gap-m">
            <p className="text-bodyLarge text-textSecondary">
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
          {exportError ? (
            <p role="alert" className="mt-s text-bodyMedium text-error">
              {exportError}
            </p>
          ) : null}
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
            <p className="text-bodyLarge text-textSecondary">
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
