'use client';

import { useRouter } from 'next/navigation';
import { type FormEvent, useState } from 'react';
import type { LocalityTree } from '../../lib/localities';
import { allAreas } from '../../lib/localities';
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

  // One ruled bar (docs/design/web-swiss-fields.md §3): the form draws the box and the
  // lines between, so its parts have no border of their own and no line ever doubles.
  // A focused part rises, or the black button would paint over the ring beside it.
  const field =
    'relative min-h-12 min-w-0 rounded-control bg-surface p-m text-bodyLarge text-textPrimary focus:z-dropdown focus:ring-1 focus:ring-borderFocus';

  return (
    <form
      data-search-bar
      onSubmit={submit}
      className="flex flex-col divide-y divide-primary rounded-control border border-primary sm:flex-row sm:divide-x sm:divide-y-0"
    >
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
        className={`${field} sm:w-44 xl:w-56`}
      />
      <datalist id="myweli-communes">
        {allAreas(tree).map(({ area }) => (
          <option key={`${area.slug}`} value={area.name} />
        ))}
      </datalist>
      <button
        type="submit"
        className="relative inline-flex min-h-12 items-center justify-center rounded-control bg-primary px-l text-labelLarge font-medium text-secondary hover:bg-primaryHover focus:z-dropdown"
      >
        Rechercher
      </button>
    </form>
  );
}
