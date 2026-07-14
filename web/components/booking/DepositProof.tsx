'use client';

import { useRef, useState } from 'react';
import { attachDepositProof, uploadDepositProof } from '../../lib/booking/deposit';
import { formatFcfa } from '../../lib/format';
import {
  deepLinkKindIsWave,
  findOperator,
  operatorLabel,
  waveDeepLink,
} from '../../lib/mobile-money';
import { useLocalities } from '../../lib/use-localities';
import { Button } from '../Button';

/// The pay-later deposit sheet, web edition (K2): amount + the salon's Mobile
/// Money coordinates + screenshot upload. Used on the booking done step AND
/// the mon-compte appointment detail (attach later).
export function DepositProof({
  appointmentId,
  amount,
  operator,
  number,
  currency,
  onAttached,
}: {
  appointmentId: string;
  amount: number;
  operator?: string | null;
  number?: string | null;
  /// The salon's currency (multi-pays) — omitted → XOF.
  currency?: string | null;
  onAttached?: () => void;
}) {
  const fileRef = useRef<HTMLInputElement>(null);
  // Multi-pays MP3: the operator's display label + the Wave deep link come
  // from the catalog's CLOSED deepLinkKind vocabulary (T56) — never a
  // payload URL. Legacy label values render as-is.
  const { tree } = useLocalities();
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

  const opLabel = operator ? operatorLabel(tree, operator) : null;
  const waveHref =
    number && deepLinkKindIsWave(findOperator(tree, operator)?.deepLinkKind)
      ? waveDeepLink(number, amount)
      : null;

  return (
    <div className="rounded-lg bg-surface p-m">
      <p className="font-medium text-textPrimary">
        Acompte à régler : {formatFcfa(amount, currency ?? undefined)}
      </p>
      <p className="mt-xs text-sm text-textSecondary">
        Payez directement au salon
        {number ? ` (${opLabel ?? 'Mobile Money'} : ${number})` : ''}, puis
        joignez la capture du paiement. MyWeli ne prélève rien.
      </p>
      {waveHref ? (
        <a
          href={waveHref}
          target="_blank"
          rel="noopener noreferrer"
          className="mt-s inline-block rounded-lg border border-border bg-secondary px-m py-xs text-sm font-medium text-textPrimary hover:bg-surfaceVariant"
        >
          Payer avec Wave
        </a>
      ) : null}
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
