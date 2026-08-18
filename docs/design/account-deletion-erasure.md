# account-deletion-erasure — the deletion that did not delete (L1)

| | |
|---|---|
| **Status** | Built (2026-07-27) |
| **Surface** | `backend/` — `DELETE /me`, and the eight tables it never reached |
| **PRD ref / phase** | FR-AUTH-005 · §18 Compliance & legal · **V1** |
| **Related spec** | [pro-account-deletion-export.md](pro-account-deletion-export.md) — the provider twin, Built. This is its consumer counterpart, and it fixes the same push defect on **both** sides |
| **Umbrella** | [legal-l1.md](legal-l1.md) — the policy this makes true |
| **Threat model** | [BACKEND.md](../BACKEND.md) §7 — new **T59**; T48 and T53 cross-linked |
| **Skills checked** | myweli-backend-guardrails · myweli-dev-guardrails |

## 1. Goal & scope

`DELETE /me` reports 204 and leaves most of the person behind. This slice makes the
endpoint mean what it says, because [legal-l1.md](legal-l1.md) publishes a privacy
policy that describes it — and **a policy that describes the current behaviour
honestly would be documenting a defect**.

### What survives an account deletion today

Measured at `f92b8dc`. Every one of these tables stores `user_id` as a **plain
`text` column with no foreign key**, so nothing cascades:

| Table | What is left behind |
|---|---|
| `reviews` | **`user_name`** — the person's display name, on a public page |
| `appointments` | `client_name`, `client_phone`, `notes`, `deposit_screenshot_url` |
| **`device_tokens`** | the FCM token — **the deleted user's phone keeps receiving push** |
| `notifications` · `notification_preferences` | title/body, and a preferences row |
| `favorites` | the rows |
| `review_reports` | `reporter_user_id`, `reason` |
| R2 `deposit` bucket | every screenshot object — **no code path deletes one, anywhere** |

The device-token row is not a compliance nicety. It is a live bug: delete your
account, keep getting notifications about a salon you no longer have a relationship
with, with no way to stop it because the account that owned the preference is gone.

### Out of scope, and why

- **`outbound_messages`** (`recipient_phone` + the full rendered body) — keyed by
  phone, and phone numbers get reassigned, so an erasure join on it would delete a
  *different* person's message history. This wants a retention TTL cron, which is
  its own slice. Recorded as a residual.
- **`messaging_opt_out`** — deliberately **kept**. It records that this person asked
  not to be contacted. Erasing it re-enables marketing to someone who opted out: an
  erasure that makes privacy *worse*.
- **`appointments.user_id`** — kept. Once the name, phone and notes are gone, a
  dangling opaque id is a business record, not an identity, and the salon needs its
  booking history to reconcile takings.

## 2. UX & flows

No new screen. The existing affordances keep their shape:

