'use client';

import Link from 'next/link';
import { DataTable } from '../DataTable';
import { Chip, ChipButton } from '../Chip';
import { EmptyState } from '../EmptyState';
import { ErrorState } from '../ErrorState';
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
import { SkeletonRows } from '../Skeleton';
import { Modal } from '../Modal';
import { TextField } from '../TextField';

/// Module `clients` C1b — the salon client base at /pro/clients
/// (docs/design/clients-c1.md §6). Derived from bookings; search + tag
/// filter server-side; « Charger plus » pagination; add-client modal with
/// 409 dedupe → the existing card.
export function ClientsClient() {
  const router = useRouter();
  const [providerId, setProviderId] = useState<string | null>(null);
  // The active salon's timezone (multi-pays MP3) — visit dates render in
  // SALON time.
  const [salonTz, setSalonTz] = useState<string | undefined>(undefined);
  const [items, setItems] = useState<SalonClientListItem[]>([]);
  const [total, setTotal] = useState(0);
  const [page, setPage] = useState(1);
  const [availableTags, setAvailableTags] = useState<string[]>(PRESET_TAGS);
  const [query, setQuery] = useState('');
  const [tag, setTag] = useState('');
  const [loading, setLoading] = useState(true);
  const [reloadKey, setReloadKey] = useState(0);
  const [error, setError] = useState(false);
  const [adding, setAdding] = useState(false);
  const debounce = useRef<ReturnType<typeof setTimeout> | null>(null);

  const load = useCallback(
    async (pid: string, opts: { query: string; tag: string; page: number }) => {
      // An explicit load supersedes any pending debounced search — the
      // review raced a stale filtered response over the cleared list.
      if (debounce.current) clearTimeout(debounce.current);
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
      setSalonTz(me.profile.provider.timezone ?? undefined);
      await load(pid, { query: '', tag: '', page: 1 });
    })();
  }, [router, load, reloadKey]);

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

  if (loading) return <SkeletonRows count={6} className="mt-l" />;
  if (error) {
    return <ErrorState title="Clients" onRetry={() => { setError(false); setQuery(''); setTag(''); setLoading(true); setReloadKey((k) => k + 1); }} />;
  }

  const emptyBase = total === 0 && !query && !tag;

  return (
    <div>
      <div className="flex items-center justify-between gap-m">
        <h1 className="text-headlineSmall font-semibold text-textPrimary">Clients</h1>
        <Button onClick={() => setAdding(true)}>+ Ajouter un client</Button>
      </div>

      <TextField
        className="mt-m max-w-md"
        label="Rechercher un client"
        hideLabel
        type="search"
        value={query}
        onChange={(e) => search(e.target.value)}
        placeholder="Nom ou téléphone…"
      />

      <div className="mt-s flex flex-wrap gap-xs">
        {availableTags.map((t) => (
          <ChipButton
            key={t}
            selected={tag === t}
            onClick={() => filterTag(t)}
          >
            {t}
          </ChipButton>
        ))}
      </div>

      {emptyBase ? (
        <div className="mt-xl rounded-xl border border-border bg-secondary p-xl text-center">
          <p className="text-textPrimary">
            Vos clients apparaîtront ici automatiquement après leur première
            réservation.
          </p>
          <p className="mt-xs text-bodyMedium text-textSecondary">
            Vous pouvez aussi les ajouter vous-même, un par un.
          </p>
        </div>
      ) : items.length === 0 ? (
        <EmptyState
          className="mt-l"
          icon="people"
          title={`Aucun client pour « ${query || tag} »`}
          description="Essayez un autre nom ou effacez le filtre."
          action={
            <Button
              variant="secondary"
              onClick={() => {
                setQuery('');
                setTag('');
                // setLoading BEFORE the reload: the review caught the base
                // « aucun client » onboarding card flashing for the whole
                // request (total was still the filtered 0).
                setLoading(true);
                if (providerId) load(providerId, { query: '', tag: '', page: 1 });
              }}
            >
              Effacer la recherche
            </Button>
          }
        />
      ) : (
        <>
          {/* B7: the roster as a DataTable (Client · Téléphone · Visites ·
              Dernière visite · Tags). Row activation navigates to the card —
              the row is the DataTable's named full-row control, so the cells
              carry no interactive children (the contract). */}
          <div className="mt-m">
            <DataTable
              columns={[
                { label: 'Client', flex: 3 },
                { label: 'Téléphone', flex: 2 },
                { label: 'Visites', flex: 1 },
                { label: 'Dernière visite', flex: 2 },
                { label: 'Tags', flex: 2 },
              ]}
              emptyTitle="Aucun client"
              rows={items.map((c) => ({
                key: c.id,
                href: `/pro/clients/${c.id}`,
                rowLabel: `Ouvrir la fiche de ${c.displayName}`,
                cells: [
                  <span key="who" className="flex min-w-0 items-center gap-s">
                    <span className="flex h-8 w-8 shrink-0 items-center justify-center rounded-pill bg-surface text-labelMedium font-medium text-textPrimary">
                      {c.displayName.slice(0, 1).toUpperCase()}
                    </span>
                    <span className="truncate font-medium text-textPrimary">
                      {c.displayName}
                    </span>
                    {c.linked ? (
                      <Chip dense className="uppercase text-textTertiary">
                        MyWeli
                      </Chip>
                    ) : null}
                    {noShowBadge(c.noShows) !== 'none' ? (
                      <Chip
                        dense
                        variant={noShowBadge(c.noShows) === 'red' ? 'tinted' : 'neutral'}
                        tint="error"
                      >
                        {noShowLabel(c.noShows)}
                      </Chip>
                    ) : null}
                  </span>,
                  <span key="tel" className="text-textSecondary">
                    {maskPhone(c.phone)}
                  </span>,
                  <span key="visits" className="text-textSecondary">
                    {c.visits > 0 ? c.visits : '—'}
                  </span>,
                  <span key="last" className="text-textSecondary">
                    {c.lastVisitAt ? formatDateFr(c.lastVisitAt, salonTz) : '—'}
                  </span>,
                  <span key="tags" className="flex flex-wrap gap-xs">
                    {c.tags.length > 0
                      ? c.tags.map((t) => (
                          <Chip dense variant="outlined" key={t}>
                            {t}
                          </Chip>
                        ))
                      : '—'}
                  </span>,
                ],
              }))}
            />
          </div>
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
    <Modal title="Ajouter un client" onClose={onClose}>
        <TextField
          className="mt-m"
          label="Nom"
          value={name}
          onChange={(e) => setName(e.target.value)}
        />
        <TextField
          className="mt-m"
          label="Téléphone"
          type="tel"
          inputMode="tel"
          autoComplete="tel"
          value={phone}
          onChange={(e) => setPhone(e.target.value)}
          placeholder="+225 07 00 00 00 00"
        />
        <TextField
          className="mt-m"
          label="Note (optionnelle)"
          multiline
          maxLength={500}
          rows={2}
          value={note}
          onChange={(e) => setNote(e.target.value)}
        />
        {message ? <p role="alert" className="mt-s text-bodyMedium text-error">{message}</p> : null}
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
    </Modal>
  );
}
