/// The way out of a booking refusal, for the refusals that have one
/// (SYSTEM.md §12, §21 row 82).
///
/// **Why a table and not an `if` at the call site.** §12 requires an error
/// state to offer a way out, and the temptation is to attach one wherever an
/// error is shown. That is wrong here in a specific way: for `slot_unavailable`
/// the way out is another *time at this salon*, so a « Découvrir des salons »
/// button would send the client away from the booking they were making. Only a
/// salon that is not live has "another salon" as its answer, and keeping that
/// judgement in one place is what stops it drifting between the two surfaces
/// that render it.
///
/// Mirrors `bookingErrorCta` in `web/lib/booking/window.ts` — same codes, same
/// label, same destination — so a client meets one product on either surface.
/// The web twin is the reason this is a free function rather than a method:
/// `core/utils/team_error_messages.dart` set the precedent of one table shared
/// by the mock and the API service so copy cannot drift between backends.
library;

import 'package:flutter/material.dart';

/// A label and the route it goes to, or `null` when retrying *here* is the
/// right answer.
class BookingErrorCta {
  const BookingErrorCta({required this.label, required this.href});

  final String label;
  final String href;
}

/// The way out, as a value.
///
/// Named so that surfaces which are NOT refusals can reuse the phrase without
/// calling [bookingErrorCta] — whose whole argument is that it answers for two
/// booking codes and `null` for everything else. Reuse the words, not the
/// function; §17's « one way to say a thing » is about the words.
const kDiscoverSalonsCta = BookingErrorCta(
  label: 'Découvrir des salons',
  href: '/',
);

BookingErrorCta? bookingErrorCta(String? code) {
  // `provider_not_found` joined the two booking codes with Decision C. Before
  // the closure it only ever meant « you sent garbage »; now it is also what a
  // client legitimately holding a stale link receives from `/availability`, and
  // the funnel rendered « Une erreur est survenue. » beside a « Réessayer »
  // that could never succeed — row 82's headline sentence, back, in the funnel
  // the slice was meant to fix.
  if (code == 'provider_not_found' ||
      code == 'provider_not_published' ||
      code == 'provider_suspended') {
    // The phrase already ships — web's `AccountClient` uses it in two empty
    // states. §17 says the product has one way to say a thing, so this reuses
    // « Découvrir des salons » rather than minting « Découvrir d'autres
    // salons », which is what the spec first drafted.
    return kDiscoverSalonsCta;
  }
  return null;
}

/// What a surface tells a client whose salon has stopped, from the salon's
/// `status` rather than from a refusal code.
///
/// **The tense carries the distinction** (`salon-state-and-refusals.md` §6):
/// « pas encore » for a salon that has never published, « ne … plus » for one
/// that has been stopped. Both sentences already ship in
/// `api_appointment_service._messageFor` for the booking refusals — this is
/// the same product fact reached from the other direction, so it must be the
/// same words. Null while the salon is live.
///
/// `status` is nullable and null means LIVE: seeded salons carry no stored
/// status and Postgres reads NULL as active.
String? salonStoppedMessage(String? status) => switch (status) {
  'draft' => 'Ce salon n’accepte pas encore de réservations en ligne.',
  'suspended' => 'Ce salon ne prend plus de rendez-vous sur Myweli.',
  _ => null,
};

/// §6 cell 5 — what a client is told when a salon page will not load because
/// the salon is gone.
///
/// **Status-agnostic BY CONSTRUCTION.** The 404 carries no status — hidden and
/// nonexistent are indistinguishable on purpose (T51's no-oracle rule) — so
/// this is the one sentence that cannot use the tense-carrying pair
/// [salonStoppedMessage] offers a surface that already holds the salon.
///
/// It lived in two files before PR1d (`api_provider_service.dart` and
/// `provider_provider.dart`) — §21 row 84's pattern at count two, caught before
/// it reached three.
const kSalonUnavailableMessage = 'Ce salon n’est plus disponible sur Myweli.';

/// The RETRYABLE sibling. Shaped after `kSlotsError` deliberately (§17, one
/// voice): « Impossible de charger X. Vérifiez votre connexion. »
const kSalonLoadError =
    'Impossible de charger ce salon. Vérifiez votre '
    'connexion.';

/// The §12 error state for a screen whose whole subject is one salon.
///
/// **The distinction §12 actually cares about.** `not_found` has no retry that
/// can succeed — the salon is not coming back this session — and its way out is
/// another salon. `network` and `server_error` are exactly the case where
/// « Réessayer » is the right control. Telling them apart by comparing French
/// sentences is how `'Salon introuvable'` became dead code that never rendered;
/// the code has been on the wire since PR1c and nothing read it.
///
/// The default arm RETRIES on purpose: an unrecognised failure is not proof
/// that retrying is futile, and §12's rule is « a retry only when retrying can
/// succeed », not « a retry only when we are certain ».
class SalonLoadFailure {
  const SalonLoadFailure({required this.message, required this.icon, this.cta});

  final String message;
  final IconData icon;

  /// Non-null means there is somewhere else to go, and therefore no retry.
  final BookingErrorCta? cta;

  bool get canRetry => cta == null;
}

SalonLoadFailure salonLoadFailure(String? errorCode) => switch (errorCode) {
  'not_found' => const SalonLoadFailure(
    message: kSalonUnavailableMessage,
    // Not `error_outline`: nothing broke. A salon left, which is a state, not
    // a fault — §12's four states, not an exception.
    icon: Icons.storefront_outlined,
    cta: kDiscoverSalonsCta,
  ),
  _ => const SalonLoadFailure(message: kSalonLoadError, icon: Icons.wifi_off),
};
