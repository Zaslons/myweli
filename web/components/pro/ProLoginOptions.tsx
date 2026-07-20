'use client';

import Link from 'next/link';
import { useEffect, useRef, useState } from 'react';
import {
  acceptInvitationPublic,
  declineInvitationPublic,
  loginProWithGoogle,
  requestEmailOtpPro,
  verifyEmailOtpPro,
} from '../../lib/api/pro';
import { formatDateFr } from '../../lib/format';
import { teamErrorMessage, type TeamInvitation } from '../../lib/pro/team';
import { useFieldErrors } from '../../lib/forms/useFieldErrors';
import { Button } from '../Button';
import { TextField } from '../TextField';

/// The identity proof retained IN MEMORY across the 202 invitation bridge
/// (team access R5a): the Google credential or the still-unconsumed
/// email+code pair. Never persisted — a reload simply means re-login.
type InviteProof =
  | { idToken: string }
  | { email: string; code: string };

/// Salon sign-in — Google (env-gated) + email OTP, replacing phone-OTP
/// (auth overhaul P4). LOGIN-ONLY: `provider_not_found` nudges the pro app
/// for registration. No phone step (registration requires the salon phone).
/// A 202 {invitations} login lands on the « Invitations » step (team access
/// R5a). Design: docs/design/pro-auth-social.md · web-team-access-r5.md §2.2.
export function ProLoginOptions({ onSuccess }: { onSuccess: () => void }) {
  const googleClientId = process.env.NEXT_PUBLIC_GOOGLE_CLIENT_ID;
  const [step, setStep] = useState<'options' | 'code' | 'invitations'>(
    'options',
  );
  const [invitations, setInvitations] = useState<TeamInvitation[]>([]);
  const proofRef = useRef<InviteProof | null>(null);
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
  // §14 rules 1/2/5 — mirrors the LoginOptions reference (web-b4-controls.md).
  const fields = useFieldErrors({
    email: (v: string) =>
      /^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(v)
        ? null
        : 'Saisissez une adresse e-mail valide.',
    code: (v: string) => (v.length >= 4 ? null : 'Saisissez le code reçu par e-mail.'),
  });
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
            if (r.invitations?.length) {
              proofRef.current = { idToken: credential };
              setInvitations(r.invitations);
              return setStep('invitations');
            }
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
    if (!fields.validate({ email: email.trim() })) return;
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
    if (!fields.validate({ code: code.trim() })) return;
    setBusy(true);
    setError(null);
    const r = await verifyEmailOtpPro(email.trim(), code.trim());
    setBusy(false);
    if (r.invitations?.length) {
      // The code stays unconsumed server-side — it doubles as the proof.
      proofRef.current = { email: email.trim(), code: code.trim() };
      setInvitations(r.invitations);
      return setStep('invitations');
    }
    if (!r.ok) {
      // « Compte introuvable » is an ACCOUNT state and drives the signup link →
      // form-level. A bad code is the code field's fault (§14 rule 1).
      if (r.error === 'provider_not_found') return setError(notFoundMessage);
      return fields.set('code', 'Code incorrect ou expiré.');
    }
    onSuccess();
  }

  async function acceptInvitation(inv: TeamInvitation) {
    if (!proofRef.current) return;
    setBusy(true);
    setError(null);
    const r = await acceptInvitationPublic({
      invitationId: inv.id,
      ...proofRef.current,
    });
    setBusy(false);
    if (!r.ok) return setError(teamErrorMessage(r.error));
    onSuccess();
  }

  async function declineInvitation(inv: TeamInvitation) {
    if (!proofRef.current) return;
    setBusy(true);
    setError(null);
    const r = await declineInvitationPublic({
      invitationId: inv.id,
      ...proofRef.current,
    });
    setBusy(false);
    if (!r.ok) return setError(teamErrorMessage(r.error));
    const rest = invitations.filter((i) => i.id !== inv.id);
    setInvitations(rest);
    if (rest.length === 0) {
      // Nothing left to join: back to the options with a clean slate.
      proofRef.current = null;
      setStep('options');
      setCode('');
    }
  }


  if (step === 'invitations') {
    return (
      <div className="flex flex-col gap-s" data-testid="pro-login-invitations">
        <h2 className="text-titleLarge font-semibold text-textPrimary">Invitations</h2>
        <p className="text-bodyMedium text-textSecondary">
          Un salon vous a invité à rejoindre son équipe.
        </p>
        <ul className="flex flex-col gap-s">
          {invitations.map((inv) => (
            <li
              key={inv.id}
              className="flex flex-col gap-s rounded-lg border border-border bg-surface p-m"
            >
              <p className="text-bodyMedium text-textPrimary">
                <span className="font-semibold">{inv.salonName}</span> vous
                invite comme {inv.roleLabel}
              </p>
              <p className="text-bodySmall text-textTertiary">
                Expire le {formatDateFr(inv.expiresAt)}
              </p>
              <div className="flex gap-s">
                <Button disabled={busy} onClick={() => acceptInvitation(inv)}>
                  Rejoindre
                </Button>
                <Button
                  variant="text"
                  disabled={busy}
                  onClick={() => declineInvitation(inv)}
                >
                  Refuser
                </Button>
              </div>
            </li>
          ))}
        </ul>
        {error ? <p role="alert" className="text-bodyMedium text-error">{error}</p> : null}
      </div>
    );
  }

  if (step === 'code') {
    return (
      <div className="flex flex-col gap-s">
        <p className="text-bodyMedium text-textSecondary">
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
        {/* cooldown-disabled is a rate limit, not validation — rule-5-legitimate. */}
        <Button variant="text" disabled={busy || cooldown > 0} onClick={sendCode}>
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
        {error === notFoundMessage ? (
          <Link href="/pro/inscription" className="text-bodyMedium underline">
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
      {error === notFoundMessage ? (
        <Link href="/pro/inscription" className="text-bodyMedium underline">
          Créer mon compte
        </Link>
      ) : null}
      <p className="text-bodySmall text-textTertiary">
        Pas encore de compte ?{' '}
        <Link href="/pro/inscription" className="underline">
          Créer mon compte
        </Link>
      </p>
    </div>
  );
}
