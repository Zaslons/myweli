/// Primary "Réserver" CTA → the on-page web booking funnel (`/<slug>/reserver`).
export function BookingCta({
  slug,
  className = '',
}: {
  slug: string;
  className?: string;
}) {
  return (
    <a
      href={`/${slug}/reserver`}
      className={
        'inline-flex items-center justify-center rounded-lg bg-primary px-l py-s ' +
        `text-sm font-medium text-secondary hover:bg-primaryLight ${className}`
      }
    >
      Réserver
    </a>
  );
}
