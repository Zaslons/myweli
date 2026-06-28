import type { Metadata } from 'next';
import Link from 'next/link';
import { JsonLd } from '../components/JsonLd';
import { OpenInAppButton } from '../components/OpenInAppButton';
import { HeroBackground } from '../components/home/HeroBackground';
import { HomeSearch } from '../components/home/HomeSearch';
import { ProviderCard } from '../components/provider/ProviderCard';
import { searchProviders } from '../lib/api/providers';
import { buildLandingSlug, categoryList } from '../lib/landing';
import { faqJsonLd, websiteJsonLd } from '../lib/seo/jsonld';

export const revalidate = 3600; // ISR — featured refreshes hourly

export const metadata: Metadata = {
  title: 'Myweli — réservez beauté & bien-être à Abidjan',
  description:
    'Réservez coiffure, tresses, barbier, onglerie et spa près de chez vous en ' +
    'Côte d’Ivoire. En ligne, 24/7, sans appel — l’acompte se règle au salon.',
  alternates: { canonical: '/' },
};

// Tiles: categories + the popular "Tresses" service. UX → /recherche (the SEO
// targets are the indexed commune×category landings in the directory below).
const TILES = [
  ...categoryList.map((c) => ({
    label: c.label,
    href: `/recherche?category=${c.apiKey}`,
  })),
  { label: 'Tresses', href: '/recherche?q=tresses' },
];

const DIRECTORY_COMMUNES = ['Cocody', 'Plateau', 'Yopougon', 'Marcory'];

const FAQ = [
  {
    question: 'Comment réserver un salon de beauté à Abidjan ?',
    answer:
      'Cherchez un service et une commune, choisissez un salon, puis réservez ' +
      'en ligne en quelques secondes — 24h/24, sans appel.',
  },
  {
    question: 'Faut-il payer en ligne sur Myweli ?',
    answer:
      'Non. Un éventuel acompte se règle directement au salon (Wave / Mobile ' +
      'Money). Myweli ne prélève aucun paiement.',
  },
  {
    question: 'Puis-je gérer mes rendez-vous ?',
    answer:
      'Oui — depuis votre compte sur le web (Mon compte) ou via l’application ' +
      'Myweli, où vous retrouvez et annulez vos réservations.',
  },
];

export default async function HomePage() {
  const featured = await searchProviders({ pageSize: 8 });

  return (
    <>
      <JsonLd data={websiteJsonLd()} />
      <JsonLd data={faqJsonLd(FAQ)} />

      <section className="relative overflow-hidden border-b border-divider">
        <HeroBackground />
        <div className="mx-auto max-w-5xl px-m py-xxl">
          <h1 className="max-w-2xl text-4xl font-semibold text-textPrimary">
            Réservez beauté & bien-être à Abidjan
          </h1>
          <p className="mt-m max-w-xl text-textSecondary">
            Coiffure, tresses, barbier, onglerie, spa — réservez en ligne, près
            de chez vous, en quelques secondes.
          </p>
          <div className="mt-l max-w-3xl">
            <HomeSearch />
          </div>
        </div>
      </section>

      <main className="mx-auto max-w-5xl px-m py-xl">
        <section>
          <h2 className="text-xl font-semibold text-textPrimary">Catégories</h2>
          <div className="mt-m grid grid-cols-2 gap-s sm:grid-cols-3 lg:grid-cols-6">
            {TILES.map((t) => (
              <Link
                key={t.label}
                href={t.href}
                className="rounded-xl border border-border bg-secondary p-m text-center text-sm text-textPrimary hover:bg-surfaceVariant"
              >
                {t.label}
              </Link>
            ))}
          </div>
        </section>

        {featured.length > 0 ? (
          <section className="mt-xl">
            <h2 className="text-xl font-semibold text-textPrimary">
              Salons populaires
            </h2>
            <div className="mt-m grid grid-cols-1 gap-m sm:grid-cols-2 lg:grid-cols-4">
              {featured.map((p) => (
                <ProviderCard key={p.id} provider={p} />
              ))}
            </div>
          </section>
        ) : null}

        <section className="mt-xl">
          <h2 className="text-xl font-semibold text-textPrimary">
            Partout à Abidjan
          </h2>
          <div className="mt-m grid grid-cols-1 gap-l sm:grid-cols-2 lg:grid-cols-4">
            {DIRECTORY_COMMUNES.map((commune) => (
              <div key={commune}>
                <h3 className="font-medium text-textPrimary">{commune}</h3>
                <ul className="mt-s space-y-xs text-sm">
                  {categoryList.map((c) => (
                    <li key={c.slug}>
                      <Link
                        href={`/${buildLandingSlug(c.slug, commune)}`}
                        className="text-textSecondary underline hover:text-textPrimary"
                      >
                        {c.label} à {commune}
                      </Link>
                    </li>
                  ))}
                </ul>
              </div>
            ))}
          </div>
        </section>

        <section className="mt-xl grid grid-cols-1 gap-m sm:grid-cols-3">
          {[
            ['Réservation en ligne', '24h/24, sans appel ni attente.'],
            [
              'Acompte direct au salon',
              'Wave / Mobile Money — Myweli ne prélève rien.',
            ],
            ['Confirmations WhatsApp', 'Rappels avant votre rendez-vous.'],
          ].map(([title, body]) => (
            <div
              key={title}
              className="rounded-xl border border-border bg-secondary p-l"
            >
              <p className="font-medium text-textPrimary">{title}</p>
              <p className="mt-xs text-sm text-textSecondary">{body}</p>
            </div>
          ))}
        </section>

        <section className="mt-xl flex flex-col items-start justify-between gap-m rounded-xl border border-border bg-surfaceVariant p-l sm:flex-row sm:items-center">
          <div>
            <p className="text-lg font-semibold text-textPrimary">
              L’app Myweli
            </p>
            <p className="mt-xs text-sm text-textSecondary">
              Réservez plus vite et gérez vos rendez-vous depuis votre poche.
            </p>
          </div>
          <OpenInAppButton />
        </section>

        <section className="mt-xl">
          <h2 className="text-xl font-semibold text-textPrimary">
            Questions fréquentes
          </h2>
          <dl className="mt-m space-y-m">
            {FAQ.map((f) => (
              <div key={f.question}>
                <dt className="font-medium text-textPrimary">{f.question}</dt>
                <dd className="mt-xs text-sm text-textSecondary">{f.answer}</dd>
              </div>
            ))}
          </dl>
        </section>
      </main>
    </>
  );
}
