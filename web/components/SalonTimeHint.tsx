'use client';

import { useEffect, useState } from 'react';
import { salonOffsetDiffers } from '../lib/time';

/// « Heures affichées : heure du salon (…) » — rendered ONLY when the
/// viewer's device clock disagrees with the SALON's (a traveler booking from
/// abroad); visitors in the salon's own zone never see it. Consumer surfaces
/// only. Multi-pays MP3: takes the salon's IANA [tz] and its country's
/// display [countryLabel] (locality-tree lookup) — defaults keep the Wave-0
/// copy. Mounted-flag gated: the device offset exists client-side only, so
/// rendering before mount would mismatch the server HTML for foreign-TZ
/// visitors. Design: docs/design/timezone-salon-time.md §2.
export function SalonTimeHint({
  date,
  tz,
  countryLabel,
  deviceOffsetMin,
  className = 'mt-s text-bodySmall text-textTertiary',
}: {
  /// The displayed instant (defaults to now) — offsets are date-dependent.
  date?: string;
  /// The salon's IANA timezone (null → Africa/Abidjan).
  tz?: string | null;
  /// The salon country's display name (null → Côte d'Ivoire).
  countryLabel?: string | null;
  /// Test seam: inject the device offset (minutes EAST of UTC).
  deviceOffsetMin?: number;
  className?: string;
}) {
  const [mounted, setMounted] = useState(false);
  useEffect(() => {
    setMounted(true);
  }, []);
  if (!mounted) return null;
  const at = date ? new Date(date) : new Date();
  const differs =
    deviceOffsetMin === undefined
      ? salonOffsetDiffers(at, tz ?? undefined)
      : salonOffsetDiffers(at, tz ?? undefined, deviceOffsetMin);
  if (!differs) return null;
  return (
    <p className={className}>
      Heures affichées : heure du salon ({countryLabel ?? 'Côte d’Ivoire'})
    </p>
  );
}
