/// A salon with no name — erased, or not loaded — in the one set of words the
/// web uses for it, the app's (`mobile/lib/core/constants/unnamed_salon.dart`;
/// docs/design/hygiene-batch9.md §2.9, WEB-SYSTEM.md). The web had « Salon »,
/// « ce salon », « MyWeli », and an empty string that printed « — votre
/// planning » with nothing before it.

/// As a title: a card's or a row's name, a heading, « Rendez-vous — Salon ».
export const UNNAMED_SALON = 'Salon';

/// In a sentence, a salon the client books with or a member joins.
export const UNNAMED_SALON_IN_SENTENCE = 'le salon';

/// At the start of a sentence: « Le salon vous invite comme Gérant ».
export const UNNAMED_SALON_AT_SENTENCE_START = 'Le salon';

/// In a sentence, the Pro session's own salon: « … perdra l'accès à votre
/// salon ».
export const UNNAMED_OWN_SALON = 'votre salon';

/// The salon's name, or [unnamed] when it has none — null, undefined, empty
/// or blank. `?? 'Salon'` alone let an empty name through as an empty title.
export function salonNameOr(name: string | null | undefined, unnamed: string): string {
  return name && name.trim() ? name : unnamed;
}

/// The Collaborateur's « Aujourd'hui » title: « {salon} — votre planning »,
/// or « Votre planning » alone when the salon has no name.
export function staffPlanningTitle(name: string | null | undefined): string {
  return name && name.trim() ? `${name} — votre planning` : 'Votre planning';
}
