import { directionsUrl, osmEmbedUrl } from '../../lib/provider-summary';

/// Localisation — address + an interactive OpenStreetMap embed (no API key) +
/// an Itinéraire link. Falls back to address-only when coords are missing.
export function MapEmbed({
  address,
  commune,
  latitude,
  longitude,
}: {
  address?: string;
  commune?: string | null;
  latitude?: number | null;
  longitude?: number | null;
}) {
  const hasCoords = latitude != null && longitude != null;
  return (
    <section className="px-m py-l">
      <h2 className="text-xl font-semibold text-textPrimary">Localisation</h2>
      <p className="mt-xs text-textSecondary">
        {address}
        {commune ? `, ${commune}` : ''}
      </p>
      {hasCoords ? (
        <>
          <iframe
            title={`Carte — ${address ?? 'salon'}`}
            loading="lazy"
            src={osmEmbedUrl(latitude, longitude)}
            className="mt-m h-64 w-full rounded-lg border border-border"
          />
          <a
            href={directionsUrl(latitude, longitude)}
            target="_blank"
            rel="noopener noreferrer"
            className="mt-s inline-block text-sm font-medium text-textPrimary underline"
          >
            Itinéraire
          </a>
        </>
      ) : null}
    </section>
  );
}
