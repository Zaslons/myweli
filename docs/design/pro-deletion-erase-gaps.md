# A deleted Pro leaves no map pin and no replaced document (B0.22)

| | |
|---|---|
| **Module** | backend — `ProviderAccountService` (`DELETE /me/provider`) and `KycService` (`POST /me/kyc`) |
| **Status** | **Draft 2026-11-13.** The change is decided (decision 137: Q12 (a) and Q13 (a) of [web-pro-account-deletion.md](web-pro-account-deletion.md)); this spec's details and O1–O2 await the owner's review. Not built. A second review's findings folded the same day (§2, §3.2 points 2 and 4, test 9, §9, O2) |
| **Owner** | the project owner: the review, the merge, the production deploy and any production read |
| **Last updated** | 2026-11-13 |
| **PRD ref / phase** | FR-AUTH-005 [V1] (`docs/PRD.md:344`) · V1 · gates android-play-release step 7 |
| **BACKLOG item** | B0.22 · decision 137 |
| **ROADMAP entry** | [2026-11-13-pro-account-deletion-spec.md](../roadmap/entries/2026-11-13-pro-account-deletion-spec.md) |
| **Skills checked** | myweli-backend-guardrails (invoked for this spec) · [BACKEND.md](../BACKEND.md) §3.3, §5, §7 · myweli-verification-guardrails' marking rule applied (not invoked) |
| **Related** | [web-pro-account-deletion.md](web-pro-account-deletion.md) §2.3, §11, §12 (the page that states both) · [pro-account-deletion-export.md](pro-account-deletion-export.md) · [backend-integrity-batch6.md](backend-integrity-batch6.md) §2.3 (decision 17) · [pro-kyc.md](pro-kyc.md) · [upload-resave-stale-pending.md](upload-resave-stale-pending.md) · [backend-upload-orphans.md](backend-upload-orphans.md) |

OBSERVED = read in the code at `main` `d19655bd`. INFERRED = reasoned from it. UNVERIFIED = not
readable from here.

## 1. Goal & scope

**Goal.** What `/pro/suppression-compte` will say becomes true. (1) At an owner's deletion, each
owned salon loses its map pin together with its address. (2) A document replaced by a KYC
re-submit is deleted from storage then, so it can no longer outlive the account.

**In scope:** two keys in `_erasedContact`; the superseded-object delete in `KycService.submit`,
with the write made safe against a concurrent submit; tests; two OpenAPI description sentences;
the T53 and T15 rows.
**Out of scope** (decisions 137–140): the commune, the city and `areaId`, which decision 137's
answer does not name (it names the pin), so they stay and the page discloses the commune and the
city as kept (an engineering consequence, not part of the answer); the salon's public photos (B0.27); a purge of the kept history (B0.24); an
admin erase tool (B0.25); the backups (B0.28); salons and objects from before the deploy (O1, O2).

## 2. What exists (OBSERVED)

- **The pin is kept.** `_erasedContact` (`provider_account_service.dart:82-89`) holds
  `phoneNumber`, `address`, `whatsapp`, the Mobile Money number and operator and
  `depositRequired`. It is merged into each owned salon at `:153`. `latitude` and `longitude`
  are not in it. They are part of the salon's « place » of decision 129 (salon-go-live Q6, capped by decision
  133; `provider_catalog_service.dart:74-82`, « (Q6) »),
  editable (`:192-204`), checked as a pair (`:409-419`), and declared to Play as « Position
  exacte » (`play-store-forms.md:383`).
- **A replaced document is kept.** `submit` (`kyc_service.dart:43-115`) reads the account's
  stored keys (`:69-72`). A key must be stored or under `pending/kyc/{accountId}/` (`:81`).
  `promoteNewKeys` passes a stored key through and maps a re-sent pending key to its stored
  promoted form (`upload_verification_service.dart:101-129`). It deletes only the `pending/`
  sources (`:176-180`). `submitKyc` then replaces the whole list
  (`postgres_provider_auth_repository.dart:476-497`; in memory, `provider_auth_repository.dart:329-340`).
  Nothing deletes a promoted `kyc/{accountId}/…` key that the new list leaves out. The R2
  manifest requires a lifecycle rule on `pending/` only (`infra/cloudflare/r2-manifest.json:44-48`);
  the manifest is a floor, never a copy of the live configuration (`:11-12`), so whether the
  live bucket holds any other rule is UNVERIFIED (`95-verify-r2.sh` would read it, on the owner's
  yes). No rule the repo requires collects a replaced document. The
  deletion erases only the keys listed at that moment (`provider_account_service.dart:174-183`).
- **No guard between read and write.** `submit` reads the account (`:44`) and writes (`:112`)
  with no lock and no comparison.
