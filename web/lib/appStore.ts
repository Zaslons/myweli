/// The one place that decides whether there is an app to send anyone to.
///
/// **Three call sites read these env vars, and two of them promised an app they
/// could not deliver.** `OpenInAppButton` and `AppInstallBanner` each correctly
/// rendered no LINK when the store URLs are unset — the apps are not listed yet
/// — but the surrounding copy stayed:
///
///   homepage  « L'app MyWeli — Réservez plus vite et gérez vos rendez-vous
///               depuis votre poche. »   …and no button under it
///   banner    « Réservez plus vite — téléchargez l'app MyWeli. »
///               …and a dismiss button, nothing to download
///
/// Verified live on production 2026-08-21: the homepage section renders, and
/// `apps.apple.com` / `play.google.com` appear nowhere in the document. A
/// visitor reads an offer and finds no way to take it.
///
/// The per-component guard could not see this, because the orphan is the
/// WRAPPER — `open-in-app.test.tsx` renders the button in isolation and passes
/// while the section around it promises an app. Exporting the condition lets
/// the wrapper ask the same question the button does.
export function appStoreUrl(): string | null {
  return (
    process.env.NEXT_PUBLIC_ANDROID_APP_URL ??
    process.env.NEXT_PUBLIC_IOS_APP_URL ??
    null
  );
}
