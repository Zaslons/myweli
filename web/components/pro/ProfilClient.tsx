'use client';

import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { type ReactNode, useEffect, useState } from 'react';
import { getMyProvider, updateProviderProfile } from '../../lib/api/pro';
import {
  type ProfileForm,
  buildProfilePayload,
  profileToForm,
  validateProfile,
} from '../../lib/pro/profile';
import { Button } from '../Button';

const input =
  'w-full rounded-lg border border-border bg-surface px-m py-s text-textPrimary';

export function ProfilClient() {
  const router = useRouter();
  const [providerId, setProviderId] = useState('');
  const [form, setForm] = useState<ProfileForm | null>(null);
  const [loading, setLoading] = useState(true);
  const [loadError, setLoadError] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [saved, setSaved] = useState(false);

  useEffect(() => {
    let active = true;
    (async () => {
      const me = await getMyProvider();
      if (me.status === 401) {
        router.replace('/pro/connexion');
        return;
      }
      if (!active) return;
      if (me.status !== 200 || !me.profile) {
        setLoadError(true);
        setLoading(false);
        return;
      }
      setProviderId(me.profile.provider.id);
      setForm(profileToForm(me.profile.provider));
      setLoading(false);
    })();
    return () => {
      active = false;
    };
  }, [router]);

  if (loading) return <p className="text-textSecondary">Chargement…</p>;
  if (loadError || !form) {
    return <p className="text-error">Une erreur est survenue. Réessayez.</p>;
  }

  function set<K extends keyof ProfileForm>(k: K, v: ProfileForm[K]) {
    setForm((f) => (f ? { ...f, [k]: v } : f));
    setSaved(false);
  }

  async function save() {
    const v = validateProfile(form as ProfileForm);
    if (v) {
      setError(v);
      return;
    }
    setBusy(true);
    setError(null);
    const r = await updateProviderProfile(
      providerId,
      buildProfilePayload(form as ProfileForm),
    );
    setBusy(false);
    if (!r.ok) {
      setError('L’enregistrement a échoué. Réessayez.');
      return;
    }
    setSaved(true);
  }

  return (
    <div className="max-w-2xl">
      <h1 className="text-2xl font-semibold text-textPrimary">Profil</h1>

      <section className="mt-l space-y-s rounded-xl border border-border bg-secondary p-l">
        <Field label="Nom du salon">
          <input
            className={input}
            value={form.name}
            onChange={(e) => set('name', e.target.value)}
          />
        </Field>
        <Field label="Description">
          <textarea
            className={input}
            rows={3}
            value={form.description}
            onChange={(e) => set('description', e.target.value)}
          />
        </Field>
        <Field label="Adresse">
          <input
            className={input}
            value={form.address}
            onChange={(e) => set('address', e.target.value)}
          />
        </Field>
        <div className="flex gap-s">
          <Field label="Commune" className="flex-1">
            <input
              className={input}
              value={form.commune}
              onChange={(e) => set('commune', e.target.value)}
            />
          </Field>
          <Field label="Ville" className="flex-1">
            <input
              className={input}
              value={form.city}
              onChange={(e) => set('city', e.target.value)}
            />
          </Field>
        </div>
        <Field label="Téléphone">
          <input
            className={input}
            value={form.phoneNumber}
            onChange={(e) => set('phoneNumber', e.target.value)}
          />
        </Field>
        <Field label="WhatsApp (optionnel)">
          <input
            className={input}
            value={form.whatsapp}
            onChange={(e) => set('whatsapp', e.target.value)}
          />
        </Field>

        {error ? <p className="text-sm text-error">{error}</p> : null}
        {saved ? (
          <p className="text-sm text-textSecondary">Profil enregistré.</p>
        ) : null}
        <div className="pt-s">
          <Button disabled={busy} onClick={save}>
            Enregistrer
          </Button>
        </div>
      </section>

      <section className="mt-l space-y-s">
        <SectionLink href="/pro/acompte" label="Acompte" />
        <SectionLink href="/pro/abonnement" label="Abonnement" />
        <span className="flex items-center justify-between rounded-xl border border-border bg-secondary p-m text-textTertiary">
          Photos &amp; Avant/Après<span className="text-xs">Bientôt</span>
        </span>
      </section>
    </div>
  );
}

function Field({
  label,
  className = '',
  children,
}: {
  label: string;
  className?: string;
  children: ReactNode;
}) {
  return (
    <label className={`block text-sm text-textTertiary ${className}`}>
      {label}
      {children}
    </label>
  );
}

function SectionLink({ href, label }: { href: string; label: string }) {
  return (
    <Link
      href={href}
      className="flex items-center justify-between rounded-xl border border-border bg-secondary p-m text-textPrimary hover:bg-surfaceVariant"
    >
      <span>{label}</span>
      <span className="text-textTertiary">›</span>
    </Link>
  );
}
