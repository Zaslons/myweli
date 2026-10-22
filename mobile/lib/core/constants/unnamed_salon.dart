/// A salon with no name — erased, or not loaded — in the one set of words the
/// app uses for it (docs/design/hygiene-batch9.md §2.9, SYSTEM.md §17.2). There
/// were five: « Salon », « le salon », « votre salon », « ce salon », and an
/// empty string (a card or a row with no title). The web says the same
/// (`web/lib/salon-name.ts`).
library;

/// As a title: a card's or a row's name, a heading, a calendar event's
/// « Rendez-vous — Salon ».
const kUnnamedSalon = 'Salon';

/// In a sentence, a salon the client books with or a member is invited to:
/// « Envoyez l'acompte à le salon » is never written — the sentences that
/// take it are built for it (« à {nom} » → « au salon » is the caller's).
const kUnnamedSalonInSentence = 'le salon';

/// At the start of a sentence: « Le salon vous invite comme Gérant ».
const kUnnamedSalonAtSentenceStart = 'Le salon';

/// In a sentence, the Pro session's own salon: « … perdra l'accès à votre
/// salon ».
const kUnnamedOwnSalon = 'votre salon';

/// The salon's name, or [unnamed] when it has none — null, empty or blank.
/// `?? 'Salon'` alone let an empty name through as an empty title.
String salonNameOr(String? name, String unnamed) =>
    (name == null || name.trim().isEmpty) ? unnamed : name;
