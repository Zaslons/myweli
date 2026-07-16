import type { Metadata } from 'next';
import Link from 'next/link';
import type {
  LocalityArea,
  LocalityCity,
  LocalityTree,
} from '../../lib/api/localities';
import { defaultCity, defaultCountry } from '../../lib/api/localities';
import {
  listProviders,
  listProvidersByCommune,
  searchProviders,
  type Provider,
} from '../../lib/api/providers';
import { buildTaxonomyPath, siblingCategoryLinks } from '../../lib/landing';
import {
  matchesService,
  siblingServiceLinks,
} from '../../lib/service-landing';
import {
  breadcrumbJsonLd,
  faqJsonLd,
  itemListJsonLd,
  siteUrl,
} from '../../lib/seo/jsonld';
import type { TaxonomyRoot } from '../../lib/taxonomy';
import { JsonLd } from '../JsonLd';
import { Faq } from '../provider/Faq';
import { ProviderCard } from '../provider/ProviderCard';

/// The nested SEO landing family (multi-pays MP3): ONE view for the three
/// levels of both taxonomies — /coiffure (root), /coiffure/abidjan (city),
/// /coiffure/abidjan/cocody (area) and the /tresses/… mirror. Geography is
/// the locality tree; categories/services stay code (lib/taxonomy.ts).
/// Replaces the flat LandingView/ServiceLandingView.

export type TaxonomyLevel =
  | { level: 'root' }
  | { level: 'city'; city: LocalityCity }
  | { level: 'area'; city: LocalityCity; area: LocalityArea };

export type TaxonomyInput = TaxonomyLevel & {
  root: TaxonomyRoot;
  tree: LocalityTree;
};

// --- shared derivations ------------------------------------------------------

function pathOf(input: TaxonomyInput): string {
  if (input.level === 'root') return buildTaxonomyPath(input.root.slug);
  if (input.level === 'city') {
    return buildTaxonomyPath(input.root.slug, input.city.slug);
  }
  return buildTaxonomyPath(input.root.slug, input.city.slug, input.area.slug);
}

/// « à Cocody » / « à Abidjan » / « en Côte d'Ivoire » (root = the home
/// market; the constant is a FALLBACK for a degraded tree only).
function placeOf(input: TaxonomyInput): { prefix: 'à' | 'en'; name: string } {
  if (input.level === 'area') return { prefix: 'à', name: input.area.name };
  if (input.level === 'city') return { prefix: 'à', name: input.city.name };
  return {
    prefix: 'en',
    name: defaultCountry(input.tree)?.name ?? "Côte d'Ivoire",
  };
}

function titleOf(input: TaxonomyInput): string {
  const place = placeOf(input);
  return `${input.root.label} ${place.prefix} ${place.name} — réserver en ligne`;
}

function h1Of(input: TaxonomyInput): string {
  const place = placeOf(input);
  return `${input.root.label} ${place.prefix} ${place.name}`;
}

function crumbsOf(input: TaxonomyInput): { name: string; url: string }[] {
  const crumbs = [
    { name: 'Accueil', url: siteUrl },
    {
      name: input.root.label,
      url: `${siteUrl}${buildTaxonomyPath(input.root.slug)}`,
    },
  ];
  if (input.level === 'city' || input.level === 'area') {
    crumbs.push({
      name: `${input.root.label} à ${input.city.name}`,
      url: `${siteUrl}${buildTaxonomyPath(input.root.slug, input.city.slug)}`,
    });
  }
  if (input.level === 'area') {
    crumbs.push({
      name: `${input.root.label} à ${input.area.name}`,
      url: `${siteUrl}${pathOf(input)}`,
    });
  }
  return crumbs;
}

function filterByService(
  providers: Provider[],
  serviceSlug: string,
): Provider[] {
  return providers.filter((p) =>
    (p.services ?? []).some((s) => matchesService(s.name, serviceSlug)),
  );
}

