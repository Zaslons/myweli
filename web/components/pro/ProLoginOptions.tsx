'use client';

import Link from 'next/link';
import { useEffect, useRef, useState } from 'react';
import {
  loginProWithGoogle,
  requestEmailOtpPro,
  verifyEmailOtpPro,
} from '../../lib/api/pro';
import { Button } from '../Button';

/// Salon sign-in — Google (env-gated) + email OTP, replacing phone-OTP
/// (auth overhaul P4). LOGIN-ONLY: `provider_not_found` nudges the pro app
/// for registration. No phone step (registration requires the salon phone).
/// Design: docs/design/pro-auth-social.md.
export function ProLoginOptions({ onSuccess }: { onSuccess: () => void }) {
  const googleClientId = process.env.NEXT_PUBLIC_GOOGLE_CLIENT_ID;
  const [step, setStep] = useState<'options' | 'code'>('options');
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
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const googleDiv = useRef<HTMLDivElement>(null);

  const notFoundMessage = 'Compte introuvable.';

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
            setBusy(true);
            setError(null);
            const r = await loginProWithGoogle(credential);
            setBusy(false);
            if (!r.ok) {
              return setError(
                r.error === 'provider_not_found'
                  ? notFoundMessage
                  : 'Connexion Google impossible.',
              );
            }
            onSuccess();
          },
        });
        window.google.accounts.id.renderButton(googleDiv.current, {
          theme: 'outline',
          size: 'large',
          width: 320,
          locale: 'fr',
        });
      })
      .catch(() => setError('Connexion Google indisponible.'));
    return () => {
      cancelled = true;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [googleClientId]);

  async function sendCode() {
    setBusy(true);
    setError(null);
    const r = await requestEmailOtpPro(email.trim());
    setBusy(false);
    if (!r.ok) return setError('E-mail invalide ou envoi impossible.');
    setDevCode(r.devCode);
    setStep('code');
    setCooldown(60);
  }

  async function verifyCode() {
    setBusy(true);
    setError(null);
    const r = await verifyEmailOtpPro(email.trim(), code.trim());
    setBusy(false);
    if (!r.ok) {
      return setError(
        r.error === 'provider_not_found'
          ? notFoundMessage
          : 'Code incorrect ou expiré.',
      );
    }
    onSuccess();
  }

  const emailValid = /^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email.trim());

  if (step === 'code') {
    return (
      <div className="flex flex-col gap-s">
        <p className="text-sm text-textSecondary">
          Entrez le code reçu par e-mail à {email.trim()}.
        </p>
        <input
          type="text"
          inputMode="numeric"
          placeholder="Code à 6 chiffres"
          value={code}
          onChange={(e) => setCode(e.target.value)}
          className="rounded-lg border border-border bg-surface px-m py-s text-textPrimary"
        />
        {devCode ? (
          <p className="text-xs text-textTertiary">Code (dev) : {devCode}</p>
        ) : null}
        <Button disabled={busy || code.trim().length < 4} onClick={verifyCode}>
          Se connecter
        </Button>
        <button
          type="button"
          disabled={busy || cooldown > 0}
          onClick={sendCode}
          className="text-sm text-textTertiary underline disabled:no-underline disabled:opacity-60"
        >
          {cooldown > 0 ? `Renvoyer le code (${cooldown}s)` : 'Renvoyer le code'}
        </button>
        <button
          type="button"
          onClick={() => {
            setStep('options');
            setCode('');
            setError(null);
          }}
          className="text-sm text-textTertiary underline"
        >
          Changer d’e-mail
        </button>
        {error ? <p className="text-sm text-error">{error}</p> : null}
        {error === notFoundMessage ? (
          <Link href="/pro/inscription" className="text-sm underline">
            Créer mon compte
          </Link>
        ) : null}
      </div>
    );
  }

  return (
    <div className="flex flex-col gap-s">
      {googleClientId ? (
        <div ref={googleDiv} className="flex justify-center" />
      ) : null}
      {googleClientId ? (
        <div className="flex items-center gap-s text-xs text-textTertiary">
          <span className="h-px flex-1 bg-divider" />
          ou
          <span className="h-px flex-1 bg-divider" />
        </div>
      ) : null}
      <input
        type="email"
        inputMode="email"
        autoComplete="email"
        placeholder="Votre e-mail"
        value={email}
        onChange={(e) => setEmail(e.target.value)}
        disabled={busy}
        className="rounded-lg border border-border bg-surface px-m py-s text-textPrimary"
      />
      <Button disabled={busy || !emailValid} onClick={sendCode}>
        Continuer avec e-mail
      </Button>
      {error ? <p className="text-sm text-error">{error}</p> : null}
      {error === notFoundMessage ? (
        <Link href="/pro/inscription" className="text-sm underline">
          Créer mon compte
        </Link>
      ) : null}
      <p className="text-xs text-textTertiary">
        Pas encore de compte ?{' '}
        <Link href="/pro/inscription" className="underline">
          Créer mon compte
        </Link>
      </p>
    </div>
  );
}
