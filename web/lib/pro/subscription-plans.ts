import type { components } from '../api/schema';
import { formatDateFr } from '../format';

/// Mirror of the app's `subscription_plans.dart` — the offer ladder
/// (pricing pivot, team access R5a). Pricing is client-side display config;
/// the API returns tier/status/dates/seats and stays the authority.
/// Design: docs/design/web-team-access-r5.md §2.3.

export type SalonOffer = components['schemas']['SalonSubscription'];
export type OfferTier = 'pro' | 'business' | 'reseau';

export const TRIAL_MONTHS = 3;

/// Anchor ("regular") monthly prices (FCFA) — intentionally above the
/// planned launch prices so the eventual paid price reads as a discount.
/// Réseau has no figure (« Sur devis »). Display only.
export const PRO_ANCHOR_MONTHLY_FCFA = 70000;
export const BUSINESS_ANCHOR_MONTHLY_FCFA = 120000;

export type OfferCard = {
  tier: OfferTier;
  name: string;
  anchorFcfa: number | null;
  seatsLabel: string;
  entitlements: string[];
  notes?: string[];
  roiLine?: string;
};

export const ROI_LINE = 'Un seul rendez-vous manqué évité paie le mois.';

export const OFFER_CARDS: OfferCard[] = [
  {
    tier: 'pro',
    name: 'Pro',
    anchorFcfa: PRO_ANCHOR_MONTHLY_FCFA,
    seatsLabel: '5 places',
    entitlements: [
      'Réservations illimitées',
      'Jusqu’à 5 membres d’équipe',
      'Rappels automatiques WhatsApp/SMS (24 h / 2 h)',
      'Règles d’acompte & protection no-show',
      'Photos & galerie avant/après',
      'Statistiques & gestion des avis',
    ],
    roiLine: ROI_LINE,
  },
  {
    tier: 'business',
    name: 'Business',
    anchorFcfa: BUSINESS_ANCHOR_MONTHLY_FCFA,
    seatsLabel: '15 places',
    entitlements: [
      'Tout de l’offre Pro',
      'Jusqu’à 15 membres d’équipe',
      'Support prioritaire dédié',
    ],
  },
  {
    tier: 'reseau',
    name: 'Réseau',
    anchorFcfa: null, // « Sur devis »
    seatsLabel: '15 places par salon',
    entitlements: [
      'Tout de l’offre Business',
      'Multi-salons (bientôt disponible)',
      'Tarif personnalisé',
    ],
    notes: ['Multi-salons — bientôt disponible', 'Tarif personnalisé'],
  },
];

export const TRIAL_KEPT_LINE =
  'Le changement d’offre conserve votre période d’essai.';

export const SETUP_HEADLINE = `Choisissez votre offre — ${TRIAL_MONTHS} mois offerts`;
export const SETUP_SUBLINE =
  'Votre salon reste gratuit pendant la configuration, mais une offre est nécessaire pour le publier.';

/// The billing-state banner (tokens only: grace = warning, expired = error).
export function offerBanner(offer: SalonOffer): {
  kind: 'trial' | 'paid' | 'grace' | 'expired';
  title: string;
  subtitle: string;
  urgent: boolean;
} {
  switch (offer.status) {
    case 'trial': {
      const left = Math.max(
        0,
        Math.ceil(
          (new Date(offer.trialEndsAt).getTime() - Date.now()) / 86_400_000,
        ),
      );
      const s = left > 1 ? 's' : '';
      return {
        kind: 'trial',
        title: `Essai gratuit — ${left} jour${s} restant${s}`,
        subtitle: `Offre ${tierName(offer.tier)} · se termine le ${formatDateFr(offer.trialEndsAt)}`,
        urgent: false,
      };
    }
    case 'paid':
      return {
        kind: 'paid',
        title: `Offre ${tierName(offer.tier)} active`,
        subtitle: offer.paidUntil
          ? `Jusqu’au ${formatDateFr(offer.paidUntil)}`
          : 'Paiement à jour',
        urgent: false,
      };
    case 'grace':
      return {
        kind: 'grace',
        title: 'Votre offre a expiré',
        subtitle: `Jusqu’au ${formatDateFr(offer.graceEndsAt)} avant la dépublication de votre salon. Contactez-nous pour régler.`,
        urgent: true,
      };
    default:
      return {
        kind: 'expired',
        title: offer.unpublishedForBilling ? 'Salon dépublié' : 'Offre expirée',
        subtitle: offer.unpublishedForBilling
          ? 'Votre salon n’est plus visible des clients. Contactez-nous pour réactiver — vos données sont intactes.'
          : 'Contactez-nous pour réactiver votre offre.',
        urgent: true,
      };
  }
}

export function tierName(tier: string): string {
  switch (tier) {
    case 'business':
      return 'Business';
    case 'reseau':
      return 'Réseau';
    default:
      return 'Pro';
  }
}

export const CONTACT_MESSAGE =
  'Bonjour MyWeli, je souhaite activer mon offre pour mon salon.';

/// wa.me contact link (number filled at the accounts phase via env).
export function contactWhatsAppUrl(message?: string): string {
  const number = process.env.NEXT_PUBLIC_MYWELI_WHATSAPP ?? '';
  return `https://wa.me/${number}?text=${encodeURIComponent(message ?? CONTACT_MESSAGE)}`;
}
