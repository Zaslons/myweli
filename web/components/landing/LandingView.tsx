import type { Metadata } from 'next';
import { listProviders } from '../../lib/api/providers';
import {
  siblingsForCategory,
  siblingsForCommune,
  type Landing,
} from '../../lib/landing';
import {
  breadcrumbJsonLd,
  faqJsonLd,
  itemListJsonLd,
  siteUrl,
} from '../../lib/seo/jsonld';
import { JsonLd } from '../JsonLd';
import { Faq } from '../provider/Faq';
import { ProviderCard } from '../provider/ProviderCard';

function lead(l: Landing): string {
  return (
    `Les meilleurs salons de ${l.label.toLowerCase()} à ${l.commune} ` +
    `(Côte d’Ivoire), réservables en ligne 24/7 — comparez tarifs, avis et ` +
    `disponibilités, puis réservez en quelques secondes.`
  );
}

function buildFaq(l: Landing): { question: string; answer: string }[] {
  const cat = l.label.toLowerCase();
  return [
    {
      question: `Où trouver un service de ${cat} à ${l.commune} ?`,
      answer:
        `Découvrez les salons de ${cat} à ${l.commune} sur Myweli, avec ` +
        `tarifs, avis et réservation en ligne.`,
    },
    {
      question: `Comment réserver à ${l.commune} ?`,
      answer:
        'Choisissez un salon, un service et un créneau, puis confirmez en ' +
        'ligne — 24/7, sans appel.',
    },
    {
      question: `Combien coûte un service de ${cat} à ${l.commune} ?`,
      answer:
        'Les tarifs varient selon le salon et la prestation. Comparez les ' +
        'prix « à partir de » sur chaque fiche.',
    },
  ];
}

export async function landingMetadata(
  l: Landing,
  slug: string,
): Promise<Metadata> {
  const providers = await listProviders(l.apiKey, l.commune);
  const title = `${l.label} à ${l.commune} — réserver en ligne`;
  const description =
    `Trouvez et réservez un salon de ${l.label.toLowerCase()} à ${l.commune}, ` +
    'Côte d’Ivoire. Tarifs, avis et disponibilités sur Myweli.';
  const url = `${siteUrl}/${slug}`;
  return {
    title,
    description,
    alternates: { canonical: url },
    // Thin/empty landings are kept crawlable for links but not indexed.
    robots: providers.length === 0 ? { index: false, follow: true } : undefined,
    openGraph: { title, description, url },
  };
}

const chip =
  'rounded-full border border-border bg-secondary px-m py-xs text-sm ' +
  'text-textPrimary hover:bg-surfaceVariant';

export async function LandingView({
  landing: l,
  slug,
}: {
  landing: Landing;
  slug: string;
}) {
  const providers = await listProviders(l.apiKey, l.commune);
  const url = `${siteUrl}/${slug}`;
  const faq = buildFaq(l);

  return (
    <main className="mx-auto max-w-3xl px-m py-l">
      <JsonLd
        data={breadcrumbJsonLd([
          { name: 'Accueil', url: siteUrl },
          { name: `${l.label} à ${l.commune}`, url },
        ])}
      />
      {providers.length > 0 ? (
        <JsonLd
          data={itemListJsonLd(
            providers.map((p) => ({
              name: p.name,
              url: `${siteUrl}/${p.slug}`,
            })),
          )}
        />
      ) : null}
      <JsonLd data={faqJsonLd(faq)} />

      <h1 className="text-3xl font-semibold text-textPrimary">
        {l.label} à {l.commune}
      </h1>
      <p className="mt-m text-textSecondary">{lead(l)}</p>

      {providers.length > 0 ? (
        <ul className="mt-l grid gap-m sm:grid-cols-2">
          {providers.map((p) => (
            <li key={p.id}>
              <ProviderCard provider={p} />
            </li>
          ))}
        </ul>
      ) : (
        <p className="mt-l text-textSecondary">
          Aucun salon pour le moment dans cette catégorie à {l.commune}.
          Découvrez d’autres communes ci-dessous.
        </p>
      )}

      <section className="mt-xl">
        <h2 className="text-lg font-semibold text-textPrimary">
          {l.label} dans d’autres communes
        </h2>
        <div className="mt-s flex flex-wrap gap-s">
          {siblingsForCategory(l.categorySlug, l.commune).map((s) => (
            <a key={s.slug} href={`/${s.slug}`} className={chip}>
              {s.commune}
            </a>
          ))}
        </div>
      </section>

      <section className="mt-l">
        <h2 className="text-lg font-semibold text-textPrimary">
          Autres prestations à {l.commune}
        </h2>
        <div className="mt-s flex flex-wrap gap-s">
          {siblingsForCommune(l.commune, l.categorySlug).map((s) => (
            <a key={s.slug} href={`/${s.slug}`} className={chip}>
              {s.label}
            </a>
          ))}
        </div>
      </section>

      <Faq items={faq} />
    </main>
  );
}
