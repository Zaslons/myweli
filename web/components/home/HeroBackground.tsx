/// Decorative, on-brand hero backdrop — monochrome surfaces only (color stays
/// reserved for actions/status). Lightweight inline SVG; swapped for real
/// photography at the content phase.
export function HeroBackground() {
  return (
    <svg
      aria-hidden="true"
      className="pointer-events-none absolute inset-0 h-full w-full"
      viewBox="0 0 1200 480"
      preserveAspectRatio="xMidYMid slice"
    >
      <rect width="1200" height="480" className="fill-secondary" />
      <circle cx="1000" cy="60" r="260" className="fill-surfaceVariant" />
      <circle cx="1140" cy="400" r="150" className="fill-surface" />
      <circle cx="90" cy="440" r="210" className="fill-surfaceVariant" opacity="0.65" />
      <path
        d="M0,360 C320,300 640,430 1200,320"
        className="stroke-border"
        strokeWidth="1.5"
        fill="none"
        opacity="0.5"
      />
      <path
        d="M0,250 C360,210 720,300 1200,210"
        className="stroke-divider"
        strokeWidth="1"
        fill="none"
        opacity="0.5"
      />
    </svg>
  );
}
