/// The shared loading state (§12, B6) — the spinner for when the result's
/// SHAPE IS NOT KNOWN (forms, single-record detail, maps). When the shape IS
/// known (a list, a grid), use <Skeleton> instead — §12: "Skeleton if the
/// shape of the result is known… Spinner only when it is not. Never both."
///
/// Before B6 this was 35 inline « Chargement… » strings, 18 byte-identical.
///
/// Deliberately NOT a live region: B5's doctrine is that regions pre-exist
/// their text, and a loading state is REMOVED when content lands — announcing
/// its disappearance is noise. The spinner is decoration; the label carries
/// the state for everyone.
export function Loading({
  label = 'Chargement…',
  className = '',
}: {
  /** Contextual copy passes through (« Chargement des créneaux… »). */
  label?: string;
  className?: string;
}) {
  return (
    <p
      className={`flex items-center gap-s text-bodyMedium text-textSecondary ${className}`}
    >
      <span
        aria-hidden="true"
        className="inline-flex h-5 w-5 shrink-0 animate-spin rounded-pill border-2 border-current border-t-transparent motion-reduce:animate-none"
      />
      {label}
    </p>
  );
}
