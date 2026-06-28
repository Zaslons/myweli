/// Primary "Réserver" CTA. Interim (pre-M5): routes to the app/install (the web
/// booking funnel is M5, which swaps this to `/<slug>/reserver`).
export function BookingCta({ className = '' }: { className?: string }) {
  const href =
    process.env.NEXT_PUBLIC_ANDROID_APP_URL ??
    process.env.NEXT_PUBLIC_IOS_APP_URL ??
    '#';
  return (
    <a
      href={href}
      className={
        'inline-flex items-center justify-center rounded-lg bg-primary px-l py-s ' +
        `text-sm font-medium text-secondary hover:bg-primaryLight ${className}`
      }
    >
      Réserver
    </a>
  );
}
