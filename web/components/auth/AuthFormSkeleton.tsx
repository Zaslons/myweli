import { Skeleton } from '../Skeleton';

/// The reserved shape of the sign-in form, shown while `ConnexionClient` loads.
///
/// **Why this exists.** `/connexion` wrapped its client component in a bare
/// `<Suspense>` — no `fallback`, which means React renders *nothing* in that
/// slot. The server streamed an empty hole and the form dropped into it on
/// hydration, growing `div#contenu` and pushing `header` and `footer`.
/// Production measured **CLS 0.131** against a 0.1 budget, on every run, under
/// mobile/3G emulation. Unthrottled it is 0.000, which is why no local check and
/// no e2e ever saw it.
///
/// **A first attempt fixed the wrong thing** — reserving the Google button's
/// height. That button is one contributor; the hole was the whole form.
///
/// The shape mirrors `LoginOptions`' initial render — phone field, submit,
/// divider, the two SSO buttons — because §12 asks for a skeleton exactly when
/// the result shape is known, and its stated purpose is preventing this jump.
/// `Skeleton` is `aria-hidden`: a picture of layout, not content.
export function AuthFormSkeleton() {
  return (
    // `min-h-72` (288px) is the floor: the hydrated form measures 294px on
    // production at 412px wide, and the shapes below sum to slightly less.
    // The floor is what removes the jump; the shapes are what make the wait
    // legible.
    <div
      className="flex min-h-72 flex-col gap-s"
      data-testid="auth-form-skeleton"
    >
      {/* label + phone field */}
      <Skeleton className="h-4 w-32" />
      <Skeleton className="h-12 w-full" />
      {/* primary action */}
      <Skeleton className="h-12 w-full" />
      {/* « ou » divider */}
      <Skeleton className="mx-auto h-4 w-16" />
      {/* Google, then Apple */}
      <Skeleton className="h-12 w-full" />
      <Skeleton className="h-12 w-full" />
    </div>
  );
}
