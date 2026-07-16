'use client';

import { useEffect, useRef, useState } from 'react';
import { isPossiblePhoneNumber } from 'react-phone-number-input';
import type { Me } from '../../lib/api/account';
import {
  loginWithApple,
  loginWithGoogle,
  requestEmailOtp,
  updateContactPhone,
  verifyEmailOtp,
} from '../../lib/auth/client';
import { Button } from '../Button';
import { PhoneField } from '../PhoneField';

/// Consumer sign-in — Google + Apple + email OTP (auth overhaul P2, replaces
/// phone-OTP). Google/Apple render only when their public client IDs are
/// configured (email-first ship). After ANY successful login, a **mandatory
/// contact-phone step** blocks until the profile has a phone (decision
/// 2026-07-02) — the salon needs a number to reach the client.
/// Design: docs/design/web-auth-social.md.

declare global {
  interface Window {
    google?: {
      accounts: {
        id: {
          initialize: (config: {
            client_id: string;
            callback: (r: { credential: string }) => void;
          }) => void;
          renderButton: (
            el: HTMLElement,
            options: {
              theme?: string;
              size?: string;
              width?: number;
              locale?: string;
              /// GIS button text variant (e.g. 'signup_with' → « S'inscrire »).
              text?: string;
            },
          ) => void;
        };
      };
    };
    AppleID?: {
      auth: {
        init: (config: {
          clientId: string;
          scope: string;
          redirectURI: string;
          usePopup: boolean;
        }) => void;
        signIn: (options?: {
          nonce?: string;
        }) => Promise<{
          authorization: { id_token: string };
          user?: { name?: { firstName?: string; lastName?: string } };
        }>;
      };
    };
  }
}

function loadScript(src: string): Promise<void> {
  return new Promise((resolve, reject) => {
    const existing = document.querySelector(`script[src="${src}"]`);
    if (existing) return resolve();
    const s = document.createElement('script');
    s.src = src;
    s.async = true;
    s.onload = () => resolve();
    s.onerror = () => reject(new Error('script_load_failed'));
    document.head.appendChild(s);
  });
}

function randomNonce(): string {
  const bytes = new Uint8Array(16);
  crypto.getRandomValues(bytes);
  return Array.from(bytes, (b) => b.toString(16).padStart(2, '0')).join('');
}

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
  const googleDiv = useRef<HTMLDivElement>(null);

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

  // Google Identity Services — official branded button (env-gated).
  useEffect(() => {
    if (!googleClientId || !googleDiv.current) return;
    let cancelled = false;
    loadScript('https://accounts.google.com/gsi/client')
      .then(() => {
        if (cancelled || !window.google || !googleDiv.current) return;
        window.google.accounts.id.initialize({
          client_id: googleClientId,
          callback: async ({ credential }) => {
            setBusy(true);
            setError(null);
            const r = await loginWithGoogle(credential);
            setBusy(false);
            if (!r.ok) return setError('Connexion Google impossible.');
            afterLogin(r.user);
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

  async function signInWithApple() {
    if (!appleClientId || busy) return;
    setBusy(true);
    setError(null);
    try {
      await loadScript(
        'https://appleid.cdn-apple.com/appleauth/static/jsapi/appleid/1/en_US/appleid.auth.js',
      );
      if (!window.AppleID) throw new Error('apple_unavailable');
      const nonce = randomNonce();
      window.AppleID.auth.init({
        clientId: appleClientId,
        scope: 'name email',
        redirectURI: `${window.location.origin}/connexion`,
        usePopup: true,
      });
      const res = await window.AppleID.auth.signIn({ nonce });
      const name = res.user?.name;
      const fullName = [name?.firstName, name?.lastName]
        .filter(Boolean)
        .join(' ');
      const r = await loginWithApple({
        identityToken: res.authorization.id_token,
        nonce,
        fullName: fullName || undefined,
      });
      if (!r.ok) {
        setError('Connexion Apple impossible.');
        return;
      }
      afterLogin(r.user);
    } catch {
      // User closed the popup or the script failed — silent for cancels.
      setError(null);
    } finally {
      setBusy(false);
    }
  }

  async function sendCode() {
    setBusy(true);
    setError(null);
    const r = await requestEmailOtp(email.trim());
    setBusy(false);
    if (!r.ok) return setError('E-mail invalide ou envoi impossible.');
    setDevCode(r.devCode);
    setStep('code');
    setCooldown(60);
  }

  async function verifyCode() {
    setBusy(true);
    setError(null);
    const r = await verifyEmailOtp(email.trim(), code.trim());
    setBusy(false);
    if (!r.ok) {
      return setError(
        r.error === 'account_suspended'
          ? 'Compte suspendu.'
          : 'Code incorrect ou expiré.',
      );
    }
    afterLogin(r.user);
  }

  async function savePhone() {
    setBusy(true);
    setError(null);
    const r = await updateContactPhone(phone);
    setBusy(false);
    if (!r.ok) return setError('Numéro invalide. Réessayez.');
    onSuccess();
  }

  const emailValid = /^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email.trim());

  // --- Mandatory contact phone (post-registration) ---------------------------
  if (step === 'phone') {
    return (
      <div className="flex flex-col gap-s">
        <p className="text-sm font-medium text-textPrimary">
          Votre numéro de téléphone
        </p>
        <p className="text-sm text-textSecondary">
          Le salon l’utilise pour vous contacter au sujet de vos rendez-vous.
        </p>
        <PhoneField onChange={setPhone} disabled={busy} />
        <Button
          disabled={busy || !phone || !isPossiblePhoneNumber(phone)}
          onClick={savePhone}
        >
          Continuer
        </Button>
        {error ? <p className="text-sm text-error">{error}</p> : null}
      </div>
    );
  }

  // --- Email code entry -------------------------------------------------------
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
      </div>
    );
  }

  // --- Options ---------------------------------------------------------------
  return (
    <div className="flex flex-col gap-s">
      {googleClientId ? (
        <div ref={googleDiv} className="flex justify-center" />
      ) : null}
      {appleClientId ? (
        <Button onClick={signInWithApple} disabled={busy}>
          Continuer avec Apple
        </Button>
      ) : null}
      {googleClientId || appleClientId ? (
        <div className="flex items-center gap-s text-xs text-textTertiary">
          <span className="flex-1 border-t border-divider" />
          ou
          <span className="flex-1 border-t border-divider" />
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
      <p className="text-xs text-textTertiary">
        En continuant, vous acceptez nos conditions d’utilisation.
      </p>
    </div>
  );
}