- **Production:** 0 KYC documents on 2026-11-12 (B0.20's read-only count). The owner deleted one
  throwaway account on 2026-11-10 (B0.12). Whether its salon had a pin is UNVERIFIED.

## 3. The change

### 3.1 The pin

`_erasedContact` gains `'latitude': null` and `'longitude': null`. Nothing else changes.
- It goes through `ProvidersRepository.updateProfile` directly (`:153`), never through
  `ProviderCatalogService.updateProfile`. So no place-change e-mail is sent (decisions 129, 133),
  and `_placeNotices?.forget` still runs after it (`:163`).
- A null pin is the state of every new salon (`providers_repository.dart:881-882`). Readers
  already handle it. The checklist lists `location` (`salon_provisioning_service.dart:206-208`).
  `placePin` returns null (`validation/salon_place_notice_service.dart:16-17`). Members who keep
  the hidden salon see it with no pin, like a new salon (INFERRED).
- A member-only salon is untouched (`:116-122`, unchanged).

### 3.2 The superseded KYC objects

1. **The write becomes a compare under a row lock.** In one transaction, `submitKyc` locks the
   row (`SELECT kyc_docs … FOR UPDATE`). It refuses if a pass-through key (one the request did
   not just promote) is no longer in the locked list. Otherwise it writes the new list and
   returns the account and the **previous** keys; on a refusal it returns the locked list, which
   point 2 subtracts. The in-memory twin does the same check. The exact signature is settled at
   build.
2. **Why the lock.** Take two submits from one account, in two tabs or as a retry racing its
   original. A replaces k1 and deletes it. B validated k1 as stored before A wrote, then writes k1
   back. The row would then point at a deleted object. With the lock, B is refused with
   **400 `invalid_input`**. The contract already names that case (« one this account no longer
   holds », `docs/api/openapi.yaml:970-972`). B's freshly promoted copies are deleted best
   effort, or they would sit unreferenced in a retained bucket, **but only those absent from the
   locked current list**. A promoted key is a pure function of its pending key (`promotedKey`,
   `upload_verification_service.dart:156-158`), so two submits that carry the same pending upload
   p2 both promote to the same k2. If A wins and stores k2, B's « own » k2 is A's committed
   document: deleting it would leave A's row pointing at a deleted object, the very failure the
   lock prevents. So the refusal deletes this request's promoted keys **minus** the locked list,
   computed inside the transaction and deleted after it.
3. **After a successful write, outside the transaction:** superseded = previous keys ∖ new keys,
   compared after promotion, so a re-sent pending key maps to its stored key and is kept. Only
   `kyc/{accountId}/…` keys count (the filter of `provider_account_service.dart:176`), never a
   `pending/` key and never another prefix. Each is deleted with
   `StorageService.deleteObject(bucket: StorageBucket.kyc)`.
4. **Best effort, as the deletion is** (`:177-182`). A storage failure is swallowed and the
   submit still answers 200 with the new list. A survivor is private, uuid-named and no longer
   referenced, and the later account deletion no longer lists it, so it stays. The page's KYC
   caveat names this moment beside the deletion (web spec §5.1: « lors de la suppression, ou
   lorsque vous avez remplacé ou renvoyé un document »). A refused or failed submit (400, 503)
   deletes nothing old.
5. `KycService` gains an optional `StorageService? storage` argument, wired in
   `dependencies.dart:682-685` and pinned by a wiring test (as `salon_validation_wiring_test.dart`).

## 4. Contract

**No path, schema, status or error code changes.** Confirmed in `docs/api/openapi.yaml`:
- `DELETE /me/provider` (`:603-642`) answers 204, 401, 403 and 409, all unchanged.
- `POST /me/kyc` (`:956-998`) answers 200, 400, 401, 403 and 503. The lost race is its existing
  400 `invalid_input`.
- `Provider.latitude` and `longitude` are already `nullable: true` (`:6013-6014`).

Two description sentences change in the same PR, so the contract states what the server does:
- `DELETE /me/provider` names the owned salons' erased contact, address and map pin. Today it
  names none of them.
- `POST /me/kyc` says that a stored document the new list leaves out is deleted from storage.

No client change is needed: the app and the website already draw a salon with no pin.

## 5. Data

**No migration.** `latitude` and `longitude` are not columns. `providers` keeps them in
`data jsonb NOT NULL` (`migrations.dart:50-59`). Postgres `updateProfile` merges the changes into
that document and syncs only `name`, `description`, `address` and `commune` to columns
(`postgres_providers_repository.dart:350-381`). No migration indexes the pin (grep `latitude` in
`migrations.dart`: no hit). A JSON null is already a stored value
(`providers_repository.dart:881-882`). The KYC list is `provider_users.kyc_docs`, and the previous
list is decoded by the same `_kycDocs`, which reads the old string form too
(`postgres_provider_auth_repository.dart:526-552,616`).

## 6. Security — threat model ([BACKEND.md](../BACKEND.md) §7)

| Row | Delta written in the backend PR |
|---|---|
| **T53** (provider account deletion) | « the salon's map pin is erased with its address (B0.22) ». No new endpoint and no new trust boundary |
| **T15** (KYC) | « a re-submit deletes the superseded objects: after the write, best effort, own prefix only; the pass-through check runs under the row lock » |

The new risk is tampering: making the server delete an object that is not the caller's. The keys
come only from the caller's own **locked stored list**, never from the request. They pass the
`kyc/{accountId}/` filter, and the bucket is fixed. So a request can only delete objects its own
account had stored. Authorization is unchanged: self-scoped by the token's `sub`, provider only.
Nothing new is logged: no key, no account id, no document name.

## 7. Performance

The pin adds two keys to an existing write. The KYC change adds no read: the lock reads the row
the write already updates. At most 8 deletes run per submit (`_maxDocuments`, `kyc_service.dart:35`),
sequentially, after the transaction, so no network call happens inside the lock.

## 8. Tests — red first, each watched red once on committed code

| # | Test | Mutation that turns it red |
|---|---|---|
| 1 | `provider_account_service_test.dart:493-523`: the `erased` constant gains both keys as null; owned salons get it, the member-only salon gets nothing | drop `latitude` from `_erasedContact` |
| 2 | in memory, end to end: an owned salon with a pin, its owner deleted → `byId` reads both null; `commune`, `city` and `areaId` unchanged | erase `commune` too |
| 3 | `test/db/postgres_repositories_test.dart` (runs with `DATABASE_URL` in CI): `updateProfile` with both null → the re-read `data` holds JSON nulls and the `address` column is untouched | write `0` instead of null |
| 4 | `kyc_test.dart`: two documents stored, one replaced → `FakeStorageService.deleted` is exactly the replaced `kyc/{id}/…` key | delete the whole previous list |
| 5 | a re-sent `pending/kyc/{id}/x` whose `kyc/{id}/x` is stored → nothing deleted | compare before the promotion mapping |
| 6 | a foreign key in the stored list (seeded as `provider_account_service_test.dart:127-131` seeds one) → never deleted | drop the prefix filter |
| 7 | `deleteObject` throws → 200, the row holds the new list | rethrow |
| 8 | a refused submit (`invalid_input`; `storage_unavailable` from the promotion) → nothing old deleted | delete before the write |
| 9 | a pass-through key removed from the row between the read and the write (a repository wrapper) → 400 `invalid_input`, the row unchanged, this request's promoted keys deleted **except** one the locked list holds: the winner stored `promotedKey(p2)` from the same pending upload p2, and that key is **not** deleted | drop the in-lock check; delete every promoted key of the refused request (the k2 assertion turns red) |
| 10 | wiring: `dependencies.dart` passes the storage to `KycService` | remove the argument |

Then the full backend suite, `dart format`, and `dart analyze --fatal-infos --fatal-warnings` = 0.
The existing contract tests stay green.

## 9. Rollout

1. This spec, in B0.19's docs PR; the owner reviews it and answers O1–O2.
2. The backend PR from `main` (`fix/pro-deletion-erase-gaps`): code, tests, the two OpenAPI
   sentences, the T53 and T15 rows, and `// Design:` links to this spec. CI green; the owner
   merges, **outside the merge hold** of android-play-release step 3 (c) (from the 0.0.2 bump's
   merge until the iOS 0.0.2 IPA is built, `android-play-release.md:164`).
3. **The production deploy, on the owner's yes** (`deploy-backend.yml`, `image_tag` = the merge
   commit), **outside any Apple review**, since nothing the reviewer relies on may change during
   a review (B0.1); the web spec §11 says the same, in the same words. It gates
   android-play-release step 7, and B0.19's page merges only after it (web spec §11).
