'use client';

import Link from 'next/link';
import { Card } from '../Card';
import { ErrorState } from '../ErrorState';
import { useRouter } from 'next/navigation';
import { useEffect, useState } from 'react';
import {
  getDepositPolicy,
  getMyProvider,
  saveDepositPolicy,
} from '../../lib/api/pro';
import { useFieldErrors } from '../../lib/forms/useFieldErrors';
import { operatorsFor } from '../../lib/localities';
import { PHONE_INVALID } from '../../lib/phone';
import {
  type DepositForm,
  buildDepositPayload,
  depositToForm,
  validateDeposit,
  validateDepositNumber,
} from '../../lib/pro/deposit';
import { useLocalities } from '../../lib/use-localities';
import { Button } from '../Button';
import { Loading } from '../Loading';
import { PhoneField } from '../PhoneField';

const input =
  'block w-full min-h-12 rounded-lg border border-borderStrong bg-surface p-m text-bodyLarge text-textPrimary focus:border-borderFocus focus:ring-1 focus:ring-borderFocus disabled:border-border disabled:text-textDisabled';

// The Mobile Money number's check, per switch position: required while a
// deposit is collected, optional otherwise — but judged whenever it is kept
// (docs/design/phone-leftovers.md §6). Module constants: useFieldErrors keys
// its callbacks on the object's identity.
const NUMBER_REQUIRED = {
  number: (v: string) => validateDepositNumber(v, { required: true }),
};
const NUMBER_OPTIONAL = {
  number: (v: string) => validateDepositNumber(v, { required: false }),
};

