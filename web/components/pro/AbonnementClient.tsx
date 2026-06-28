'use client';

import { useRouter } from 'next/navigation';
import { useEffect, useState } from 'react';
import { getSubscription } from '../../lib/api/pro';
import { formatFcfa } from '../../lib/format';
import {
  type Subscription,
  FREE_ENTITLEMENTS,
  PRO_ANCHOR_MONTHLY_FCFA,
  PRO_ENTITLEMENTS,
  ROI_LINE,
  TRIAL_MONTHS,
  contactWhatsAppUrl,
  isTrialing,
  subscriptionSubtitle,
  subscriptionTitle,
} from '../../lib/pro/subscription-plans';

export function AbonnementClient() {
  const router = useRouter();
  const [sub, setSub] = useState<Subscription | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(false);

  useEffect(() => {
    let active = true;
    (async () => {
      const r = await getSubscription();
      if (r.status === 401) {
        router.replace('/pro/connexion');
        return;
      }
      if (!active) return;
      if (r.status !== 200 || !r.subscription) {
        setError(true);
        setLoading(false);
        return;
      }
      setSub(r.subscription);
      setLoading(false);
    })();
    return () => {
      active = false;
    };
  }, [router]);

  if (loading) return <p className="text-textSecondary">Chargement…</p>;
  if (error || !sub) {
    return <p className="text-error">Une erreur est survenue. Réessayez.</p>;
  }

  return (
    <div className="max-w-2xl">
      <h1 className="text-2xl font-semibold text-textPrimary">Mon abonnement</h1>

      <section
        className={`mt-l rounded-xl border p-l ${
          isTrialing(sub)
            ? 'border-primary bg-surface'
            : 'border-border bg-secondary'
        }`}
      >
        <p className="font-medium text-textPrimary">{subscriptionTitle(sub)}</p>
        <p className="mt-xs text-sm text-textSecondary">
          {subscriptionSubtitle(sub)}
        </p>
      </section>

      <section className="mt-l rounded-xl border border-border bg-secondary p-l">
        <h2 className="text-lg font-semibold text-textPrimary">Offre Pro</h2>
        <p className="mt-s">
          <span className="text-2xl font-semibold text-textPrimary">
            Gratuit pendant {TRIAL_MONTHS} mois
          </span>
          <span className="ml-s text-sm text-textTertiary line-through">
            {formatFcfa(PRO_ANCHOR_MONTHLY_FCFA)}/mois
          </span>
        </p>
        <ul className="mt-m space-y-xs text-sm text-textSecondary">
          {PRO_ENTITLEMENTS.map((e) => (
            <li key={e}>· {e}</li>
          ))}
        </ul>
        <p className="mt-m text-sm italic text-textTertiary">{ROI_LINE}</p>
        <a
          href={contactWhatsAppUrl()}
          target="_blank"
          rel="noopener noreferrer"
          className="mt-l inline-flex items-center justify-center rounded-lg bg-primary px-l py-s text-sm font-medium text-secondary hover:bg-primaryLight"
        >
          Nous contacter
        </a>
      </section>

      <section className="mt-l rounded-xl border border-border bg-secondary p-l">
        <h2 className="text-lg font-semibold text-textPrimary">
          Offre Découverte (gratuite)
        </h2>
        <ul className="mt-m space-y-xs text-sm text-textSecondary">
          {FREE_ENTITLEMENTS.map((e) => (
            <li key={e}>· {e}</li>
          ))}
        </ul>
      </section>
    </div>
  );
}
