'use client';

import { useRouter } from 'next/navigation';
import { useEffect, useState } from 'react';
import {
  getDepositPolicy,
  getMyProvider,
  saveDepositPolicy,
} from '../../lib/api/pro';
import {
  type DepositForm,
  OPERATORS,
  buildDepositPayload,
  depositToForm,
  validateDeposit,
} from '../../lib/pro/deposit';
import { Button } from '../Button';

const input =
  'w-full rounded-lg border border-border bg-surface px-m py-s text-textPrimary';

export function AcompteClient() {
  const router = useRouter();
  const [providerId, setProviderId] = useState('');
  const [form, setForm] = useState<DepositForm | null>(null);
  const [loading, setLoading] = useState(true);
  const [loadError, setLoadError] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [saved, setSaved] = useState(false);

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
      setError('L’enregistrement a échoué. Réessayez.');
      return;
    }
    setSaved(true);
  }

  return (
    <div className="max-w-2xl">
      <h1 className="text-2xl font-semibold text-textPrimary">Acompte</h1>

      <section className="mt-l space-y-m rounded-xl border border-border bg-secondary p-l">
        <label className="flex items-center gap-s text-textPrimary">
          <input
            type="checkbox"
            checked={form.required}
            onChange={(e) => set('required', e.target.checked)}
          />
          Exiger un acompte
        </label>

        {form.required ? (
          <>
            <label className="block text-sm text-textTertiary">
              Pourcentage de l’acompte (%)
              <input
                className={input}
                inputMode="numeric"
                value={form.percent}
                onChange={(e) => set('percent', e.target.value)}
              />
            </label>
            <label className="block text-sm text-textTertiary">
              Opérateur Mobile Money
              <select
                className={input}
                value={form.operator}
                onChange={(e) => set('operator', e.target.value)}
              >
                <option value="">— Choisir —</option>
                {OPERATORS.map((o) => (
                  <option key={o.value} value={o.value}>
                    {o.label}
                  </option>
                ))}
              </select>
            </label>
            <label className="block text-sm text-textTertiary">
              Numéro Mobile Money
              <input
                className={input}
                value={form.number}
                onChange={(e) => set('number', e.target.value)}
              />
            </label>
          </>
        ) : null}

        <label className="block text-sm text-textTertiary">
          Fenêtre d’annulation (heures)
          <input
            className={input}
            inputMode="numeric"
            value={form.windowHours}
            onChange={(e) => set('windowHours', e.target.value)}
          />
        </label>

        {error ? <p className="text-sm text-error">{error}</p> : null}
        {saved ? (
          <p className="text-sm text-textSecondary">Acompte enregistré.</p>
        ) : null}
        <Button disabled={busy} onClick={save}>
          Enregistrer
        </Button>
      </section>
    </div>
  );
}
