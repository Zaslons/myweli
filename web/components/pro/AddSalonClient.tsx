'use client';

import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { useEffect, useState } from 'react';
import { isPossiblePhoneNumber } from 'react-phone-number-input';
import { useFieldErrors } from '../../lib/forms/useFieldErrors';
import { PhoneField } from '../PhoneField';
import { TextField } from '../TextField';
import {
  addSalon,
  getMyProvider,
  selectSalon,
} from '../../lib/api/pro';
import { teamErrorCta, teamErrorMessage } from '../../lib/pro/team';
import { Button } from '../Button';
import { LocalityPicker } from './LocalityPicker';

const BUSINESS_TYPES = [
  { value: 'salon', label: 'Salon de beauté' },
  { value: 'barber', label: 'Barbier' },
  { value: 'spa', label: 'Spa' },
  { value: 'nailSalon', label: 'Institut de manucure' },
  { value: 'massage', label: 'Massage' },
  { value: 'other', label: 'Autre' },
];

/// « Ajouter un salon » (module `access` R6 — docs/design/
/// team-access-r6-multi-salons.md §6): the register business fields WITHOUT
/// the identity block (the session already exists). Réseau-gated
/// SERVER-side (403 `reseau_required` / 409 `salon_limit` — rendered via
/// the shared French table). Success switches to the new DRAFT salon and
/// lands on the dashboard, where the GoLiveCard checklist is the same setup
/// arc as the first salon.
export function AddSalonClient() {
  const router = useRouter();
  const [businessName, setBusinessName] = useState('');
  const [businessType, setBusinessType] = useState('salon');
  const [phone, setPhone] = useState<string | undefined>(undefined);
  const [address, setAddress] = useState('');
  // Multi-pays MP3: the locality area — optional here, the publish gate
  // enforces it (T57).
  const [areaId, setAreaId] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [errorCode, setErrorCode] = useState<string | undefined>();
  // §14 rules 1/2/5 (web-b4-controls.md): the old fieldError <p> named the
  // failing field in a form-level message — it now renders under the field.
  const fields = useFieldErrors({
    businessName: (v: string) =>
      v.trim() !== '' ? null : 'Saisissez le nom du salon.',
    phone: (v: string) =>
      !v || isPossiblePhoneNumber(v) ? null : 'Saisissez un numéro de téléphone valide.',
  });

  useEffect(() => {
    let active = true;
    (async () => {
      const me = await getMyProvider();
      if (me.status === 401) {
        router.replace('/pro/connexion');
        return;
      }
      // The account's contact number is the sensible default (editable —
      // a second salon often has its own line).
      if (active && me.status === 200 && me.profile?.account.phoneNumber) {
        setPhone((current) => current ?? me.profile!.account.phoneNumber);
      }
    })();
    return () => {
      active = false;
    };
  }, [router]);

  async function submit() {
    if (!fields.validate({ businessName, phone })) return;
    setErrorCode(undefined);
    setBusy(true);
    const r = await addSalon({
      businessName: businessName.trim(),
      businessType,
      phoneNumber: phone || undefined,
      address: address.trim() === '' ? undefined : address.trim(),
      areaId: areaId ?? undefined,
    });
    if (!r.ok || !r.salon) {
      setBusy(false);
      setErrorCode(r.error ?? 'unknown');
      return;
    }
    // Switch to the new draft, then land on its dashboard (the GoLiveCard
    // checklist = the onboarding surface on web).
    await selectSalon(r.salon.salonId);
    router.replace('/pro');
    // busy stays true through the redirect — no double submit.
  }

  const cta = teamErrorCta(errorCode);

  return (
    <div className="max-w-xl">
      <h1 className="text-headlineSmall font-semibold text-textPrimary">
        Ajouter un salon
      </h1>
      <p className="mt-xs text-bodyMedium text-textSecondary">
        Le nouveau salon démarre en brouillon avec sa propre configuration :
        fiche, catalogue, équipe, offre et période d’essai.
      </p>

      <TextField
        className="mt-l"
        label="Nom du salon"
        value={businessName}
        onChange={(e) => {
          setBusinessName(e.target.value);
          fields.revalidate('businessName', e.target.value);
        }}
        placeholder="Ex : Salon Excellence Yopougon"
        error={fields.errors.businessName}
      />
      <label className="mt-m block text-labelMedium text-textSecondary">
        Type d’entreprise
        <select
          value={businessType}
          onChange={(e) => setBusinessType(e.target.value)}
          className="mt-xs block w-full min-h-12 rounded-lg border border-borderStrong bg-surface p-m text-bodyMedium text-textPrimary"
        >
          {BUSINESS_TYPES.map((t) => (
            <option key={t.value} value={t.value}>
              {t.label}
            </option>
          ))}
        </select>
      </label>
      <div className="mt-m">
        <PhoneField
          label="Téléphone du salon"
          initialValue={phone}
          onChange={(v) => {
            setPhone(v);
            fields.revalidate('phone', v);
          }}
          error={fields.errors.phone}
        />
      </div>
      <TextField
        className="mt-m"
        label="Adresse (optionnelle)"
        value={address}
        onChange={(e) => setAddress(e.target.value)}
        placeholder="Quartier, commune…"
      />

      {/* Multi-pays MP3: où se trouve le salon (recommandé — requis pour la
          mise en ligne). */}
      <div className="mt-m">
        <LocalityPicker areaId={areaId} onChange={setAreaId} />
      </div>

      {errorCode ? (
        <p className="mt-s text-bodyMedium text-error">
          {teamErrorMessage(errorCode)}
        </p>
      ) : null}
      {cta ? (
        <Link href={cta.href} className="mt-xs inline-block text-bodyMedium underline">
          {cta.label}
        </Link>
      ) : null}

      <div className="mt-l">
        <Button onClick={submit} disabled={busy || businessName.trim() === ''}>
          {busy ? 'Création…' : 'Créer le salon'}
        </Button>
      </div>

      <p className="mt-m text-bodySmall text-textTertiary">
        Réservé à l’offre Réseau. Le badge « Vérifié » de votre compte
        s’applique automatiquement au nouveau salon.
      </p>
    </div>
  );
}