/// City/root pages list beyond the API's commune filter: fetch wide, then
/// scope by the salon's own market fields (citySlug/countryCode — MP1;
/// legacy rows without them count as the home market).
function geoScope(items: Provider[], input: TaxonomyInput): Provider[] {
  if (input.level === 'area') return items;
  if (input.level === 'city') {
    const home = defaultCity(input.tree)?.slug;
    return items.filter((p) => (p.citySlug ?? home) === input.city.slug);
  }
  const homeCode = defaultCountry(input.tree)?.code;
  return items.filter((p) => (p.countryCode ?? homeCode) === homeCode);
}

async function providersFor(input: TaxonomyInput): Promise<Provider[]> {
  const { root } = input;
  if (root.kind === 'category') {
    if (input.level === 'area') {
      return listProviders(root.category.apiKey, input.area.name);
    }
    return geoScope(
      await searchProviders({ category: root.category.apiKey, pageSize: 24 }),
      input,
    );
  }
  if (input.level === 'area') {
    return filterByService(
      await listProvidersByCommune(input.area.name),
      root.service.slug,
    );
  }
  return geoScope(
    filterByService(await searchProviders({ pageSize: 50 }), root.service.slug),
    input,
  );
}

function buildFaq(
  input: TaxonomyInput,
): { question: string; answer: string }[] {
  const label = input.root.label.toLowerCase();
  const place = placeOf(input);
  const where = `${place.prefix} ${place.name}`;
  const find =
    input.root.kind === 'category'
      ? `un service de ${label}`
      : `un salon pour ${label}`;
  return [
    {
      question: `Où trouver ${find} ${where} ?`,
      answer:
        `Découvrez les salons proposant ${label} ${where} sur MyWeli, avec ` +
        'tarifs, avis et réservation en ligne.',
    },
    {
      question: `Comment réserver ${where} ?`,
      answer:
        'Choisissez un salon, un service et un créneau, puis confirmez en ' +
        'ligne — 24/7, sans appel.',
    },
    {
      question: `Combien coûte ${label} ${where} ?`,
      answer:
        'Les tarifs varient selon le salon et la prestation. Comparez les ' +
        'prix « à partir de » sur chaque fiche.',
    },
  ];
}

// --- metadata ----------------------------------------------------------------

export async function taxonomyMetadata(
  input: TaxonomyInput,
): Promise<Metadata> {
  const providers = await providersFor(input);
  const title = titleOf(input);
  const place = placeOf(input);
  const description =
    `Trouvez et réservez ${input.root.label.toLowerCase()} ${place.prefix} ` +
    `${place.name}. Tarifs, avis et disponibilités sur MyWeli.`;
  const url = `${siteUrl}${pathOf(input)}`;
  return {
    title,
    description,
    alternates: { canonical: url },
    // Thin/empty landings stay crawlable for links but unindexed.
    robots:
      providers.length === 0 ? { index: false, follow: true } : undefined,
    openGraph: { title, description, url },
  };
}

// --- the view ----------------------------------------------------------------

const chip =
  'rounded-pill border border-border bg-secondary px-m py-xs text-bodyMedium ' +
  'text-textPrimary hover:bg-surfaceVariant';

/// French names for LocalityArea.labelKind (section headings).
const AREA_KIND_LABEL: Record<string, string> = {
  commune: 'commune',
  quartier: 'quartier',
  arrondissement: 'arrondissement',
};

function areaKindOf(city: LocalityCity): string {
  return AREA_KIND_LABEL[city.areas[0]?.labelKind ?? 'commune'] ?? 'commune';
}

function Crumbs({ input }: { input: TaxonomyInput }) {
  const crumbs = crumbsOf(input);
  return (
    <nav aria-label="Fil d’Ariane" className="text-bodyMedium text-textSecondary">
      <ol className="flex flex-wrap items-center gap-xs">
        {crumbs.map((c, i) => {
          const last = i === crumbs.length - 1;
          const href = c.url.replace(siteUrl, '') || '/';
          return (
            <li key={c.url} className="flex items-center gap-xs">
              {i > 0 ? <span aria-hidden>›</span> : null}
              {last ? (
                <span aria-current="page" className="text-textPrimary">
                  {c.name}
                </span>
              ) : (
                <Link href={href} className="underline hover:text-textPrimary">
                  {c.name}
                </Link>
              )}
            </li>
          );
        })}
      </ol>
    </nav>
  );
}

