/// Pure helpers for the pro Acompte (deposit policy) form. Unit-tested.
/// Multi-pays MP3: the operator list is CATALOG data — the salon country's
/// `operators` from GET /localities (lib/api/localities.ts `operatorsFor`) —
/// never a hardcoded list; the backend validates against the same catalog.

import { normalizePhone, phoneFieldError } from '../phone';

export type DepositPolicy = {
  depositRequired: boolean;
  depositPercentage: number; // 0..1
  cancellationWindowHours: number;
  mobileMoneyOperator?: string | null;
  mobileMoneyNumber?: string | null;
};

export type DepositForm = {
  required: boolean;
  percent: string; // 0..100
  windowHours: string;
  operator: string;
  number: string;
};

export function depositToForm(p?: DepositPolicy): DepositForm {
  return {
    required: p?.depositRequired ?? false,
    percent: p?.depositPercentage != null ? String(Math.round(p.depositPercentage * 100)) : '',
    windowHours:
      p?.cancellationWindowHours != null ? String(p.cancellationWindowHours) : '24',
    operator: p?.mobileMoneyOperator ?? '',
    number: p?.mobileMoneyNumber ?? '',
  };
}

export function validateDeposit(f: DepositForm): string | null {
  const window = Number(f.windowHours);
  if (
    f.windowHours.trim() === '' ||
    Number.isNaN(window) ||
    window < 0 ||
    window > 720
  ) {
    return 'Fenêtre d’annulation invalide (0–720 h).';
  }
  if (!f.required) return null;
  const pct = Number(f.percent);
  if (f.percent.trim() === '' || Number.isNaN(pct) || pct <= 0 || pct > 100) {
    return 'Pourcentage invalide (1–100 %).';
  }
  if (!f.operator) return 'Choisissez un opérateur Mobile Money.';
  return null;
}

/// « Numéro Mobile Money » — its fault renders UNDER the field (§14 rule 1,
/// `useFieldErrors` in AcompteClient), so [validateDeposit] does not carry it.
/// The number is KEPT whatever the switch says (docs/design/phone-leftovers.md
/// §6 — parity with the app), so it is judged whenever it is not empty, and
/// required only while a deposit is collected. The shared rule:
/// docs/design/phone-national-length.md.
export function validateDepositNumber(
  v: string,
  { required }: { required: boolean },
): string | null {
  return phoneFieldError(v, { required });
}

export function buildDepositPayload(f: DepositForm): DepositPolicy {
  return {
    depositRequired: f.required,
    depositPercentage: f.required ? Number(f.percent) / 100 : 0,
    cancellationWindowHours: Number(f.windowHours),
    mobileMoneyOperator: f.required && f.operator ? f.operator : null,
    // Sent as checked, switch on or off — the PUT replaces the whole policy,
    // and `null` here used to ERASE the salon's number whenever deposits were
    // off. Separators stripped (the server takes E.164 only); empty → null.
    mobileMoneyNumber: normalizePhone(f.number) || null,
  };
}
