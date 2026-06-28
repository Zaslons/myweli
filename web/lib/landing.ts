import { slugify } from './slug';

/// SEO landing = a category × commune hub (e.g. /coiffure-cocody). Vocab + slug
/// parse/build, pure + tested. Design: docs/design/web-m4-landing.md.

export type Landing = {
  categorySlug: string; // FR slug, e.g. "coiffure"
  apiKey: string; // backend category, e.g. "salon"
  label: string; // display, e.g. "Coiffure"
  commune: string; // display, e.g. "Cocody"
};

const categories: { slug: string; apiKey: string; label: string }[] = [
  { slug: 'coiffure', apiKey: 'salon', label: 'Coiffure' },
  { slug: 'barbier', apiKey: 'barber', label: 'Barbier' },
  { slug: 'onglerie', apiKey: 'nail', label: 'Onglerie' },
  { slug: 'spa', apiKey: 'spa', label: 'Spa' },
  { slug: 'massage', apiKey: 'massage', label: 'Massage' },
];

export const communes = [
  'Cocody',
  'Plateau',
  'Yopougon',
  'Marcory',
  'Treichville',
  'Adjamé',
  'Abobo',
  'Koumassi',
  'Port-Bouët',
  'Attécoubé',
  'Bingerville',
];

const communeBySlug = new Map(communes.map((c) => [slugify(c), c]));

export function buildLandingSlug(categorySlug: string, commune: string): string {
  return `${categorySlug}-${slugify(commune)}`;
}

/// Parse a flat slug into a landing, or null if it isn't a known combo.
export function parseLandingSlug(slug: string): Landing | null {
  const cat = categories.find((c) => slug.startsWith(`${c.slug}-`));
  if (!cat) return null;
  const commune = communeBySlug.get(slug.slice(cat.slug.length + 1));
  if (!commune) return null;
  return {
    categorySlug: cat.slug,
    apiKey: cat.apiKey,
    label: cat.label,
    commune,
  };
}

export function categorySlugForApiKey(apiKey: string): string | null {
  return categories.find((c) => c.apiKey === apiKey)?.slug ?? null;
}

/// Same category, the other communes (SEO internal links).
export function siblingsForCategory(
  categorySlug: string,
  exceptCommune: string,
): { slug: string; commune: string }[] {
  return communes
    .filter((c) => c !== exceptCommune)
    .map((c) => ({ slug: buildLandingSlug(categorySlug, c), commune: c }));
}

/// Other categories, same commune (SEO internal links).
export function siblingsForCommune(
  commune: string,
  exceptCategorySlug: string,
): { slug: string; label: string }[] {
  return categories
    .filter((c) => c.slug !== exceptCategorySlug)
    .map((c) => ({ slug: buildLandingSlug(c.slug, commune), label: c.label }));
}
