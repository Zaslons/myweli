'use client';

import { useRouter } from 'next/navigation';
import { useCallback, useEffect, useState } from 'react';
import {
  type ProProfile,
  createArtist,
  createService,
  deleteArtist,
  deleteService,
  getMyProvider,
  updateArtist,
  updateService,
} from '../../lib/api/pro';
import { formatDuration, priceRange } from '../../lib/format';
import {
  type Artist,
  type ArtistForm,
  type Service,
  type ServiceForm,
  artistToForm,
  buildArtistPayload,
  buildServicePayload,
  emptyArtistForm,
  emptyServiceForm,
  serviceToForm,
  validateArtist,
  validateService,
} from '../../lib/pro/catalogue';
import { Button } from '../Button';

type Tab = 'services' | 'equipe';
// `open` = which form shows: null · 'new' · an item id (edit).
type Open = null | 'new' | string;

export function CatalogueClient() {
  const router = useRouter();
  const [profile, setProfile] = useState<ProProfile | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(false);
  const [tab, setTab] = useState<Tab>('services');
  const [open, setOpen] = useState<Open>(null);

  const load = useCallback(async () => {
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
    setProfile(me.profile);
    setLoading(false);
  }, [router]);

  useEffect(() => {
    load();
  }, [load]);

  if (loading) return <p className="text-textSecondary">Chargement…</p>;
  if (error || !profile) {
    return <p className="text-error">Une erreur est survenue. Réessayez.</p>;
  }

  const providerId = profile.provider.id;
  const services = profile.provider.services ?? [];
  const artists = profile.provider.artists ?? [];

  async function afterSave() {
    setOpen(null);
    await load();
  }
  function switchTab(t: Tab) {
    setTab(t);
    setOpen(null);
  }

  const addLabel = tab === 'services' ? 'Ajouter un service' : 'Ajouter un membre';

  return (
    <div>
      <div className="flex items-center justify-between gap-m">
        <h1 className="text-2xl font-semibold text-textPrimary">Catalogue</h1>
        {open !== 'new' ? (
          <Button onClick={() => setOpen('new')}>{addLabel}</Button>
        ) : null}
      </div>

      <div className="mt-l flex gap-s border-b border-divider">
        {(
          [
            { key: 'services', label: 'Services' },
            { key: 'equipe', label: 'Équipe' },
          ] as { key: Tab; label: string }[]
        ).map((t) => (
          <button
            key={t.key}
            type="button"
            onClick={() => switchTab(t.key)}
            className={`px-m py-s text-sm ${
              tab === t.key
                ? 'border-b-2 border-primary text-textPrimary'
                : 'text-textTertiary'
            }`}
          >
            {t.label}
          </button>
        ))}
      </div>

      {open === 'new' ? (
        <div className="mt-m">
          {tab === 'services' ? (
            <ServiceFormCard
              providerId={providerId}
              initial={emptyServiceForm}
              onCancel={() => setOpen(null)}
              onSaved={afterSave}
            />
          ) : (
            <ArtistFormCard
              providerId={providerId}
              initial={emptyArtistForm}
              onCancel={() => setOpen(null)}
              onSaved={afterSave}
            />
          )}
        </div>
      ) : null}

      <div className="mt-l space-y-s">
        {tab === 'services'
          ? renderList(
              services,
              open,
              (s) => (
                <ServiceRow service={s} onEdit={() => setOpen(s.id)} />
              ),
              (s) => (
                <ServiceFormCard
                  providerId={providerId}
                  serviceId={s.id}
                  initial={serviceToForm(s)}
                  onCancel={() => setOpen(null)}
                  onSaved={afterSave}
                />
              ),
              'Aucun service. Ajoutez votre premier service.',
            )
          : renderList(
              artists,
              open,
              (a) => <ArtistRow artist={a} onEdit={() => setOpen(a.id)} />,
              (a) => (
                <ArtistFormCard
                  providerId={providerId}
                  artistId={a.id}
                  initial={artistToForm(a)}
                  onCancel={() => setOpen(null)}
                  onSaved={afterSave}
                />
              ),
              'Aucun membre. Ajoutez votre équipe.',
            )}
      </div>
    </div>
  );
}

