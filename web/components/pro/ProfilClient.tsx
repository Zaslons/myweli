'use client';

import Link from 'next/link';
import { Card } from '../Card';
import { ErrorState } from '../ErrorState';
import { useRouter } from 'next/navigation';
import { type ReactNode, useEffect, useRef, useState } from 'react';
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
import { findCity } from '../../lib/localities';
import { centerOf } from '../../lib/discovery/map';
import { hasCap } from '../../lib/pro/team';
import { uploadLogoImage } from '../../lib/pro/upload';
import { useLocalities } from '../../lib/use-localities';
import { Button } from '../Button';
import { Loading } from '../Loading';
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
        <Loading label="Chargement de la carte…" />
      </div>
    ),
  },
);

const input =
  'block w-full min-h-12 rounded-lg border border-borderStrong bg-surface p-m text-bodyLarge text-textPrimary focus:border-borderFocus focus:ring-1 focus:ring-borderFocus disabled:border-border disabled:text-textDisabled';

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
  const [reloadKey, setReloadKey] = useState(0);
  const [loadError, setLoadError] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [saved, setSaved] = useState(false);
  // The logo uploader (salon-logo.md §5) — upload now, persist via
  // « Enregistrer » with the rest of the staged form.
  const logoRef = useRef<HTMLInputElement>(null);
  const [logoUploading, setLogoUploading] = useState(false);
  const [logoError, setLogoError] = useState<string | null>(null);

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
  }, [router, reloadKey]);

  if (loading) return <Loading className="mt-l" />;
  if (loadError || !form) {
    return <ErrorState title="Profil" onRetry={() => { setLoadError(false); setLoading(true); setReloadKey((k) => k + 1); }} />;
  }

  // Team access R5b (amended): members WITHOUT profile.manage get a SLIM
  // personal view — identity + role + salon + « Supprimer mon compte »
  // (account-deletion parity for everyone; export stays owner-side).
  const membership = profile?.membership;
  if (profile && membership && !hasCap(membership, 'profile.manage')) {
    return (
      <div className="max-w-xl">
        <h1 className="text-headlineSmall font-semibold text-textPrimary">Profil</h1>
        <Card as="section" className="mt-l space-y-s">
          {profile.account.email ? (
            <p className="break-all text-bodyMedium text-textPrimary">
              {profile.account.email}
            </p>
          ) : null}
          <TeamRoleChip role={membership.role} />
          <p className="text-bodyMedium text-textSecondary">
            Salon : {profile.provider.name}
          </p>
        </Card>
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
      <h1 className="text-headlineSmall font-semibold text-textPrimary">Profil</h1>

      <Card as="section" className="mt-l space-y-s">
        {/* Logo du salon (salon-logo.md §5) — first, like the app's editor. */}
        <div className="flex items-center gap-m">
          {form.logoUrl ? (
            <span className="relative">
              {/* eslint-disable-next-line @next/next/no-img-element */}
              <img
                src={form.logoUrl}
                alt="Logo du salon"
                className="h-14 w-14 rounded-pill object-cover"
              />
              {/* §13.2: the 48px TARGET is the button; the visible pill is the
                  inner span, unmoved at the thumbnail's corner. */}
              <button
                type="button"
                aria-label="Supprimer le logo"
                onClick={() => {
                  set('logoUrl', null);
                  setLogoError(null);
                }}
                className="absolute -right-s -top-s flex h-12 w-12 items-center justify-center"
              >
                <span className="rounded-pill bg-primary px-xs text-iconXS text-secondary">
                  ✕
                </span>
              </button>
            </span>
          ) : null}
          <input
            ref={logoRef}
            type="file"
            accept="image/jpeg,image/png,image/webp"
            className="hidden"
            aria-label="Logo du salon"
            onChange={async (e) => {
              const file = e.target.files?.[0];
              e.target.value = '';
              if (!file) return;
              setLogoUploading(true);
              setLogoError(null);
              const url = await uploadLogoImage(file);
              setLogoUploading(false);
              if (!url) return setLogoError('Échec de l’envoi du logo.');
              set('logoUrl', url);
            }}
          />
          <Button
            variant="secondary"
            isLoading={logoUploading}
            onClick={() => logoRef.current?.click()}
          >
            {form.logoUrl ? 'Changer le logo' : 'Ajouter un logo'}
          </Button>
        </div>
        {logoError ? (
          <p role="alert" className="text-bodyMedium text-error">
            {logoError}
          </p>
        ) : null}
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
        {/* Input-side hygiene (fix/address-commune-dedupe): owners typed the
            commune here, echoing the picker just below — the render dedupe
            hides it, this stops the data being stored twice. The hint lives
            OUTSIDE the wrapping <label> deliberately: inside it, its text
            joins the field's accessible NAME, and « …la commune… » made
            getByLabel('Commune') ambiguous (the e2e caught it). */}
        <div>
          <Field label="Adresse">
            <input
              className={input}
              value={form.address}
              onChange={(e) => set('address', e.target.value)}
              aria-describedby="adresse-hint"
            />
          </Field>
          <span
            id="adresse-hint"
            className="mt-xs block text-bodySmall text-textTertiary"
          >
            Rue et numéro — la commune est choisie ci-dessous.
          </span>
        </div>
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

        {error ? <p role="alert" className="text-bodyMedium text-error">{error}</p> : null}
        <p
          role="status"
          className={saved ? 'text-bodyMedium text-textSecondary' : 'sr-only'}
        >
          {saved ? 'Profil enregistré.' : ''}
        </p>
        <div className="pt-s">
          <Button disabled={busy} onClick={save}>
            Enregistrer
          </Button>
        </div>
      </Card>

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
    <label className={`block text-bodyMedium text-textTertiary ${className}`}>
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
        {hint ? <span className="mr-s text-bodyMedium">{hint}</span> : null}›
      </span>
    </Link>
  );
}
