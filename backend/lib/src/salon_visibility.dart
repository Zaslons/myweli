/// Who may see a salon, said once (T51 · Decision C).
///
/// **One primitive, the way `MembershipService.salonForRequest` is one
/// primitive.** Before this file the rule lived in three different spellings —
/// `query()`'s filter in each repository impl and a hand-rolled
/// `provider['status'] == 'draft'` in the by-slug route — and the fourth
/// spelling was the one that was missing: `GET /providers/{id}` had none at
/// all. Every public door now calls this.
///
/// **Why this is not a repository method.** `byId`/`bySlug` must keep returning
/// hidden salons: ~25 internal callers depend on it (publish, admin, the
/// subscription scheduler's unpublish, `/me/provider`, and `BookingService`,
/// which has to READ the status to choose between `provider_not_published` and
/// `provider_suspended`). A filtered sibling would double the interface and
/// invite the wrong one at one of those 25 sites. The doors need a *predicate*,
/// not a *query*.
library;

/// The statuses that hide a salon from every anonymous read.
///
/// **The HIDE form, never `status != 'active'`.** A salon with no `status` at
/// all must stay visible, and the negative spelling would refuse every one of
/// them — `booking_service.dart:65-67` records the same trap for the same
/// reason, and `query()` already spells it this way in both repository impls
/// (`providers_repository.dart:152-156`, `postgres_providers_repository.dart:35-37`).
/// `salon_visibility_test.dart` holds the spelling with an assertion instead of
/// a third comment.
///
/// **Where that trap is real, corrected (Q1).** This paragraph used to say
/// « Postgres reads a NULL column as active ». It does not, and cannot: the
/// column is `NOT NULL DEFAULT 'active'` (0 of 4 seeded rows null, measured),
/// and `postgres_providers_repository.dart:669` folds `?? 'active'` on top of
/// that. So against Postgres a document always carries one of
/// `active | draft | suspended`, and the HIDE and SHOW spellings are
/// **behaviourally identical** — the SHOW form was applied as a mutation and
/// the 47-case funnel e2e stayed green, correctly.
///
/// The status-less document is the **in-memory** repository's, whose fixtures
/// carry no `status` key. That is the environment `salon_visibility_test.dart`
/// runs in, and it is the guard. A live-server test cannot cover this, which is
/// why `backend-q1-funnel-smoke.md` §8 states it as a limit rather than
/// implying otherwise.
///
/// It fails **open**: a fourth status invented tomorrow would be public. That
/// is the right default — a new lifecycle state should not silently vanish from
/// discovery — and the contract's enum is pinned so nobody adds one without
/// reading this.
const hiddenSalonStatuses = {'draft', 'suspended'};

/// May an anonymous caller read this salon document?
///
/// Takes the nullable map straight from `byId`/`bySlug` so a door can ask once:
/// missing and hidden are the same 404, deliberately — T51's rule is that a
/// draft must be **indistinguishable** from a salon that does not exist, or the
/// 404 becomes an enumeration oracle.
bool isPublicSalon(Map<String, dynamic>? salon) =>
    salon != null && !hiddenSalonStatuses.contains(salon['status']);

/// The lifecycle status a client should be told, with the NULL trap resolved
/// **here** so no client resolves it again.
///
/// A consumer holding a booking at a salon needs to know it stopped taking
/// appointments (`salon-state-and-refusals.md` §6), and the moment that fact
/// crosses the wire as a nullable string, every client invents its own default.
/// One of them will spell it `?? 'draft'` and quietly stop a live salon from
/// being booked.
String publicSalonStatus(Map<String, dynamic> salon) =>
    (salon['status'] as String?) ?? 'active';

/// May this client transact with this salon, and if not, what are they told?
///
/// **The refusal `book` spelled inline since row 82, extracted now that
/// `reschedule` needs the identical answer.** Two call sites is where a rule
/// stops being a guard and becomes a spelling, and the spelling is the thing
/// that drifts.
///
/// **Two states, two codes.** They used to share one, `provider_suspended`, for
/// `draft` as well — and no client surface had a sentence for it, so all four
/// fell through to « Une erreur est survenue. » (§21 row 82). The state the code
/// was named for takes a deliberate admin act; the state it was silent about is
/// the one EVERY salon starts in. The client cannot disambiguate for itself
/// either, so the server carries it. Same argument the contract already makes
/// for `beyond_horizon` against `slot_unavailable`: one code that makes every
/// client say the wrong thing is worse than two.
///
/// **Not `status != 'active'`** — the same NULL trap [isPublicSalon] exists for.
///
/// **`bookManual` deliberately does NOT call this.** A salon that has not
/// published yet owns its calendar and refuses only `suspended` (Decision A).
/// That asymmetry is the point of row 82, not an oversight, and folding it in
/// here would silently undo it; `salon_state_refusal_test.dart` holds both
/// halves.
///
/// A missing salon folds to `provider_not_found`, which is what both callers
/// already returned for one — so the extraction is behaviour-identical at each
/// site, and a caller asks one question instead of two.
String? clientBookingRefusal(Map<String, dynamic>? salon) {
  if (salon == null) return 'provider_not_found';
  if (salon['status'] == 'suspended') return 'provider_suspended';
  if (salon['status'] == 'draft') return 'provider_not_published';
  return null;
}
