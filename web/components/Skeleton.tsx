/// The shared skeleton (§12, B6) — for loading states whose result SHAPE IS
/// KNOWN (a list, a card grid): "it reduces perceived latency and prevents
/// layout jump." Spinners (<Loading>) are for unknown shapes only. Never both.
///
/// Before B6 exactly ONE skeleton existed (ProSidebar's six static rows) and
/// `animate-pulse` appeared nowhere — §12's rule was satisfied on zero pages.
///
/// The whole block is `aria-hidden`: a skeleton is a picture of layout, not
/// content — AT users get the loaded content when it lands (the ProSidebar
/// precedent, kept by its own test's post-load waits). `motion-reduce` stills
/// the pulse.
export function Skeleton({ className = '' }: { className?: string }) {
  return (
    <div
      aria-hidden="true"
      className={`animate-pulse rounded-lg bg-surfaceVariant motion-reduce:animate-none ${className}`}
    />
  );
}

/** A list-shaped placeholder — the generalized ProSidebar shape. */
export function SkeletonRows({
  count = 6,
  className = '',
}: {
  count?: number;
  className?: string;
}) {
  return (
    <div aria-hidden="true" className={`space-y-s ${className}`}>
      {Array.from({ length: count }).map((_, i) => (
        <div
          key={i}
          className="h-12 animate-pulse rounded-lg bg-surfaceVariant motion-reduce:animate-none"
        />
      ))}
    </div>
  );
}

/** A card-grid-shaped placeholder (photo grids, favorite cards). */
export function SkeletonGrid({
  count = 6,
  className = 'grid-cols-2 sm:grid-cols-3',
}: {
  count?: number;
  /** The grid's column classes — mirror the real grid so nothing jumps. */
  className?: string;
}) {
  return (
    <div aria-hidden="true" className={`grid gap-m ${className}`}>
      {Array.from({ length: count }).map((_, i) => (
        <div
          key={i}
          className="h-32 animate-pulse rounded-xl bg-surfaceVariant motion-reduce:animate-none"
        />
      ))}
    </div>
  );
}
