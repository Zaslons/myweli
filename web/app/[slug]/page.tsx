import type { Metadata } from 'next';
import { notFound } from 'next/navigation';
import { JsonLd } from '../../components/JsonLd';
import { Faq } from '../../components/provider/Faq';
import { ProviderHero } from '../../components/provider/Hero';
import { Hours } from '../../components/provider/Hours';
import { ReviewList } from '../../components/provider/ReviewList';
import { ServiceList } from '../../components/provider/ServiceList';
import {
  getAllProviderSlugs,
  getProviderBySlug,
  type Provider,
} from '../../lib/api/providers';
import { formatFcfa } from '../../lib/format';
import {
  breadcrumbJsonLd,
  categoryLabelFr,
  faqJsonLd,
  localBusinessJsonLd,
  siteUrl,
} from '../../lib/seo/jsonld';

export const revalidate = 3600;
export const dynamicParams = true;

export async function generateStaticParams() {
  const slugs = await getAllProviderSlugs();
  return slugs.map((slug) => ({ slug }));
}

export async function generateMetadata({
  params,
}: {
  params: { slug: string };
}): Promise<Metadata> {
  const p = await getProviderBySlug(params.slug);
  if (!p) return { title: 'Salon introuvable' };
  const commune = p.commune ?? 'Abidjan';
  const cat = categoryLabelFr(p.category);
  const title = `${p.name} — ${cat} à ${commune}`;
  const description =
    `${p.name} : ${cat.toLowerCase()} à ${commune}, Côte d’Ivoire. ` +
    'Réservez en ligne — services, tarifs, horaires et avis.';
  const url = `${siteUrl}/${params.slug}`;
  return {
    title,
    description,
    alternates: { canonical: url },
    openGraph: {
      title,
      description,
      url,
      images: p.imageUrls?.length ? [p.imageUrls[0]] : undefined,
    },
  };
}

function buildFaq(p: Provider): { question: string; answer: string }[] {
  const commune = p.commune ?? 'Abidjan';
  const items = [
    {
      question: `Comment réserver chez ${p.name} ?`,
      answer:
        `Réservez en ligne sur Myweli en quelques secondes : choisissez un ` +
        `service, un créneau, puis confirmez. Disponible 24/7, sans appel.`,
    },
    {
      question: `Où se trouve ${p.name} ?`,
      answer:
        `${p.name} est situé à ${commune}` +
        `${p.address ? `, ${p.address}` : ''}, Côte d’Ivoire.`,
    },
  ];
  const active = (p.services ?? []).filter((s) => s.active !== false);
  if (active.length > 0) {
    const min = Math.min(...active.map((s) => s.price));
    items.push({
      question: `Quels sont les tarifs de ${p.name} ?`,
      answer:
        `Les prestations démarrent à partir de ${formatFcfa(min)}. ` +
        'Voir la liste complète des services et tarifs sur la page.',
    });
  }
  items.push({
    question: 'Faut-il payer un acompte ?',
    answer: p.depositRequired
      ? `Oui, ce salon demande un acompte pour confirmer, payé directement au ` +
        `salon via Mobile Money — Myweli ne prélève rien.`
      : `Non, aucun acompte n’est requis pour réserver chez ${p.name}.`,
  });
  return items;
}

export default async function ProviderPage({
  params,
}: {
  params: { slug: string };
}) {
  const p = await getProviderBySlug(params.slug);
  if (!p) notFound();

  const url = `${siteUrl}/${params.slug}`;
  const commune = p.commune ?? 'Abidjan';
  const cat = categoryLabelFr(p.category).toLowerCase();
  const faq = buildFaq(p);
  const artists = p.artists ?? [];

  return (
    <main className="mx-auto max-w-3xl">
      <JsonLd data={localBusinessJsonLd(p, url)} />
      <JsonLd data={faqJsonLd(faq)} />
      <JsonLd
        data={breadcrumbJsonLd([
          { name: 'Accueil', url: siteUrl },
          { name: p.name, url },
        ])}
      />

      <ProviderHero provider={p} />

      {/* Answer-first lead (AEO). */}
      <p className="px-m text-textSecondary">
        Réservez en ligne chez {p.name}, {cat} à {commune} (Côte d’Ivoire).
        Services, tarifs, horaires et avis — réservation 24/7, sans appel.
      </p>

      <ServiceList services={p.services ?? []} />

      {artists.length > 0 ? (
        <section className="px-m py-l">
          <h2 className="text-xl font-semibold text-textPrimary">Équipe</h2>
          <ul className="mt-m flex flex-wrap gap-m text-sm">
            {artists.map((a) => (
              <li key={a.id}>
                <span className="text-textPrimary">{a.name}</span>
                {a.specialization ? (
                  <span className="text-textTertiary"> · {a.specialization}</span>
                ) : null}
              </li>
            ))}
          </ul>
        </section>
      ) : null}

      <Hours availability={p.availability} />

      <section className="px-m py-l">
        <h2 className="text-xl font-semibold text-textPrimary">Localisation</h2>
        <p className="mt-xs text-textSecondary">
          {p.address}
          {p.commune ? `, ${p.commune}` : ''}
        </p>
        {p.latitude != null && p.longitude != null ? (
          <a
            href={`https://www.google.com/maps/search/?api=1&query=${p.latitude},${p.longitude}`}
            target="_blank"
            rel="noopener noreferrer"
            className="mt-s inline-block text-sm font-medium text-textPrimary underline"
          >
            Itinéraire
          </a>
        ) : null}
      </section>

      <ReviewList
        reviews={p.reviews ?? []}
        rating={p.rating}
        reviewCount={p.reviewCount}
      />

      <section className="px-m py-l">
        <h2 className="text-xl font-semibold text-textPrimary">Contact</h2>
        <div className="mt-m flex flex-wrap gap-s">
          <a
            href={`tel:${p.phoneNumber}`}
            className="rounded-lg border border-border bg-secondary px-l py-s text-sm font-medium text-textPrimary"
          >
            Appeler
          </a>
          {p.whatsapp ? (
            <a
              href={`https://wa.me/${p.whatsapp.replace(/[^0-9]/g, '')}`}
              target="_blank"
              rel="noopener noreferrer"
              className="rounded-lg border border-border bg-secondary px-l py-s text-sm font-medium text-textPrimary"
            >
              WhatsApp
            </a>
          ) : null}
        </div>
      </section>

      <Faq items={faq} />
    </main>
  );
}
