'use client';

import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { useEffect, useRef, useState } from 'react';
import { isPossiblePhoneNumber } from 'react-phone-number-input';
import { registerPro, requestEmailOtpPro } from '../../lib/api/pro';
import { useFieldErrors } from '../../lib/forms/useFieldErrors';
import { Button } from '../Button';
import { PhoneField } from '../PhoneField';
import { TextField } from '../TextField';
import { LocalityPicker } from './LocalityPicker';

const BUSINESS_TYPES = [
  { value: 'salon', label: 'Salon de beauté' },
  { value: 'barber', label: 'Barbier' },
  { value: 'spa', label: 'Spa' },
  { value: 'nailSalon', label: 'Institut de manucure' },
  { value: 'massage', label: 'Massage' },
  { value: 'other', label: 'Autre' },
];

/// Salon registration on the web (docs/design/web-pro-registration.md):
/// business fields + login identity (Google env-gated | email code) in one
/// submit — mirrors the app's ProRegisterScreen. 201 → pro cookies → /pro.
export function ProRegisterClient() {
  const router = useRouter();
  const googleClientId = process.env.NEXT_PUBLIC_GOOGLE_CLIENT_ID;

  // Business fields (validated before ANY identity path fires).
  const [businessName, setBusinessName] = useState('');
  const [businessType, setBusinessType] = useState('salon');
  const [phone, setPhone] = useState<string | undefined>();
  const [address, setAddress] = useState('');
  // Multi-pays MP3: the locality area — optional here, the publish gate
  // enforces it (T57).
  const [areaId, setAreaId] = useState<string | null>(null);

  // Email identity path.
  const [email, setEmail] = useState('');
  const [code, setCode] = useState('');
  const [codeSent, setCodeSent] = useState(false);
  const [devCode, setDevCode] = useState<string | undefined>();

  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const googleDiv = useRef<HTMLDivElement>(null);

  // §14 rules 1/2/5 (web-b4-controls.md): the old fieldsOrError() named the
  // failing field IN A FORM-LEVEL message — the message now lives UNDER the
  // field it belongs to.
  const fields = useFieldErrors({
    businessName: (v: string) =>
      v.trim().length > 0 ? null : 'Saisissez le nom de l’entreprise.',
    phone: (v: string) =>
      v && isPossiblePhoneNumber(v)
        ? null
        : 'Saisissez le numéro de téléphone du salon.',
    email: (v: string) =>
      /^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(v)
        ? null
        : 'Saisissez une adresse e-mail valide.',
    code: (v: string) => (v.length >= 4 ? null : 'Saisissez le code reçu par e-mail.'),
  });

  function fieldsOrError(): boolean {
    return fields.validate({
      businessName: businessName.trim(),
      phone: phone ?? '',
    });
  }

  async function submit(identity: {
    idToken?: string;
    email?: string;
    code?: string;
  }) {
    setBusy(true);
    setError(null);
    const r = await registerPro(identity, {
      businessName: businessName.trim(),
      businessType,
      phoneNumber: phone!,
      address: address.trim() || undefined,
      areaId: areaId ?? undefined,
    });
    setBusy(false);
    if (r.ok) {
      router.replace('/pro');
      return;
    }
    setError(
      r.error === 'provider_exists'
        ? 'Un compte existe déjà pour cette identité. Connectez-vous.'
        : r.error === 'otp_invalid'
          ? 'Code incorrect ou expiré.'
          : r.error === 'invalid_phone'
            ? 'Numéro de téléphone invalide.'
            : 'Une erreur est survenue. Réessayez.',
    );
  }

  // Google (GIS) — env-gated, same loader as the login page.
  useEffect(() => {
    if (!googleClientId || !googleDiv.current) return;
    let cancelled = false;
    const src = 'https://accounts.google.com/gsi/client';
    const load = (): Promise<void> =>
      new Promise((resolve, reject) => {
        if (document.querySelector(`script[src="${src}"]`)) return resolve();
        const s = document.createElement('script');
        s.src = src;
        s.async = true;
        s.onload = () => resolve();
        s.onerror = () => reject(new Error('script_load_failed'));
        document.head.appendChild(s);
      });
    load()
      .then(() => {
        if (cancelled || !window.google || !googleDiv.current) return;
        window.google.accounts.id.initialize({
          client_id: googleClientId,
          callback: async ({ credential }) => {
            if (!fieldsOrError()) return;
            await submit({ idToken: credential });
          },
        });
        window.google.accounts.id.renderButton(googleDiv.current, {
          theme: 'outline',
          size: 'large',
          text: 'signup_with',
          width: 320,
        });
      })
      .catch(() => {/* the email path stays available */});
    return () => {
      cancelled = true;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [googleClientId, businessName, businessType, phone, address, areaId]);

  async function sendCode() {
    if (
      !fields.validate({
        businessName: businessName.trim(),
        phone: phone ?? '',
        email: email.trim(),
      })
    ) {
      return;
    }
    setBusy(true);
    setError(null);
    const r = await requestEmailOtpPro(email.trim());
    setBusy(false);
    if (!r.ok) {
      setError('Envoi du code impossible. Réessayez.');
      return;
    }
    setDevCode(r.devCode);
    setCodeSent(true);
  }

  return (
    <div className="mx-auto max-w-md">
      <h1 className="text-headlineSmall font-semibold text-textPrimary">
        Créez votre compte professionnel
      </h1>
      <p className="mt-xs text-bodyMedium text-textSecondary">
        Rejoignez MyWeli Pro et gérez votre salon.
      </p>

      {/* Business fields */}
      <TextField
        className="mt-l"
        label="Nom de l’entreprise"
        value={businessName}
        onChange={(e) => {
          setBusinessName(e.target.value);
          fields.revalidate('businessName', e.target.value);
        }}
        placeholder="Ex : Salon de Beauté Marie"
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
      />

      {/* Multi-pays MP3: où se trouve le salon (recommandé — requis pour la
          mise en ligne). */}
      <div className="mt-m">
        <LocalityPicker areaId={areaId} onChange={setAreaId} />
      </div>

      {/* Identity */}
      <h2 className="mt-l font-medium text-textPrimary">
        Votre identité de connexion
      </h2>
      <p className="mt-xs text-bodySmall text-textTertiary">
        Elle vous servira à vous connecter à votre espace pro.
      </p>

      {googleClientId ? (
        <div className="mt-m flex justify-center">
          <div ref={googleDiv} />
        </div>
      ) : null}

      <div className="mt-m flex items-center gap-s">
        <div className="flex-1 border-t border-border" />
        <span className="text-bodySmall text-textTertiary">ou par e-mail</span>
        <div className="flex-1 border-t border-border" />
      </div>

      <TextField
        className="mt-m"
        label="Votre e-mail"
        type="email"
        inputMode="email"
        autoComplete="email"
        value={email}
        onChange={(e) => {
          setEmail(e.target.value);
          fields.revalidate('email', e.target.value);
        }}
        placeholder="exemple@email.com"
        error={fields.errors.email}
      />

      {!codeSent ? (
        <Button
          className="mt-m w-full"
          onClick={sendCode}
          disabled={busy}
          isLoading={busy}
        >
          Recevoir un code
        </Button>
      ) : (
        <>
          <TextField
            className="mt-m"
            label="Code à 6 chiffres"
            inputMode="numeric"
            autoComplete="one-time-code"
            maxLength={6}
            value={code}
            onChange={(e) => {
              setCode(e.target.value);
              fields.revalidate('code', e.target.value);
            }}
            error={fields.errors.code}
          />
          {devCode ? (
            <p className="mt-xs text-bodySmall text-textTertiary">
              Code (dev) : {devCode}
            </p>
          ) : null}
          <Button
            className="mt-m w-full"
            onClick={() => {
              // The FULL subset this submit depends on — not just the code
              // (validating one field must not imply the others are fine).
              if (
                !fields.validate({
                  businessName: businessName.trim(),
                  phone: phone ?? '',
                  code: code.trim(),
                })
              ) {
                return;
              }
              submit({ email: email.trim(), code: code.trim() });
            }}
            disabled={busy}
            isLoading={busy}
          >
            S’inscrire
          </Button>
          <Button
            variant="text"
            className="mt-s w-full"
            onClick={sendCode}
            disabled={busy}
          >
            Renvoyer le code
          </Button>
        </>
      )}

      {error ? <p className="mt-m text-bodyMedium text-error">{error}</p> : null}

      <p className="mt-l text-center text-bodyMedium text-textSecondary">
        Déjà un compte ?{' '}
        <Link href="/pro/connexion" className="underline">
          Se connecter
        </Link>
      </p>
    </div>
  );
}
