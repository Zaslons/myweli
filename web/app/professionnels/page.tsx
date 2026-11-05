import type { Metadata } from 'next';
import { ButtonLink } from '../../components/ButtonLink';
import { JsonLd } from '../../components/JsonLd';
import { SiteFaqList } from '../../components/SiteFaqList';
import { SiteHero } from '../../components/SiteHero';
import { SiteSection } from '../../components/SiteSection';
import { PRO_LANDING as L } from '../../lib/pro/landing';
import { faqJsonLd, siteUrl } from '../../lib/seo/jsonld';
import { SITE_CONTAINER } from '../../lib/siteGrid';

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

export default function ProfessionnelsPage() {
  return (
    <>
      <JsonLd data={faqJsonLd([...L.faq])} />
      <main>
        <SiteHero title={L.title}>
          <p className="max-w-xl text-bodyLarge text-textSecondary">{L.subtitle}</p>
          <div className="mt-l flex flex-wrap items-center gap-s">
            <ButtonLink href="/pro/inscription">{L.signUp}</ButtonLink>
            <ButtonLink href="/pro/connexion" variant="secondary">
              {L.signIn}
            </ButtonLink>
          </div>
          <p className="mt-m text-bodyMedium text-textSecondary">{L.trial}</p>
        </SiteHero>

        <SiteSection title={L.benefitsTitle} titleId="pro-benefits" stacked>
          <ul className="grid grid-cols-1 gap-x-l gap-y-l sm:grid-cols-2 lg:grid-cols-3">
            {L.benefits.map((b) => (
              <li key={b.title} className="border-t border-divider pt-m">
                <h3 className="text-titleMedium font-semibold text-textPrimary">{b.title}</h3>
                <p className="mt-xs text-bodyLarge text-textSecondary">{b.body}</p>
              </li>
            ))}
          </ul>
        </SiteSection>

        <SiteSection title={L.stepsTitle} titleId="pro-steps">
          <ol className="grid grid-cols-1 gap-y-l sm:grid-cols-3 sm:gap-x-l">
            {L.steps.map((step, i) => (
              <li key={step} className="flex items-baseline gap-m sm:block">
                <span
                  aria-hidden="true"
                  className="text-displayMedium font-semibold tracking-tight text-textPrimary"
                >
                  {i + 1}
                </span>
                <p className="text-bodyLarge text-textPrimary sm:mt-s">{step}</p>
              </li>
            ))}
          </ol>
        </SiteSection>

        <SiteSection title={L.faqTitle} titleId="pro-faq">
          <SiteFaqList items={L.faq} />
        </SiteSection>

        <section aria-labelledby="pro-closing" className="border-t border-primary">
          <div
            className={`${SITE_CONTAINER} flex flex-col items-start gap-m py-xl lg:flex-row lg:items-center lg:justify-between lg:gap-l lg:py-xxl`}
          >
            <h2
              id="pro-closing"
              className="text-headlineSmall font-semibold text-textPrimary lg:text-headlineMedium"
            >
              {L.closing}
            </h2>
            {/* Secondary: the hero holds the page's one filled action. */}
            <ButtonLink href="/pro/inscription" variant="secondary" className="shrink-0">
              {L.signUp}
            </ButtonLink>
          </div>
        </section>
      </main>
    </>
  );
}
