'use client';

import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { useCallback, useEffect, useRef, useState } from 'react';
import { addClient, getMyProvider, listClients } from '../../lib/api/pro';
import {
  PRESET_TAGS,
  type SalonClientListItem,
  maskPhone,
  noShowBadge,
  noShowLabel,
} from '../../lib/pro/clients';
import { formatDateFr } from '../../lib/format';
import { Button } from '../Button';

/// Module `clients` C1b — the salon client base at /pro/clients
/// (docs/design/clients-c1.md §6). Derived from bookings; search + tag
/// filter server-side; « Charger plus » pagination; add-client modal with
/// 409 dedupe → the existing card.
export function ClientsClient() {
  const router = useRouter();
  const [providerId, setProviderId] = useState<string | null>(null);
  const [items, setItems] = useState<SalonClientListItem[]>([]);
  const [total, setTotal] = useState(0);
  const [page, setPage] = useState(1);
  const [availableTags, setAvailableTags] = useState<string[]>(PRESET_TAGS);
  const [query, setQuery] = useState('');
  const [tag, setTag] = useState('');
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(false);
  const [adding, setAdding] = useState(false);
  const debounce = useRef<ReturnType<typeof setTimeout> | null>(null);

  const load = useCallback(
    async (pid: string, opts: { query: string; tag: string; page: number }) => {
      const r = await listClients(pid, {
        query: opts.query || undefined,
        tag: opts.tag || undefined,
        page: opts.page,
      });
      if (r.status === 401) {
        router.replace('/pro/connexion');
        return;
      }
      if (r.status !== 200 || !r.list) {
        setError(true);
        setLoading(false);
        return;
      }
      setItems((prev) =>
        opts.page > 1 ? [...prev, ...r.list!.items] : r.list!.items,
      );
      setTotal(r.list.total);
      if (r.list.availableTags?.length) setAvailableTags(r.list.availableTags);
      setPage(opts.page);
      setError(false);
      setLoading(false);
    },
    [router],
  );

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
      await load(pid, { query: '', tag: '', page: 1 });
    })();
  }, [router, load]);

  function search(next: string) {
    setQuery(next);
    if (!providerId) return;
    if (debounce.current) clearTimeout(debounce.current);
    debounce.current = setTimeout(() => {
      load(providerId, { query: next, tag, page: 1 });
    }, 300);
  }

  function filterTag(next: string) {
    const value = next === tag ? '' : next;
    setTag(value);
    if (providerId) load(providerId, { query, tag: value, page: 1 });
  }

  if (loading) return <p className="text-textSecondary">Chargement…</p>;
  if (error) {
    return <p className="text-error">Une erreur est survenue. Réessayez.</p>;
  }

  const emptyBase = total === 0 && !query && !tag;

  return (
    <div>
      <div className="flex items-center justify-between gap-m">
        <h1 className="text-2xl font-semibold text-textPrimary">Clients</h1>
        <Button onClick={() => setAdding(true)}>+ Ajouter un client</Button>
      </div>

      <input
        type="search"
        value={query}
        onChange={(e) => search(e.target.value)}
        placeholder="Nom ou téléphone…"
        aria-label="Rechercher un client"
        className="mt-m w-full max-w-md rounded-lg border border-border bg-secondary px-m py-s text-sm text-textPrimary"
      />

      <div className="mt-s flex flex-wrap gap-xs">
        {availableTags.map((t) => (
          <button
            key={t}
            type="button"
            onClick={() => filterTag(t)}
            className={`rounded-full border px-s py-xs text-xs ${
              tag === t
                ? 'border-primary bg-primary text-secondary'
                : 'border-border bg-surface text-textSecondary'
            }`}
          >
            {t}
          </button>
        ))}
      </div>

      {emptyBase ? (
        <div className="mt-xl rounded-xl border border-border bg-secondary p-xl text-center">
          <p className="text-textPrimary">
            Vos clients apparaîtront ici automatiquement après leur première
            réservation.
          </p>
          <p className="mt-xs text-sm text-textSecondary">
            Vous pouvez aussi les ajouter vous-même, un par un.
          </p>
        </div>
      ) : items.length === 0 ? (
        <p className="mt-l text-textSecondary">
          Aucun client pour « {query || tag} ».
        </p>
      ) : (
        <>
          <ul className="mt-m divide-y divide-border rounded-xl border border-border bg-secondary">
            {items.map((c) => (
              <li key={c.id}>
                <Link
                  href={`/pro/clients/${c.id}`}
                  className="flex items-center gap-m p-m hover:bg-surface"
                >
                  <span className="flex h-10 w-10 shrink-0 items-center justify-center rounded-full bg-surface text-sm font-medium text-textPrimary">
                    {c.displayName.slice(0, 1).toUpperCase()}
                  </span>
                  <span className="min-w-0 flex-1">
                    <span className="flex items-center gap-xs">
                      <span className="truncate font-medium text-textPrimary">
                        {c.displayName}
                      </span>
                      {c.linked ? (
                        <span className="rounded-full bg-surface px-xs text-[10px] uppercase text-textTertiary">
                          MyWeli
                        </span>
                      ) : null}
                      {noShowBadge(c.noShows) !== 'none' ? (
                        <span
                          className={`rounded-full px-xs text-[10px] ${
                            noShowBadge(c.noShows) === 'red'
                              ? 'bg-error/10 text-error'
                              : 'bg-surface text-textSecondary'
                          }`}
                        >
                          {noShowLabel(c.noShows)}
                        </span>
                      ) : null}
                    </span>
                    <span className="mt-xs block text-xs text-textSecondary">
                      {maskPhone(c.phone)}
                      {c.visits > 0
                        ? ` · ${c.visits} visite${c.visits > 1 ? 's' : ''}`
                        : ''}
                      {c.lastVisitAt
                        ? ` · dernière ${formatDateFr(c.lastVisitAt)}`
                        : ''}
                    </span>
                  </span>
                  <span className="flex gap-xs">
                    {c.tags.map((t) => (
                      <span
                        key={t}
                        className="rounded-full border border-border px-xs text-[10px] text-textSecondary"
                      >
                        {t}
                      </span>
                    ))}
                  </span>
                </Link>
              </li>
            ))}
          </ul>
          {items.length < total ? (
            <div className="mt-m text-center">
              <Button
                variant="secondary"
                onClick={() =>
                  providerId && load(providerId, { query, tag, page: page + 1 })
                }
              >
                Charger plus
              </Button>
            </div>
          ) : null}
        </>
      )}

      {adding && providerId ? (
        <AddClientModal
          providerId={providerId}
          onClose={() => setAdding(false)}
          onCreated={(id) => router.push(`/pro/clients/${id}`)}
        />
      ) : null}
    </div>
  );
}

