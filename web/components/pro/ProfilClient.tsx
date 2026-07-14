'use client';

import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { type ReactNode, useEffect, useState } from 'react';
import type { ProProfile } from '../../lib/api/pro';
import { getMyProvider, updateProviderProfile } from '../../lib/api/pro';
import {
  PROFILE_CATEGORIES,
  type ProfileForm,
  buildProfilePayload,
  profileToForm,
  validateProfile,
} from '../../lib/pro/profile';
import dynamic from 'next/dynamic';
import { findCity } from '../../lib/api/localities';
import { centerOf } from '../../lib/discovery/map';
import { hasCap } from '../../lib/pro/team';
import { useLocalities } from '../../lib/use-localities';
import { Button } from '../Button';
import { CompteDangerSection } from './CompteDangerSection';
import { LocalityPicker } from './LocalityPicker';
import { TeamRoleChip } from './TeamRoleChip';

// MapLibre is browser-only; the pin picker loads with the page (authed, not
// an indexed surface — no CWV concern).
const LocationPicker = dynamic(
  () => import('./LocationPicker').then((m) => m.LocationPicker),
  {
    ssr: false,
    loading: () => (
      <div className="flex h-64 items-center justify-center rounded-lg border border-border bg-surfaceVariant md:h-80">
        <p className="text-sm text-textSecondary">Chargement de la carte…</p>
      </div>
    ),
  },
);

const input =
  'w-full rounded-lg border border-border bg-surface px-m py-s text-textPrimary';

export function ProfilClient() {
  const router = useRouter();
  // The locality tree (multi-pays MP3) — the area picker + the map's
  // unplaced-pin center.
  const { tree } = useLocalities();
  const [providerId, setProviderId] = useState('');
  // Kept whole for the export assembly (audit 11.5).
  const [profile, setProfile] = useState<ProProfile | null>(null);
  const [verification, setVerification] = useState<
    'pending' | 'verified' | 'rejected'
  >('pending');
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
      setProfile(me.profile);
      setVerification(me.profile.account.verificationStatus ?? 'pending');
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

  // Team access R5b (amended): members WITHOUT profile.manage get a SLIM
  // personal view — identity + role + salon + « Supprimer mon compte »
  // (account-deletion parity for everyone; export stays owner-side).
  const membership = profile?.membership;
  if (profile && membership && !hasCap(membership, 'profile.manage')) {
    return (
      <div className="max-w-xl">
        <h1 className="text-2xl font-semibold text-textPrimary">Profil</h1>
        <section className="mt-l space-y-s rounded-xl border border-border bg-secondary p-l">
          {profile.account.email ? (
            <p className="break-all text-sm text-textPrimary">
              {profile.account.email}
            </p>
          ) : null}
          <TeamRoleChip role={membership.role} />
          <p className="text-sm text-textSecondary">
            Salon : {profile.provider.name}
          </p>
        </section>
        <CompteDangerSection profile={profile} exportEnabled={false} />
      </div>
    );
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
        {/* Multi-pays MP3: the area picker writes areaId — the serveur en
            dérive commune/ville (et fuseau/devise, T57). */}
        <LocalityPicker
          areaId={form.areaId}
          legacyCommune={form.commune}
          onChange={(areaId) => set('areaId', areaId)}
          fallbackValue={form.commune}
          onFallbackChange={(v) => set('commune', v)}
        />
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
        <Field label="Catégorie">
          <select
            className={input}
            value={form.category}
            onChange={(e) => set('category', e.target.value)}
          >
            {PROFILE_CATEGORIES.map((c) => (
              <option key={c.key} value={c.key}>
                {c.label}
              </option>
            ))}
          </select>
        </Field>
        <Field label="Position sur la carte">
          {/* The pin your clients see on la carte (pro-salon-lifecycle L1);
              required to go live. */}
          <LocationPicker
            latitude={form.latitude}
            longitude={form.longitude}
            fallbackCenter={centerOf(
              findCity(tree, profile?.provider.citySlug ?? '') ??
                tree.countries[0]?.cities[0],
            )}
            onChange={(lat, lng) =>
              setForm((f) =>
                f ? { ...f, latitude: lat, longitude: lng } : f,
              )
            }
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
        <SectionLink
          href="/pro/verification"
          label="Vérification"
          hint={
            verification === 'verified'
              ? 'Compte vérifié'
              : verification === 'rejected'
                ? 'Vérification refusée'
                : 'En attente'
          }
        />
        <SectionLink href="/pro/acompte" label="Acompte" />
        <SectionLink href="/pro/abonnement" label="Abonnement" />
        <SectionLink href="/pro/medias" label="Photos & Avant/Après" />
      </section>

      {/* Audit 11.5 — export + deletion (AUTH-004/005 for pros). */}
      {profile ? <CompteDangerSection profile={profile} /> : null}
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

function SectionLink({
  href,
  label,
  hint,
}: {
  href: string;
  label: string;
  hint?: string;
}) {
  return (
    <Link
      href={href}
      className="flex items-center justify-between rounded-xl border border-border bg-secondary p-m text-textPrimary hover:bg-surfaceVariant"
    >
      <span>{label}</span>
      <span className="text-textTertiary">
        {hint ? <span className="mr-s text-sm">{hint}</span> : null}›
      </span>
    </Link>
  );
}
