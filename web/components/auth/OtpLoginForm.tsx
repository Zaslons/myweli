'use client';

import { useState } from 'react';
import { requestOtp, verifyOtp } from '../../lib/booking/client';
import { Button } from '../Button';

/// Phone → OTP login. Reuses the M5 BFF (request-otp / verify). On success the
/// session cookies are set by the BFF; `onSuccess` lets the caller navigate.
export function OtpLoginForm({ onSuccess }: { onSuccess: () => void }) {
  const [phone, setPhone] = useState('');
  const [code, setCode] = useState('');
  const [otpSent, setOtpSent] = useState(false);
  const [devCode, setDevCode] = useState<string | undefined>();
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function send() {
    setBusy(true);
    setError(null);
    const r = await requestOtp(phone);
    setBusy(false);
    if (!r.ok) return setError('Numéro invalide ou envoi impossible.');
    setOtpSent(true);
    setDevCode(r.devCode);
  }

  async function verify() {
    setBusy(true);
    setError(null);
    const r = await verifyOtp(phone, code);
    setBusy(false);
    if (!r.ok) return setError('Code incorrect ou expiré.');
    onSuccess();
  }

  return (
    <div className="flex flex-col gap-s">
      <input
        type="tel"
        inputMode="tel"
        placeholder="+225 07 00 00 00 00"
        value={phone}
        onChange={(e) => setPhone(e.target.value)}
        disabled={otpSent}
        className="rounded-lg border border-border bg-surface px-m py-s text-textPrimary"
      />
      {!otpSent ? (
        <Button disabled={busy || phone.length < 8} onClick={send}>
          Envoyer le code
        </Button>
      ) : (
        <>
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
          <Button disabled={busy || code.length < 4} onClick={verify}>
            Se connecter
          </Button>
        </>
      )}
      {error ? <p className="text-sm text-error">{error}</p> : null}
    </div>
  );
}
