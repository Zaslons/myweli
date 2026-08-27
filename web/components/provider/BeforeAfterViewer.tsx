'use client';

import Image from 'next/image';
import { useState } from 'react';
import type { Provider } from '../../lib/api/providers';
import { Modal } from '../Modal';

type Pair = NonNullable<Provider['beforeAfters']>[number];

/// The drag-reveal comparator (docs/design/web-provider-before-after.md) —
/// the app's `BeforeAfterSlider`, web-adapted. The AFTER image is the
/// full-bleed base; the BEFORE image sits above it, clipped from the left up
/// to the handle — dragging right reveals more « avant ».
///
/// **The control is a native `<input type="range">`**, full-bleed and
/// transparent except for its thumb (the visible handle, styled in
/// `globals.css` `.myweli-ba`): pointer scrub, touch, click-jumps-to-position
/// and arrow keys are all native — the app's absolute-position drag plus the
/// keyboard path Flutter's `Semantics(slider:)` never had. The reveal clip
/// and the rule ride inline styles: the values are per-frame dynamic, and
/// arbitrary Tailwind values are lint errors by design.
function Comparator({
  pair,
  value,
  onChange,
  heightClass,
}: {
  pair: Pair;
  value: number;
  onChange: (v: number) => void;
  heightClass: string;
}) {
  return (
    <div
      className={`relative w-full overflow-hidden rounded-lg ${heightClass}`}
    >
      <Image
        src={pair.after}
        alt=""
        fill
        loading="lazy"
        sizes="(min-width: 640px) 50vw, 100vw"
        className="object-cover"
      />
      <div
        aria-hidden="true"
        className="absolute inset-0"
        style={{ clipPath: `inset(0 ${100 - value}% 0 0)` }}
      >
        <Image
          src={pair.before}
          alt=""
          fill
          loading="lazy"
          sizes="(min-width: 640px) 50vw, 100vw"
          className="object-cover"
        />
      </div>
      {/* The rule under the thumb — decorative; the range carries the name. */}
      <div
        aria-hidden="true"
        className="absolute inset-y-0 w-px bg-secondary"
        style={{ left: `${value}%` }}
      />
      {/* Corner tags — aria-hidden for the app's ExcludeSemantics reason: the
          slider's own label already says avant/après, and the tags must not
          leak into its accessible name. */}
      <span
        aria-hidden="true"
        className="absolute bottom-s left-s rounded-pill bg-primary/60 px-s py-xs text-bodySmall text-secondary"
      >
        Avant
      </span>
      <span
        aria-hidden="true"
        className="absolute bottom-s right-s rounded-pill bg-primary/60 px-s py-xs text-bodySmall text-secondary"
      >
        Après
      </span>
      <input
        type="range"
        min={0}
        max={100}
        value={value}
        onChange={(e) => onChange(Number(e.target.value))}
        aria-label="Comparateur avant/après"
        aria-valuetext={`${value} %`}
        className="myweli-ba absolute inset-0 h-full w-full"
      />
    </div>
  );
}

/// The fullscreen copy gets its own reveal state, like the app's fullscreen
/// dialog mounts its own slider — the inline and enlarged comparisons are
/// separate gestures, not one shared position.
function FullscreenComparator({ pair }: { pair: Pair }) {
  const [value, setValue] = useState(50);
  return (
    <Comparator
      pair={pair}
      value={value}
      onChange={setValue}
      heightClass="h-64 sm:h-96"
    />
  );
}

export function BeforeAfterViewer({ pairs }: { pairs: Pair[] }) {
  // A pair missing either image cannot compare — skipped, like the app.
  const valid = pairs.filter((p) => p.before && p.after);
  const [index, setIndex] = useState(0);
  // 50 — dead centre, the state the SSR renders. Switching pairs keeps the
  // position (the app's slider state survives a pair switch too).
  const [value, setValue] = useState(50);
  const [open, setOpen] = useState(false);
  if (valid.length === 0) return null;
  const pair = valid[Math.min(index, valid.length - 1)];

  return (
    <figure className="rounded-lg border border-border bg-secondary p-s">
      <Comparator
        pair={pair}
        value={value}
        onChange={setValue}
        heightClass="h-56 sm:h-80"
      />
      {pair.caption ? (
        <figcaption className="mt-s text-bodyMedium text-textSecondary">
          {pair.caption}
        </figcaption>
      ) : null}
      <div className="flex flex-wrap items-center justify-between gap-s">
        {/* The app's hint, minus its « toucher pour agrandir » half — that
            gesture is the NAMED button beside it here, because tap-on-image
            would fight the range's own click-jumps-to-position. */}
        <p className="text-bodySmall text-textTertiary">Glisser pour comparer</p>
        <button
          type="button"
          onClick={() => setOpen(true)}
          className="min-h-12 text-bodyMedium text-textTertiary underline"
        >
          Agrandir
        </button>
      </div>
      {valid.length > 1 ? (
        <ul className="mt-xs flex gap-s overflow-x-auto">
          {valid.map((p, i) => (
            <li key={`${p.before}-${i}`} className="shrink-0">
              <button
                type="button"
                aria-label={`Comparaison ${i + 1}`}
                aria-pressed={i === index}
                onClick={() => setIndex(i)}
                className={`relative block h-14 w-20 overflow-hidden rounded-sm border-2 ${
                  i === index ? 'border-primary' : 'border-borderStrong'
                }`}
              >
                <Image
                  src={p.after}
                  alt=""
                  fill
                  loading="lazy"
                  sizes="80px"
                  className="object-cover"
                />
              </button>
            </li>
          ))}
        </ul>
      ) : null}
      {open ? (
        <Modal
          label={pair.caption ?? 'Comparaison avant/après'}
          onClose={() => setOpen(false)}
          panelClassName="w-full max-w-3xl rounded-xl border border-border bg-secondary p-m"
        >
          <FullscreenComparator pair={pair} />
          {pair.caption ? (
            <p className="mt-s text-bodyMedium text-textSecondary">
              {pair.caption}
            </p>
          ) : null}
          <div className="mt-m flex justify-end">
            <button
              type="button"
              aria-label="Fermer"
              onClick={() => setOpen(false)}
              className="flex min-h-12 min-w-12 items-center justify-center rounded-pill border border-borderStrong bg-surface text-iconXS text-textPrimary"
            >
              ✕
            </button>
          </div>
        </Modal>
      ) : null}
    </figure>
  );
}
