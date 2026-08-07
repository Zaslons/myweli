/// The one not-found boundary — every `notFound()` in the app renders it:
/// an unknown salon slug, an unknown city, an unknown area, a bogus flat
/// combo, the booking funnel.
///
/// **The body stays the hedge it already was.** Decision C's §6 cell 5 wanted
/// « Ce salon n'est plus disponible sur MyWeli. », and that sentence cannot go
/// here: this page is **identity-agnostic** as well as status-agnostic — it
/// cannot know it was asked for a salon rather than for `/coiffure-nowhere`.
/// « Ce salon ou cette page n'existe pas (ou plus) » already carries the salon
/// case, in the right tense. The precise sentence lives where the surface DOES
/// know: mobile's three landing screens, which fetch one salon by id.
///
/// **The CTA unified in PR1d.** It read « Retour à l'accueil » while mobile and
/// both booking refusals said « Découvrir des salons » — same destination, two
/// labels, which is §21 row 84's pattern. One phrase now (§17).
export default function NotFound() {
  return (
    <main className="mx-auto max-w-3xl px-m py-xxl text-center">
      <h1 className="text-headlineMedium font-semibold text-textPrimary">
        Page introuvable
      </h1>
      <p className="mt-m text-bodyLarge text-textSecondary">
        Ce salon ou cette page n’existe pas (ou plus).
      </p>
      <a
        href="/"
        className="mt-l inline-flex items-center justify-center rounded-lg bg-primary px-l py-s text-labelLarge font-medium text-secondary"
      >
        Découvrir des salons
      </a>
    </main>
  );
}
