/// The two values an erased identity leaves behind (L1 —
/// docs/design/account-deletion-erasure.md §5).
///
/// **Neither value is new; only their home is.** `'Client'` has been the neutral
/// label since MP2 in two places that never knew about each other —
/// `postgres_clients_repository.dart`'s T48 anonymisation, and
/// `reviews_service.dart`'s fallback author name for a reviewer with no name on
/// file. Both now reference this.
///
/// That is deliberate, and it is the mutation hook the erasure gate leans on:
/// change [anonymousClientLabel] and the reviews assertion **and** the
/// salon-clients assertion fail together, which is the only way to prove one
/// source feeds both. Two literals that happen to be spelled the same prove
/// nothing.
library;

/// The display name an erased person leaves on records that survive them — a
/// salon's client card, a review's author line.
const String anonymousClientLabel = 'Client';

/// The tombstone `user_id` written over an erased reviewer.
///
/// **Not `NULL`, and the reason is three surfaces deep.** `reviews.user_id` is
/// `text NOT NULL` (`migrations.dart:226`), the DTO is required, and
/// `mobile/lib/models/review.dart` types it as a non-nullable `String`. A NULL
/// would need a migration *plus* an OpenAPI change *plus* a `schema.ts`
/// regeneration *plus* a mobile model change — and mobile ships on its own
/// cadence, so **the app already in the store would crash on the first
/// anonymised review** until users updated. A tombstone costs nothing and breaks
/// nobody.
///
/// It is not a valid user id, so it can never collide with a live account or be
/// resolved back to one.
const String deletedUserId = '__deleted__';