function renderList<T extends { id: string }>(
  items: T[],
  open: Open,
  row: (item: T) => JSX.Element,
  editor: (item: T) => JSX.Element,
  empty: string,
) {
  if (items.length === 0 && open !== 'new') {
    return (
      <p className="rounded-xl border border-border bg-secondary p-l text-center text-textSecondary">
        {empty}
      </p>
    );
  }
  return items.map((item) => (
    <div key={item.id}>{open === item.id ? editor(item) : row(item)}</div>
  ));
}

function ServiceRow({
  service,
  onEdit,
}: {
  service: Service;
  onEdit: () => void;
}) {
  return (
    <div className="flex items-center justify-between rounded-xl border border-border bg-secondary p-m">
      <div>
        <p className="font-medium text-textPrimary">
          {service.name}
          {service.active === false ? (
            <span className="ml-s rounded-full bg-surface px-s py-xs text-xs text-textTertiary">
              Inactif
            </span>
          ) : null}
        </p>
        <p className="text-sm text-textTertiary">
          {service.durationMinutes != null
            ? `${formatDuration(service.durationMinutes)} · `
            : ''}
          {service.price != null
            ? priceRange(service.price, service.priceMax)
            : ''}
        </p>
      </div>
      <Button variant="secondary" onClick={onEdit}>
        Modifier
      </Button>
    </div>
  );
}

function ArtistRow({ artist, onEdit }: { artist: Artist; onEdit: () => void }) {
  return (
    <div className="flex items-center justify-between rounded-xl border border-border bg-secondary p-m">
      <div>
        <p className="font-medium text-textPrimary">{artist.name}</p>
        {artist.specialization ? (
          <p className="text-sm text-textTertiary">{artist.specialization}</p>
        ) : null}
      </div>
      <Button variant="secondary" onClick={onEdit}>
        Modifier
      </Button>
    </div>
  );
}

const inputCls =
  'w-full rounded-lg border border-border bg-surface px-m py-s text-textPrimary';

function ServiceFormCard({
  providerId,
  serviceId,
  initial,
  onCancel,
  onSaved,
}: {
  providerId: string;
  serviceId?: string;
  initial: ServiceForm;
  onCancel: () => void;
  onSaved: () => void;
}) {
  const [form, setForm] = useState<ServiceForm>(initial);
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  const [confirmDelete, setConfirmDelete] = useState(false);

  function set<K extends keyof ServiceForm>(k: K, v: ServiceForm[K]) {
    setForm((f) => ({ ...f, [k]: v }));
  }

  async function save() {
    const v = validateService(form);
    if (v) return setErr(v);
    setBusy(true);
    setErr(null);
    const payload = buildServicePayload(form);
    const r = serviceId
      ? await updateService(providerId, serviceId, payload)
      : await createService(providerId, payload);
    setBusy(false);
    if (!r.ok) return setErr('L’enregistrement a échoué. Réessayez.');
    onSaved();
  }

  async function remove() {
    if (!serviceId) return;
    setBusy(true);
    const r = await deleteService(providerId, serviceId);
    setBusy(false);
    if (!r.ok) return setErr('La suppression a échoué.');
    onSaved();
  }

  return (
    <div className="rounded-xl border border-border bg-secondary p-l">
      <div className="space-y-s">
        <label className="block text-sm text-textTertiary">
          Nom du service
          <input
            className={inputCls}
            value={form.name}
            onChange={(e) => set('name', e.target.value)}
          />
        </label>
        <label className="block text-sm text-textTertiary">
          Description
          <input
            className={inputCls}
            value={form.description}
            onChange={(e) => set('description', e.target.value)}
          />
        </label>
        <div className="flex gap-s">
          <label className="block flex-1 text-sm text-textTertiary">
            Prix — à partir de (FCFA)
            <input
              className={inputCls}
              inputMode="numeric"
              value={form.price}
              onChange={(e) => set('price', e.target.value)}
            />
          </label>
          <label className="block flex-1 text-sm text-textTertiary">
            Prix maximum (optionnel)
            <input
              className={inputCls}
              inputMode="numeric"
              value={form.priceMax}
              onChange={(e) => set('priceMax', e.target.value)}
            />
          </label>
        </div>
        <label className="block text-sm text-textTertiary">
          Durée (minutes)
          <input
            className={inputCls}
            inputMode="numeric"
            value={form.durationMinutes}
            onChange={(e) => set('durationMinutes', e.target.value)}
          />
        </label>
        <label className="flex items-center gap-s text-sm text-textPrimary">
          <input
            type="checkbox"
            checked={form.active}
            onChange={(e) => set('active', e.target.checked)}
          />
          Service actif (réservable)
        </label>
      </div>

      {err ? <p className="mt-s text-sm text-error">{err}</p> : null}

      <FormActions
        busy={busy}
        canDelete={!!serviceId}
        deleteLabel="Supprimer ce service ?"
        confirmDelete={confirmDelete}
        onSave={save}
        onCancel={onCancel}
        onAskDelete={() => setConfirmDelete(true)}
        onDelete={remove}
      />
    </div>
  );
}

