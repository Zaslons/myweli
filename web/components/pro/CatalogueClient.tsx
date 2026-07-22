'use client';

import { useRouter } from 'next/navigation';
import { DataTable } from '../DataTable';
import { StatusChip } from '../StatusChip';
import { EmptyState } from '../EmptyState';
import { ErrorState } from '../ErrorState';
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
import { SkeletonRows } from '../Skeleton';

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

  if (loading) return <SkeletonRows count={5} className="mt-l" />;
  if (error || !profile) {
    return <ErrorState title="Catalogue" onRetry={() => { setError(false); setLoading(true); void load(); }} />;
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
        <h1 className="text-headlineSmall font-semibold text-textPrimary">Catalogue</h1>
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
            className={`px-m py-s text-bodyMedium ${
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
          ? renderTable(
              services,
              open,
              [
                { label: 'Nom', flex: 3 },
                { label: 'Durée', flex: 1 },
                { label: 'Prix', flex: 2 },
                { label: 'Statut', flex: 1 },
                { label: 'Actions', flex: 1, align: 'right' },
              ],
              (sv) => [
                <span key="n" className="min-w-0 truncate font-medium text-textPrimary">
                  {sv.name}
                </span>,
                <span key="d" className="text-textSecondary">
                  {sv.durationMinutes != null
                    ? formatDuration(sv.durationMinutes)
                    : '—'}
                </span>,
                <span key="p" className="text-textSecondary">
                  {sv.price != null
                    ? priceRange(sv.price, sv.priceMax, profile.provider.currency ?? undefined)
                    : '—'}
                </span>,
                sv.active === false ? (
                  <StatusChip key="s" status="inactive" label="Inactif" dense />
                ) : (
                  <StatusChip key="s" status="active" dense />
                ),
                <Button key="e" variant="secondary" onClick={() => setOpen(sv.id)}>
                  Modifier
                </Button>,
              ],
              (sv) => (
                <ServiceFormCard
                  providerId={providerId}
                  serviceId={sv.id}
                  initial={serviceToForm(sv)}
                  artists={artists}
                  onCancel={() => setOpen(null)}
                  onSaved={afterSave}
                />
              ),
              { title: 'Aucun service', description: 'Ajoutez votre premier service.' },
            )
          : renderTable(
              artists,
              open,
              [
                { label: 'Nom', flex: 2 },
                { label: 'Spécialité', flex: 2 },
                { label: 'Actions', flex: 1, align: 'right' },
              ],
              (a) => [
                <span key="n" className="font-medium text-textPrimary">
                  {a.name}
                </span>,
                <span key="s" className="text-textSecondary">
                  {a.specialization ?? '—'}
                </span>,
                <Button key="e" variant="secondary" onClick={() => setOpen(a.id)}>
                  Modifier
                </Button>,
              ],
              (a) => (
                <ArtistFormCard
                  providerId={providerId}
                  artistId={a.id}
                  initial={artistToForm(a)}
                  onCancel={() => setOpen(null)}
                  onSaved={afterSave}
                />
              ),
              { title: 'Aucun employé', description: 'Ajoutez vos fiches employés.' },
            )}
      </div>
    </div>
  );
}

/// B7's rethreading: the rows moved into a <DataTable> and the inline editor
/// renders BELOW it (same state machine — `open` picks the edited item; the
/// « Ajouter » flow is unchanged). Rows carry explicit « Modifier » buttons,
/// never row-level onClick (the DataTable contract: interactive cells).
function renderTable<T extends { id: string }>(
  items: T[],
  open: Open,
  columns: { label: string; flex?: number; align?: 'left' | 'right' }[],
  toCells: (item: T) => JSX.Element[],
  editor: (item: T) => JSX.Element,
  empty: { title: string; description: string },
) {
  const editing = items.find((i) => open === i.id);
  return (
    <>
      <DataTable
        columns={columns}
        emptyTitle={empty.title}
        emptyDescription={empty.description}
        rows={items.map((item) => ({ key: item.id, cells: toCells(item) }))}
      />
      {editing ? <div className="mt-m">{editor(editing)}</div> : null}
    </>
  );
}

const inputCls =
  'block w-full min-h-12 rounded-lg border border-borderStrong bg-surface p-m text-bodyMedium text-textPrimary focus:border-borderFocus focus:ring-1 focus:ring-borderFocus disabled:border-border disabled:text-textDisabled';

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
        <label className="block text-bodyMedium text-textTertiary">
          Nom du service
          <input
            className={inputCls}
            value={form.name}
            onChange={(e) => set('name', e.target.value)}
          />
        </label>
        <label className="block text-bodyMedium text-textTertiary">
          Description
          <input
            className={inputCls}
            value={form.description}
            onChange={(e) => set('description', e.target.value)}
          />
        </label>
        <div className="flex gap-s">
          <label className="block flex-1 text-bodyMedium text-textTertiary">
            Prix — à partir de (FCFA)
            <input
              className={inputCls}
              inputMode="numeric"
              value={form.price}
              onChange={(e) => set('price', e.target.value)}
            />
          </label>
          <label className="block flex-1 text-bodyMedium text-textTertiary">
            Prix maximum (optionnel)
            <input
              className={inputCls}
              inputMode="numeric"
              value={form.priceMax}
              onChange={(e) => set('priceMax', e.target.value)}
            />
          </label>
        </div>
        <label className="block text-bodyMedium text-textTertiary">
          Durée (minutes)
          <input
            className={inputCls}
            inputMode="numeric"
            value={form.durationMinutes}
            onChange={(e) => set('durationMinutes', e.target.value)}
          />
        </label>
        {/* Audit 3.2: the app's per-hair-length duration editor. */}
        <label className="flex min-h-12 items-center gap-s text-bodyMedium text-textPrimary">
          <input
            type="checkbox"
            className="h-5 w-5 shrink-0 accent-primary"
            checked={form.hasVariants}
            onChange={(e) => set('hasVariants', e.target.checked)}
          />
          Durée selon la longueur de cheveux
        </label>
        {form.hasVariants ? (
          <div className="flex gap-s">
            <label className="block flex-1 text-bodyMedium text-textTertiary">
              Court (min)
              <input
                className={inputCls}
                inputMode="numeric"
                value={form.variantCourt}
                onChange={(e) => set('variantCourt', e.target.value)}
              />
            </label>
            <label className="block flex-1 text-bodyMedium text-textTertiary">
              Moyen (min)
              <input
                className={inputCls}
                inputMode="numeric"
                value={form.variantMoyen}
                onChange={(e) => set('variantMoyen', e.target.value)}
              />
            </label>
            <label className="block flex-1 text-bodyMedium text-textTertiary">
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
        <label className="flex min-h-12 items-center gap-s text-bodyMedium text-textPrimary">
          <input
            type="checkbox"
            className="h-5 w-5 shrink-0 accent-primary"
            checked={form.active}
            onChange={(e) => set('active', e.target.checked)}
          />
          Service actif (réservable)
        </label>
        {/* Audit 3.1: capability assignment — feeds the booking hub's
            dimming + the per-artist capacity engine. */}
        {artists.length > 0 ? (
          <div>
            <p className="text-bodyMedium text-textPrimary">
              Qui peut réaliser ce service ?
            </p>
            <p className="text-bodySmall text-textTertiary">
              Aucune sélection = toute l’équipe.
            </p>
            <div className="mt-xs space-y-xs">
              {artists.map((a) => (
                <label
                  key={a.id}
                  className="flex min-h-12 items-center gap-s text-bodyMedium text-textPrimary"
                >
                  <input
                    type="checkbox"
                    className="h-5 w-5 shrink-0 accent-primary"
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

      {err ? <p role="alert" className="mt-s text-bodyMedium text-error">{err}</p> : null}

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
        <label className="block text-bodyMedium text-textTertiary">
          Nom
          <input
            className={inputCls}
            value={form.name}
            onChange={(e) => setForm((f) => ({ ...f, name: e.target.value }))}
          />
        </label>
        <label className="block text-bodyMedium text-textTertiary">
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
                alt="Portrait de l’employé"
                className="h-14 w-14 rounded-pill object-cover"
              />
              {/* §13.2: the 48px TARGET is the button; the visible pill is the
                  inner span, unmoved at the thumbnail's corner. */}
              <button
                type="button"
                aria-label="Retirer la photo"
                onClick={() => setForm((f) => ({ ...f, imageUrl: null }))}
                className="absolute -right-s -top-s flex h-12 w-12 items-center justify-center"
              >
                <span className="rounded-pill bg-primary px-xs text-iconXS text-secondary">
                  ✕
                </span>
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
            isLoading={uploading}
            onClick={() => photoRef.current?.click()}
          >
            {form.imageUrl ? 'Changer la photo' : 'Ajouter une photo'}
          </Button>
        </div>

        {/* Audit 3.4: per-staff hours — the capacity engine reads them
            (empty = inherits the salon's hours). */}
        <label className="flex min-h-12 items-center gap-s text-bodyMedium text-textPrimary">
          <input
            type="checkbox"
            className="h-5 w-5 shrink-0 accent-primary"
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

      {err ? <p role="alert" className="mt-s text-bodyMedium text-error">{err}</p> : null}

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
            <span className="text-bodyMedium text-textSecondary">{deleteLabel}</span>
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
