'use client';

import { useState } from 'react';
import { isPossiblePhoneNumber } from 'react-phone-number-input';
import { useFieldErrors } from '../../lib/forms/useFieldErrors';
import { Button } from '../Button';
import { PhoneField } from '../PhoneField';
import { TextField } from '../TextField';

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
  // §14 rules 1/2/5 — mirrors the LoginOptions reference (web-b4-controls.md).
  const fields = useFieldErrors({
    phone: (v: string) =>
      v && isPossiblePhoneNumber(v)
        ? null
        : 'Saisissez un numéro de téléphone valide.',
    code: (v: string) => (v.length >= 4 ? null : 'Saisissez le code reçu par SMS.'),
  });

  async function send() {
    if (!fields.validate({ phone })) return;
    setBusy(true);
    const r = await requestCode(phone);
    setBusy(false);
    if (!r.ok) return fields.set('phone', 'Numéro invalide ou envoi impossible.');
    setOtpSent(true);
    setDevCode(r.devCode);
  }

  async function verify() {
    if (!fields.validate({ code })) return;
    setBusy(true);
    const r = await verifyCode(phone, code);
    setBusy(false);
    if (!r.ok) return fields.set('code', verifyErrorMessage(r.error));
    onSuccess();
  }

  return (
    <div className="flex flex-col gap-s">
      <PhoneField
        onChange={(v) => {
          setPhone(v);
          fields.revalidate('phone', v);
        }}
        disabled={otpSent}
        error={fields.errors.phone}
      />
      {!otpSent ? (
        <Button disabled={busy} isLoading={busy} onClick={send}>
          Envoyer le code
        </Button>
      ) : (
        <>
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
          <Button disabled={busy} isLoading={busy} onClick={verify}>
            Se connecter
          </Button>
        </>
      )}
    </div>
  );
}
