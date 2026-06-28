/// Minimal home placeholder (M2). The full marketing/discovery home + the
/// provider/landing pages arrive in M3+. Token-styled, French, SSR.
export default function HomePage() {
  return (
    <main className="mx-auto max-w-3xl px-m py-xxl">
      <h1 className="text-4xl font-semibold text-textPrimary">
        Réservez votre beauté, en quelques secondes
      </h1>
      <p className="mt-m text-textSecondary">
        Coiffure, barbier, onglerie et spa près de chez vous en Côte d’Ivoire.
        Réservation en ligne, 24/7 — sans appel, sans attente.
      </p>
      <div className="mt-l">
        <a
          href="/"
          className="inline-flex items-center justify-center rounded-lg bg-primary px-l py-s text-sm font-medium text-secondary"
        >
          Découvrir les salons
        </a>
      </div>
    </main>
  );
}
