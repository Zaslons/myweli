/// « MyWeli Pro pour les salons » — the public page's copy, in one module so
/// the honesty pin (tests/promise-honesty-pin.test.ts) reads every word of it.
/// Approved word for word by the owner, 2026-10-19
/// (docs/design/web-pro-access.md §4). Every benefit is something the product
/// does TODAY; there is no price (the owner's decision).

export type Faq = { question: string; answer: string };

export const PRO_LANDING = {
  title: 'Le logiciel de réservation des salons de beauté en Côte d’Ivoire',
  subtitle:
    'Recevez des réservations en ligne 24 h/24, et gérez agenda, équipe, clientèle et acomptes au même endroit.',
  signUp: 'Inscrire mon salon',
  signIn: 'J’ai déjà un compte',
  trial: '3 mois offerts — sans carte bancaire.',
  benefitsTitle: 'Tout ce qu’il faut pour votre salon',
  benefits: [
    {
      title: 'Votre agenda, tenu tout seul',
      body: 'Les clients réservent sur vos créneaux réels ; vous ajoutez les rendez-vous pris au téléphone ou au comptoir. Vue journée, semaine, et par membre d’équipe.',
    },
    {
      title: 'Votre vitrine sur myweli.com',
      body: 'Photos, avant/après, logo, prestations et tarifs, horaires : votre page publique se remplit en quelques minutes.',
    },
    {
      title: 'Votre clientèle, enregistrée d’elle-même',
      body: 'Chaque réservation crée ou retrouve la fiche client : historique, notes, étiquettes.',
    },
    {
      title: 'Vos acomptes, sans intermédiaire',
      body: 'Le client paie l’acompte sur votre Mobile Money et joint sa preuve ; vous confirmez. MyWeli ne touche jamais vos fonds.',
    },
    {
      title: 'Moins de rendez-vous manqués',
      body: 'Rappels automatiques à vos clients dans l’app MyWeli (24 h et 2 h avant), et règles d’acompte.',
    },
    {
      title: 'Votre équipe',
      body: 'Invitez manager, réception et collaborateurs, chacun avec les accès de son rôle.',
    },
  ],
  stepsTitle: 'Comment ça marche',
  steps: [
    'Créez votre compte',
    'Ajoutez vos prestations, vos horaires et vos photos',
    'Mettez votre salon en ligne — vos 3 mois offerts commencent',
  ],
  faqTitle: 'Questions fréquentes',
  faq: [
    {
      question: 'Combien coûte MyWeli Pro ?',
      answer:
        'Vos 3 premiers mois sont offerts, sans carte bancaire. Vous choisissez ensuite, depuis votre Espace Pro, l’offre adaptée à votre salon : la taille de votre équipe, le nombre de salons.',
    },
    {
      question: 'Mes clients paient-ils en ligne ?',
      answer:
        'Non. L’acompte éventuel est envoyé par Mobile Money directement sur votre numéro ; MyWeli ne prélève rien.',
    },
    {
      question: 'Faut-il installer une application ?',
      answer: 'Non : tout se gère depuis myweli.com, sur ordinateur comme sur téléphone.',
    },
    {
      question: 'Puis-je gérer plusieurs salons ?',
      answer: 'Oui, avec l’offre Réseau : chaque salon a sa propre offre et son propre essai.',
    },
  ] satisfies Faq[],
  closing: 'Prêt à recevoir vos premières réservations ?',
} as const;
