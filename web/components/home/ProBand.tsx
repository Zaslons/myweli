import { ButtonLink } from '../ButtonLink';
import { SiteSection } from '../SiteSection';

/// The home page's door for salons (docs/design/web-pro-access.md P3): the
/// question, what MyWeli Pro gives — only what exists today — and the way to
/// the salons page. A secondary action: the page's own job is booking.
export function ProBand() {
  return (
    <SiteSection title="Vous êtes un salon ?" titleId="pro-band-title">
      <div className="flex flex-col items-start gap-m lg:flex-row lg:items-center lg:justify-between lg:gap-l">
        <p className="max-w-content text-bodyLarge text-textSecondary">
          {/* A no-break space: « 24 h/24 » must not split across lines. */}
          Recevez vos réservations en ligne, 24&nbsp;h/24, et gérez agenda, équipe et clientèle au
          même endroit.
        </p>
        <ButtonLink href="/professionnels" variant="secondary" className="shrink-0">
          Découvrir MyWeli Pro
        </ButtonLink>
      </div>
    </SiteSection>
  );
}
