/// "Ouvrir dans l'app" — contextual install/open push (WEB-DESIGN-STANDARDS §7).
/// Store/deep-link URLs come from env (filled at the accounts phase).
export function OpenInAppButton({ className = '' }: { className?: string }) {
  // No '#' fallback — the same reasoning `AppInstallBanner` already applies:
  // an <a href="#"> is a dead link wearing a CTA. Production served exactly
  // that on the homepage until 2026-08-20, because the store URLs do not exist
  // until the apps are listed. Render nothing until there is somewhere to go.
  const href =
    process.env.NEXT_PUBLIC_ANDROID_APP_URL ??
    process.env.NEXT_PUBLIC_IOS_APP_URL ??
    null;
  if (!href) return null;
  return (
    <a
      href={href}
      className={
        'inline-flex items-center justify-center rounded-lg border border-border ' +
        'bg-secondary px-l py-s text-labelLarge font-medium text-textPrimary ' +
        `hover:bg-surfaceVariant ${className}`
      }
    >
      Ouvrir dans l’app
    </a>
  );
}