- Consumer: `profile_screen.dart` « Supprimer mon compte » → `showConfirmDialog`
  with `confirmWord: 'SUPPRIMER'` (SYSTEM.md §15's irreversible rung).
- Web: `components/account/AccountClient.tsx`, same type-to-confirm.

**What changes is the copy, because it is currently false.** The dialog promises
« Vos rendez-vous, favoris et avis seront supprimés ». After this slice that is
*still* not true — appointments are stripped, not deleted; reviews are anonymised,
not deleted. The dialog, the OpenAPI `delete:` description and
`/suppression-compte` all carry **one** transcription of the table in §4.

## 3. API & contract

`DELETE /me` — unchanged path, unchanged 204, one new failure mode.

| Status | When |
|---|---|
| `204` | erased |
| `401` | no principal |
| **`403`** | the principal is not a consumer (see §6) |
| `404` | no such user; also the idempotent second call |
| **`409`** | **L2** — `future_bookings`: a pending or confirmed booking is still ahead. Cancel it and retry |

`docs/api/openapi.yaml`'s `delete:` description gains the deleted / anonymised /
retained table verbatim. That text is the contract three surfaces paraphrase.

## 4. Data model

No migration. Eight existing tables, one new verb each.

| Table | Verb | Statement |
|---|---|---|
| `device_tokens` | delete | `DELETE … WHERE user_id = @u` |
| `notifications` | delete | `DELETE … WHERE user_id = @u` |
| `notification_preferences` | delete | `DELETE … WHERE user_id = @u` |
| `favorites` | delete | `DELETE … WHERE user_id = @u` |
| `reviews` | **anonymise** | `SET user_name = @label, user_id = @tomb` |
| `review_reports` | delete | `DELETE … WHERE reporter_user_id = @u` |
| `appointments` | **anonymise** | clears three columns, returns the deposit keys |
| `salon_clients` | anonymise | unchanged (T48, `postgres_clients_repository.dart:221-229`) |
| `users` + `otp_codes` + `email_otp_codes` | delete | unchanged; `refresh_tokens` cascade |

### ⚠️ Reviews are anonymised with a tombstone, never NULLed

`reviews.user_id` is **`text NOT NULL`** (`migrations.dart:226`), the DTO is
required, and `mobile/lib/models/review.dart:10` types it as a non-nullable
`String`. A NULL would need a migration **plus** an OpenAPI change **plus** a
`schema.ts` regeneration **plus** a mobile model change — and mobile ships on its
own cadence, so **the app already in the store would crash on the first anonymised
review** until users updated. A tombstone id costs nothing and breaks nobody.

### Why anonymise rather than delete

The rating is a public aggregate the salon **earned**. Deleting the row silently
re-scores a business because a customer closed an account. Anonymising keeps the
score honest and removes the person.

`review_reports` is the exception and gets deleted, because anonymising it is
*impossible*: `UNIQUE (review_id, reporter_user_id)` (`migrations.dart:329`) means
two erased users who reported the same review would collide on the shared tombstone.
Side effect, recorded: an **open, unactioned** report loses its count; an
already-hidden review stays hidden, because moderation status lives on `reviews`.

### The appointments statement

Postgres has no `RETURNING OLD.*`, and the deposit keys must be read *before* the
column is cleared. One CTE does both in one round-trip, so "the key I returned" and
"the key I cleared" are the same set by construction rather than by luck:

```sql
WITH victims AS (
  SELECT deposit_screenshot_url AS key FROM appointments
   WHERE user_id = @uid AND deposit_screenshot_url IS NOT NULL
), cleared AS (
  UPDATE appointments
     SET client_name = NULL, client_phone = NULL, notes = NULL,
         deposit_screenshot_url = NULL
   WHERE user_id = @uid
)
SELECT key FROM victims
```

## 5. Architecture & patterns

`routes → services → repositories`, no layer skipped. One orchestrating service
modelled on `ProviderAccountService` (`provider_account_service.dart:32-83`), plus
one method per repository interface — mirroring the `// ---- Privacy (threat T48) ----`
block that already exists at `clients_repository.dart:59-63`.

**Every new method needs its in-memory twin**, because that is what the tests use.

### One shared const

`backend/lib/src/privacy/anonymized_identity.dart` — `anonymousClientLabel`
(`'Client'`, already the value at `postgres_clients_repository.dart:224` and the
fallback author name at `reviews_service.dart:104`) and `deletedUserId`. The
existing literals become references, so changing the const fails the reviews **and**
the salon-clients assertions together — the proof that one source feeds both.

### Ordering: children first, identity last

```
devices → notifications → prefs → favorites → reviews → appointments
        → salon_clients → deposit objects (best-effort) → users row
```

**This reverses today's order**, and the reversal is the point.
`routes/me/index.dart:56-60` deletes the `users` row *first* and anonymises
`salon_clients` second — so if step 2 throws, the salon CRM keeps that person's name
and phone forever and there is no token left to retry with.

There is no cross-repository transaction and there cannot be one: the storage DELETE
is an HTTP call outside any DB session. Atomicity is therefore replaced by a stated
invariant:

> **Every step is idempotent, so a failed erasure leaves a live account whose owner
> can press Delete again, and the retry converges.**

That holds only if the identity goes last. It is gated (§8).

A `runTx` across all eight tables was considered and rejected: it buys partial
atomicity but needs one class that knows eight tables — the layering violation
BACKEND.md §1 forbids — has no honest in-memory twin, and still cannot cover the
storage call.

## 6. Security & authz

- **Deny by default.** The route resolves the principal in middleware as it does
  today; no principal → 401.
- **New role gate → 403.** `device_tokens` and `notifications` hold **provider rows
  too** — `user_id` is whatever the token's `sub` is, with a `role` column beside it
  (`migrations.dart:424-430`; `routes/me/devices/index.dart:46` sets
  `role: principal.role`). A cascade keyed only on `user_id` would therefore reach
  across the consumer/pro boundary if a provider token ever hit this route. It is a
  consumer endpoint; the gate makes that explicit rather than incidental.
- **Storage ownership re-checked at the key.** Only `deposit/$userId/…` keys are
  DELETEd, mirroring `provider_account_service.dart:70`'s KYC prefix check. A
  foreign key on the user's own row is skipped, not trusted.
- **Best-effort storage, never blocking.** A failed object DELETE is swallowed, as
  on the KYC path. The objects are uuid-named in a private bucket with the rows
  gone, so they are unreachable — but the honest phrasing in the policy is
  *attempted*, not *guaranteed*.
- **Threat model:** new **T59** (consumer erasure), T5's `/me` cell amended, the
  three residuals from §1 recorded, T53 cross-linked.

## 7. Performance

Eight indexed single-key statements plus at most a handful of HTTP DELETEs, on a
once-per-account path. No budget touched. Not batched: clarity beats a round-trip
on an operation a user performs once.

## 8. Testing plan

`backend/test/me_erasure_test.dart`, built like
`provider_account_service_test.dart:55-64` — real in-memory repositories, a
`FakeStorageService`, and a `MockClient` capturing DELETEs.

Seeds **victim A** (1 review · 1 appointment with name/phone/notes and
`deposit/A/proof.jpg` · 2 device tokens · 3 notifications · a prefs row · 2
favorites · 1 filed report · 1 salon_client) **and bystander B** with the identical
shape. Bystander B is the whole design: an over-broad predicate anywhere passes
every victim assertion and fails B.

### Required negative tests

| Test | The mutation it survives |
|---|---|
| anonymous DELETE → 401, **and no repository is touched** | any "erase before auth" reordering |
| **provider-role token → 403, and that account's `device_tokens` + `notifications` rows still present** | dropping the role gate |
| unknown `sub` → 404, nothing erased; second DELETE → clean 404, no extra HTTP DELETE | idempotence |
| A erased ⇒ **every** one of B's rows in all eight tables byte-identical | an over-broad predicate |
| exactly the own-prefix `deposit/A/…` key is DELETEd; a foreign key on A's row is skipped | loosening to `startsWith('deposit/')` |
| `MockClient` throws ⇒ erasure still succeeds, user gone | the best-effort contract |
| **`_devices.deleteForUser` throws ⇒ the `users` row SURVIVES** | moving `deleteUser` to the top — **the ordering gate** |

Plus per-method repository unit tests (victim changed, bystander byte-identical) and
additions to `backend/test/db/postgres_repositories_test.dart`, beside the existing
`clients.anonymizeUser('uX')` at `:894`.

**Every gate is watched fail before its fix.** A gate you have not watched fail is
not a gate.

## 9. Rollout & scope discipline

Additive and backward-compatible: no migration, no DTO change, no client change
required. Deploy **backend first** — the web page and the app copy describe
behaviour that must already be true when they ship.

V1 only. No new surface.

## 10. Definition of done

- [ ] `dart analyze --fatal-infos --fatal-warnings` = 0 · format clean · tests green
- [ ] `openapi.yaml` `delete:` enumerates deleted / anonymised / retained
- [ ] `BACKEND.md` §7 T59 + the three residuals recorded
- [ ] The pro side's identical push defect fixed in the same PR
- [ ] Every gate mutation-proven red before its fix
- [ ] Spec cross-linked from `user_erasure_service.dart` and from legal-l1.md
- [ ] Feature branch → PR → **the user merges**; no Claude attribution

## 10.1 ⚠️ What the adversarial review found

Four things, every one of them after the whole suite was green — which is the
point of running one.

1. **The tombstone was defeated by a URL.** Anonymising `reviews.user_id` hid the
   id in the column and left it in the payload beside it: review photos live at
   `review/{userId}/{uuid}.{ext}` in the **public** bucket
   (`upload_signing_service.dart:98`) and `photo_urls` was untouched. An erased
   reviewer's photos stayed served, their id legible in the address bar, and every
   review that person ever left groupable by prefix — often photographs of their
   own face or hair. `anonymizeUser` now returns those keys and the service erases
   them, gated with a bystander.
2. **The deposit erasure cannot converge on a retry, and the copy promised it
   would.** Both anonymise statements clear their key column *as they read it*, so
   a second attempt returns an empty list and a surviving object is unreachable
   forever. §6 had already required the honest word — *attempted*, not
   *guaranteed* — and neither user-facing surface used it. Both now say
   **best-effort** in as many words.
3. **`salon_client_notes` and `salon_clients.tags` were undeclared residuals.**
   `BACKEND.md` T48 records them; the three surfaces this slice calls "one
   contract" did not. A salon's note can read « allergique à l'ammoniaque, habite
   près de la pharmacie » — *"no longer identifying"* is an assumption about free
   text, not a fact. Now named on the policy, the deletion page and the contract.
4. **The consumer erasure has no future-bookings gate** while the provider one
   does. **Closed in L2** — the owner answered the product question: the consumer
   is blocked too. See §11.

## 12. The admin path — `DELETE /admin/users/{id}/erase` (2026-08-18)

**Same cascade, second caller.** `UserErasureService` is untouched; the admin
route calls `AdminUserService.erase`, which calls `eraseUser` and writes a
`user.erase` audit row afterwards.

**Why it exists.** §6 assumed the person can sign in — `DELETE /me` reads the
identity from their own token. An erasure request arrives **by e-mail**, from
someone with a lost phone, a closed mailbox or a changed number, and the privacy
policy promises erasure to that person too. Until now, honouring it meant raw
SQL against production — which is exactly how the cascade got missed the first
time (`users` deleted, `device_tokens` left behind, so a deleted user's phone
kept ringing). A second implementation would have been a second chance at the
same bug.

**What made it urgent.** Three Q1b smoke accounts sat in production from
2026-08-06 (`e2e-…@smoke.test`, two `r2probe-…@smoke.test`).
`backend-q1b-smoke-seam.md` §7 had prescribed "purge by identity suffix" and it
was never run — LAUNCH.md §4 stayed unticked because of them.

**Design notes worth keeping:**

- **A sub-path, not `DELETE /admin/users/{id}`.** That URL serves the read-only
  support view. Putting an irreversible action on the URL an agent loads to
  *look* at someone is how a mistyped verb becomes an incident.
- **The audit row is written after the cascade succeeds**, never before: a log
  line claiming an erasure that did not happen is worse than none. Pinned by a
  test asserting nothing is audited on `not_found`.
- **The audit row carries no PII** — the id and an optional reason, nothing
  else. Once the identity is gone this row is the only record it existed; if it
  held the phone or e-mail, "erasure" would have *moved* the data. Also pinned.
- **`future_bookings` still refuses, with no admin override.** A salon holding a
  slot for a named person must not be stranded with one it can neither contact
  nor fill. An admin bypass would make this endpoint the easy way around §6's
  rule rather than a second door to the same room.
- **The 401/403 boundary is not re-proven here** — `routes/admin/_middleware.dart`
  gates every `/admin/*` path and `admin_test.dart` already holds it.

## 11. Open questions

- **`outbound_messages` retention.** Phone + full body, growing without bound, and
  not erasable by a `user_id` join. Needs a TTL and a cron. Filed, not solved here.
- **~~Does an anonymised review still need its photos?~~ Answered: no.** This
  entry originally kept them, reasoning that *"the photo belongs to the review,
  and the prefix is opaque"*. The prefix is **not** opaque — it is the primary key
  the tombstone exists to hide, and an erased reviewer's photos stayed publicly
  served with their id in the URL. Now detached and erased, gated with a
  bystander. Recorded because the wrong answer was written down first, and
  confidently.
- **~~Should a consumer be blocked from deleting with future bookings?~~
  Answered: yes (L2).** The owner's call, and it matches the provider path — the
  consumer must cancel first. The gate runs **before the first erasure step**, so
  a refusal is never a half-deletion, and the route returns **409
  `future_bookings`** exactly as `/me/provider` does. Both clients name the
  remedy instead of saying « la suppression a échoué », which was advice that
  could not work: retrying fails identically until the booking is cancelled.
