'use client';

import { useRef, useState } from 'react';
import { attachDepositProof, uploadDepositProof } from '../../lib/booking/deposit';
import { formatFcfa } from '../../lib/format';
import { Button } from '../Button';

/// The pay-later deposit sheet, web edition (K2): amount + the salon's Mobile
/// Money coordinates + screenshot upload. Used on the booking done step AND
/// the mon-compte appointment detail (attach later).
export function DepositProof({
  appointmentId,
  amount,
  operator,
  number,
  onAttached,
}: {
  appointmentId: string;
  amount: number;
  operator?: string | null;
  number?: string | null;
  onAttached?: () => void;
}) {
  const fileRef = useRef<HTMLInputElement>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState(false);
  const [sent, setSent] = useState(false);

  async function send() {
    const file = fileRef.current?.files?.[0];
    if (!file) return;
    setBusy(true);
    setError(false);
    const key = await uploadDepositProof(file);
    const attached = key ? await attachDepositProof(appointmentId, key) : { ok: false };
    setBusy(false);
    if (!attached.ok) {
      setError(true);
      return;
    }
    setSent(true);
    onAttached?.();
  }

  if (sent) {
    return (
      <div className="rounded-lg bg-surface p-m">
        <p className="font-medium text-textPrimary">
          Acompte envoyé · en attente de confirmation du salon
        </p>
        <p className="mt-xs text-sm text-textSecondary">
          Le salon confirme votre rendez-vous dès réception.
        </p>
      </div>
    );
  }

  return (
    <div className="rounded-lg bg-surface p-m">
      <p className="font-medium text-textPrimary">
        Acompte à régler : {formatFcfa(amount)}
      </p>
      <p className="mt-xs text-sm text-textSecondary">
        Payez directement au salon
        {number ? ` (${operator ?? 'Mobile Money'} : ${number})` : ''}, puis
        joignez la capture du paiement. MyWeli ne prélève rien.
      </p>
      <div className="mt-s flex flex-wrap items-center gap-s">
        <input
          ref={fileRef}
          type="file"
          accept="image/*"
          aria-label="Capture du paiement"
          className="text-sm text-textSecondary"
        />
        <Button disabled={busy} onClick={send}>
          {busy ? 'Envoi…' : 'Envoyer la preuve'}
        </Button>
      </div>
      {error ? (
        <p className="mt-s text-sm text-error">
          L’envoi a échoué. Vérifiez l’image et réessayez.
        </p>
      ) : null}
      <p className="mt-s text-xs text-textTertiary">
        Vous pouvez aussi la joindre plus tard depuis « Mon compte » ou l’app.
      </p>
    </div>
  );
}
