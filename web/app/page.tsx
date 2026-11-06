import type { Metadata } from 'next';
import Link from 'next/link';
import { JsonLd } from '../components/JsonLd';
import { ProBand } from '../components/home/ProBand';
import { OpenInAppButton } from '../components/OpenInAppButton';
import { HomeSearch } from '../components/home/HomeSearch';
import { ProviderCard } from '../components/provider/ProviderCard';
import { SiteFaqList } from '../components/SiteFaqList';
import { SiteHero } from '../components/SiteHero';
import { SiteSection } from '../components/SiteSection';
import { defaultCity, getLocalityTree } from '../lib/api/localities';
import { searchProviders } from '../lib/api/providers';
import { buildTaxonomyPath, categoryList } from '../lib/landing';
import { faqJsonLd, websiteJsonLd } from '../lib/seo/jsonld';
import { appStoreUrl } from '../lib/appStore';
import { SITE_CONTAINER } from '../lib/siteGrid';

export const revalidate = 3600; // ISR — featured refreshes hourly

/// The home market's first city names the page (multi-pays MP3: geography
/// from the locality tree; « Abidjan » is only the degraded-tree fallback).
export async function generateMetadata(): Promise<Metadata> {
  const cityName = defaultCity(await getLocalityTree())?.name ?? 'Abidjan';
  return {
    title: `MyWeli — réservez beauté & bien-être à ${cityName}`,
    description:
      'Réservez coiffure, tresses, barbier, onglerie et spa près de chez vous en ' +
      'Côte d’Ivoire. En ligne, 24/7, sans appel — l’acompte se règle au salon.',
    alternates: { canonical: '/' },
  };
}

// Tiles: categories + the popular "Tresses" service. UX → /recherche (the SEO
// targets are the indexed area×category landings in the directory below).
const TILES = [
  ...categoryList.map((c) => ({
    label: c.label,
    href: `/recherche?category=${c.apiKey}`,
  })),
  { label: 'Tresses', href: '/recherche?q=tresses' },
];

function buildFaq(cityName: string) {
  return [
    {
      question: `Comment réserver un salon de beauté à ${cityName} ?`,
      answer:
        'Cherchez un service et une commune, choisissez un salon, puis réservez ' +
        'en ligne en quelques secondes — 24h/24, sans appel.',
    },
    {
      question: 'Faut-il payer en ligne sur MyWeli ?',
      answer:
        'Non. Un éventuel acompte se règle directement au salon (Wave / Mobile ' +
        'Money). MyWeli ne prélève aucun paiement.',
    },
    {
      question: 'Puis-je gérer mes rendez-vous ?',
      answer:
        'Oui — depuis votre compte sur le web (Mon compte) ou via l’application ' +
        'MyWeli, où vous retrouvez et annulez vos réservations.',
    },
  ];
}

/// One commune's links into the nested landing tree. Called twice (see the
/// directory below), which is why it is one function: the two cannot drift.
function AreaLinks({ citySlug, area }: { citySlug: string; area: { slug: string; name: string } }) {
  return (
    <ul>
      {categoryList.map((c) => (
        <li key={c.slug}>
          <Link
            href={buildTaxonomyPath(c.slug, citySlug, area.slug)}
            className="flex min-h-12 items-center text-bodyMedium text-textSecondary hover:text-textPrimary"
          >
            {c.label} à {area.name}
          </Link>
        </li>
      ))}
    </ul>
  );
}

