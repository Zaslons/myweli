import { ButtonLink } from '../ButtonLink';

/// The home page's door for salons (docs/design/web-pro-access.md P3): the
/// question, what MyWeli Pro gives — only what exists today — and the way to
/// the salons page. A secondary action: the page's own job is booking.
export function ProBand() {
  return (
    <section
      aria-labelledby="pro-band-title"
      className="mt-xl flex flex-col items-start justify-between gap-m rounded-xl border border-border bg-surfaceVariant p-l sm:flex-row sm:items-center"
    >
      <div>
        <h2 id="pro-band-title" className="text-titleLarge font-semibold text-textPrimary">
          Vous êtes un salon ?
        </h2>
        <p className="mt-xs text-bodyLarge text-textSecondary">
          Recevez vos réservations en ligne, 24 h/24, et gérez agenda, équipe et clientèle au même
          endroit.
        </p>
      </div>
      <ButtonLink href="/professionnels" variant="secondary" className="shrink-0">
        Découvrir MyWeli Pro
      </ButtonLink>
    </section>
  );
}
