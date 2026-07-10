/// Primary "Réserver" CTA → the on-page web booking funnel (`/<slug>/reserver`).
/// `disabled` = the owner's pre-publish preview (drafts refuse bookings).
export function BookingCta({
  slug,
  className = '',
  disabled = false,
}: {
  slug: string;
  className?: string;
  disabled?: boolean;
}) {
  if (disabled) {
    return (
      <button
        type="button"
        disabled
        title="Disponible après la mise en ligne"
        className={
          'inline-flex cursor-not-allowed items-center justify-center rounded-lg ' +
          `bg-primary/40 px-l py-s text-sm font-medium text-secondary ${className}`
        }
      >
        Réserver
      </button>
    );
  }
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
