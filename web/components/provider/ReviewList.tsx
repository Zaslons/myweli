import type { Review } from '../../lib/api/providers';
import { formatDateFr } from '../../lib/format';

export function ReviewList({
  reviews,
  rating,
  reviewCount,
}: {
  reviews: Review[];
  rating: number;
  reviewCount: number;
}) {
  if (reviewCount === 0) return null;
  return (
    <section className="px-m py-l">
      <h2 className="text-xl font-semibold text-textPrimary">
        Avis ({reviewCount})
      </h2>
      <p className="mt-xs text-sm text-textSecondary">
        ★ {rating.toFixed(1)} sur 5
      </p>
      <ul className="mt-m space-y-m">
        {reviews.map((r) => (
          <li key={r.id} className="rounded-lg bg-secondary p-m">
            <div className="flex justify-between">
              <span className="font-medium text-textPrimary">{r.userName}</span>
              <span className="text-sm text-textTertiary">★ {r.rating}</span>
            </div>
            {r.text ? (
              <p className="mt-xs text-sm text-textSecondary">{r.text}</p>
            ) : null}
            <p className="mt-xs text-xs text-textTertiary">
              {formatDateFr(r.createdAt)}
            </p>
          </li>
        ))}
      </ul>
    </section>
  );
}
