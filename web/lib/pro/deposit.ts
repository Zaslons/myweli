/// Pure helpers for the pro Acompte (deposit policy) form. Unit-tested.
/// Multi-pays MP3: the operator list is CATALOG data — the salon country's
/// `operators` from GET /localities (lib/api/localities.ts `operatorsFor`) —
/// never a hardcoded list; the backend validates against the same catalog.

const E164 = /^\+[1-9]\d{7,14}$/;

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
  if (!E164.test(f.number.trim())) {
    return 'Numéro Mobile Money invalide (format international).';
  }
  return null;
}

export function buildDepositPayload(f: DepositForm): DepositPolicy {
  return {
    depositRequired: f.required,
    depositPercentage: f.required ? Number(f.percent) / 100 : 0,
    cancellationWindowHours: Number(f.windowHours),
    mobileMoneyOperator: f.required && f.operator ? f.operator : null,
    mobileMoneyNumber: f.required && f.number.trim() ? f.number.trim() : null,
  };
}
