import { Chip } from './Chip';

/// The shared rating display (§3.5, B6) — the web twin of `AppRating`:
/// « ★ 4,8 (32 avis) ». The star is DECORATION (aria-hidden); the numeral is
/// the information — `starRating`'s 1.62:1 gold is invisible to a low-vision
/// user, so meaning never rides on the glyph (the web renders it in ink, which
/// is §3.5-safe by construction).
///
/// French decimal COMMA via fr-FR formatting — before B6 every site rendered
/// `rating.toFixed(1)` (« 4.8 », the anglophone point) on a French product.
///
/// This is a DISPLAY. The review-form star input is B5's radio group; the
/// ♥ favorite toggles are §16's filled/outline glyph swap — neither is this.
export function ratingFr(value: number): string {
  return value.toLocaleString('fr-FR', {
    minimumFractionDigits: 1,
    maximumFractionDigits: 1,
  });
}

export function Rating({
  value,
  count,
  suffix,
  className = '',
}: {
  value: number;
  /** Review count → « (32 avis) ». */
  count?: number;
  /** Alternative tail, e.g. « sur 5 ». Ignored when `count` is given. */
  suffix?: string;
  className?: string;
}) {
  return (
    <span className={className}>
      <span aria-hidden="true">★</span> {ratingFr(value)}
      {count != null
        ? ` (${count} avis)`
        : suffix
          ? ` ${suffix}`
          : ''}
    </span>
  );
}

/// The salon-level rule (docs/design/salon-rating-new-and-visits-card.md
/// §2.1), shared with the app's `AppRating`: a salon nobody has reviewed yet
/// reads « Nouveau ». It used to read NOTHING here (three `reviewCount > 0`
/// guards) while the app printed « ★ 0.0 · 0 avis » — two surfaces, two
/// wrong answers to the same question.
export function SalonRating({
  rating,
  reviewCount,
  withCount = false,
  dense = true,
  className = '',
}: {
  rating: number;
  reviewCount: number;
  /** « (32 avis) » after the value — the salon page header. */
  withCount?: boolean;
  /** The list-row micro-badge tier (cards, map popups). */
  dense?: boolean;
  className?: string;
}) {
  if (reviewCount > 0) {
    return (
      <Rating
        value={rating}
        count={withCount ? reviewCount : undefined}
        className={className}
      />
    );
  }
  return (
    <Chip dense={dense} className={className}>
      Nouveau<span className="sr-only"> salon, pas encore d’avis</span>
    </Chip>
  );
}
