import { api } from './client';
import { emptyTree } from '../localities';

/// Fetching the locality tree (multi-pays MP3 —
/// docs/design/multi-pays-end-version.md §6). **Server-side only** — it imports
/// `./client`, which is `server-only`.
///
/// Types and pure lookups live in `lib/localities.ts` and are re-exported here
/// so server callers keep one import. Client components must import them from
/// `lib/localities` directly, and the build fails loudly if they do not.
///
/// Client components get the tree through `/api/localities` +
/// `lib/use-localities.ts`, never from here.
export type {
  LocalityTree,
  LocalityCountry,
  LocalityCity,
  LocalityArea,
  MomoOperator,
} from '../localities';
export {
  emptyTree,
  defaultCountry,
  defaultCity,
  findCity,
  findArea,
  allAreas,
  countryOf,
  countryName,
  operatorsFor,
} from '../localities';

/// Fetch the tree; empty tree on any failure so SSG/ISR builds never crash
/// (the getLandingSlugs idiom). Module-cached per server process — the
/// endpoint is public, parameterless and CDN-cacheable (T56).
let cached: Promise<import('../localities').LocalityTree> | null = null;

export async function getLocalityTree(): Promise<
  import('../localities').LocalityTree
> {
  cached ??= (async () => {
    try {
      const { data, error } = await api.GET('/localities', {});
      if (error || !data) return emptyTree;
      return data;
    } catch {
      return emptyTree;
    }
  })().then((tree) => {
    // Never pin a failed fetch for the process lifetime.
    if (tree.countries.length === 0) cached = null;
    return tree;
  });
  return cached;
}

/// Test seam: reset the module cache.
export function resetLocalityCache(): void {
  cached = null;
}
