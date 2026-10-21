'use client';

import { useEffect, useRef, useState } from 'react';
import type { Me } from '../../lib/api/account';
import { NO_CONNECTION_MESSAGE, writeFailureMessage } from '../../lib/api/network';
import {
  loginWithApple,
  loginWithGoogle,
  requestEmailOtp,
  updateContactPhone,
  verifyEmailOtp,
} from '../../lib/auth/client';
import { useFieldErrors } from '../../lib/forms/useFieldErrors';
import {
  PHONE_INVALID,
  normalizePhone,
  phoneFieldError,
} from '../../lib/phone';
import { Button } from '../Button';
import { PhoneField } from '../PhoneField';
import { TextField } from '../TextField';
import { appleIdentity } from '../../lib/auth/apple';
import { AppleSignInButton } from './AppleSignInButton';
import { GoogleSignInButton } from './GoogleSignInButton';
import { LegalConsentText } from '../LegalConsentText';

/// Consumer sign-in — Google + Apple + email OTP (auth overhaul P2, replaces
/// phone-OTP). Google/Apple render only when their public client IDs are
/// configured (email-first ship). After ANY successful login, a **mandatory
/// contact-phone step** blocks until the profile has a phone (decision
/// 2026-07-02) — the salon needs a number to reach the client.
/// Design: docs/design/web-auth-social.md.

