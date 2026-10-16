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

/// The percentage the form proposes when none has been chosen yet — a stored
/// 0, where every new salon starts (docs/design/acompte-off-parity.md §2).
/// The app's `kDefaultDepositPercentage`, pinned to it by a cross test
/// (tests/deposit-default-parity.test.ts).
export const DEFAULT_DEPOSIT_PERCENT = 30;

export function depositToForm(p?: DepositPolicy): DepositForm {
  const stored = p?.depositPercentage ?? 0;
  return {
    required: p?.depositRequired ?? false,
    // A stored 0 (or none) reads « not chosen yet »: the form proposes the
    // default, as the app does — never a « 0 » the switch would refuse. A
    // chosen one is read to the hundredth of a percent, not rounded to a
    // whole one: deposits off send the field back, so an untouched save
    // writes what it read — exactly for anything the web writes (two
    // decimals at most, [percentOk]): 0.125 is « 12.5 », never « 13 »; the
    // app slider's 0.6500000000000001 is « 65 ».
    percent: String(
      stored > 0 ? Number((stored * 100).toFixed(2)) : DEFAULT_DEPOSIT_PERCENT,
    ),
    windowHours:
      p?.cancellationWindowHours != null ? String(p.cancellationWindowHours) : '24',
    operator: p?.mobileMoneyOperator ?? '',
    number: p?.mobileMoneyNumber ?? '',
  };
}

/// The percentage field's rule (1–100, as its message says). [validateDeposit]
/// holds the salon to it while a deposit is collected; [buildDepositPayload]
/// sends the field only when it passes. Below 1 is refused: '0.4' passed the
/// old `> 0`, was stored as 0.004, came back as « 0 » and could not be saved
/// again. Two decimals at most — what [depositToForm] reads back exactly
/// ('12.345' would come back « 12.35 » and be rewritten by an untouched save).
function percentOk(percent: string): boolean {
  const text = percent.trim();
  if (!/^\d+(\.\d{1,2})?$/.test(text)) return false;
  const pct = Number(text);
  return pct >= 1 && pct <= 100;
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
  if (!percentOk(f.percent)) return 'Pourcentage invalide (1–100 %).';
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

/// The PUT replaces the whole policy, so everything the form holds is sent,
/// switch on or off — as the app does. Deposits off used to send `null` / `0`
/// and ERASE the operator and the percentage; a client still owing a deposit
/// reads the operator from the salon's CURRENT policy
/// (docs/design/acompte-off-parity.md D1).
///
/// [lastPercentage]: the fraction last loaded or saved. It stands in for a
/// percentage field that fails its rule — hidden while deposits are off, a
/// fault the salon cannot see must neither block nor change the save.
export function buildDepositPayload(
  f: DepositForm,
  lastPercentage: number,
): DepositPolicy {
  return {
    depositRequired: f.required,
    depositPercentage: percentOk(f.percent) ? Number(f.percent) / 100 : lastPercentage,
    cancellationWindowHours: Number(f.windowHours),
    mobileMoneyOperator: f.operator || null,
    // Sent as checked, switch on or off — `null` here used to ERASE the
    // salon's number whenever deposits were off (phone-leftovers.md §6).
    // Separators stripped (the server takes E.164 only); empty → null.
    mobileMoneyNumber: normalizePhone(f.number) || null,
  };
}
