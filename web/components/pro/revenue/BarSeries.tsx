'use client';

import { type KeyboardEvent, type PointerEvent, useRef, useState } from 'react';

export type BarPoint = {
  value: number;
  /// Under the chart: the first, middle and last buckets (« 1er nov. »).
  axisLabel: string;
  /// The line above the chart when the bar is chosen
  /// (« mar. 4 nov. · 45 000 FCFA · 2 rendez-vous »).
  sentence: string;
};

/// « Évolution » — « Réalisé » per bucket (docs/design/pro-revenue-
/// analytics.md §4.6, §5.1, §12.1, §22). The web twin of the app's
/// `BarSeries`, and drawn the same way: **plain boxes in a row**, no chart
/// library, nothing repainted per frame.
///
/// - **The pointer chooses the nearest bar** — hovering with a mouse, or
///   pressing and dragging sideways on a touch screen — so a 6px bar (31 on
///   a phone) is still easy to reach; a vertical swipe scrolls the page.
///   Leaving the chart with the mouse clears it.
/// - **A chosen bar is told by its fill, not an outline**: it stays
///   `primary`, the others turn `borderStrong`. A `borderFocus` outline would
///   be black on a black bar.
/// - **One focusable element, an ARIA slider** (§22 precision): ← / → (and ↑
///   / ↓, Début, Fin) move between the bars, Échap returns to the period's
///   total, and a screen reader hears each bar's sentence as the slider's
///   value. An image is not operable (and jsx-a11y refuses a tab stop on
///   one); no bar is its own button — 31 of them would be 6px targets.
/// - The line above the chart is for the eye: the slider already speaks it,
///   so it is not a live region (that would say every bar twice).
export function BarSeries({
  points,
  summary,
  label = 'Évolution du réalisé',
}: {
  points: BarPoint[];
  /// What the line says with no bar chosen: the period's total.
  summary: string;
  label?: string;
}) {
  const [selected, setSelected] = useState<number | null>(null);
  const area = useRef<HTMLDivElement>(null);
  const n = points.length;
  const max = points.reduce((m, p) => (p.value > m ? p.value : m), 0);
  const line = selected == null ? summary : points[selected].sentence;

  function selectAt(clientX: number) {
    const box = area.current?.getBoundingClientRect();
    if (!box || box.width <= 0 || n === 0) return;
    const i = Math.floor(((clientX - box.left) / box.width) * n);
    setSelected(Math.min(n - 1, Math.max(0, i)));
  }

  function onKeyDown(e: KeyboardEvent<HTMLDivElement>) {
    let next: number | null | undefined;
    switch (e.key) {
      case 'ArrowRight':
      case 'ArrowUp':
        next = selected == null ? 0 : Math.min(n - 1, selected + 1);
        break;
      case 'ArrowLeft':
      case 'ArrowDown':
        next = selected == null ? n - 1 : Math.max(0, selected - 1);
        break;
      case 'Home':
        next = 0;
        break;
      case 'End':
        next = n - 1;
        break;
      case 'Escape':
        next = null;
        break;
      default:
        return;
    }
    // The page's own ← / → step the period: not while the chart has them.
    e.preventDefault();
    e.stopPropagation();
    setSelected(next);
  }

  function onPointerDown(e: PointerEvent<HTMLDivElement>) {
    if (e.pointerType !== 'mouse') {
      // Keep the finger's drag on the chart, not on the page's scroll.
      e.currentTarget.setPointerCapture?.(e.pointerId);
    }
    selectAt(e.clientX);
  }

  function onPointerMove(e: PointerEvent<HTMLDivElement>) {
    if (e.pointerType === 'mouse' || e.buttons !== 0) selectAt(e.clientX);
  }

  const axis = [
    n > 0 ? points[0].axisLabel : null,
    n > 2 ? points[Math.floor(n / 2)].axisLabel : null,
    n > 1 ? points[n - 1].axisLabel : null,
  ];

  return (
    <div>
      <p aria-hidden="true" className="text-bodyMedium text-textPrimary">
        {line}
      </p>
      <div
        ref={area}
        role="slider"
        tabIndex={0}
        aria-label={label}
        aria-orientation="horizontal"
        aria-valuemin={0}
        aria-valuemax={n}
        aria-valuenow={selected == null ? 0 : selected + 1}
        aria-valuetext={line}
        onKeyDown={onKeyDown}
        onPointerDown={onPointerDown}
        onPointerMove={onPointerMove}
        onPointerLeave={(e) => {
          if (e.pointerType === 'mouse') setSelected(null);
        }}
        // `touch-pan-y`: a vertical swipe still scrolls the page; only a
        // horizontal drag chooses a bar (the app's own split).
        className="mt-s flex h-40 cursor-pointer touch-pan-y select-none items-end border-b border-divider"
      >
        {points.map((p, i) => {
          // A non-zero bucket is always seen: at least a sliver.
          const pct = max > 0 && p.value > 0 ? Math.max(2, (p.value / max) * 100) : 0;
          const chosen = selected == null || selected === i;
          return (
            <div
              key={i}
              // 1px of transparent border each side: a 2px gap between bars
              // at any width, as the app's (no 2px spacing token exists).
              className={`flex-1 rounded-t-sm border-x border-transparent bg-clip-padding ${
                chosen ? 'bg-primary' : 'bg-borderStrong'
              }`}
              style={{ height: `${pct}%` }}
            />
          );
        })}
      </div>
      <div
        aria-hidden="true"
        className="mt-xs flex justify-between gap-s text-bodySmall text-textTertiary"
      >
        {axis.map((a, i) => (
          <span key={i}>{a ?? ''}</span>
        ))}
      </div>
    </div>
  );
}

/// « Voir les données » — the chart as a table (§5.1): the form zoomed text
/// and anyone who prefers it read.
export function BarSeriesTable({
  rows,
}: {
  rows: { key: string; date: string; amount: string; count: string }[];
}) {
  return (
    <div className="overflow-x-auto">
      <table className="w-full text-left text-bodyMedium">
        <caption className="sr-only">Évolution du réalisé</caption>
        <thead>
          <tr className="border-b border-divider text-bodySmall text-textTertiary">
            <th scope="col" className="py-s pr-m font-normal">
              Date
            </th>
            <th scope="col" className="py-s pr-m text-right font-normal">
              Réalisé
            </th>
            <th scope="col" className="py-s text-right font-normal">
              Rendez-vous
            </th>
          </tr>
        </thead>
        <tbody>
          {rows.map((r) => (
            <tr key={r.key} className="border-b border-divider last:border-b-0">
              <th scope="row" className="py-s pr-m font-normal text-textPrimary">
                {r.date}
              </th>
              <td className="whitespace-nowrap py-s pr-m text-right text-textPrimary">
                {r.amount}
              </td>
              <td className="whitespace-nowrap py-s text-right text-textSecondary">{r.count}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}