function AddClientModal({
  providerId,
  onClose,
  onCreated,
}: {
  providerId: string;
  onClose: () => void;
  onCreated: (clientId: string) => void;
}) {
  const [name, setName] = useState('');
  const [phone, setPhone] = useState('');
  const [note, setNote] = useState('');
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState<string | null>(null);

  async function submit() {
    setBusy(true);
    setMessage(null);
    const r = await addClient(providerId, {
      name: name.trim(),
      phone: phone.trim(),
      note: note.trim() || undefined,
    });
    setBusy(false);
    if (r.ok && r.clientId) {
      onCreated(r.clientId);
      return;
    }
    if (r.status === 409 && r.clientId) {
      // Dedupe: the phone already has a card — open it.
      setMessage('Ce numéro existe déjà — ouverture de la fiche…');
      onCreated(r.clientId);
      return;
    }
    setMessage(
      r.error === 'invalid_phone'
        ? 'Numéro invalide (format international, ex. +2250700000000).'
        : 'Une erreur est survenue. Réessayez.',
    );
  }

  return (
    <div
      role="dialog"
      aria-modal="true"
      aria-label="Ajouter un client"
      className="fixed inset-0 z-50 flex items-center justify-center bg-primary/40 p-m"
    >
      <div className="w-full max-w-md rounded-xl border border-border bg-secondary p-l">
        <h2 className="text-lg font-semibold text-textPrimary">
          Ajouter un client
        </h2>
        <label className="mt-m block text-sm text-textSecondary">
          Nom
          <input
            value={name}
            onChange={(e) => setName(e.target.value)}
            className="mt-xs w-full rounded-lg border border-border bg-surface px-m py-s text-sm text-textPrimary"
          />
        </label>
        <label className="mt-m block text-sm text-textSecondary">
          Téléphone
          <input
            type="tel"
            value={phone}
            onChange={(e) => setPhone(e.target.value)}
            placeholder="+225 07 00 00 00 00"
            className="mt-xs w-full rounded-lg border border-border bg-surface px-m py-s text-sm text-textPrimary"
          />
        </label>
        <label className="mt-m block text-sm text-textSecondary">
          Note (optionnelle)
          <textarea
            value={note}
            onChange={(e) => setNote(e.target.value)}
            maxLength={500}
            rows={2}
            className="mt-xs w-full rounded-lg border border-border bg-surface px-m py-s text-sm text-textPrimary"
          />
        </label>
        {message ? <p className="mt-s text-sm text-error">{message}</p> : null}
        <div className="mt-l flex justify-end gap-s">
          <Button variant="secondary" onClick={onClose} disabled={busy}>
            Annuler
          </Button>
          <Button
            onClick={submit}
            disabled={busy || !name.trim() || !phone.trim()}
          >
            Ajouter
          </Button>
        </div>
      </div>
    </div>
  );
}
