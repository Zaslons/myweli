'use client';

import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { useEffect, useState } from 'react';
import {
  getDepositPolicy,
  getMyProvider,
  saveDepositPolicy,
} from '../../lib/api/pro';
import { operatorsFor } from '../../lib/api/localities';
import {
  type DepositForm,
  buildDepositPayload,
  depositToForm,
  validateDeposit,
} from '../../lib/pro/deposit';
import { useLocalities } from '../../lib/use-localities';
import { Button } from '../Button';

const input =
  'block w-full min-h-12 rounded-lg border border-borderStrong bg-surface p-m text-bodyMedium text-textPrimary focus:border-borderFocus focus:ring-1 focus:ring-borderFocus disabled:border-border disabled:text-textDisabled';

export function AcompteClient() {
  const router = useRouter();
  // Multi-pays MP3: the operator list is the salon COUNTRY's catalog
  // (GET /localities) — the backend validates against the same source.
  const localities = useLocalities();
  const [countryCode, setCountryCode] = useState<string | null>(null);
  const [providerId, setProviderId] = useState('');
  const [form, setForm] = useState<DepositForm | null>(null);
  const [loading, setLoading] = useState(true);
  const [loadError, setLoadError] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [saved, setSaved] = useState(false);
  const [verified, setVerified] = useState(false);

  useEffect(() => {
    let active = true;
    (async () => {
      const me = await getMyProvider();
      if (me.status === 401) {
        router.replace('/pro/connexion');
        return;
      }
      if (me.status !== 200 || !me.profile) {
        if (active) {
          setLoadError(true);
          setLoading(false);
        }
        return;
      }
      const pid = me.profile.provider.id;
      const dp = await getDepositPolicy(pid);
      if (!active) return;
      setProviderId(pid);
      setCountryCode(me.profile.provider.countryCode ?? null);
      setVerified(me.profile.account.verificationStatus === 'verified');
      setForm(depositToForm(dp.status === 200 ? dp.policy : undefined));
      setLoading(false);
    })();
    return () => {
      active = false;
    };
  }, [router]);

  if (loading) return <p className="text-textSecondary">Chargement…</p>;
  if (loadError || !form) {
    return <p className="text-error">Une erreur est survenue. Réessayez.</p>;
  }

  function set<K extends keyof DepositForm>(k: K, v: DepositForm[K]) {
    setForm((f) => (f ? { ...f, [k]: v } : f));
    setSaved(false);
  }

  async function save() {
    const v = validateDeposit(form as DepositForm);
    if (v) {
      setError(v);
      return;
    }
    setBusy(true);
    setError(null);
    const r = await saveDepositPolicy(
      providerId,
      buildDepositPayload(form as DepositForm),
    );
    setBusy(false);
    if (!r.ok) {
      setError(
        r.error === 'verification_required'
          ? 'Vérifiez votre compte pour activer les acomptes.'
          : 'L’enregistrement a échoué. Réessayez.',
      );
      return;
    }
    setSaved(true);
  }

  return (
    <div className="max-w-2xl">
      <h1 className="text-headlineSmall font-semibold text-textPrimary">Acompte</h1>

      {/* T52: deposits are verified-only — the server enforces it; this
          mirrors the rule with guidance. */}
      {!verified ? (
        <div className="mt-l rounded-xl border border-border bg-surface p-m text-bodyMedium text-textSecondary">
          Les acomptes sont disponibles après la vérification de votre
          compte.{' '}
          <Link href="/pro/verification" className="underline">
            Vérifier mon compte
          </Link>
        </div>
      ) : null}

      <section className="mt-l space-y-m rounded-xl border border-border bg-secondary p-l">
        <label
          className={`flex items-center gap-s text-textPrimary ${
            verified ? '' : 'opacity-50'
          }`}
        >
          <input
            type="checkbox"
            disabled={!verified}
            checked={form.required}
            onChange={(e) => set('required', e.target.checked)}
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
                  <span className="flex-1 text-bodyMedium text-error">
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
            <label className="block text-bodyMedium text-textTertiary">
              Numéro Mobile Money
              <input
                className={input}
                value={form.number}
                onChange={(e) => set('number', e.target.value)}
              />
            </label>
          </>
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

        {error ? <p className="text-bodyMedium text-error">{error}</p> : null}
        {saved ? (
          <p className="text-bodyMedium text-textSecondary">Acompte enregistré.</p>
        ) : null}
        <Button disabled={busy} onClick={save}>
          Enregistrer
        </Button>
      </section>
    </div>
  );
}
