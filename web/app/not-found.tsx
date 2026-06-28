export default function NotFound() {
  return (
    <main className="mx-auto max-w-3xl px-m py-xxl text-center">
      <h1 className="text-3xl font-semibold text-textPrimary">
        Page introuvable
      </h1>
      <p className="mt-m text-textSecondary">
        Ce salon ou cette page n’existe pas (ou plus).
      </p>
      <a
        href="/"
        className="mt-l inline-flex items-center justify-center rounded-lg bg-primary px-l py-s text-sm font-medium text-secondary"
      >
        Retour à l’accueil
      </a>
    </main>
  );
}
