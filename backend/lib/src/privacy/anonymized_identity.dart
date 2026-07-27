/// The two values an erased identity leaves behind (L1 —
/// docs/design/account-deletion-erasure.md §5).
///
/// **Neither value is new; only their home is.** `'Client'` has been the neutral
/// label since MP2 in several places that never knew about each other — the two
/// migrated here, plus `clients_service.dart:355,370` and the `migrations.dart`
/// backfill at `:615,633` that CREATES the rows, which are left alone because a
/// migration's literal is a historical record, not a live default —
/// `postgres_clients_repository.dart`'s T48 anonymisation, and
/// `reviews_service.dart`'s fallback author name for a reviewer with no name on
/// file. Both now reference this.
///
/// **⚠️ The first version of this comment claimed a mutation hook that does not
/// fire, and the adversarial review caught it.** It said changing
/// [anonymousClientLabel] would redden the reviews assertion and the
/// salon-clients assertion together. It does not: both assertions in
/// `privacy_repositories_test.dart` compare against the *constant*, so both
/// sides move with it and the file stays green. What actually goes red is
/// `test/clients_test.dart:499` and `test/db/postgres_repositories_test.dart:897`,
/// which pin the **literal** `'Client'` — pre-existing tests, not written for
/// this, and the real reason the unification is safe.
///
/// The lesson is the one this programme keeps relearning: an assertion phrased
/// in terms of the thing it is testing proves that the thing equals itself.
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