export function AcompteClient() {
  const router = useRouter();
  // Multi-pays MP3: the operator list is the salon COUNTRY's catalog
  // (GET /localities) — the backend validates against the same source.
  const localities = useLocalities();
  const [countryCode, setCountryCode] = useState<string | null>(null);
  const [providerId, setProviderId] = useState('');
  const [form, setForm] = useState<DepositForm | null>(null);
  // The percentage (a fraction) last loaded or saved — sent when the field,
  // hidden while deposits are off, fails its rule
  // (docs/design/acompte-off-parity.md decision 1).
  const [lastPercentage, setLastPercentage] = useState(0);
  const [loading, setLoading] = useState(true);
  const [reloadKey, setReloadKey] = useState(0);
  const [loadError, setLoadError] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [saved, setSaved] = useState(false);
  const [verified, setVerified] = useState(false);
  // « Numéro Mobile Money » answers UNDER its field (§14 rules 1/2 —
  // docs/design/phone-national-length.md); the rest stays form-level.
  const fields = useFieldErrors(
    form?.required ? NUMBER_REQUIRED : NUMBER_OPTIONAL,
  );
  // Deposits off hide the number — and with it the one place a refused number
  // can be shown and fixed (the app's `_showNumberWhileOff`). Set by a refused
  // save; it stays while the salon fixes the number (the field must not vanish
  // the moment it turns valid), and goes once that is done: a successful save,
  // or the switch moved — then the field is the switch's again.
  const [showNumberWhileOff, setShowNumberWhileOff] = useState(false);

  useEffect(() => {
    let active = true;
    // Any failed load — a refusal, a 5xx, no network — is the ErrorState and
    // its « Réessayer », never a blank form: saving one would overwrite the
    // real policy (docs/design/acompte-off-parity.md D3).
    function fail() {
      if (!active) return;
      setLoadError(true);
      setLoading(false);
    }
    (async () => {
      try {
        const me = await getMyProvider();
        if (me.status === 401) {
          router.replace('/pro/connexion');
          return;
        }
        if (me.status !== 200 || !me.profile) {
          fail();
          return;
        }
        const pid = me.profile.provider.id;
        const dp = await getDepositPolicy(pid);
        if (dp.status !== 200 || !dp.policy) {
          fail();
          return;
        }
        if (!active) return;
        setProviderId(pid);
        setCountryCode(me.profile.provider.countryCode ?? null);
        setVerified(me.profile.account.verificationStatus === 'verified');
        setForm(depositToForm(dp.policy));
        setLastPercentage(dp.policy.depositPercentage ?? 0);
        setLoading(false);
      } catch {
        fail();
      }
    })();
    return () => {
      active = false;
    };
  }, [router, reloadKey]);

  if (loading) return <Loading className="mt-l" />;
  if (loadError || !form) {
    return <ErrorState title="Acompte" onRetry={() => { setLoadError(false); setLoading(true); setReloadKey((k) => k + 1); }} />;
  }

  function set<K extends keyof DepositForm>(k: K, v: DepositForm[K]) {
    setForm((f) => (f ? { ...f, [k]: v } : f));
    setSaved(false);
  }

  async function save() {
    const f = form as DepositForm;
    // The number is checked where it is sent — and it is sent whatever the
    // switch says (docs/design/phone-leftovers.md §6). Both checks run, so
    // every fault shows at once.
    const numberOk = fields.validate({ number: f.number });
    if (!numberOk && !f.required) setShowNumberWhileOff(true);
    const v = validateDeposit(f);
    setError(v);
    if (v || !numberOk) return;
    setBusy(true);
    setError(null);
    const payload = buildDepositPayload(f, lastPercentage);
    // No network is a failed save like any other — never « Enregistrer » left
    // disabled for ever (docs/design/acompte-off-parity.md §8).
    const r = await saveDepositPolicy(providerId, payload).catch(
      (): { ok: false; status: number; error?: string } => ({ ok: false, status: 0 }),
    );
    setBusy(false);
    if (!r.ok) {
      // The server names the number (phone-leftovers §2): under its field —
      // revealed first when deposits are off.
      if (r.error === 'invalid_phone') {
        fields.set('number', PHONE_INVALID);
        if (!f.required) setShowNumberWhileOff(true);
        return;
      }
      setError(
        r.error === 'verification_required'
          ? 'Vérifiez votre compte pour activer les acomptes.'
          : 'L’enregistrement a échoué. Réessayez.',
      );
      return;
    }
    setLastPercentage(payload.depositPercentage);
    setShowNumberWhileOff(false);
    setSaved(true);
  }

  return (
    <div className="max-w-2xl">
      <h1 className="text-headlineSmall font-semibold text-textPrimary">Acompte</h1>

      {/* T52: deposits are verified-only — the server enforces it; this
          mirrors the rule with guidance. */}
      {!verified ? (
        <div className="mt-l rounded-xl border border-border bg-surface p-m text-bodyLarge text-textSecondary">
          Les acomptes sont disponibles après la vérification de votre
          compte.{' '}
          <Link href="/pro/verification" className="underline">
            Vérifier mon compte
          </Link>
        </div>
      ) : null}

      <Card as="section" className="mt-l space-y-m">
        <label
          className={`flex items-center gap-s text-textPrimary ${
            verified ? '' : 'opacity-50'
          }`}
        >
          <input
            type="checkbox"
            disabled={!verified}
            checked={form.required}
            onChange={(e) => {
              set('required', e.target.checked);
              setShowNumberWhileOff(false);
            }}
          />
          Exiger un acompte
        </label>

        {form.required ? (
          <>
            <label className="block text-bodyMedium text-textTertiary">
              Pourcentage de l’acompte (%)
              <input
                className={input}
                inputMode="numeric"
                value={form.percent}
                onChange={(e) => set('percent', e.target.value)}
              />
            </label>
            <label className="block text-bodyMedium text-textTertiary">
              Opérateur Mobile Money
              {localities.loading ? (
                <select className={input} disabled>
                  <option>Chargement…</option>
                </select>
              ) : localities.error ? (
                <span className="mt-xs flex items-center gap-s">
                  <span role="alert" className="flex-1 text-bodyMedium text-error">
                    Liste des opérateurs indisponible.
                  </span>
                  <Button variant="secondary" onClick={localities.retry}>
                    Réessayer
                  </Button>
                </span>
              ) : (
                <select
                  className={input}
                  value={form.operator}
                  onChange={(e) => set('operator', e.target.value)}
                >
                  <option value="">— Choisir —</option>
                  {operatorsFor(localities.tree, countryCode).map((o) => (
                    <option key={o.id} value={o.id}>
                      {o.label}
                    </option>
                  ))}
                </select>
              )}
            </label>
          </>
        ) : null}
        {/* The shared PhoneField (+225 on screen — parity with the app). It
            mounts with the switch — or with a refusal while deposits are off —
            after the policy has loaded, so its initialValue is the current
            number. */}
        {form.required || showNumberWhileOff ? (
          <PhoneField
            label="Numéro Mobile Money"
            initialValue={form.number}
            onChange={(v) => {
              set('number', v);
              fields.revalidate('number', v);
            }}
            error={fields.errors.number}
          />
        ) : null}

        <label className="block text-bodyMedium text-textTertiary">
          Fenêtre d’annulation (heures)
          <input
            className={input}
            inputMode="numeric"
            value={form.windowHours}
            onChange={(e) => set('windowHours', e.target.value)}
          />
        </label>

        {error ? <p role="alert" className="text-bodyMedium text-error">{error}</p> : null}
        <p
          role="status"
          className={saved ? 'text-bodyMedium text-textSecondary' : 'sr-only'}
        >
          {saved ? 'Acompte enregistré.' : ''}
        </p>
        <Button disabled={busy} onClick={save}>
          Enregistrer
        </Button>
      </Card>
    </div>
  );
}
