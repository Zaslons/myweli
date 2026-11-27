import type { RevenueDelta } from '../../../lib/pro/revenue-wording';

/// A change against the comparison (docs/design/pro-revenue-analytics.md
/// §3.6, §12.1): an arrow and the signed text, in `success` / `error` by the
/// figure's good direction, `textSecondary` for « stable ». **Never colour
/// alone**: the arrow and the sign carry the direction, and the tile or the
/// row says the sentence to a screen reader (`delta.spoken`).
export function DeltaBadge({
  delta,
  className = '',
}: {
  delta: RevenueDelta;
  className?: string;
}) {
  const color =
    delta.tone === 'good'
      ? 'text-success'
      : delta.tone === 'bad'
        ? 'text-error'
        : 'text-textSecondary';
  return (
    <span
      className={`inline-flex items-center gap-xs whitespace-nowrap text-labelMedium font-medium ${color} ${className}`}
    >
      {delta.up === null ? null : <span aria-hidden="true">{delta.up ? '↑' : '↓'}</span>}
      <span>{delta.text}</span>
    </span>
  );
}
