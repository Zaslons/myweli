/// A row's share of the period's « Réalisé » (docs/design/pro-revenue-
/// analytics.md §12.1): `primary` on `surfaceVariant`, pill-shaped. Hidden
/// from screen readers — the row says the share in words.
export function ShareBar({ share, className = '' }: { share: number; className?: string }) {
  const pct = Math.max(0, Math.min(1, share)) * 100;
  return (
    <div
      aria-hidden="true"
      className={`h-1 overflow-hidden rounded-pill bg-surfaceVariant ${className}`}
    >
      {/* A width from the data: the one inline style (AvisClient's bars). */}
      <div className="h-full rounded-pill bg-primary" style={{ width: `${pct}%` }} />
    </div>
  );
}
