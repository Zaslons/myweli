'use client';

import Link from 'next/link';
import { useEffect, useRef, useState } from 'react';
import {
  acceptInvitationPublic,
  declineInvitationPublic,
  loginProWithApple,
  loginProWithGoogle,
  requestEmailOtpPro,
  verifyEmailOtpPro,
} from '../../lib/api/pro';
import { formatDateFr } from '../../lib/format';
import {
  teamErrorMessage,
  type TeamInvitation,
} from '../../lib/pro/team';
import { useFieldErrors } from '../../lib/forms/useFieldErrors';
import { Button } from '../Button';
import { TextField } from '../TextField';
import { GoogleSignInButton } from '../auth/GoogleSignInButton';
import { LegalConsentText } from '../LegalConsentText';
import { AppleSignInButton } from '../auth/AppleSignInButton';
import { appleIdentity } from '../../lib/auth/apple';
import { forgetSalon } from '../../lib/pro/remembered-salon';
import { type SignInRefusal, codeRefusal, sendRefusal } from '../../lib/auth/otp-failure';
import { UNNAMED_SALON_AT_SENTENCE_START, salonNameOr } from '../../lib/salon-name';

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
  // Apple renders only when its public client id is configured — the client
  // sign-in's rule (docs/design/web-pro-apple.md).
  const appleClientId = process.env.NEXT_PUBLIC_APPLE_CLIENT_ID;
  const [step, setStep] = useState<'options' | 'code' | 'invitations'>(
    'options',
  );
  const [invitations, setInvitations] = useState<TeamInvitation[]>([]);
  const proofRef = useRef<InviteProof | null>(null);
  /// Every way in ends here: an account is signed in, so the salon a previous
  /// session remembered is not this one's to name (decision 14,
  /// docs/design/web-pro-truthful-failure.md §2.4).
  const signedIn = () => {
    forgetSalon();
    onSuccess();
  };
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

  const notFoundMessage = 'Compte introuvable.';


  /// A refused step, said where the table puts it — under a field only while
  /// that field is on screen (« Renvoyer le code » has no e-mail field to
  /// point at), under the form otherwise (docs/design/web-client-polish.md
  /// §2.1).
  function refuse(f: SignInRefusal) {
    const shown = f.field === 'code' ? step === 'code' : step === 'options';
    if (f.field && shown) return fields.set(f.field, f.message);
    setError(f.message);
  }

  async function sendCode() {
    if (!fields.validate({ email: email.trim() })) return;
    setBusy(true);
    setError(null);
    const r = await requestEmailOtpPro(email.trim());
    setBusy(false);
    // No answer, a rate limit or an outage is not the e-mail's fault: only
    // the server's `invalid_email` goes under the field.
    if (!r.ok) return refuse(sendRefusal(r));
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
      // form-level. The rest is the shared table: the code's own verdicts
      // under the field, what is not the code's fault under the form.
      if (r.error === 'provider_not_found') return setError(notFoundMessage);
      return refuse(codeRefusal(r));
    }
    signedIn();
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
    signedIn();
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
        <p className="text-bodyLarge text-textSecondary">
          Un salon vous a invité à rejoindre son équipe.
        </p>
        <ul className="flex flex-col gap-s">
          {invitations.map((inv) => (
            <li
              key={inv.id}
              className="flex flex-col gap-s rounded-lg border border-border bg-surface p-m"
            >
              <p className="text-bodyLarge text-textPrimary">
                <span className="font-semibold">
                  {salonNameOr(inv.salonName, UNNAMED_SALON_AT_SENTENCE_START)}
                </span>{' '}
                vous
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
      {/* The Google script is fetched by this button's FIRST tap, never on
          mount — see GoogleSignInButton for the production measurement of what
          mounting it cost. The facade also occupies the slot from first paint,
          so `min-h-12` now reserves space for a real control instead of a hole
          that CLS 0.131 was measured against. */}
      {googleClientId ? (
        <GoogleSignInButton
          clientId={googleClientId}
          text="continue_with"
          disabled={busy}
          onUnavailable={() => setError('Connexion Google indisponible.')}
          onCredential={async (credential) => {
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
            signedIn();
          }}
        />
      ) : null}
      {appleClientId ? (
        <AppleSignInButton
          disabled={busy}
          onClick={async () => {
            if (busy) return;
            setBusy(true);
            setError(null);
            // A closed popup is null — silent, as on the client's sign-in.
            const id = await appleIdentity(appleClientId);
            if (!id) {
              setBusy(false);
              return;
            }
            const r = await loginProWithApple(id);
            setBusy(false);
            if (!r.ok) {
              return setError(
                r.error === 'provider_not_found'
                  ? notFoundMessage
                  : 'Connexion Apple impossible.',
              );
            }
            signedIn();
          }}
        />
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
      <LegalConsentText lead="En continuant" />
    </div>
  );
}
