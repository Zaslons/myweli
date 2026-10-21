'use client';

import Link from 'next/link';
import { ErrorState } from '../ErrorState';
import { useRouter } from 'next/navigation';
import { useCallback, useEffect, useState } from 'react';
import type { Me } from '../../lib/api/account';
import {
  getFavorites,
  getMe,
  listAppointments,
} from '../../lib/api/account';
import {
  EXPORT_BUILD_FAILED,
  EXPORT_COPY_FAILED,
  type ExportSection,
  buildUserDataExport,
  exportFailureMessage,
} from '../../lib/account/export';
import { Button } from '../Button';
import { Loading } from '../Loading';

/// « Mes données » (parity 11.2 — the app's data-export screen, web-adapted):
/// profile + rendez-vous + favoris assembled client-side into one JSON,
/// downloadable and copyable.
///
/// The copy is whole or it is not offered: a read that fails names the
/// missing data and the page offers « Réessayer », never a section emptied
/// by its failure (docs/design/consumer-export-completeness.md).
///
/// The document is built once, in `load()`, not while rendering: an entry the
/// file cannot hold is the page's error state with « Réessayer » — it used to
/// break the page (docs/design/web-client-polish.md §2.3).
export function DataExportClient() {
  const router = useRouter();
  const [me, setMe] = useState<Me | null>(null);
  const [appointmentCount, setAppointmentCount] = useState(0);
  const [favoriteCount, setFavoriteCount] = useState(0);
  const [json, setJson] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [failed, setFailed] = useState<ExportSection[]>([]);
  const [buildFailed, setBuildFailed] = useState(false);
  const [copied, setCopied] = useState(false);
  const [copyFailed, setCopyFailed] = useState(false);

  const load = useCallback(async () => {
    setLoading(true);
    setFailed([]);
    setBuildFailed(false);
    // None of the three throws: a request with no usable answer — no network,
    // or a body cut off on the way — is status 0 (lib/api/network.ts,
    // docs/design/web-consumer-network-failure.md §2), one more failed section.
    const [m, a, f] = await Promise.all([
      getMe(),
      listAppointments(),
      getFavorites(),
    ]);
    if ([m, a, f].some((r) => r.status === 401)) {
      router.replace('/connexion?returnTo=/mon-compte/donnees');
      return;
    }
    const user = m.status === 200 ? m.user ?? null : null;
    const missing: ExportSection[] = [];
    if (!user) missing.push('profile');
    if (a.status !== 200) missing.push('appointments');
    if (f.status !== 200) missing.push('favorites');
    if (!user || missing.length > 0) {
      setFailed(missing);
      setLoading(false);
      return;
    }
    try {
      const doc = buildUserDataExport({
        me: user,
        appointments: a.items,
        favoriteProviderNames: f.favorites.map((p) => p.name),
      });
      setJson(JSON.stringify(doc, null, 2));
      setMe(user);
      setAppointmentCount(a.items.length);
      setFavoriteCount(f.favorites.length);
    } catch {
      // The reads answered; the file could not be made from them.
      setBuildFailed(true);
    }
    setLoading(false);
  }, [router]);

  useEffect(() => {
    load();
  }, [load]);

  useEffect(() => {
    if (!copied) return;
    const t = setTimeout(() => setCopied(false), 2000);
    return () => clearTimeout(t);
  }, [copied]);

  if (loading) return <Loading className="mt-l" />;
  if (buildFailed) {
    return (
      <div>
        <ErrorState title="Mes données" message={EXPORT_BUILD_FAILED} onRetry={load} />
      </div>
    );
  }
  if (failed.length > 0 || !me || json === null) {
    return (
      <div>
        <ErrorState
          title="Mes données"
          message={exportFailureMessage(failed)}
          onRetry={load}
        />
      </div>
    );
  }

  // Narrowed for the handlers below (they close over it).
  const file = json;

  function download() {
    setCopyFailed(false);
    const blob = new Blob([file], { type: 'application/json' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = 'myweli-donnees.json';
    a.click();
    URL.revokeObjectURL(url);
  }

  async function copy() {
    setCopyFailed(false);
    try {
      await navigator.clipboard.writeText(file);
    } catch {
      // Permission, an unfocused page, or no clipboard at all (an insecure
      // origin) — the download needs none of them.
      setCopyFailed(true);
      return;
    }
    setCopied(true);
  }

  return (
    <div className="max-w-2xl">
      <Link href="/mon-compte" className="text-bodyMedium text-textTertiary">
        ← Mon compte
      </Link>
      <h1 className="mt-s text-headlineSmall font-semibold text-textPrimary">
        Mes données
      </h1>
      <p className="mt-xs text-bodyLarge text-textSecondary">
        Une copie de vos données MyWeli : profil, rendez-vous et favoris.
      </p>

      <section className="mt-l rounded-xl border border-border bg-secondary p-l">
        <dl className="space-y-xs text-bodyMedium">
          <div className="flex justify-between gap-m">
            <dt className="text-textTertiary">Profil</dt>
            <dd className="text-textPrimary">{me.email ?? me.phoneNumber}</dd>
          </div>
          <div className="flex justify-between gap-m">
            <dt className="text-textTertiary">Rendez-vous</dt>
            <dd className="text-textPrimary">{appointmentCount}</dd>
          </div>
          <div className="flex justify-between gap-m">
            <dt className="text-textTertiary">Favoris</dt>
            <dd className="text-textPrimary">{favoriteCount}</dd>
          </div>
        </dl>
        <div className="mt-m flex flex-wrap gap-s">
          <Button onClick={download}>Télécharger (JSON)</Button>
          <Button variant="secondary" onClick={copy}>
            {copied ? 'Copié ✓' : 'Copier'}
          </Button>
          <span role="status" className="sr-only">
            {copied ? 'Données copiées.' : ''}
          </span>
        </div>
        {copyFailed ? (
          <p role="alert" className="mt-s text-bodyMedium text-error">
            {EXPORT_COPY_FAILED}
          </p>
        ) : null}
      </section>
    </div>
  );
}
