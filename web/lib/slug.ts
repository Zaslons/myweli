// URL slug helper (mirror of backend/lib/src/slug.dart). Pure + deterministic.

const accents: Record<string, string> = {
  à: 'a', â: 'a', ä: 'a', á: 'a', ã: 'a', å: 'a',
  ç: 'c',
  è: 'e', é: 'e', ê: 'e', ë: 'e',
  ì: 'i', í: 'i', î: 'i', ï: 'i',
  ñ: 'n',
  ò: 'o', ó: 'o', ô: 'o', ö: 'o', õ: 'o',
  ù: 'u', ú: 'u', û: 'u', ü: 'u',
  ý: 'y', ÿ: 'y',
  œ: 'oe', æ: 'ae',
};

export function slugify(input: string): string {
  const lower = input.toLowerCase();
  const deaccented = [...lower].map((c) => accents[c] ?? c).join('');
  return deaccented.replace(/[^a-z0-9]+/g, '-').replace(/^-+|-+$/g, '');
}

/// Lowercase + deaccent, keeping spaces (for keyword substring matching).
export function normalize(input: string): string {
  return [...input.toLowerCase()].map((c) => accents[c] ?? c).join('');
}
