'use client';

import { useMemo, useState } from 'react';
import type { LocalityCity } from '../../lib/api/localities';
import { slugify } from '../../lib/slug';
import { useLocalities } from '../../lib/use-localities';
import { Button } from '../Button';

const input =
  'block w-full min-h-12 rounded-lg border border-borderStrong bg-surface p-m text-bodyMedium text-textPrimary focus:border-borderFocus focus:ring-1 focus:ring-borderFocus disabled:border-border disabled:text-textDisabled';

/// French names for LocalityArea.labelKind (the second select's label).
const AREA_KIND_LABEL: Record<string, string> = {
  commune: 'Commune',
  quartier: 'Quartier',
  arrondissement: 'Arrondissement',
};

/// The salon locality picker (multi-pays MP3 — the web mirror of the app's
/// commune picker): Ville → commune/quartier from GET /localities, writing
/// the AREA ID (the server derives commune/city/timezone/currency — T57).
/// Four states: loading (disabled selects) · error (« Réessayer » + a
/// free-text commune fallback that preserves the backend's name self-heal) ·
/// success · and the empty option (« Sélectionnez… ») since the area stays
/// optional at registration — the publish gate is the enforcement point.
export function LocalityPicker({
  areaId,
  legacyCommune,
  onChange,
  fallbackValue,
  onFallbackChange,
}: {
  /// The selected area id (null = nothing chosen yet).
  areaId: string | null;
  /// Legacy display name (pre-MP1 salons) — preselects by slug match.
  legacyCommune?: string;
  onChange: (areaId: string | null) => void;
  /// The free-text commune used ONLY on the error path (self-heal). Omit on
  /// forms whose endpoint takes no commune (registration/add-salon) — the
  /// error path then shows a note instead of an input.
  fallbackValue?: string;
  onFallbackChange?: (commune: string) => void;
}) {
  const { tree, loading, error, retry } = useLocalities();
  const cities = useMemo(
    () => tree.countries.flatMap((c) => c.cities),
    [tree],
  );

  // The city owning the selection (areaId first, then the legacy commune's
  // slug); user navigation overrides via local state.
  const derivedCitySlug = useMemo(() => {
    const wanted = areaId ?? (legacyCommune ? slugify(legacyCommune) : null);
    if (wanted) {
      for (const city of cities) {
        if (city.areas.some((a) => a.slug === wanted || a.id === wanted)) {
          return city.slug;
        }
      }
    }
    return cities[0]?.slug ?? '';
  }, [areaId, legacyCommune, cities]);
  const [pickedCity, setPickedCity] = useState<string | null>(null);
  const citySlug = pickedCity ?? derivedCitySlug;
  const city: LocalityCity | null =
    cities.find((c) => c.slug === citySlug) ?? cities[0] ?? null;

  // Preselect: the stored areaId, else the legacy commune's slug match.
  const selectedArea = useMemo(() => {
    if (!city) return '';
    if (areaId && city.areas.some((a) => a.id === areaId)) return areaId;
    if (!areaId && legacyCommune) {
      const slug = slugify(legacyCommune);
      return city.areas.find((a) => a.slug === slug)?.id ?? '';
    }
    return '';
  }, [city, areaId, legacyCommune]);

  if (loading) {
    return (
      <div className="flex gap-s">
        <select className={input} disabled aria-label="Ville">
          <option>Chargement…</option>
        </select>
        <select className={input} disabled aria-label="Commune">
          <option>Chargement…</option>
        </select>
      </div>
    );
  }

  if (error || cities.length === 0) {
    if (onFallbackChange === undefined) {
      return (
        <div className="flex items-center gap-s">
          <p className="flex-1 text-bodyMedium text-textSecondary">
            Liste des communes indisponible — vous pourrez préciser la commune
            plus tard dans votre profil.
          </p>
          <Button variant="secondary" onClick={retry}>
            Réessayer
          </Button>
        </div>
      );
    }
    return (
      <div>
        <div className="flex items-center gap-s">
          <input
            className={input}
            aria-label="Commune"
            placeholder="Commune (ex. Cocody)"
            value={fallbackValue ?? ''}
            onChange={(e) => onFallbackChange(e.target.value)}
          />
          <Button variant="secondary" onClick={retry}>
            Réessayer
          </Button>
        </div>
        <p className="mt-xs text-bodySmall text-textTertiary">
          Liste des communes indisponible — saisissez le nom, nous le
          rattacherons automatiquement.
        </p>
      </div>
    );
  }

  const kindLabel =
    AREA_KIND_LABEL[city?.areas[0]?.labelKind ?? 'commune'] ?? 'Commune';

  return (
    <div className="flex gap-s">
      <label className="block flex-1 text-bodyMedium text-textTertiary">
        Ville
        <select
          className={input}
          aria-label="Ville"
          value={citySlug}
          onChange={(e) => {
            setPickedCity(e.target.value);
            onChange(null); // a new city resets the area choice
          }}
        >
          {cities.map((c) => (
            <option key={c.slug} value={c.slug}>
              {c.name}
            </option>
          ))}
        </select>
      </label>
      <label className="block flex-1 text-bodyMedium text-textTertiary">
        {kindLabel}
        <select
          className={input}
          aria-label={kindLabel}
          value={selectedArea}
          onChange={(e) => onChange(e.target.value || null)}
        >
          <option value="">Sélectionnez…</option>
          {(city?.areas ?? []).map((a) => (
            <option key={a.id} value={a.id}>
              {a.name}
            </option>
          ))}
        </select>
      </label>
    </div>
  );
}