export function LoginOptions({ onSuccess }: { onSuccess: () => void }) {
  const googleClientId = process.env.NEXT_PUBLIC_GOOGLE_CLIENT_ID;
  const appleClientId = process.env.NEXT_PUBLIC_APPLE_CLIENT_ID;

  const [step, setStep] = useState<'options' | 'code' | 'phone'>('options');
  // Resend cooldown (module 11): 60 s, restarted on each send.
  const [cooldown, setCooldown] = useState(0);
  useEffect(() => {
    if (cooldown <= 0) return;
    const t = setInterval(() => setCooldown((c) => c - 1), 1000);
    return () => clearInterval(t);
  }, [cooldown]);

  const [email, setEmail] = useState('');
  const [code, setCode] = useState('');
  const [devCode, setDevCode] = useState<string | undefined>();
  const [phone, setPhone] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  // §14 rules 1/2/5 — the funnels are the reference implementation
  // (docs/design/web-b4-controls.md): validate on submit, re-validate on change
  // once errored, submit never disabled-as-validation, and server-side field
  // faults land under their field too.
  const fields = useFieldErrors({
    email: (v: string) =>
      /^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(v)
        ? null
        : 'Saisissez une adresse e-mail valide.',
    code: (v: string) => (v.length >= 4 ? null : 'Saisissez le code reçu par e-mail.'),
    // The shared rule (docs/design/phone-national-length.md): a market's
    // number has exactly its national length, and the message says how many.
    phone: (v: string) => phoneFieldError(v, { required: true }),
  });

  /// Post-login: the contact phone is MANDATORY — block until the profile has
  /// one (fresh registrations arrive without it).
  function afterLogin(user: Me | null | undefined) {
    if (user && !user.phoneNumber) {
      setError(null);
      setStep('phone');
      return;
    }
    onSuccess();
  }

  async function signInWithApple() {
    if (!appleClientId || busy) return;
    setBusy(true);
    setError(null);
    // Closed popup or a failed script → null, silently (a cancel is not an
    // error). The flow itself lives in lib/auth/apple.ts, shared with the
    // salon's sign-in.
    const id = await appleIdentity(appleClientId);
    if (!id) {
      setBusy(false);
      return;
    }
    const r = await loginWithApple(id);
    setBusy(false);
    if (!r.ok) {
      setError('Connexion Apple impossible.');
      return;
    }
    afterLogin(r.user);
  }

  async function sendCode() {
    if (!fields.validate({ email: email.trim() })) return;
    setBusy(true);
    setError(null);
    const r = await requestEmailOtp(email.trim());
    setBusy(false);
    // Status 0 = no answer: the e-mail was never judged — not its fault
    // (docs/design/web-consumer-network-failure.md §3.2).
    if (r.status === 0) return setError(NO_CONNECTION_MESSAGE);
    if (!r.ok) return setError('E-mail invalide ou envoi impossible.');
    setDevCode(r.devCode);
    setStep('code');
    setCooldown(60);
  }

  async function verifyCode() {
    if (!fields.validate({ code: code.trim() })) return;
    setBusy(true);
    setError(null);
    const r = await verifyEmailOtp(email.trim(), code.trim());
    setBusy(false);
    if (!r.ok) {
      // No answer is nobody's fault but the network's → form-level, and the
      // code is not accused of a verdict no server gave.
      if (r.status === 0) return setError(NO_CONNECTION_MESSAGE);
      // « Compte suspendu » is an ACCOUNT state → form-level. A bad code is the
      // code field's fault → under the field (§14 rule 1).
      if (r.error === 'account_suspended') return setError('Compte suspendu.');
      return fields.set('code', 'Code incorrect ou expiré.');
    }
    afterLogin(r.user);
  }

  async function savePhone() {
    if (!fields.validate({ phone })) return;
    setBusy(true);
    setError(null);
    const r = await updateContactPhone(normalizePhone(phone));
    setBusy(false);
    if (!r.ok) {
      // The server's verdict on the number is the field's; anything else
      // (network, 5xx) is not the number's fault — the form says so.
      if (r.error === 'invalid_phone') return fields.set('phone', PHONE_INVALID);
      return setError(writeFailureMessage(r.status, 'L’enregistrement a échoué. Réessayez.'));
    }
    onSuccess();
  }

  // --- Mandatory contact phone (post-registration) ---------------------------
  if (step === 'phone') {
    return (
      <div className="flex flex-col gap-s">
        <p className="text-bodyLarge text-textSecondary">
          Le salon l’utilise pour vous contacter au sujet de vos rendez-vous.
        </p>
        <PhoneField
          label="Votre numéro de téléphone"
          onChange={(v) => {
            setPhone(v);
            fields.revalidate('phone', v);
          }}
          disabled={busy}
          error={fields.errors.phone}
        />
        <Button disabled={busy} isLoading={busy} onClick={savePhone}>
          Continuer
        </Button>
        {error ? <p role="alert" className="text-bodyMedium text-error">{error}</p> : null}
      </div>
    );
  }

  // --- Email code entry -------------------------------------------------------
  if (step === 'code') {
    return (
      <div className="flex flex-col gap-s">
        <p className="text-bodyLarge text-textSecondary">
          Entrez le code reçu par e-mail à {email.trim()}.
        </p>
        <TextField
          label="Code à 6 chiffres"
          type="text"
          inputMode="numeric"
          autoComplete="one-time-code"
          value={code}
          onChange={(e) => {
            setCode(e.target.value);
            fields.revalidate('code', e.target.value);
          }}
          error={fields.errors.code}
        />
        {devCode ? (
          <p className="text-bodySmall text-textTertiary">Code (dev) : {devCode}</p>
        ) : null}
        <Button disabled={busy} isLoading={busy} onClick={verifyCode}>
          Se connecter
        </Button>
        {/* cooldown-disabled is NOT §14 rule 5's anti-pattern — it is a rate
            limit, not validation, and the label says when it reopens. */}
        <Button
          variant="text"
          disabled={busy || cooldown > 0}
          onClick={sendCode}
        >
          {cooldown > 0 ? `Renvoyer le code (${cooldown}s)` : 'Renvoyer le code'}
        </Button>
        <Button
          variant="text"
          onClick={() => {
            setStep('options');
            setCode('');
            setError(null);
            fields.clear();
          }}
        >
          Changer d’e-mail
        </Button>
        {error ? <p role="alert" className="text-bodyMedium text-error">{error}</p> : null}
      </div>
    );
  }

  // --- Options ---------------------------------------------------------------
  return (
    <div className="flex flex-col gap-s">
      {/* The Google script is fetched by this button's FIRST tap, never on
          mount. Opening this page used to disclose the visitor's IP and
          user-agent to Google and let it set `g_state`, before any consent and
          before Google had been chosen — see GoogleSignInButton for the
          measurement. The facade also occupies the slot from first paint, so
          the `min-h-12` reservation that was papering over CLS 0.131 now holds
          a real control rather than a hole. */}
      {googleClientId ? (
        <GoogleSignInButton
          clientId={googleClientId}
          text="continue_with"
          disabled={busy}
          onUnavailable={() => setError('Connexion Google indisponible.')}
          onCredential={async (credential) => {
            setBusy(true);
            setError(null);
            const r = await loginWithGoogle(credential);
            setBusy(false);
            if (!r.ok) return setError('Connexion Google impossible.');
            afterLogin(r.user);
          }}
        />
      ) : null}
      {appleClientId ? (
        <AppleSignInButton onClick={signInWithApple} disabled={busy} />
      ) : null}
      {googleClientId || appleClientId ? (
        <div className="flex items-center gap-s text-bodySmall text-textTertiary">
          <span className="flex-1 border-t border-divider" />
          ou
          <span className="flex-1 border-t border-divider" />
        </div>
      ) : null}
      <TextField
        label="Votre e-mail"
        type="email"
        inputMode="email"
        autoComplete="email"
        value={email}
        onChange={(e) => {
          setEmail(e.target.value);
          fields.revalidate('email', e.target.value);
        }}
        disabled={busy}
        error={fields.errors.email}
      />
      <Button disabled={busy} isLoading={busy} onClick={sendCode}>
        Continuer avec e-mail
      </Button>
      {error ? <p role="alert" className="text-bodyMedium text-error">{error}</p> : null}
      {/* §5 (web-pro-access.md): both documents, linked — the app's sentence. */}
      <LegalConsentText lead="En continuant" />
    </div>
  );
}
