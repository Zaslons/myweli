import type { Metadata } from 'next';
import { ButtonLink } from '../../components/ButtonLink';
import { JsonLd } from '../../components/JsonLd';
import { HeroBackground } from '../../components/home/HeroBackground';
import { PRO_LANDING as L } from '../../lib/pro/landing';
import { faqJsonLd, siteUrl } from '../../lib/seo/jsonld';

/// « MyWeli Pro pour les salons » — the public page a salon finds
/// (docs/design/web-pro-access.md §4). Indexable and static; ONE filled action
/// per screen (von Restorff), two choices (Hick): sign up, or sign in. The
/// companion path made the web the only place an offer is chosen, and nothing
/// on the site pointed here before (§1).
///
/// `professionnels` is reserved as a salon slug (backend `slug.dart`): this
/// static route shares `/[slug]` with salon pages.
export const metadata: Metadata = {
  title: 'MyWeli Pro — logiciel de réservation pour salons de beauté en Côte d’Ivoire',
  description:
    'Recevez des réservations en ligne 24 h/24 et gérez agenda, équipe, clientèle et acomptes Mobile Money. 3 mois offerts, sans carte bancaire.',
  alternates: { canonical: '/professionnels' },
  openGraph: {
    title: 'MyWeli Pro — pour les salons de beauté',
    description: 'Recevez des réservations en ligne 24 h/24. 3 mois offerts.',
    url: `${siteUrl}/professionnels`,
  },
};

const h2 = 'text-titleLarge font-semibold text-textPrimary';

export default function ProfessionnelsPage() {
  return (
    <>
      <JsonLd data={faqJsonLd([...L.faq])} />
      <main>
        <section className="relative overflow-hidden border-b border-divider">
          <HeroBackground />
          {/* `relative`: the backdrop is absolutely positioned (see the home
              page's hero for why this class is load-bearing). */}
          <div className="relative mx-auto max-w-5xl px-m py-xxl">
            <h1 className="max-w-2xl text-headlineLarge font-semibold text-textPrimary">{L.title}</h1>
            <p className="mt-m max-w-xl text-bodyLarge text-textSecondary">{L.subtitle}</p>
            <div className="mt-l flex flex-wrap items-center gap-s">
              <ButtonLink href="/pro/inscription">{L.signUp}</ButtonLink>
              <ButtonLink href="/pro/connexion" variant="secondary">
                {L.signIn}
              </ButtonLink>
            </div>
            <p className="mt-m text-bodyMedium text-textSecondary">{L.trial}</p>
          </div>
        </section>

        <div className="mx-auto max-w-5xl px-m py-xl">
          <section aria-labelledby="pro-benefits">
            <h2 id="pro-benefits" className={h2}>
              {L.benefitsTitle}
            </h2>
            <ul className="mt-m grid grid-cols-1 gap-m sm:grid-cols-2 lg:grid-cols-3">
              {L.benefits.map((b) => (
                <li key={b.title} className="rounded-xl border border-border bg-secondary p-l">
                  <h3 className="text-titleMedium font-semibold text-textPrimary">{b.title}</h3>
                  <p className="mt-xs text-bodyLarge text-textSecondary">{b.body}</p>
                </li>
              ))}
            </ul>
          </section>

          <section aria-labelledby="pro-steps" className="mt-xl">
            <h2 id="pro-steps" className={h2}>
              {L.stepsTitle}
            </h2>
            <ol className="mt-m grid grid-cols-1 gap-m sm:grid-cols-3">
              {L.steps.map((step, i) => (
                <li key={step} className="flex items-start gap-s">
                  <span
                    aria-hidden="true"
                    className="flex min-h-8 min-w-8 shrink-0 items-center justify-center rounded-pill bg-primary text-labelLarge font-medium text-secondary"
                  >
                    {i + 1}
                  </span>
                  <span className="text-bodyLarge text-textPrimary">{step}</span>
                </li>
              ))}
            </ol>
          </section>

          <section aria-labelledby="pro-faq" className="mt-xl">
            <h2 id="pro-faq" className={h2}>
              {L.faqTitle}
            </h2>
            <dl className="mt-m space-y-m">
              {L.faq.map((f) => (
                <div key={f.question}>
                  <dt className="font-medium text-textPrimary">{f.question}</dt>
                  <dd className="mt-xs text-bodyLarge text-textSecondary">{f.answer}</dd>
                </div>
              ))}
            </dl>
          </section>

          <section
            aria-labelledby="pro-closing"
            className="mt-xl flex flex-col items-start justify-between gap-m rounded-xl border border-border bg-surfaceVariant p-l sm:flex-row sm:items-center"
          >
            <h2 id="pro-closing" className={h2}>
              {L.closing}
            </h2>
            {/* Secondary: the hero holds the page's one filled action. */}
            <ButtonLink href="/pro/inscription" variant="secondary" className="shrink-0">
              {L.signUp}
            </ButtonLink>
          </section>
        </div>
      </main>
    </>
  );
}