export default async function HomePage() {
  const [featured, tree] = await Promise.all([
    searchProviders({ pageSize: 8 }),
    getLocalityTree(),
  ]);
  const city = defaultCity(tree);
  const cityName = city?.name ?? 'Abidjan';
  // The directory teases the first areas; each column links into the nested
  // landing tree (the city pages carry the full area list).
  const directoryAreas = (city?.areas ?? []).slice(0, 4);
  const faq = buildFaq(cityName);

  return (
    <>
      <JsonLd data={websiteJsonLd()} />
      <JsonLd data={faqJsonLd(faq)} />

      <main>
        <SiteHero
          title={
            <>
              Réservez beauté & <span className="whitespace-nowrap">bien-être</span> à {cityName}
            </>
          }
        >
          <p className="max-w-xl text-bodyLarge text-textSecondary">
            Coiffure, tresses, barbier, onglerie, spa — réservez en ligne, près
            de chez vous, en quelques secondes.
          </p>
          <div className="mt-l">
            <HomeSearch tree={tree} />
          </div>
        </SiteHero>

        <SiteSection title="Catégories">
          <ul className="grid grid-cols-2 gap-x-m lg:grid-cols-3 lg:gap-x-l">
            {TILES.map((t) => (
              <li key={t.label}>
                <Link
                  href={t.href}
                  className="flex min-h-12 items-center border-b border-divider text-bodyLarge text-textPrimary hover:text-textSecondary"
                >
                  {t.label}
                </Link>
              </li>
            ))}
          </ul>
        </SiteSection>

        {featured.length > 0 ? (
          <SiteSection title="Salons populaires" stacked>
            <div className="grid grid-cols-1 gap-x-m gap-y-l sm:grid-cols-2 lg:grid-cols-4 lg:gap-x-l">
              {featured.map((p) => (
                <ProviderCard key={p.id} provider={p} />
              ))}
            </div>
          </SiteSection>
        ) : null}

        {city && directoryAreas.length > 0 ? (
          <SiteSection title={`Partout à ${cityName}`}>
            {/* Two forms of one list, so that neither needs a script. A phone gets
                one disclosure per commune, since twenty links is a long scroll; from
                `lg` they are all open, and a `<details>` pressed open would tell a
                screen reader « collapsed » about links it can see. Both are in the
                served HTML, and the one not in use is `display: none`. */}
            <div className="lg:hidden">
              {directoryAreas.map((area) => (
                <details key={area.slug} className="group border-b border-divider">
                  <summary className="flex min-h-12 cursor-pointer list-none items-center justify-between gap-m">
                    <h3 className="text-bodyLarge font-medium text-textPrimary">{area.name}</h3>
                    <span aria-hidden="true" className="text-iconS text-textSecondary group-open:rotate-180">
                      ▾
                    </span>
                  </summary>
                  <AreaLinks citySlug={city.slug} area={area} />
                </details>
              ))}
            </div>
            <div className="hidden grid-cols-4 gap-x-l lg:grid">
              {directoryAreas.map((area) => (
                <div key={area.slug}>
                  <h3 className="flex min-h-12 items-center text-bodyLarge font-medium text-textPrimary">
                    {area.name}
                  </h3>
                  <AreaLinks citySlug={city.slug} area={area} />
                </div>
              ))}
            </div>
          </SiteSection>
        ) : null}

        <section className="border-t border-primary">
          <div className={`${SITE_CONTAINER} py-m lg:grid lg:grid-cols-3 lg:gap-x-l lg:py-xxl`}>
            {[
              ['Réservation en ligne', '24h/24, sans appel ni attente.'],
              [
                'Acompte direct au salon',
                'Wave / Mobile Money — MyWeli ne prélève rien.',
              ],
              // No WhatsApp/SMS until messaging is switched on — the app's
              // notifications carry both (promise-honesty-sweep.md, T5).
              [
                'Rappels dans l’app',
                // No-break spaces: « 2 h » split across two lines at 375.
                'Confirmation du salon, puis rappels 24\u00a0h et 2\u00a0h avant votre rendez-vous.',
              ],
            ].map(([title, body]) => (
              <div key={title} className="border-t border-divider py-m first:border-t-0 lg:border-t-0 lg:py-0">
                <p className="font-medium text-textPrimary">{title}</p>
                <p className="mt-xs text-bodyLarge text-textSecondary">{body}</p>
              </div>
            ))}
          </div>
        </section>

        {/* **The whole section, not just the button.** `OpenInAppButton`
            already renders nothing while the apps are unlisted — but the copy
            around it stayed, so production served « L'app MyWeli — Réservez
            plus vite … » with no way to get it (verified 2026-08-21: no
            apps.apple.com or play.google.com anywhere in the document). The
            component-level test could not see it, because the orphan is the
            wrapper. */}
        {appStoreUrl() ? (
          <SiteSection title="L’app MyWeli">
            <div className="flex flex-col items-start gap-m lg:flex-row lg:items-center lg:justify-between lg:gap-l">
              <p className="text-bodyLarge text-textSecondary">
                Réservez plus vite et gérez vos rendez-vous depuis votre poche.
              </p>
              <OpenInAppButton />
            </div>
          </SiteSection>
        ) : null}

        {/* The salons' door (web-pro-access.md P3), before the FAQ. */}
        <ProBand />

        <SiteSection title="Questions fréquentes">
          <SiteFaqList items={faq} />
        </SiteSection>
      </main>
    </>
  );
}
