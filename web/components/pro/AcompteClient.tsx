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
import { loadFailure, loadFailureMessage, type LoadFailure } from '../../lib/api/load-failure';
import { writeFailureMessage } from '../../lib/api/network';
import { useFieldErrors } from '../../lib/forms/useFieldErrors';
import { operatorsFor } from '../../lib/localities';
import { PHONE_INVALID } from '../../lib/phone';
import { formatFcfa } from '../../lib/format';
import {
  DEPOSIT_PERCENT_RANGE,
  DEPOSIT_SAMPLE_TOTAL,
  type DepositForm,
  buildDepositPayload,
  depositExample,
  depositToForm,
  sliderPosition,
  validateDeposit,
  validateDepositNumber,
  windowChoices,
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
  // The example's currency: the salon's (multi-pays MP3).
  const [currency, setCurrency] = useState<string | undefined>(undefined);
  const [providerId, setProviderId] = useState('');
  const [form, setForm] = useState<DepositForm | null>(null);
  // The percentage (a fraction) last loaded or saved — sent when the field,
  // hidden while deposits are off, fails its rule
  // (docs/design/acompte-off-parity.md decision 1).
  const [lastPercentage, setLastPercentage] = useState(0);
  const [loading, setLoading] = useState(true);
  const [reloadKey, setReloadKey] = useState(0);
  const [loadError, setLoadError] = useState<LoadFailure | false>(false);
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
    // real policy (docs/design/acompte-off-parity.md D3). It keeps WHY, so
    // the state can name the network (web-pro-no-connection-copy.md §2).
    function fail(failure: LoadFailure) {
      if (!active) return;
      setLoadError(failure);
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
          fail(loadFailure(me.status));
          return;
        }
        const pid = me.profile.provider.id;
        const dp = await getDepositPolicy(pid);
        if (dp.status !== 200 || !dp.policy) {
          fail(loadFailure(dp.status));
          return;
        }
        if (!active) return;
        setProviderId(pid);
        setCountryCode(me.profile.provider.countryCode ?? null);
        setCurrency(me.profile.provider.currency ?? undefined);
        setVerified(me.profile.account.verificationStatus === 'verified');
        setForm(depositToForm(dp.policy));
        setLastPercentage(dp.policy.depositPercentage ?? 0);
        setLoading(false);
      } catch {
        // The wrappers never throw (WEB.md §3): this is the page's own
        // code, not the network.
        fail('failed');
      }
    })();
    return () => {
      active = false;
    };
  }, [router, reloadKey]);

  if (loading) return <Loading className="mt-l" />;
  if (loadError || !form) {
    return <ErrorState title="Acompte" message={loadFailureMessage(loadError)} onRetry={() => { setLoadError(false); setLoading(true); setReloadKey((k) => k + 1); }} />;
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
    // A new answer replaces the last one: « Acompte enregistré. » must not
    // stay on screen beside the failure of the next save.
    setSaved(false);
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
          : writeFailureMessage(r.status, 'L’enregistrement a échoué. Réessayez.'),
      );
      return;
    }
    setLastPercentage(payload.depositPercentage);
    setShowNumberWhileOff(false);
    setSaved(true);
  }

  // What the slider stands for: the value itself — one saved before (100 %,
  // 37,5 %) included, until the salon moves the thumb.
  const percentNumber = Number(form.percent);
  const percentLabel = `${
    Number.isFinite(percentNumber) && form.percent.trim() !== ''
      ? percentNumber.toLocaleString('fr-FR')
      : sliderPosition(form.percent)
  } %`;
  const percentShown =
    Number.isFinite(percentNumber) && form.percent.trim() !== ''
      ? percentNumber
      : sliderPosition(form.percent);
  const example = depositExample(percentShown);

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

      {/* docs/design/web-pro-deposit-app-rules.md — the app's screen, in its
          order: the switch, the percentage, the example, where the deposit
          is received, the cancellation policy. */}
      <Card as="section" className="mt-l space-y-m">
        <div className={verified ? '' : 'opacity-50'}>
          <label className="flex items-center gap-s text-textPrimary">
            <input
              type="checkbox"
              disabled={!verified}
              checked={form.required}
              aria-describedby="deposit-required-hint"
              onChange={(e) => {
                set('required', e.target.checked);
                setShowNumberWhileOff(false);
              }}
            />
            Exiger un acompte
          </label>
          <p id="deposit-required-hint" className="mt-xs text-bodySmall text-textTertiary">
            Limite les rendez-vous manqués
          </p>
        </div>

        {form.required ? (
          <>
            <div className="rounded-xl border border-border bg-secondary p-m">
              <div className="flex items-center justify-between gap-s">
                <label htmlFor="deposit-percent" className="text-bodyMedium text-textPrimary">
                  Pourcentage de l’acompte
                </label>
                <span className="shrink-0 whitespace-nowrap text-titleMedium text-textPrimary">{percentLabel}</span>
              </div>
              <input
                id="deposit-percent"
                type="range"
                className="mt-s block min-h-12 w-full accent-primary"
                min={DEPOSIT_PERCENT_RANGE.min}
                max={DEPOSIT_PERCENT_RANGE.max}
                step={DEPOSIT_PERCENT_RANGE.step}
                value={sliderPosition(form.percent)}
                aria-valuetext={percentLabel}
                onChange={(e) => set('percent', e.target.value)}
              />
            </div>
            <div
              data-testid="deposit-example"
              className="space-y-xs rounded-xl bg-surface p-m"
            >
              <p className="text-bodySmall text-textSecondary">
                {`Exemple sur une prestation de ${formatFcfa(DEPOSIT_SAMPLE_TOTAL, currency)}`}
              </p>
              <p className="flex justify-between gap-s text-bodyMedium text-textPrimary">
                {/* The client pays by Mobile Money straight to the salon —
                    never in the app (no-custody; promise-honesty-sweep T2). */}
                <span>Acompte sur votre Mobile Money</span>
                <span className="shrink-0 whitespace-nowrap font-semibold">{formatFcfa(example.deposit, currency)}</span>
              </p>
              <p className="flex justify-between gap-s text-bodySmall text-textSecondary">
                <span>Solde au salon</span>
                <span className="shrink-0 whitespace-nowrap">{formatFcfa(example.balance, currency)}</span>
              </p>
            </div>
          </>
        ) : null}

        {form.required || showNumberWhileOff ? (
          <div className="space-y-m rounded-xl border border-border bg-secondary p-m">
            <div>
              <p className="text-bodyMedium text-textPrimary">Recevoir l’acompte</p>
              <p className="mt-xs text-bodySmall text-textTertiary">
                Le client envoie l’acompte directement sur ce compte Mobile Money. MyWeli ne le traite pas.
              </p>
            </div>
            {form.required ? (
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
            ) : null}
            {/* The shared PhoneField (+225 on screen — parity with the app).
                It mounts with the switch — or with a refusal while deposits
                are off — after the policy has loaded, so its initialValue is
                the current number. */}
            <PhoneField
              label="Numéro Mobile Money"
              initialValue={form.number}
              onChange={(v) => {
                set('number', v);
                fields.revalidate('number', v);
              }}
              error={fields.errors.number}
            />
          </div>
        ) : null}

        <div className="rounded-xl border border-border bg-secondary p-m">
          <p id="cancellation-title" className="text-bodyMedium text-textPrimary">
            Politique d’annulation
          </p>
          <p className="mt-xs text-bodySmall text-textTertiary">
            Au-delà de ce délai avant le rendez-vous, le client peut annuler et garder son acompte ; en deçà, l’acompte n’est pas remboursé.
          </p>
          <div
            role="radiogroup"
            aria-labelledby="cancellation-title"
            className="mt-m flex flex-wrap gap-s"
          >
            {windowChoices(Number(form.windowHours)).map((h) => {
              const checked = Number(form.windowHours) === h;
              return (
                <label
                  key={h}
                  className={`flex min-h-12 min-w-12 cursor-pointer items-center justify-center gap-xs rounded-pill border px-m text-bodyMedium ${
                    checked
                      ? 'border-primary bg-primary text-secondary'
                      : 'border-border bg-surface text-textPrimary'
                  }`}
                >
                  <input
                    type="radio"
                    name="cancellation-window"
                    className="accent-secondary"
                    value={h}
                    checked={checked}
                    onChange={() => set('windowHours', String(h))}
                  />
                  {`${h} h`}
                </label>
              );
            })}
          </div>
        </div>

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
