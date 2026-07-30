'use client';

import dynamic from 'next/dynamic';
import { Loading } from '../Loading';
import { useEffect, useRef, useState } from 'react';
import { directionsUrl } from '../../lib/provider-summary';

// MapLibre loads ONLY when the section approaches the viewport — the salon
// page is an indexed SEO surface and its CWV budget must not pay for a map
// that sits below the fold.
const SalonLocationMap = dynamic(
  () => import('./SalonLocationMap').then((m) => m.SalonLocationMap),
  {
    ssr: false,
    loading: () => (
      <div className="flex h-full w-full items-center justify-center bg-surfaceVariant">
        <Loading label="Chargement de la carte…" />
      </div>
    ),
  },
);

/// Localisation — address + the site's one map identity (MapLibre + Positron
/// + the app's salon pin, same as /recherche — docs/design/web-discovery-map.md)
/// + an Itinéraire link. Falls back to address-only when coords are missing.
export function MapEmbed({
  name,
  category,
  address,
  commune,
  latitude,
  longitude,
}: {
  name: string;
  category?: string;
  address?: string;
  commune?: string | null;
  latitude?: number | null;
  longitude?: number | null;
}) {
  const hasCoords = latitude != null && longitude != null;
  const holder = useRef<HTMLDivElement>(null);
  const [inView, setInView] = useState(false);

  useEffect(() => {
    const el = holder.current;
    if (!el || !hasCoords) return;
    const io = new IntersectionObserver(
      (entries) => {
        if (entries.some((e) => e.isIntersecting)) {
          setInView(true);
          io.disconnect();
        }
      },
      { rootMargin: '300px' },
    );
    io.observe(el);
    return () => io.disconnect();
  }, [hasCoords]);

  return (
    <section className="px-m py-l">
      <h2 className="text-titleLarge font-semibold text-textPrimary">Localisation</h2>
      <p className="mt-xs text-textSecondary">
        {address}
        {commune ? `, ${commune}` : ''}
      </p>
      {hasCoords ? (
        <>
          <div
            ref={holder}
            role="region"
            aria-label={`Carte — ${address ?? name}`}
            className="mt-m h-64 w-full overflow-hidden rounded-lg border border-border md:h-80"
          >
            {inView ? (
              <SalonLocationMap
                name={name}
                category={category}
                latitude={latitude}
                longitude={longitude}
              />
            ) : (
              <div className="h-full w-full bg-surfaceVariant" />
            )}
          </div>
          <a
            href={directionsUrl(latitude, longitude)}
            target="_blank"
            rel="noopener noreferrer"
            className="mt-s inline-block text-labelLarge font-medium text-textPrimary underline"
          >
            Itinéraire
          </a>
        </>
      ) : null}
    </section>
  );
}
