'use client';

import { Button } from './Button';

/// The shared error state (§12, B6): "a human French message + a RETRY
/// control. An error state without a way out is a crash with better manners."
///
/// Before B6, 12 sites returned a bare one-line alert whose copy said
/// « Réessayez. » and shipped NO retry control — and the 15 pro error states
/// replaced their whole page INCLUDING its h1 (B5 recorded the debt against
/// this component). 7 sites had hand-rolled the correct shape; this is that
/// shape, generalized.
///
/// `title` renders the PAGE h1 — full-page error states pass their page title
/// so the heading skeleton survives the error (§4: one h1 per page, every
/// state). Section-level errors omit it.
export function ErrorState({
  title,
  message = 'Une erreur est survenue. Réessayez.',
  onRetry,
  className = '',
}: {
  /** The page title — renders as the h1 for full-page error states. */
  title?: string;
  message?: string;
  onRetry?: () => void;
  className?: string;
}) {
  return (
    <div className={className}>
      {title ? (
        <h1 className="text-headlineSmall font-semibold text-textPrimary">
          {title}
        </h1>
      ) : null}
      <p role="alert" className={`text-bodyMedium text-error ${title ? 'mt-m' : ''}`}>
        {message}
      </p>
      {onRetry ? (
        <div className="mt-m">
          <Button variant="secondary" onClick={onRetry}>
            Réessayer
          </Button>
        </div>
      ) : null}
    </div>
  );
}
