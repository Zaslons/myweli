import { SITE_CONTAINER } from '../../lib/siteGrid';

/// « Le pagne MyWeli »: rows of plaits, black on the page's paper, after the long
/// quiet bands of Baule strip-woven cloth (docs/design/web-swiss-direction.md §4).
/// Its rules are §4.3, held by tests/weave.test.tsx: one motif, the logo once, no
/// text, no animation, and colour only through the theme, so that a dark version
/// is a value swap. It is MyWeli's own drawing, and copy never calls it traditional.
///
/// One tile, 28 high with a 13-high row in it, so a single `<rect>` draws every row:
/// that is what keeps both forms well under the 4 KB §4.7 allows. The ink stays a
/// little clear of the tile's sides: closer, and browsers wrap a pale sliver of it
/// round to the far side, which shows at the end of each row.
function Plaits({ id, x = 0, y = 0 }: { id: string; x?: number; y?: number }) {
  return (
    <pattern
      id={id}
      width="10"
      height="28"
      patternUnits="userSpaceOnUse"
      patternTransform={`translate(${x} ${y})`}
    >
      <path
        d="M1.4 2L4.6 5.2M6 11L8.8 8.2"
        fill="none"
        className="stroke-primary"
        strokeWidth="1.9"
        strokeLinecap="round"
      />
    </pattern>
  );
}

/// The mark exactly as `public/brand/myweli_mark_black.svg` draws it: its path,
/// its viewBox and its stroke, placed rather than redrawn (§3).
function Mark({ x, y, height }: { x: number; y: number; height: number }) {
  return (
    <svg x={x} y={y} width={(height * 186) / 296} height={height} viewBox="357.0 112.0 186.0 296.0">
      <path
        d="M389.58 145.00 L450.00 205.42 L510.42 145.00 L510.42 375.00 L450.00 314.58 L389.58 375.00 Z"
        fill="none"
        className="stroke-primary"
        strokeWidth="28.85"
        strokeLinejoin="round"
        strokeLinecap="round"
      />
    </svg>
  );
}

/// The hero from `lg`. Fills its positioned parent, is scaled by its width and cut
/// at the bottom like cloth off a roll, so nothing is ever cut down its side. The
/// rows end on the viewBox's right edge, so they end where the page's container does.
export function WovenPanel() {
  const fill = 'url(#weave-panel)';
  return (
    <svg
      data-weave="panel"
      aria-hidden="true"
      focusable="false"
      viewBox="0 0 285 840"
      preserveAspectRatio="xMinYMin slice"
      className="absolute inset-0 h-full w-full"
    >
      <defs>
        <Plaits id="weave-panel" x={15} y={18} />
      </defs>
      <rect x="15" y="18" width="270" height="112" fill={fill} />
      <rect x="15" y="130" width="180" height="84" fill={fill} />
      <rect x="15" y="214" width="270" height="626" fill={fill} />
      <Mark x={216.65} y={124.5} height={85} />
    </svg>
  );
}

/// The hero below `lg`: three rows and the mark, flush with the container's edges.
/// Past a phone's width it stops growing (`sm:max-w-lg`): drawn wider, the motif stops
/// being texture, which is §4.3's rule 4.
export function WovenBand() {
  return (
    <svg
      data-weave="band"
      aria-hidden="true"
      focusable="false"
      viewBox="0 0 270 69"
      className="block h-auto w-full sm:max-w-lg"
    >
      <defs>
        <Plaits id="weave-band" />
      </defs>
      <rect width="210" height="69" fill="url(#weave-band)" />
      <Mark x={232} y={1} height={67} />
    </svg>
  );
}

/// The band on its own row, on the site's container, with a row rule under it.
export function WovenBandRow({ className = '' }: { className?: string }) {
  return (
    <div className={`border-b border-divider ${className}`}>
      <div className={`${SITE_CONTAINER} py-m`}>
        <WovenBand />
      </div>
    </div>
  );
}
