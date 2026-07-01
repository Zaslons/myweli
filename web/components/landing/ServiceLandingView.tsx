import type { Metadata } from 'next';
import { listProvidersByCommune, type Provider } from '../../lib/api/providers';
import {
  matchesService,
  siblingCommunesForService,
  siblingServicesForCommune,
  type ServiceLanding,
} from '../../lib/service-landing';
import {
  breadcrumbJsonLd,
  faqJsonLd,
  itemListJsonLd,
  siteUrl,
} from '../../lib/seo/jsonld';
import { JsonLd } from '../JsonLd';
import { Faq } from '../provider/Faq';
import { ProviderCard } from '../provider/ProviderCard';

function filterByService(providers: Provider[], serviceSlug: string): Provider[] {
  return providers.filter((p) =>
    (p.services ?? []).some((s) => matchesService(s.name, serviceSlug)),
  );
}

function buildFaq(l: ServiceLanding): { question: string; answer: string }[] {
  const s = l.label.toLowerCase();
  return [
    {
      question: `Où faire ${s} à ${l.commune} ?`,
      answer:
        `Découvrez les salons proposant ${s} à ${l.commune} sur MyWeli, ` +
        `avec tarifs, avis et réservation en ligne.`,
    },
    {
      question: `Comment réserver ${s} à ${l.commune} ?`,
      answer:
        'Choisissez un salon, le service et un créneau, puis confirmez en ' +
        'ligne — 24/7, sans appel.',
    },
    {
      question: `Combien coûte ${s} à ${l.commune} ?`,
      answer:
        'Les tarifs varient selon le salon. Comparez les prix « à partir de » ' +
        'sur chaque fiche.',
    },
  ];
}

export async function serviceLandingMetadata(
  l: ServiceLanding,
  slug: string,
): Promise<Metadata> {
  const providers = filterByService(
    await listProvidersByCommune(l.commune),
    l.serviceSlug,
  );
  const title = `${l.label} à ${l.commune} — réserver en ligne`;
  const description =
    `Réservez ${l.label.toLowerCase()} à ${l.commune}, Côte d’Ivoire. ` +
    'Salons, tarifs et avis sur MyWeli.';
  const url = `${siteUrl}/${slug}`;
  return {
    title,
    description,
    alternates: { canonical: url },
    robots: providers.length === 0 ? { index: false, follow: true } : undefined,
    openGraph: { title, description, url },
  };
}

const chip =
  'rounded-full border border-border bg-secondary px-m py-xs text-sm ' +
  'text-textPrimary hover:bg-surfaceVariant';

export async function ServiceLandingView({
  landing: l,
  slug,
}: {
  landing: ServiceLanding;
  slug: string;
}) {
  const providers = filterByService(
    await listProvidersByCommune(l.commune),
    l.serviceSlug,
  );
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
      <p className="mt-m text-textSecondary">
        Réservez {l.label.toLowerCase()} à {l.commune} (Côte d’Ivoire) — comparez
        les salons, tarifs et avis, puis réservez en ligne 24/7.
      </p>

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
          Aucun salon proposant {l.label.toLowerCase()} à {l.commune} pour le
          moment. Découvrez d’autres communes ci-dessous.
        </p>
      )}

      <section className="mt-xl">
        <h2 className="text-lg font-semibold text-textPrimary">
          {l.label} dans d’autres communes
        </h2>
        <div className="mt-s flex flex-wrap gap-s">
          {siblingCommunesForService(l.serviceSlug, l.commune).map((x) => (
            <a key={x.slug} href={`/${x.slug}`} className={chip}>
              {x.commune}
            </a>
          ))}
        </div>
      </section>

      <section className="mt-l">
        <h2 className="text-lg font-semibold text-textPrimary">
          Autres prestations à {l.commune}
        </h2>
        <div className="mt-s flex flex-wrap gap-s">
          {siblingServicesForCommune(l.commune, l.serviceSlug).map((x) => (
            <a key={x.slug} href={`/${x.slug}`} className={chip}>
              {x.label}
            </a>
          ))}
        </div>
      </section>

      <Faq items={faq} />
    </main>
  );
}
