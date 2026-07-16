'use client';

import { useRouter } from 'next/navigation';
import { type FormEvent, useState } from 'react';
import type { LocalityTree } from '../../lib/api/localities';
import { allAreas } from '../../lib/api/localities';
import { resolveSearchHref } from '../../lib/discovery';

/// Hero/discovery search: service + commune → an existing SEO landing when both
/// resolve, else /recherche. Reused (prefilled) on the results page. The
/// commune suggestions + routing geography come from the locality tree
/// (multi-pays MP3), passed by the server page.
export function HomeSearch({
  tree,
  defaultService = '',
  defaultCommune = '',
}: {
  tree: LocalityTree;
  defaultService?: string;
  defaultCommune?: string;
}) {
  const router = useRouter();
  const [service, setService] = useState(defaultService);
  const [commune, setCommune] = useState(defaultCommune);

  function submit(e: FormEvent) {
    e.preventDefault();
    router.push(resolveSearchHref(service, commune, tree));
  }

  const field =
    'rounded-lg border border-border bg-surface px-m py-s text-textPrimary';

  return (
    <form onSubmit={submit} className="flex flex-col gap-s sm:flex-row">
      <input
        aria-label="Service ou salon"
        placeholder="Quel service ou salon ?"
        value={service}
        onChange={(e) => setService(e.target.value)}
        className={`flex-1 ${field}`}
      />
      <input
        aria-label="Commune"
        list="myweli-communes"
        placeholder="Où ? (commune)"
        value={commune}
        onChange={(e) => setCommune(e.target.value)}
        className={`${field} sm:w-56`}
      />
      <datalist id="myweli-communes">
        {allAreas(tree).map(({ area }) => (
          <option key={`${area.slug}`} value={area.name} />
        ))}
      </datalist>
      <button
        type="submit"
        className="rounded-lg bg-primary px-l py-s text-labelLarge font-medium text-secondary hover:bg-primaryHover"
      >
        Rechercher
      </button>
    </form>
  );
}
