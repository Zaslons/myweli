import type { Metadata } from 'next';
import Link from 'next/link';

import { JsonLd } from '../../components/JsonLd';
import { breadcrumbJsonLd, siteUrl } from '../../lib/seo/jsonld';
import { SUPPORT, supportMailto, supportWhatsAppUrl } from '../../lib/support';

/// The page every support affordance points at.
///
/// ## Why it exists
///
/// There was no support channel at all. `SUPPORT_WHATSAPP` had no default and
/// was passed by no build, so the app's « Aide & Support » showed « Contact
/// bientôt disponible. » in every artifact ever shipped; on web the row simply
/// did not render; and the Pro app had no contact affordance anywhere. Meanwhile
/// the mentions légales told the public that in-app tile *was* the contact
/// channel of record.
///
/// App Store Connect requires a Support URL and Play requires a support email,
/// so this is also a submission blocker — but the reason to build it is that a
/// user with a problem currently has nowhere to go.
///
/// **A page rather than a `wa.me` link**, deliberately: the WhatsApp number waits
/// on company registration, and a page can gain a channel without an app
/// release. The address is a constant in `lib/support.ts`, next to `COMPANY`'s
/// reasoning — a published fact about the business belongs in a PR, not a
/// dashboard.
///
/// Not a `LegalPage`: that wrapper stamps « Dernière mise à jour » from
/// `LEGAL_UPDATED_AT` and reads `legalRoute`, and this is not one of the four
/// legal documents. `backend/lib/src/slug.dart` reserves `support` all the same,
/// or a salon taking that slug would be shadowed by this route *and* would
/// capture the address both store listings publish.
export const metadata: Metadata = {
  title: 'Aide & Support',
  description:
    'Comment joindre l’équipe MyWeli : assistance sur votre compte, vos ' +
    'rendez-vous, votre salon. Réponse en français.',
  alternates: { canonical: SUPPORT.path },
  openGraph: {
    title: 'Aide & Support',
    description: 'Comment joindre l’équipe MyWeli.',
    url: `${siteUrl}${SUPPORT.path}`,
  },
};

const TOPICS = [
  {
    q: 'Un rendez-vous',
    a: 'Annulation, report, ou un salon qui ne répond pas. Précisez la date et le nom du salon.',
    subject: 'Rendez-vous',
  },
  {
    q: 'Mon compte',
    a: 'Connexion impossible, numéro ou e-mail à changer, suppression du compte.',
    subject: 'Mon compte',
  },
  {
    q: 'Un acompte',
    a: 'Paiement non reconnu, remboursement, ou un justificatif refusé. Joignez la capture d’écran envoyée lors de la réservation.',
    subject: 'Acompte',
  },
  {
    q: 'Mon salon (professionnels)',
    a: 'Mise en ligne, équipe, offre et facturation. Indiquez le nom du salon.',
    subject: 'Mon salon',
  },
] as const;

export default function SupportPage() {
  const whatsapp = supportWhatsAppUrl();

  return (
    <main className="mx-auto max-w-content px-m py-l">
      <JsonLd
        data={breadcrumbJsonLd([
          { name: 'Accueil', url: `${siteUrl}/` },
          { name: 'Aide & Support', url: `${siteUrl}${SUPPORT.path}` },
        ])}
      />

      <nav
        aria-label="Fil d’Ariane"
        className="text-bodyMedium text-textSecondary"
      >
        <ol className="flex flex-wrap items-center gap-xs">
          <li>
            <Link href="/" className="underline hover:text-textPrimary">
              Accueil
            </Link>
          </li>
          <li className="flex items-center gap-xs">
            <span aria-hidden>›</span>
            <span aria-current="page" className="text-textPrimary">
              Aide &amp; Support
            </span>
          </li>
        </ol>
      </nav>

      <h1 className="mt-m text-headlineMedium font-semibold text-textPrimary">
        Aide &amp; Support
      </h1>
      <p className="mt-s text-bodyLarge text-textSecondary">
        Une question, un problème avec un rendez-vous ou votre salon ? Écrivez-nous
        — nous répondons en français.
      </p>

      <section aria-labelledby="nous-ecrire" className="mt-l">
        <h2
          id="nous-ecrire"
          className="text-titleLarge font-semibold text-textPrimary"
        >
          Nous écrire
        </h2>

        <ul className="mt-m flex flex-col gap-m">
          <li>
            <a
              href={supportMailto()}
              className="flex min-h-xxl items-center rounded-md border border-divider px-m py-s text-bodyLarge text-textPrimary underline hover:bg-surfaceVariant"
            >
              {SUPPORT.email}
            </a>
            <p className="mt-xs text-bodyMedium text-textSecondary">
              Le moyen le plus sûr de nous joindre. Décrivez votre situation et,
              si c’est utile, joignez une capture d’écran.
            </p>
          </li>

          {whatsapp ? (
            <li>
              <a
                href={whatsapp}
                target="_blank"
                rel="noopener noreferrer"
                className="flex min-h-xxl items-center rounded-md border border-divider px-m py-s text-bodyLarge text-textPrimary underline hover:bg-surfaceVariant"
              >
                WhatsApp
              </a>
              <p className="mt-xs text-bodyMedium text-textSecondary">
                Pour un échange rapide aux heures ouvrables.
              </p>
            </li>
          ) : null}
        </ul>
      </section>

      <section aria-labelledby="quoi-ecrire" className="mt-xl">
        <h2
          id="quoi-ecrire"
          className="text-titleLarge font-semibold text-textPrimary"
        >
          Ce qu’il nous faut pour vous aider vite
        </h2>
        <dl className="mt-m flex flex-col gap-m">
          {TOPICS.map((t) => (
            <div key={t.q}>
              <dt className="text-bodyLarge font-semibold text-textPrimary">
                {t.q}
              </dt>
              <dd className="mt-xs text-bodyMedium text-textSecondary">
                {t.a}{' '}
                <a href={supportMailto(t.subject)} className="underline">
                  Écrire à ce sujet
                </a>
              </dd>
            </div>
          ))}
        </dl>
      </section>

      <section aria-labelledby="deja-repondu" className="mt-xl">
        <h2
          id="deja-repondu"
          className="text-titleLarge font-semibold text-textPrimary"
        >
          Réponses immédiates
        </h2>
        <ul className="mt-m flex list-disc flex-col gap-s pl-l text-bodyMedium text-textSecondary">
          <li>
            <Link href="/suppression-compte" className="underline">
              Supprimer mon compte
            </Link>{' '}
            — la marche à suivre et ce qui est effacé.
          </li>
          <li>
            <Link href="/politique-confidentialite" className="underline">
              Politique de confidentialité
            </Link>{' '}
            — quelles données nous traitons et pourquoi.
          </li>
          <li>
            <Link href="/cgu" className="underline">
              Conditions d’utilisation
            </Link>
          </li>
        </ul>
      </section>
    </main>
  );
}
