'use client';

import { useRouter } from 'next/navigation';
import { useEffect, useState } from 'react';
import { chooseOffer, getMyProvider, getSalonSubscription } from '../../lib/api/pro';
import { formatFcfa } from '../../lib/format';
import {
  type OfferCard,
  type OfferTier,
  type SalonOffer,
  OFFER_CARDS,
  SETUP_HEADLINE,
  SETUP_SUBLINE,
  TRIAL_KEPT_LINE,
  TRIAL_MONTHS,
  contactWhatsAppUrl,
  offerBanner,
} from '../../lib/pro/subscription-plans';
import { seatsLabel } from '../../lib/pro/team';
import { Button } from '../Button';

/// /pro/abonnement (team access R5a — docs/design/web-team-access-r5.md §2.3):
/// the offer picker on GET/PUT /providers/{id}/subscription. Setup (404) shows
/// the 3-month-free headline + the three offer cards; an active offer shows the
/// billing-state banner + a seats bar and lets the owner switch (the trial
/// clock is kept). Grace/expired route to WhatsApp.
export function AbonnementClient() {
  const router = useRouter();
  const [providerId, setProviderId] = useState<string | null>(null);
  const [offer, setOffer] = useState<SalonOffer | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(false);
  const [choosing, setChoosing] = useState<OfferTier | null>(null);
  const [notice, setNotice] = useState<string | null>(null);

  useEffect(() => {
    let active = true;
    (async () => {
      const me = await getMyProvider();
      if (me.status === 401) {
        router.replace('/pro/connexion');
        return;
      }
      if (!active) return;
      if (me.status !== 200 || !me.profile) {
        setError(true);
        setLoading(false);
        return;
      }
      const pid = me.profile.provider.id;
      setProviderId(pid);
      const sub = await getSalonSubscription(pid);
      if (!active) return;
      if (sub.status === 200 && sub.offer) {
        setOffer(sub.offer);
      } else if (sub.status !== 404) {
        setError(true);
      }
      setLoading(false);
    })();
    return () => {
      active = false;
    };
  }, [router]);

  async function pick(tier: OfferTier) {
    if (!providerId) return;
    setChoosing(tier);
    setNotice(null);
    const r = await chooseOffer(providerId, tier);
    setChoosing(null);
    if (!r.ok || !r.offer) {
      setNotice(
        r.error === 'trial_used'
          ? 'Votre essai gratuit a déjà été utilisé. Contactez-nous pour activer votre offre.'
          : 'Le changement d’offre a échoué. Réessayez.',
      );
      return;
    }
    setOffer(r.offer);
    setNotice(null);
  }

  if (loading) return <p className="text-textSecondary">Chargement…</p>;
  if (error) {
    return <p className="text-error">Une erreur est survenue. Réessayez.</p>;
  }

  const setup = offer === null;
  const banner = offer ? offerBanner(offer) : null;

  return (
    <div className="max-w-3xl">
      <h1 className="text-2xl font-semibold text-textPrimary">Mon abonnement</h1>

      {setup ? (
        <section className="mt-l rounded-xl border border-primary bg-surface p-l">
          <p className="text-lg font-semibold text-textPrimary">
            {SETUP_HEADLINE}
          </p>
          <p className="mt-xs text-sm text-textSecondary">{SETUP_SUBLINE}</p>
        </section>
      ) : banner ? (
        <section
          className={`mt-l rounded-xl border p-l ${
            banner.kind === 'grace'
              ? 'border-warning/50 bg-warning/10'
              : banner.kind === 'expired'
                ? 'border-error/50 bg-error/10'
                : 'border-primary bg-surface'
          }`}
        >
          <p
            className={`font-semibold ${
              banner.kind === 'grace'
                ? 'text-warning'
                : banner.kind === 'expired'
                  ? 'text-error'
                  : 'text-textPrimary'
            }`}
          >
            {banner.title}
          </p>
          <p className="mt-xs text-sm text-textSecondary">{banner.subtitle}</p>
          {banner.urgent ? (
            <a
              href={contactWhatsAppUrl()}
              target="_blank"
              rel="noopener noreferrer"
              className="mt-m inline-flex items-center justify-center rounded-lg bg-primary px-l py-s text-sm font-medium text-secondary hover:bg-primaryLight"
            >
              Nous contacter sur WhatsApp
            </a>
          ) : null}
        </section>
      ) : null}

      {offer ? (
        <section className="mt-l max-w-sm">
          <p className="text-sm text-textSecondary">{seatsLabel(offer.seats)}</p>
          <div className="mt-xs h-2 overflow-hidden rounded-full bg-surfaceVariant">
            <div
              className="h-full rounded-full bg-primary"
              style={{
                width: `${Math.min(
                  100,
                  offer.seats.cap === 0
                    ? 0
                    : (offer.seats.used / offer.seats.cap) * 100,
                )}%`,
              }}
            />
          </div>
        </section>
      ) : null}

      <div className="mt-l grid gap-m md:grid-cols-3">
        {OFFER_CARDS.map((card) => (
          <OfferCardView
            key={card.tier}
            card={card}
            current={offer?.tier === card.tier}
            busy={choosing === card.tier}
            disabled={choosing !== null}
            ctaLabel={
              setup
                ? 'Choisir cette offre'
                : offer?.tier === card.tier
                  ? 'Offre actuelle'
                  : 'Passer à cette offre'
            }
            onChoose={() => pick(card.tier)}
          />
        ))}
      </div>

      {notice ? (
        <p className="mt-m rounded-lg border border-warning/40 bg-warning/10 p-m text-sm text-warning">
          {notice}
        </p>
      ) : null}

      <p className="mt-m text-sm text-textTertiary">{TRIAL_KEPT_LINE}</p>
    </div>
  );
}

function OfferCardView({
  card,
  current,
  busy,
  disabled,
  ctaLabel,
  onChoose,
}: {
  card: OfferCard;
  current: boolean;
  busy: boolean;
  disabled: boolean;
  ctaLabel: string;
  onChoose: () => void;
}) {
  return (
    <section
      className={`flex flex-col rounded-xl border p-l ${
        current ? 'border-primary bg-surface' : 'border-border bg-secondary'
      }`}
    >
      <h2 className="text-lg font-semibold text-textPrimary">{card.name}</h2>
      <p className="mt-s">
        <span className="text-xl font-semibold text-textPrimary">
          Gratuit {TRIAL_MONTHS} mois
        </span>
        {card.anchorFcfa != null ? (
          <span className="ml-s text-sm text-textTertiary line-through">
            {formatFcfa(card.anchorFcfa)}/mois
          </span>
        ) : (
          <span className="ml-s text-sm text-textTertiary">puis sur devis</span>
        )}
      </p>
      <p className="mt-xs text-sm text-textSecondary">{card.seatsLabel}</p>
      <ul className="mt-m flex-1 space-y-xs text-sm text-textSecondary">
        {card.entitlements.map((e) => (
          <li key={e}>· {e}</li>
        ))}
      </ul>
      {card.roiLine ? (
        <p className="mt-m text-sm italic text-textTertiary">{card.roiLine}</p>
      ) : null}
      {card.notes?.length ? (
        <ul className="mt-s space-y-xs text-xs text-textTertiary">
          {card.notes.map((n) => (
            <li key={n}>{n}</li>
          ))}
        </ul>
      ) : null}
      <Button
        onClick={onChoose}
        disabled={disabled || current}
        className="mt-l"
      >
        {busy ? 'Un instant…' : ctaLabel}
      </Button>
    </section>
  );
}
