'use client';

import { useEffect, useState } from 'react';
import { salonOffsetDiffers } from '../lib/time';

/// « Heures affichées : heure du salon (Côte d'Ivoire) » — rendered ONLY when
/// the viewer's device clock disagrees with the salon's (a traveler booking
/// from abroad); visitors in Côte d'Ivoire never see it. Consumer surfaces
/// only. Mounted-flag gated: the device offset exists client-side only, so
/// rendering before mount would mismatch the server HTML for foreign-TZ
/// visitors. Design: docs/design/timezone-salon-time.md §2.
export function SalonTimeHint({
  date,
  deviceOffsetMin,
  className = 'mt-s text-xs text-textTertiary',
}: {
  /// The displayed instant (defaults to now) — offsets are date-dependent.
  date?: string;
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
      ? salonOffsetDiffers(at)
      : salonOffsetDiffers(at, undefined, deviceOffsetMin);
  if (!differs) return null;
  return (
    <p className={className}>
      Heures affichées : heure du salon (Côte d’Ivoire)
    </p>
  );
}
