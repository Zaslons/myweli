'use client';

import { useRouter } from 'next/navigation';
import { useCallback, useEffect, useState } from 'react';
import {
  type ProProfile,
  createService,
  deleteService,
  getMyProvider,
  updateService,
} from '../../lib/api/pro';
import { formatDuration, priceRange } from '../../lib/format';
import {
  type Service,
  type ServiceForm,
  buildServicePayload,
  emptyServiceForm,
  serviceToForm,
  validateService,
} from '../../lib/pro/catalogue';
import { Button } from '../Button';

// `open` = which form is showing: null (none) · 'new' · a serviceId (edit).
type Open = null | 'new' | string;

export function CatalogueClient() {
  const router = useRouter();
  const [profile, setProfile] = useState<ProProfile | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(false);
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

  async function afterSave() {
    setOpen(null);
    await load();
  }

  return (
    <div>
      <div className="flex items-center justify-between gap-m">
        <h1 className="text-2xl font-semibold text-textPrimary">Catalogue</h1>
        {open !== 'new' ? (
          <Button onClick={() => setOpen('new')}>Ajouter un service</Button>
        ) : null}
      </div>

      {open === 'new' ? (
        <div className="mt-m">
          <ServiceFormCard
            providerId={providerId}
            initial={emptyServiceForm}
            onCancel={() => setOpen(null)}
            onSaved={afterSave}
          />
        </div>
      ) : null}

      <div className="mt-l space-y-s">
        {services.length === 0 && open !== 'new' ? (
          <p className="rounded-xl border border-border bg-secondary p-l text-center text-textSecondary">
            Aucun service. Ajoutez votre premier service.
          </p>
        ) : (
          services.map((s) =>
            open === s.id ? (
              <ServiceFormCard
                key={s.id}
                providerId={providerId}
                serviceId={s.id}
                initial={serviceToForm(s)}
                onCancel={() => setOpen(null)}
                onSaved={afterSave}
              />
            ) : (
              <ServiceRow
                key={s.id}
                service={s}
                onEdit={() => setOpen(s.id)}
              />
            ),
          )
        )}
      </div>
    </div>
  );
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
    if (v) {
      setErr(v);
      return;
    }
    setBusy(true);
    setErr(null);
    const payload = buildServicePayload(form);
    const r = serviceId
      ? await updateService(providerId, serviceId, payload)
      : await createService(providerId, payload);
    setBusy(false);
    if (!r.ok) {
      setErr('L’enregistrement a échoué. Réessayez.');
      return;
    }
    onSaved();
  }

  async function remove() {
    if (!serviceId) return;
    setBusy(true);
    const r = await deleteService(providerId, serviceId);
    setBusy(false);
    if (!r.ok) {
      setErr('La suppression a échoué.');
      return;
    }
    onSaved();
  }

  const input =
    'w-full rounded-lg border border-border bg-surface px-m py-s text-textPrimary';

  return (
    <div className="rounded-xl border border-border bg-secondary p-l">
      <div className="space-y-s">
        <label className="block text-sm text-textTertiary">
          Nom du service
          <input
            className={input}
            value={form.name}
            onChange={(e) => set('name', e.target.value)}
          />
        </label>
        <label className="block text-sm text-textTertiary">
          Description
          <input
            className={input}
            value={form.description}
            onChange={(e) => set('description', e.target.value)}
          />
        </label>
        <div className="flex gap-s">
          <label className="block flex-1 text-sm text-textTertiary">
            Prix — à partir de (FCFA)
            <input
              className={input}
              inputMode="numeric"
              value={form.price}
              onChange={(e) => set('price', e.target.value)}
            />
          </label>
          <label className="block flex-1 text-sm text-textTertiary">
            Prix maximum (optionnel)
            <input
              className={input}
              inputMode="numeric"
              value={form.priceMax}
              onChange={(e) => set('priceMax', e.target.value)}
            />
          </label>
        </div>
        <label className="block text-sm text-textTertiary">
          Durée (minutes)
          <input
            className={input}
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

      <div className="mt-l flex flex-wrap items-center gap-s">
        <Button disabled={busy} onClick={save}>
          Enregistrer
        </Button>
        <Button variant="secondary" disabled={busy} onClick={onCancel}>
          Annuler
        </Button>
        {serviceId ? (
          confirmDelete ? (
            <span className="flex items-center gap-s">
              <span className="text-sm text-textSecondary">
                Supprimer ce service ?
              </span>
              <Button variant="secondary" disabled={busy} onClick={remove}>
                Oui, supprimer
              </Button>
            </span>
          ) : (
            <Button
              variant="secondary"
              disabled={busy}
              onClick={() => setConfirmDelete(true)}
            >
              Supprimer
            </Button>
          )
        ) : null}
      </div>
    </div>
  );
}
