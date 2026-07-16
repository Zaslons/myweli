'use client';

import { useState } from 'react';
import { isPossiblePhoneNumber } from 'react-phone-number-input';
import { Button } from '../Button';
import { PhoneField } from '../PhoneField';

type OtpResult = { ok: boolean; devCode?: string; error?: string };
type VerifyResult = { ok: boolean; error?: string };

/// Phone → OTP login. The request/verify calls are injected so the same form
/// serves the consumer (M6) and the provider (M7) BFFs. On success the session
/// cookies are set by the BFF; `onSuccess` lets the caller navigate.
export function OtpLoginForm({
  onSuccess,
  requestCode,
  verifyCode,
  verifyErrorMessage = () => 'Code incorrect ou expiré.',
}: {
  onSuccess: () => void;
  requestCode: (phone: string) => Promise<OtpResult>;
  verifyCode: (phone: string, code: string) => Promise<VerifyResult>;
  verifyErrorMessage?: (error?: string) => string;
}) {
  const [phone, setPhone] = useState('');
  const [code, setCode] = useState('');
  const [otpSent, setOtpSent] = useState(false);
  const [devCode, setDevCode] = useState<string | undefined>();
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function send() {
    setBusy(true);
    setError(null);
    const r = await requestCode(phone);
    setBusy(false);
    if (!r.ok) return setError('Numéro invalide ou envoi impossible.');
    setOtpSent(true);
    setDevCode(r.devCode);
  }

  async function verify() {
    setBusy(true);
    setError(null);
    const r = await verifyCode(phone, code);
    setBusy(false);
    if (!r.ok) return setError(verifyErrorMessage(r.error));
    onSuccess();
  }

  return (
    <div className="flex flex-col gap-s">
      <PhoneField onChange={setPhone} disabled={otpSent} />
      {!otpSent ? (
        <Button
          disabled={busy || !phone || !isPossiblePhoneNumber(phone)}
          onClick={send}
        >
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
            <p className="text-bodySmall text-textTertiary">Code (dev) : {devCode}</p>
          ) : null}
          <Button disabled={busy || code.length < 4} onClick={verify}>
            Se connecter
          </Button>
        </>
      )}
      {error ? <p className="text-bodyMedium text-error">{error}</p> : null}
    </div>
  );
}