4. **The read-back.**
   - *What can be observed:* the revision serving 100 % with that image; `/health` 200 through
     `api.myweli.com`; « Production checks » green; no new error in the logs after the switch.
   - *What cannot:* the erase itself. Production data is real (since 2026-11-10), and Claude makes
     no deletion and no re-submit there. The evidence is the tests above.
   - *Optional, on the owner's yes, as B0.12's test was (2026-11-10):* the owner signs up a
     throwaway salon, sets its pin, submits a KYC document, replaces it, then deletes the account.
     Two read-only reads follow: that salon's `data->'latitude'` (Cloud SQL) and the listing of
     `kyc/{id}/` in the private bucket (R2). Both should be empty.
5. Docs: this spec → Built, then Live with the deploy's date; B0.22 ticked in BACKLOG.

## 10. Open questions

- **O1 — Salons whose owner was deleted before the deploy keep their pin.** First a read-only
  count, on the owner's yes: salons with no `provider_users.provider_id` link, no active owner
  membership and a non-null pin. Then (a) erase those pins once, by hand, each on the owner's yes;
  or (b) leave them, which makes the page's sentence false for them. **Rec: (a) if the count is
  not 0.**
- **O2 — Superseded objects from before the deploy.** Production held 0 KYC documents on
  2026-11-12, so none is expected, but any rejection followed by a re-submit between that count
  and the deploy leaves one, and §9's read-back cannot see storage. Should a read-only R2 listing
  of `kyc/` against the stored keys confirm that on the deploy day, on the owner's yes? **Rec: yes,
  once.** Either way it is now **a condition of B0.19's page** (web spec §11 step 3): that listing,
  or the owner's confirmation that no KYC submission was rejected and re-submitted before the
  deploy.