export async function TaxonomyLandingView(input: TaxonomyInput) {
  const providers = await providersFor(input);
  const faq = buildFaq(input);
  const place = placeOf(input);
  const label = input.root.label;
  const cities = input.tree.countries.flatMap((c) => c.cities);
  const siblingsAtLevel =
    input.root.kind === 'category' ? siblingCategoryLinks : siblingServiceLinks;
  const citySlug = input.level === 'root' ? undefined : input.city.slug;
  const areaSlug = input.level === 'area' ? input.area.slug : undefined;

  return (
    <main className="mx-auto max-w-3xl px-m py-l">
      <JsonLd data={breadcrumbJsonLd(crumbsOf(input))} />
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

      <Crumbs input={input} />

      <h1 className="mt-m text-headlineMedium font-semibold text-textPrimary">
        {h1Of(input)}
      </h1>
      <p className="mt-m text-textSecondary">
        Les meilleurs salons de {label.toLowerCase()} {place.prefix}{' '}
        {place.name}, réservables en ligne 24/7 — comparez tarifs, avis et
        disponibilités, puis réservez en quelques secondes.
      </p>

      {/* Root level: pick your city. City level: pick your commune/quartier. */}
      {input.level === 'root' && cities.length > 0 ? (
        <section className="mt-l">
          <h2 className="text-titleLarge font-semibold text-textPrimary">
            Choisissez votre ville
          </h2>
          <div className="mt-s grid grid-cols-1 gap-s sm:grid-cols-2">
            {cities.map((city) => (
              <Link
                key={city.slug}
                href={buildTaxonomyPath(input.root.slug, city.slug)}
                className="rounded-xl border border-border bg-secondary p-m hover:bg-surfaceVariant"
              >
                <span className="font-medium text-textPrimary">
                  {label} à {city.name}
                </span>
                <span className="mt-xs block text-bodyMedium text-textSecondary">
                  {city.areas.length}{' '}
                  {`${areaKindOf(city)}${city.areas.length > 1 ? 's' : ''}`}
                </span>
              </Link>
            ))}
          </div>
        </section>
      ) : null}

      {input.level === 'city' ? (
        <section className="mt-l">
          <h2 className="text-titleLarge font-semibold text-textPrimary">
            Choisissez votre {areaKindOf(input.city)}
          </h2>
          <div className="mt-s flex flex-wrap gap-s">
            {input.city.areas.map((a) => (
              <Link
                key={a.slug}
                href={buildTaxonomyPath(
                  input.root.slug,
                  input.city.slug,
                  a.slug,
                )}
                className={chip}
              >
                {a.name}
              </Link>
            ))}
          </div>
        </section>
      ) : null}

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
          Aucun salon de {label.toLowerCase()} {place.prefix} {place.name} pour
          le moment. Explorez les liens ci-dessous.
        </p>
      )}

      {/* Area level: the same root across the city's other areas. */}
      {input.level === 'area' ? (
        <section className="mt-xl">
          <h2 className="text-titleLarge font-semibold text-textPrimary">
            {label} dans d’autres {areaKindOf(input.city)}s
          </h2>
          <div className="mt-s flex flex-wrap gap-s">
            {input.city.areas
              .filter((a) => a.slug !== input.area.slug)
              .map((a) => (
                <Link
                  key={a.slug}
                  href={buildTaxonomyPath(
                    input.root.slug,
                    input.city.slug,
                    a.slug,
                  )}
                  className={chip}
                >
                  {a.name}
                </Link>
              ))}
          </div>
        </section>
      ) : null}

      <section className="mt-l">
        <h2 className="text-titleLarge font-semibold text-textPrimary">
          Autres prestations {place.prefix} {place.name}
        </h2>
        <div className="mt-s flex flex-wrap gap-s">
          {siblingsAtLevel(input.root.slug, citySlug, areaSlug).map((s) => (
            <Link key={s.href} href={s.href} className={chip}>
              {s.label}
            </Link>
          ))}
        </div>
      </section>

      <Faq items={faq} />
    </main>
  );
}
