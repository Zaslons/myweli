import { Card } from '../../Card';
import type { RevenueDelta } from '../../../lib/pro/revenue-wording';
import { DeltaBadge } from './DeltaBadge';

export type KpiTileData = {
  key: string;
  title: string;
  value: string;
  delta?: RevenueDelta | null;
  /// Under the value: « estimé », « 3 absences · 45 000 FCFA », « Prévu »'s
  /// two lines (one per array item).
  caption?: string[] | null;
  /// The tile as one sentence (§12.3): « Réalisé : 1 250 000 FCFA, en
  /// hausse de 12 % par rapport à octobre 2026 ».
  spoken: string;
  /// « Prévu » takes the whole row (§4.5).
  wide?: boolean;
};

/// The figures (docs/design/pro-revenue-analytics.md §4.5, §5.1, §12.1) —
/// the web twin of the app's `KpiGrid`. One tile per row on a phone, two
/// across from `sm`, four from `xl` (« Prévu » always a row of its own).
/// The value never breaks inside an amount (`whitespace-nowrap`); the
/// columns are chosen so the longest figure fits its tile.
export function KpiGrid({ tiles }: { tiles: KpiTileData[] }) {
  return (
    <ul className="grid grid-cols-1 gap-m sm:grid-cols-2 xl:grid-cols-4">
      {tiles.map((t) => (
        <KpiTile key={t.key} tile={t} />
      ))}
    </ul>
  );
}

function KpiTile({ tile }: { tile: KpiTileData }) {
  return (
    <Card as="li" className={tile.wide ? 'sm:col-span-2 xl:col-span-4' : ''}>
      {/* Drawn for the eye; the sentence below is what a screen reader
          hears, in one piece (the app's one semantics node per tile). */}
      <div aria-hidden="true">
        <p className="text-bodySmall text-textSecondary">{tile.title}</p>
        <p className="mt-xs whitespace-nowrap text-titleLarge font-semibold text-textPrimary">
          {tile.value}
        </p>
        {tile.delta ? <DeltaBadge delta={tile.delta} className="mt-xs" /> : null}
        {tile.caption?.map((line) => (
          <p key={line} className="mt-xs text-bodySmall text-textTertiary">
            {line}
          </p>
        ))}
      </div>
      <p className="sr-only">{tile.spoken}</p>
    </Card>
  );
}
