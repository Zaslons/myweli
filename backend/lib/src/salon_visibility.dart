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
/// **The HIDE form, never `status != 'active'`.** Seeded salons carry no
/// `status` key at all and Postgres reads a NULL column as active, so the
/// negative spelling refuses every seeded salon and every in-memory fixture —
/// `booking_service.dart:65-67` records the same trap for the same reason, and
/// `query()` already spells it this way in both repository impls
/// (`providers_repository.dart:152-156`, `postgres_providers_repository.dart:35-37`).
/// `salon_visibility_test.dart` holds the spelling with an assertion instead of
/// a third comment.
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
