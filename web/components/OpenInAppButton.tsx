/// "Ouvrir dans l'app" — contextual install/open push (WEB-DESIGN-STANDARDS §7).
/// Store/deep-link URLs come from env (filled at the accounts phase).
export function OpenInAppButton({ className = '' }: { className?: string }) {
  const href =
    process.env.NEXT_PUBLIC_ANDROID_APP_URL ??
    process.env.NEXT_PUBLIC_IOS_APP_URL ??
    '#';
  return (
    <a
      href={href}
      className={
        'inline-flex items-center justify-center rounded-lg border border-border ' +
        'bg-secondary px-l py-s text-sm font-medium text-textPrimary ' +
        `hover:bg-surfaceVariant ${className}`
      }
    >
      Ouvrir dans l’app
    </a>
  );
}
