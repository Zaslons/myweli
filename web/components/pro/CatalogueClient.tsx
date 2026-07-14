'use client';

import { useRouter } from 'next/navigation';
import { useCallback, useEffect, useRef, useState } from 'react';
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
  type DayForm,
  daysToSchedule,
  scheduleToDays,
} from '../../lib/pro/availability';
import { DayHoursEditor } from './DayHoursEditor';
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
import { uploadGalleryImage } from '../../lib/pro/upload';
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

  const addLabel = tab === 'services' ? 'Ajouter un service' : 'Ajouter un employé';

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
            { key: 'equipe', label: 'Employés' },
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
              artists={artists}
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
                <ServiceRow
                  service={s}
                  currency={profile?.provider.currency}
                  onEdit={() => setOpen(s.id)}
                />
              ),
              (s) => (
                <ServiceFormCard
                  providerId={providerId}
                  serviceId={s.id}
                  initial={serviceToForm(s)}
                  artists={artists}
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
              'Aucun employé. Ajoutez vos fiches employés.',
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
  currency,
}: {
  service: Service;
  onEdit: () => void;
  /// The salon's currency (multi-pays MP3).
  currency?: string | null;
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
            ? priceRange(service.price, service.priceMax, currency ?? undefined)
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
  artists,
  onCancel,
  onSaved,
}: {
  providerId: string;
  serviceId?: string;
  initial: ServiceForm;
  artists: Artist[];
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
        {/* Audit 3.2: the app's per-hair-length duration editor. */}
        <label className="flex items-center gap-s text-sm text-textPrimary">
          <input
            type="checkbox"
            checked={form.hasVariants}
            onChange={(e) => set('hasVariants', e.target.checked)}
          />
          Durée selon la longueur de cheveux
        </label>
        {form.hasVariants ? (
          <div className="flex gap-s">
            <label className="block flex-1 text-sm text-textTertiary">
              Court (min)
              <input
                className={inputCls}
                inputMode="numeric"
                value={form.variantCourt}
                onChange={(e) => set('variantCourt', e.target.value)}
              />
            </label>
            <label className="block flex-1 text-sm text-textTertiary">
              Moyen (min)
              <input
                className={inputCls}
                inputMode="numeric"
                value={form.variantMoyen}
                onChange={(e) => set('variantMoyen', e.target.value)}
              />
            </label>
            <label className="block flex-1 text-sm text-textTertiary">
              Long (min)
              <input
                className={inputCls}
                inputMode="numeric"
                value={form.variantLong}
                onChange={(e) => set('variantLong', e.target.value)}
              />
            </label>
          </div>
        ) : null}
        <label className="flex items-center gap-s text-sm text-textPrimary">
          <input
            type="checkbox"
            checked={form.active}
            onChange={(e) => set('active', e.target.checked)}
          />
          Service actif (réservable)
        </label>
        {/* Audit 3.1: capability assignment — feeds the booking hub's
            dimming + the per-artist capacity engine. */}
        {artists.length > 0 ? (
          <div>
            <p className="text-sm text-textPrimary">
              Qui peut réaliser ce service ?
            </p>
            <p className="text-xs text-textTertiary">
              Aucune sélection = toute l’équipe.
            </p>
            <div className="mt-xs space-y-xs">
              {artists.map((a) => (
                <label
                  key={a.id}
                  className="flex items-center gap-s text-sm text-textPrimary"
                >
                  <input
                    type="checkbox"
                    checked={form.artistIds.includes(a.id)}
                    onChange={(e) =>
                      set(
                        'artistIds',
                        e.target.checked
                          ? [...form.artistIds, a.id]
                          : form.artistIds.filter((x) => x !== a.id),
                      )
                    }
                  />
                  {a.name}
                  {a.specialization ? (
                    <span className="text-textTertiary">
                      · {a.specialization}
                    </span>
                  ) : null}
                </label>
              ))}
            </div>
          </div>
        ) : null}
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
  const [customHours, setCustomHours] = useState(
    Object.keys(initial.workingHours).length > 0,
  );
  const [hoursDays, setHoursDays] = useState(() =>
    scheduleToDays(initial.workingHours),
  );
  const [busy, setBusy] = useState(false);
  const [uploading, setUploading] = useState(false);
  const photoRef = useRef<HTMLInputElement>(null);
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

        {/* Audit 3.5: the avatar (the app's photo upload, gallery pipeline). */}
        <div className="flex items-center gap-m">
          {form.imageUrl ? (
            <span className="relative">
              {/* eslint-disable-next-line @next/next/no-img-element */}
              <img
                src={form.imageUrl}
                alt="Photo de l’employé"
                className="h-14 w-14 rounded-full object-cover"
              />
              <button
                type="button"
                aria-label="Retirer la photo"
                onClick={() => setForm((f) => ({ ...f, imageUrl: null }))}
                className="absolute -right-1 -top-1 rounded-full bg-primary px-1 text-xs text-secondary"
              >
                ✕
              </button>
            </span>
          ) : null}
          <input
            ref={photoRef}
            type="file"
            accept="image/jpeg,image/png,image/webp"
            className="hidden"
            aria-label="Photo de l’employé"
            onChange={async (e) => {
              const file = e.target.files?.[0];
              e.target.value = '';
              if (!file) return;
              setUploading(true);
              setErr(null);
              const url = await uploadGalleryImage(file);
              setUploading(false);
              if (!url) return setErr('Échec de l’envoi de la photo.');
              setForm((f) => ({ ...f, imageUrl: url }));
            }}
          />
          <Button
            variant="secondary"
            disabled={uploading}
            onClick={() => photoRef.current?.click()}
          >
            {uploading
              ? 'Envoi…'
              : form.imageUrl
                ? 'Changer la photo'
                : 'Ajouter une photo'}
          </Button>
        </div>

        {/* Audit 3.4: per-staff hours — the capacity engine reads them
            (empty = inherits the salon's hours). */}
        <label className="flex items-center gap-s text-sm text-textPrimary">
          <input
            type="checkbox"
            checked={customHours}
            onChange={(e) => {
              setCustomHours(e.target.checked);
              if (!e.target.checked) {
                setForm((f) => ({ ...f, workingHours: {} }));
              }
            }}
          />
          Horaires personnalisés (sinon : les horaires du salon)
        </label>
        {customHours ? (
          <div className="mt-xs">
            <DayHoursEditor
              days={hoursDays}
              onLabel="Travaille"
              offLabel="Repos"
              onPatch={(idx: number, patch: Partial<DayForm>) => {
                const next = hoursDays.map((x, j) =>
                  j === idx ? { ...x, ...patch } : x,
                );
                setHoursDays(next);
                setForm((f) => ({
                  ...f,
                  workingHours: daysToSchedule(next, f.workingHours),
                }));
              }}
            />
          </div>
        ) : null}
      </div>

      {err ? <p className="mt-s text-sm text-error">{err}</p> : null}

      <FormActions
        busy={busy}
        canDelete={!!artistId}
        deleteLabel="Supprimer cet employé ?"
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
