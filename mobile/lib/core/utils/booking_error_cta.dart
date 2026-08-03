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

/// A label and the route it goes to, or `null` when retrying *here* is the
/// right answer.
class BookingErrorCta {
  const BookingErrorCta({required this.label, required this.href});

  final String label;
  final String href;
}

BookingErrorCta? bookingErrorCta(String? code) {
  if (code == 'provider_not_published' || code == 'provider_suspended') {
    // The phrase already ships — web's `AccountClient` uses it in two empty
    // states. §17 says the product has one way to say a thing, so this reuses
    // « Découvrir des salons » rather than minting « Découvrir d'autres
    // salons », which is what the spec first drafted.
    return const BookingErrorCta(label: 'Découvrir des salons', href: '/');
  }
  return null;
}
