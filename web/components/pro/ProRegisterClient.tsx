'use client';

import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { useEffect, useRef, useState } from 'react';
import PhoneInput, {
  isPossiblePhoneNumber,
} from 'react-phone-number-input';
import 'react-phone-number-input/style.css';
import { registerPro, requestEmailOtpPro } from '../../lib/api/pro';
import { Button } from '../Button';

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

  // Email identity path.
  const [email, setEmail] = useState('');
  const [code, setCode] = useState('');
  const [codeSent, setCodeSent] = useState(false);
  const [devCode, setDevCode] = useState<string | undefined>();

  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const googleDiv = useRef<HTMLDivElement>(null);

  const fieldsValid =
    businessName.trim().length > 0 &&
    !!phone &&
    isPossiblePhoneNumber(phone ?? '');
  const emailValid = /^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email.trim());

  function fieldsOrError(): boolean {
    if (fieldsValid) return true;
    setError(
      businessName.trim().length === 0
        ? 'Le nom de l’entreprise est requis.'
        : 'Le numéro de téléphone du salon est requis.',
    );
    return false;
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
  }, [googleClientId, businessName, businessType, phone, address]);

  async function sendCode() {
    if (!fieldsOrError()) return;
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
      <h1 className="text-2xl font-semibold text-textPrimary">
        Créez votre compte professionnel
      </h1>
      <p className="mt-xs text-sm text-textSecondary">
        Rejoignez MyWeli Pro et gérez votre salon.
      </p>

      {/* Business fields */}
      <label className="mt-l block text-sm text-textSecondary">
        Nom de l’entreprise
        <input
          value={businessName}
          onChange={(e) => setBusinessName(e.target.value)}
          placeholder="Ex : Salon de Beauté Marie"
          className="mt-xs w-full rounded-lg border border-border bg-surface px-m py-s text-sm text-textPrimary"
        />
      </label>
      <label className="mt-m block text-sm text-textSecondary">
        Type d’entreprise
        <select
          value={businessType}
          onChange={(e) => setBusinessType(e.target.value)}
          className="mt-xs w-full rounded-lg border border-border bg-surface px-m py-s text-sm text-textPrimary"
        >
          {BUSINESS_TYPES.map((t) => (
            <option key={t.value} value={t.value}>
              {t.label}
            </option>
          ))}
        </select>
      </label>
      <label className="mt-m block text-sm text-textSecondary">
        Téléphone du salon
        <PhoneInput
          international
          defaultCountry="CI"
          value={phone}
          onChange={setPhone}
          className="mt-xs rounded-lg border border-border bg-surface px-m py-s text-sm text-textPrimary"
        />
      </label>
      <label className="mt-m block text-sm text-textSecondary">
        Adresse (optionnelle)
        <input
          value={address}
          onChange={(e) => setAddress(e.target.value)}
          placeholder="Adresse de l’entreprise"
          className="mt-xs w-full rounded-lg border border-border bg-surface px-m py-s text-sm text-textPrimary"
        />
      </label>

      {/* Identity */}
      <h2 className="mt-l font-medium text-textPrimary">
        Votre identité de connexion
      </h2>
      <p className="mt-xs text-xs text-textTertiary">
        Elle vous servira à vous connecter à votre espace pro.
      </p>

      {googleClientId ? (
        <div className="mt-m flex justify-center">
          <div ref={googleDiv} />
        </div>
      ) : null}

      <div className="mt-m flex items-center gap-s">
        <div className="h-px flex-1 bg-border" />
        <span className="text-xs text-textTertiary">ou par e-mail</span>
        <div className="h-px flex-1 bg-border" />
      </div>

      <label className="mt-m block text-sm text-textSecondary">
        Votre e-mail
        <input
          type="email"
          value={email}
          onChange={(e) => setEmail(e.target.value)}
          placeholder="exemple@email.com"
          className="mt-xs w-full rounded-lg border border-border bg-surface px-m py-s text-sm text-textPrimary"
        />
      </label>

      {!codeSent ? (
        <Button
          className="mt-m w-full"
          onClick={sendCode}
          disabled={busy || !emailValid}
        >
          Recevoir un code
        </Button>
      ) : (
        <>
          <label className="mt-m block text-sm text-textSecondary">
            Code à 6 chiffres
            <input
              inputMode="numeric"
              maxLength={6}
              value={code}
              onChange={(e) => setCode(e.target.value)}
              className="mt-xs w-full rounded-lg border border-border bg-surface px-m py-s text-sm text-textPrimary"
            />
          </label>
          {devCode ? (
            <p className="mt-xs text-xs text-textTertiary">
              Code (dev) : {devCode}
            </p>
          ) : null}
          <Button
            className="mt-m w-full"
            onClick={() => submit({ email: email.trim(), code: code.trim() })}
            disabled={busy || code.trim().length < 4}
          >
            S’inscrire
          </Button>
          <button
            type="button"
            className="mt-s w-full text-center text-xs text-textTertiary underline"
            onClick={sendCode}
            disabled={busy}
          >
            Renvoyer le code
          </button>
        </>
      )}

      {error ? <p className="mt-m text-sm text-error">{error}</p> : null}

      <p className="mt-l text-center text-sm text-textSecondary">
        Déjà un compte ?{' '}
        <Link href="/pro/connexion" className="underline">
          Se connecter
        </Link>
      </p>
    </div>
  );
}