function ArtistFormCard({
  providerId,
  artistId,
  initial,
  onCancel,
  onSaved,
}: {
  providerId: string;
  artistId?: string;
  initial: ArtistForm;
  onCancel: () => void;
  onSaved: () => void;
}) {
  const [form, setForm] = useState<ArtistForm>(initial);
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  const [confirmDelete, setConfirmDelete] = useState(false);

  async function save() {
    const v = validateArtist(form);
    if (v) return setErr(v);
    setBusy(true);
    setErr(null);
    const payload = buildArtistPayload(form);
    const r = artistId
      ? await updateArtist(providerId, artistId, payload)
      : await createArtist(providerId, payload);
    setBusy(false);
    if (!r.ok) return setErr('L’enregistrement a échoué. Réessayez.');
    onSaved();
  }

  async function remove() {
    if (!artistId) return;
    setBusy(true);
    const r = await deleteArtist(providerId, artistId);
    setBusy(false);
    if (!r.ok) return setErr('La suppression a échoué.');
    onSaved();
  }

  return (
    <div className="rounded-xl border border-border bg-secondary p-l">
      <div className="space-y-s">
        <label className="block text-sm text-textTertiary">
          Nom
          <input
            className={inputCls}
            value={form.name}
            onChange={(e) => setForm((f) => ({ ...f, name: e.target.value }))}
          />
        </label>
        <label className="block text-sm text-textTertiary">
          Spécialisation (optionnel)
          <input
            className={inputCls}
            value={form.specialization}
            onChange={(e) =>
              setForm((f) => ({ ...f, specialization: e.target.value }))
            }
          />
        </label>
      </div>

      {err ? <p className="mt-s text-sm text-error">{err}</p> : null}

      <FormActions
        busy={busy}
        canDelete={!!artistId}
        deleteLabel="Supprimer ce membre ?"
        confirmDelete={confirmDelete}
        onSave={save}
        onCancel={onCancel}
        onAskDelete={() => setConfirmDelete(true)}
        onDelete={remove}
      />
    </div>
  );
}

function FormActions({
  busy,
  canDelete,
  deleteLabel,
  confirmDelete,
  onSave,
  onCancel,
  onAskDelete,
  onDelete,
}: {
  busy: boolean;
  canDelete: boolean;
  deleteLabel: string;
  confirmDelete: boolean;
  onSave: () => void;
  onCancel: () => void;
  onAskDelete: () => void;
  onDelete: () => void;
}) {
  return (
    <div className="mt-l flex flex-wrap items-center gap-s">
      <Button disabled={busy} onClick={onSave}>
        Enregistrer
      </Button>
      <Button variant="secondary" disabled={busy} onClick={onCancel}>
        Annuler
      </Button>
      {canDelete ? (
        confirmDelete ? (
          <span className="flex items-center gap-s">
            <span className="text-sm text-textSecondary">{deleteLabel}</span>
            <Button variant="secondary" disabled={busy} onClick={onDelete}>
              Oui, supprimer
            </Button>
          </span>
        ) : (
          <Button variant="secondary" disabled={busy} onClick={onAskDelete}>
            Supprimer
          </Button>
        )
      ) : null}
    </div>
  );
}
