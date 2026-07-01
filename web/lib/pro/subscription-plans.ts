import { formatDateFr } from '../format';

/// Mirror of the app's `subscription_plans.dart` + the PRO-SUB status copy.
/// Pricing is client-side config (the API returns only tier/status/trial).

export const TRIAL_MONTHS = 3;

/// Anchor ("regular") monthly Pro price (FCFA) — intentionally above the planned
/// launch price so the eventual paid price reads as a discount. Display only.
export const PRO_ANCHOR_MONTHLY_FCFA = 70000;

export const FREE_ENTITLEMENTS = [
  'Profil public + page de réservation',
  'Accepter les réservations · calendrier',
  '1 membre du personnel',
  'Acomptes activés',
  'Confirmations WhatsApp/SMS de base',
];

export const PRO_ENTITLEMENTS = [
  'Réservations illimitées · jusqu’à 5 membres',
  'Rappels automatiques WhatsApp/SMS (24 h / 2 h)',
  'Règles d’acompte & protection no-show',
  'Photos & galerie avant/après',
  'Statistiques & gestion des avis',
  'Sans la marque MyWeli · support prioritaire',
];

export const ROI_LINE = 'Un seul rendez-vous manqué évité paie le mois.';

export const CONTACT_MESSAGE =
  'Bonjour MyWeli, je souhaite passer à l’offre Pro.';

export type Subscription = {
  tier: string;
  status: string;
  trialEndsAt?: string | null;
  trialDaysLeft?: number;
};

export function isTrialing(sub: Subscription): boolean {
  return sub.status === 'trial';
}

export function subscriptionTitle(sub: Subscription): string {
  if (isTrialing(sub)) {
    const n = sub.trialDaysLeft ?? 0;
    const s = n > 1 ? 's' : '';
    return `Essai gratuit — ${n} jour${s} restant${s}`;
  }
  return 'Essai terminé — offre Gratuite';
}

export function subscriptionSubtitle(sub: Subscription): string {
  if (isTrialing(sub) && sub.trialEndsAt) {
    return `Se termine le ${formatDateFr(sub.trialEndsAt)}`;
  }
  return 'Vous profitez de l’offre Découverte (gratuite).';
}

/// wa.me contact link (number filled at the accounts phase via env).
export function contactWhatsAppUrl(): string {
  const number = process.env.NEXT_PUBLIC_MYWELI_WHATSAPP ?? '';
  return `https://wa.me/${number}?text=${encodeURIComponent(CONTACT_MESSAGE)}`;
}
