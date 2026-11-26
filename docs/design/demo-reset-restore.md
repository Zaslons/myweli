# The demo salon's reset restores what a reviewer changed (B16.2)

| | |
|---|---|
| **Module** | backend: the store-review demo (`DemoResetService`, the demo snapshot store) and `providers` (one new writer, `replaceServices`) |
| **Status** | **Approved 2026-11-25.** The owner answered the five questions of §11 at once, « Approve as recommended »: decisions 250–254 in BACKLOG, batch 16 (#865). **B16.2 built 2026-11-25** (§8.8), on the owner's « Yes, build B16.2 », in its own backend PR, **merged** as `59409ef0` (#869). **Read before the deploy** on 2026-11-25 (§9.1): the live demo equals the snapshot except its hours; the owner chose « Let the reset restore ». **Deployed** on 2026-11-26 (`myweli-api-00060-bwq`, image `59409ef`) and read back. The first fixed reset is due 2026-11-30 03:30 UTC; the read after it, on the owner's word. |
| **Owner** | the project owner: the answers, the build's go, the merge, the read before the deploy, the deploy and the read after it, each on the owner's word |
| **Last updated** | 2026-11-26 |
| **PRD ref / phase** | the store-review account (threat T69) · V1 |
| **ROADMAP entry** | [2026-11-25-demo-reset-restore-spec.md](../roadmap/entries/2026-11-25-demo-reset-restore-spec.md) |
| **Skills checked** | myweli-dev-guardrails · myweli-backend-guardrails · myweli-verification-guardrails · [BACKEND.md](../BACKEND.md) §5 (decision 223), §7 (T69) |
| **Related** | [twin-fidelity-survey.md](twin-fidelity-survey.md) §2.2 (where this was found), §3.2 (C-M1) and §6 (decisions 219, 222) · [backend-demo-review-account.md](backend-demo-review-account.md) §6.2 (the reset's design) and §9 (the captures in production) · [provider-category-column.md](provider-category-column.md) §12 (the `rating` found there) |

---

## 1. Goal & scope

**The defect.** The demo salon exists for the store reviewers (Apple, Google Play), who sign in with the credentials printed in the review notes. Every 7 days, a reset is meant to put it back the way the owner curated it ([backend-demo-review-account.md](backend-demo-review-account.md) §6.2: « name, description, services, photos, availability »). It does not restore the services, and in production it does not restore the hours either. A reviewer who adds, deletes or reprices a service, or changes the hours, leaves it that way for every reviewer after. Before/after pairs added by a reviewer stay too. And the reset writes back a rating it does not own.

**Goal.** After each reset, the demo salon is what the owner curated: its profile, its services (the list, each field, the order), its hours, its before/after pairs, its artists. The reset leaves alone what is not the reviewer's to change: the admin's `featured` flag and the rating the reviews compute. A snapshot the reset cannot apply is refused without blocking the rest of the nightly maintenance.

**In scope:**
- the reset's restore step (`demo_reset_service.dart`);
- one new writer on both twins, `replaceServices` (Q1);
- the in-memory snapshot store's copies (C-M1: decision 222 fixes a test-only difference when its store is next touched, and this touches it);
- the reset's test, run on both twins (decision 223).

**Out of scope:**
- the rest of the reset, unchanged: the agenda and client-book wipe, the regenerated agenda, the offer pin, the KYC erasure. The regenerated agenda's data changes separately: decision 249 (revenue analytics, B17 R2) seeds past completed bookings across collaborateurs and prestations, in the same file. Whichever is built second merges the other — R2 was, on 2026-11-26, on top of this spec's restore ([pro-revenue-analytics.md](pro-revenue-analytics.md) §20.5). That agenda reads the services and artists this spec restores;
- the demo account's own settings a reviewer can change and no reset restores: its notification preferences (`PUT /me/notification-preferences`) and its device registrations (`POST /me/devices`);
- C-D1, the disputes a wipe cascades away in Postgres and keeps in memory: the disputes group of batch 16;
- the images a reviewer uploads, which a restore stops pointing at (§12).

---

## 2. What exists today (OBSERVED)

### 2.1 How the reset restores the salon

- `tickIfDue` copies the snapshot's document, removes `id`, `slug` and `status` (`_neverRestored`, `demo_reset_service.dart:59`), and sends the rest to `updateProfile` (`:146-148`). Its comment (`:143-145`) says « everything the catalog surfaces can write gets reverted ».
- `updateProfile` merges: Postgres reads `data`, `addAll`s the changes and writes `data` back, with the five columns of `kProviderDocumentColumns` (`postgres_providers_repository.dart:370`). The in-memory twin `addAll`s into its live map (`providers_repository.dart:324`).
- The snapshot is what `byId` returned at the capture. The in-memory store keeps `Map.from(doc)`, a shallow copy (`demo_snapshot_repository.dart:44`), and hands out that stored map on every read (`:51`). The Postgres store keeps `jsonb`, so every read is a new decode.
- `markReset` is the reset's last step (`demo_reset_service.dart:170`). The reset runs inside the nightly maintenance tick, before the salon purge, and a throw escapes the tick (`maintenance_tick.dart:56-57`).

### 2.2 Where each part of the demo salon lives, and whether today's reset reaches it

File references below: `pg` is `postgres_providers_repository.dart`, `mem` is `providers_repository.dart`.

| Part | Postgres | In memory | Reset today, Postgres | Reset today, in memory |
|---|---|---|---|---|
| name, description, address, commune, category, phone, WhatsApp, map pin, market fields, logo, gallery, deposit policy, `verified` | `data` (five of them also in columns, kept in step since B16.1) | the document | ✅ restored | ✅ restored |
| **artists** | `data` | the document's list; `addArtist`, `updateArtist`, `deleteArtist` change it **in place** (`mem:412`, `:423`, `:440`) | ✅ restored | ❌ the snapshot's list **is** the live list (C-M1) |
| **services** | the `provider_services` table; `byId` reads them there (`pg:127-142`), ordered by `created_at` (`pg:513`) | the document's list; `addService`, `updateService`, `deleteService` change it **in place** (`mem:296`, `:307`, `:335`) | ❌ the merge writes a copy into `data`, which `byId` never reads | ❌ C-M1: the reviewer's edits rewrite the snapshot too |
| **hours** | four tables: `provider_availability`, working hours, breaks, blocked dates (`pg:275-280`); `replaceAvailability` (`pg:267`) | the document's map; `replaceAvailability` replaces it (`mem:345`) | ❌ same as services | ✅ restored |
| **before/after pairs** | `data` | the document | ❌ when the curated salon had none: a new salon's document has no `beforeAfters` key (`draftSalonDocument`, `mem:863`), so the snapshot has none to merge back | ❌ same |
| `featured` | a column; one writer, the admin console (`setFeatured`, `admin_provider_service.dart:192`) | a document key | never touched (the merge writes `data.featured`, which `_withFlags` overrides on read, `pg:686`) | **reverted** when the key existed at the capture |
| `rating`, `reviewCount` | `data`, and `rating` also a column; one writer, `updateRatings` (`pg:405`), from the reviews (`reviews_service.dart:249`) | the document | `data` reverted, the `rating` column not: **the two disagree**, and the column orders discovery and the admin list | reverted |
| `status` | a column | the document | never restored, by design (draft forever) | same |

### 2.3 Proven on both twins

A throwaway probe ran the real `DemoResetService` on each twin, with a throwaway local database for Postgres, deleted after. It curated a salon through the real writers (two services, Monday hours, a 10-minute buffer) and captured it. Then, through the same writers, a « reviewer » added a service, repriced one, deleted the other, cleared the hours, renamed the salon and added a before/after pair. Separately, the admin set `featured`, and `updateRatings` wrote 4.5 from 2 reviews. Then the reset ran.

| After the reset | In memory | Postgres |
|---|---|---|
| name (the control) | restored | restored |
| services | **the reviewer's**: `Coupe:1`, `Ajout du relecteur:1` | **the reviewer's**: same |
| what the snapshot now holds | **the reviewer's services** | the curated ones |
| hours | restored | **the reviewer's**: no Monday, buffer 0 |
| before/after pairs | **the reviewer's** | **the reviewer's** |
| `featured` | kept (the key was absent at capture) | kept |
| `rating` in the document | 0 (the snapshot's) | 0 (the snapshot's), with the **column at 4.5** |

Two more facts the design relies on, probed the same way on both twins:
- **The hours round-trip.** `byId`'s `availability`, written back through `replaceAvailability`, reads back equal, including a blocked day of a New York salon, breaks, horizon and notice. The read has no `ORDER BY` on its windows (`pg:585-593`, `:622-628`), so equality is per weekday, as sets.
- **A deleted service re-added through `addService` comes back last:** `[B, C, A]` on both twins. So restoring through the existing service writers loses the curated order whenever a reviewer deleted a curated service (Q1).

### 2.4 Why no test saw it

- `demo_reset_test.dart` runs on the in-memory twin only.
- It builds the demo's services through `updateProfile` (`:119-125`), which replaces the list, so the snapshot keeps the old list and the restore looks right. A reviewer uses the service writers, which change the list in place.
- Even a test through the service writers would have passed in memory: the shallow snapshot shares the live list (C-M1), so « the curated services » it compared against were the reviewer's.

### 2.5 Production (not read)

- The demo salon is `provider_1787778426683705`. The snapshot was last captured on 2026-10-14, after a description fix ([backend-demo-review-account.md](backend-demo-review-account.md) §9), and the reset has run weekly since. Its credentials are printed in both stores' review notes (T69), and the Pro app has been public since 2026-11-10.
- **Not read:** whether the live demo's services, hours or before/after pairs differ from the snapshot today, and whether any difference is a reviewer's or a curation made after the capture that was meant to stay. A fixed reset would undo both kinds. That is Q4.

---

## 3. API & contract

None. No route, no DTO, no status code changes; `openapi.yaml` is untouched. The maintenance tick's `demoReset` outcome gains one value, `refused:bad_snapshot` (§5.1), in the same field as `refused:not_demo_owned`.

## 4. Data model

No migration. `replaceServices` writes `provider_services` rows with an explicit `created_at` (§5.2).

---

## 5. Architecture & design

### 5.1 The restore plan (Q2, Q3)

The snapshot's keys fall into three named sets in `demo_reset_service.dart`:

1. **Never restored** (`kDemoNeverRestored`): `id`, `slug`, `status` as today, plus `featured`, `rating` and `reviewCount` (Q2). Each has a writer that is not the reviewer's: the admin console for `featured`, the reviews for the two ratings. The reset does not wipe reviews, so a restored rating would contradict them.
2. **Restored by their own writer** (`kDemoRestoredByOwnWriter`), each through an explicit call, never through the merge:
   - `services` → `replaceServices` (Q1);
   - `availability` → `replaceAvailability`, already on both twins and proven to round-trip (§2.3);
   - `beforeAfters` → `updateBeforeAfters`, with the snapshot's list, or `[]` when the snapshot has none (Q3).

   A snapshot without `services` or `availability` skips that writer: an absent key never wipes the catalogue or the hours. Only `beforeAfters` maps « absent » to « none », because a new salon's document lacks it.
3. **Everything else** is merged through `updateProfile`, as today. A merge, not a whole-document replace, on purpose: a key a later migration adds to every salon's document (as the multi-pays fields were) survives the restore of an older snapshot. A replace would delete it until the next boot backfill.
   - **`verified` stays in the merge.** Its writers are the admin's (`admin_kyc_service.dart:178`, `salon_directory_service.dart:220`), like `featured`'s. But the reset also erases the demo account's KYC back to « pending » (`_forgetKyc`, `demo_reset_service.dart:168`), so the badge follows the snapshot with it. Q4's read checks that the snapshot's `verified` is `false`.

**The snapshot is checked before the first write.** Each own-writer key present must have the shape its writer needs:
- `services` is a list of maps, each with `id`, `name`, `price` and `durationMinutes`;
- `availability` is a map;
- `beforeAfters`, when present, is a list.

Otherwise the reset writes nothing and returns `refused:bad_snapshot`, logged on one line like `not_demo_owned`. The tick then goes on to the salon purge. Without this check, a snapshot the new writers cannot take would throw. The throw would escape the tick before the purge, every night, because `markReset` is the reset's last step (§2.1).

**Order:**
1. the profile merge first: it puts back the timezone, which `replaceAvailability` reads to store a blocked day (`pg:273`);
2. then services, hours and pairs;
3. then the rest of the reset, unchanged: the wipe, the regenerated agenda (it reads the restored services), the offer pin, the KYC erasure.

The comment at `:143-145` is rewritten to say this.

**Why before/after pairs are the only key handled by name.** Every key the owner's writers can set is in a new salon's document, so it is in any snapshot, except `beforeAfters`. That covers the profile fields, the logo, the market fields, the deposit policy, the gallery and the artists. The demo salon was created on 2026-08-26, after the last change to `draftSalonDocument` (2026-07-31), so its snapshot carries every one of them. A guard (§8.4) pins that list against `draftSalonDocument`.

### 5.2 `replaceServices` (Q1)

```dart
/// Replace [providerId]'s services wholesale, in the given order; returns the
/// stored list ([] for none), or null if the provider doesn't exist. Refuses
/// a service id another salon owns. Only the demo reset calls it
/// (docs/design/demo-reset-restore.md §6).
Future<List<Map<String, dynamic>>?> replaceServices(
  String providerId,
  List<Map<String, dynamic>> services,
);
```

- **Postgres**, in one transaction (`runTx`, the `FOR UPDATE` pattern of `pg:307-320`):
  1. lock the salon's row (`SELECT 1 FROM providers WHERE id = @pid FOR UPDATE`); no row → null;
  2. delete its services;
  3. insert each in the given order, with the columns `addService` writes (one shared mapping) and `created_at = now() − (n − i) µs`. That is strictly increasing in the snapshot's order, and before the transaction's `now()`, so a service added later sorts after them.

  **A plain `INSERT`, never an upsert** (§6): `provider_services.id` is a global primary key (`migrations.dart:155`). An id another salon owns then fails with 23505 and the whole transaction rolls back.

  After the commit, it returns `_servicesByProvider`'s list, read through the pool as `replaceAvailability` does (`pg:293`), `[]` when empty.
  - **Nothing references `provider_services` by foreign key:** no `REFERENCES provider_services` anywhere in the migrations; appointments keep their service ids in `jsonb`. The services keep their ids. Only `_servicesByProvider` reads `created_at` (`pg:512-513`).
- **In memory:** a service id that another salon in the store holds throws, and nothing changes. Otherwise `p['services']` becomes a deep copy of the list, in order, and it returns another copy.
- **Not chosen (Q1's alternative):** diffing through `addService`, `updateService` and `deleteService`. Each is already on both twins. But the restore would not be atomic, and a curated service a reviewer deleted would come back last (§2.3).

### 5.3 The snapshot store keeps its own copy (C-M1, decision 222)

The in-memory store copies through JSON on `capture` and on every `read`, as Postgres's `jsonb` does. A document that is not JSON then fails on both twins alike, at the capture. With it, the reviewer's in-place edits can no longer reach the snapshot, and a restored list can no longer alias the snapshot's.

### 5.4 Contracts on both twins (BACKEND.md §5, decision 223)

1. **`replaceServicesContract`** (the providers store), in `test/providers/`, next to `profile_filters_contract.dart`. Its services are passed in the stored shape (every key `byId` returns for a service), with ids unique to the run (the seed holds `service1`–`service8`, and ids are global). Each case has its own reason text:
   - « [replace] »: on a salon with three services, a list that drops one, re-adds a deleted one under its old id, changes a price and reorders; `byId` then lists exactly that, in that order, each field equal;
   - « [later add] »: a service added after it sorts last;
   - « [other salon] »: another salon's services are untouched;
   - « [foreign id] »: a list holding an id another salon owns is refused, and both salons' services are unchanged;
   - « [unknown salon] »: null;
   - « [copy] »: changing the argument afterwards changes nothing stored;
   - « [order] », **on Postgres only**: `created_at` strictly increasing in the given order, read from the table.
2. **`demoSnapshotContract`** (the snapshot store):
   - « [capture copy] »: a capture is unaffected by later changes to the document it was given, nested lists included;
   - « [read copy] »: a read is unaffected by changes to an earlier read's lists;
   - « [clock] »: `markReset` moves the clock; a second capture replaces the first and restarts it.
3. **`demoResetRestoreContract`** (the reset, over a providers store and a snapshot store): §2.3's scenario, one test per part, each with its reason text:
   - « [profile] » (the control);
   - « [services] »: list, fields and order;
   - « [hours] »: per weekday, compared as sets (§2.3);
   - « [before-after] »;
   - « [artists] »;
   - « [featured] »;
   - « [rating] » for the document's rating, and on Postgres « [rating column] »: the column agrees with it;
   - « [snapshot kept] »: the snapshot still holds the curated services after the reset;
   - « [bad snapshot] »: a snapshot whose `services` is not a list → `refused:bad_snapshot`, and nothing on the salon changed.

   **The test's rules:**
   - The salon is curated, and the reviewer acts, **only through the real writers**.
   - `featured` is set to `false` before the capture, so the in-memory snapshot carries the key.
   - **The expected values are a JSON copy the test takes at the capture**, never a reference: in memory, `byId` hands out the live map, so a reference or a value read back from the snapshot would follow the reviewer's edits.
   - **The curated salon is in a non-UTC zone (`Asia/Tokyo`), with a blocked day.** The « reviewer » moves it to `Africa/Abidjan` through the repository, so the order of §5.1 is observable. Restored in the other order, the blocked day lands a day early. The seeded locality tree has one city, Abidjan, at UTC+0 (`localities_repository.dart:114`); production's locality table was not read. So this order may guard nothing in production today. It is guarded for the day an area is not UTC+0.

**Runners:**
- in memory: `test/demo/` (and `test/providers/` for the first contract);
- on Postgres: in `postgres_repositories_test.dart`, whose tests run in order. Its rows are `draft` and deleted on teardown, and the `demo_snapshot` row is deleted on teardown. No other test file shares that database's `demo_snapshot`: the purge, admin-account and migration tests create their own databases (`postgres_salon_purge_test.dart:49-53`), and the file's per-test `TRUNCATE` touches neither `providers`, `provider_services` nor `demo_snapshot`.

The reset's other collaborators (auth, membership, bookings, clients, offer) stay in memory in both runs: the stores under test are the providers store and the snapshot store.

### 5.5 Layering

Service and repository only; no route, no new dependency in `dependencies.dart`.

---

## 6. Security & authz

- **T69 is unchanged where it matters:**
  - the target comes from the compile-time constant;
  - the reset's destructive half re-verifies that the salon is demo-owned before anything (`demo_reset_service.dart:126-141`);
  - the shape check, `replaceServices` and `updateBeforeAfters` all run after that check.
- **`replaceServices` is a new destructive writer:** it wipes a salon's catalogue and has no route.
  - **It never moves a service between salons.** The owner check covers the salon, not the service ids inside the snapshot. An upsert would let a snapshot carrying another salon's service id take that service over. So it is a plain `INSERT`, and an id another salon owns is refused on both twins (« [foreign id] », §5.4).
  - **A test pins its only caller to `demo_reset_service.dart`,** with comments stripped, the way `demo_locks_inventory_test.dart` pins the identity delete. A second caller turns it red, so a future use is a decision, not an accident.
- **BACKEND.md §7, row T69,** gains a dated line: the reset now writes the services and hours tables, leaves `featured` and the ratings alone, and refuses a snapshot it cannot apply.

## 7. Performance

Once a week, one salon, about a dozen rows. Nothing to budget.

---

## 8. Testing plan — red first, on committed code

### 8.1 Red first

The red commit holds the three contracts. It also declares `replaceServices` on the interface, with both twins throwing `UnimplementedError('B16.2')`, so it compiles. Expected reds, each for its stated reason:

| Case | In memory | Postgres |
|---|---|---|
| `replaceServicesContract`, every case | red: `UnimplementedError: B16.2` | red: same |
| « [capture copy] », « [read copy] » | **red** (the shallow copy) | green |
| « [clock] » | green | green |
| « [profile] » (control) | green | green |
| « [services] » | **red** (C-M1) | **red** |
| « [hours] » | green | **red** |
| « [before-after] » | **red** | **red** |
| « [artists] » | **red** (C-M1) | green |
| « [featured] » | **red** (the restore writes `false` back) | green |
| « [rating] » | **red** (0, not 4.5) | **red** (document 0) |
| « [rating column] » | n/a | **red** (column 4.5, document 0) |
| « [snapshot kept] » | **red** | green |
| « [bad snapshot] » | **red** (`ran`, not refused) | **red** (same) |

Each part runs as its own test, so one red does not hide the next.

### 8.2 Green

All of §8.1 green on both twins. The existing `demo_reset_test.dart` stays green, its `updateProfile`-built services included. Then the full backend suite on a fresh local database; `dart analyze` 0; `dart format` clean.

### 8.3 Mutations, on committed code, each with the failure text required

| | The mutation | Must go red, with |
|---|---|---|
| m1 | the `replaceServices` call removed, and `services` out of `kDemoRestoredByOwnWriter`, so services fall back to the merge | Postgres « [services] »; **in memory stays green** (C2: the merge restores the document's list there) |
| m2 | the `replaceAvailability` call removed | « [hours] » on Postgres; in memory too, since `availability` no longer rides the merge |
| m3 | the `updateBeforeAfters` call removed | « [before-after] », both twins |
| m4 | `featured` out of `kDemoNeverRestored` | in memory « [featured] » |
| m5 | `rating` out of `kDemoNeverRestored` | « [rating] », both twins |
| m6 | the in-memory capture back to `Map.from` | in memory « [capture copy] », « [services] », « [artists] » |
| m7 | the in-memory read hands out the stored map | in memory « [read copy] » |
| m8 | Postgres `replaceServices` inserts with the default `created_at` | « [order] » (the raw `created_at` check; a list-order check alone could pass on ties) |
| m9 | Postgres `replaceServices` skips the delete | the 23505 `provider_services_pkey` error, in « [replace] » and in every Postgres restore case (§8.3's controls exempt it) |
| m10 | a second caller of `replaceServices` | the caller guard (§6) |
| m11 | the profile merge moved after `replaceAvailability` | Postgres « [hours] » (the blocked day a day early) |
| m12 | in-memory `replaceServices` stores its argument itself | in memory « [copy] » |
| m13 | the shape check removed | « [bad snapshot] », both twins |
| m14 | the in-memory foreign-id refusal removed | in memory « [foreign id] » |

**Controls.**
- **C1:** « [profile] » stays green under every mutation, except m9 on Postgres, where the restore throws before any assertion.
- **C2:** m1 leaves the in-memory run green, which shows the two runs tell the twins apart.

### 8.4 The rest

- **The key guard (§5.1):** a hand-written list of the document keys the owner's writers can set must each be in `draftSalonDocument` or in `kDemoRestoredByOwnWriter`. It sees `beforeAfters` today.
  - **What it cannot see:** a writable key added to a writer without being added to its list. Its comment says so, and names the writers it was read from: the profile PATCH (with the logo and the market keys), the deposit policy, the gallery, the before/after pairs, the artists, the services and the hours.
- The caller guard of §6.

### 8.8 As built (B16.2, 2026-11-25)

Branch `fix/b16-2-demo-reset` from `main` (`afd2de97`). Two commits: the tests red first (`d11c98f3`), then the fix (`8413a3f1`).

- **Red first,** on a fresh local database, for the reasons of §8.1:
  - **in memory:** every `replaceServices` case (`UnimplementedError: B16.2`; « [foreign id] » on its own reason); « [capture copy] », « [read copy] »; « [services] », « [before-after] », « [artists] », « [featured] », « [rating] » (0 for 4.5), « [snapshot kept] », « [bad snapshot] » (`ran`, not refused); the key guard (`beforeAfters`) and the caller guard. Green: « [clock] », « [profile] », « [hours] ».
  - **on Postgres:** every `replaceServices` case; « [services] », « [hours] » (buffer 0 for 10), « [before-after] », « [rating] », « [rating column] » (4.5 against 0), « [bad snapshot] ». Green: « [profile] », « [artists] », « [featured] », « [snapshot kept] », the snapshot store.
- **The code:**
  - `replaceServices` on both twins (`providers_repository.dart`, `postgres_providers_repository.dart`), `addService` and it sharing one column mapping (`_serviceParams`);
  - the in-memory snapshot store's JSON copies (`demo_snapshot_repository.dart`);
  - `kDemoNeverRestored`, `kDemoRestoredByOwnWriter`, the shape check and the restore order (`demo_reset_service.dart`);
  - the maintenance tick's comment names `refused:bad_snapshot`.
- **Green:**
  - in memory: the three contracts, both guards, and every demo, maintenance, admin and multi-pays test (176);
  - on Postgres: the three contracts (21);
  - the full backend suite on a fresh local database: **3089 passed, 2 skipped**, exit 0, every Postgres file run;
  - analyze 0, format clean.
- **Mutations,** on committed code, with a clean tree, each edit checked to apply once and to change its file. All six targets were green unmutated first (C0). m1–m14 each went red with the texts of §8.3:
  - **C1 held:** no « [profile] » failure under any mutation but m9 on Postgres.
  - **C2 held:** m1 leaves the in-memory run green.
  - **m8 was rerun alone.** Its required text was at first « [order] », which the test's name also carries, so the match proved nothing. Rerun alone, it failed with its reason, « is not after », and turned « [replace] » red too: on equal `created_at` values, Postgres returns the list in any order.
- **Where the build differs from §8, and why:**
  - **`demo_reset_test.dart` changed, where §8.2 said it stays as it is:**
    - its two services gain the duration every stored service has, or the shape check refuses them, rightly;
    - each test gets its own empty store. With no argument, `InMemoryProvidersRepository()` **is** the global `seedProviders` list, so each earlier test's demo salon stayed in it with the same service ids, `s1` and `s2`. `replaceServices` now refuses those ids, as Postgres would (§12).
  - **Both guards are in one file,** `test/demo/demo_reset_guards_test.dart`: the key guard (§8.4) and the caller guard (§6).
- The throwaway local databases were dropped.

---

## 9. Rollout & scope discipline

1. **Build,** in its own backend PR, on the owner's word (Q5); merge on the owner's word.
2. **Read production before the deploy** (Q4), read-only, batch 14's method: the Auth Proxy, a read-only session, a probe write refused, counts and booleans only. `providers.data` is decoded in both forms, as in B16.1's read: production stores it as a JSON string inside `jsonb`, where `data->>'rating'` reads NULL. `demo_snapshot.doc` is decoded the same way. What it reads:
   - the snapshot's `captured_at` and `last_reset_at`;
   - whether the live demo salon's services equal the snapshot's (count, ids, each field, the order);
   - whether its hours equal the snapshot's;
   - whether it has before/after pairs that the snapshot lacks;
   - whether its `rating` column equals its document;
   - how many reviews it has;
   - whether the snapshot's `verified` is `false`.

   What happens next depends on the result:
   - **The live demo equals the snapshot:** deploy.
   - **It differs:** the owner looks at the demo salon in the Pro app and chooses between two options:
     - **recapture first**, so the live state becomes the snapshot (`POST /admin/demo/snapshot`, an admin action, the owner's);
     - **or let the reset restore the snapshot.**
3. **Deploy** on the owner's word. Nothing runs at the deploy. The first fixed reset is the next one due, 7 days after `last_reset_at`, on the nightly maintenance tick.
4. **Read after that reset,** read-only, on the owner's word:
   - the tick answered `ran`;
   - the live demo equals the snapshot (services, hours, pairs);
   - the `rating` column equals the document.

**Rollback.** Safe: no migration. An older image restores through `updateProfile` again, so services and hours stop being restored, which is today's state.

**Residual.**
- **The reset is a sequence of writes, as today, not one transaction.** A failure partway leaves a partly restored demo.
- **A throw still escapes the tick before the salon purge.** That is today's behaviour, from the database for instance. And since `markReset` comes last, a throw repeats each night until its cause is gone.
- The shape check removes the new writers' predictable causes, and `replaceServices` itself is atomic, so a salon is never left with half a catalogue.

### 9.1 As run

**Step 1, the merge.** #869 merged on 2026-11-25 at 16:21 UTC as `59409ef0`, on the owner's « Yes, merge it ». `main`'s tree equals the tested head `6b10a56f`; no attribution line; 12 checks of 12. `main` had moved three times while it waited (#867, #868 with #870, #871), and was merged in each time, with no rebase.

**Step 2, the read before the deploy,** on the owner's « Yes, run the read », 2026-11-25 at 18:12 UTC.
- **Method:** the Auth Proxy; a session read-only by default and again inside `BEGIN READ ONLY … ROLLBACK`; the probe write refused (« cannot execute UPDATE in a read-only transaction »). It prints counts, booleans, timestamps and key names only. Both documents decoded in both forms: the salon's `data` is stored as a string, the snapshot's `doc` as an object.
- **Dry run first,** on a throwaway local database holding a demo salon with planted differences: a price, a service another salon owns, a new service, the buffer, the windows, the breaks, the blocked days, the pairs, the ratings and the profile keys. Each answer was the planted one. That database was dropped.
- **What it read:**

| What | Result |
|---|---|
| The snapshot | captured 2026-10-14 18:57 UTC; last reset 2026-11-23 03:30 UTC; next due 2026-11-30 03:30 UTC |
| The shape check (`_badSnapshotKey`) | passes: services, availability and pairs are all `ok`, so the reset will not answer `refused:bad_snapshot` |
| Services | 5 and 5: the same ids, in the same order, every field equal; none created since the capture or the last reset |
| Would `replaceServices` refuse? | no: no snapshot service id belongs to another salon, and no foreign key points at `provider_services` |
| Working hours | 6 windows on each side, equal as multisets |
| `bookingHorizonDays`, `minimumNoticeMinutes` | equal |
| **`bufferMinutes`** | **differs** (the values were not printed) |
| **Breaks** | **snapshot 0, live 2** |
| Blocked days | none on either side |
| Before/after pairs | 1 on each side, equal |
| Ratings | 0 in the column, the document and the snapshot; no reviews |
| `verified`, `featured` | `false`, `false` |
| Profile keys the merge restores | none differs |
| Artists | none on either side |

- **The owner's choice** (2026-11-26): « Let the reset restore ». No recapture. The first fixed reset sets the buffer back to the snapshot's value and removes the two breaks. The database cannot tell who made those two changes since the capture; they lasted because, until this build, the reset never put the hours back in production.

**Step 3, the deploy,** on the owner's « Yes, deploy it », 2026-11-26.
- `deploy-backend.yml`, production, `image_tag=59409ef`, from `main` at `8159fb84` (run 45806355169, success). Since `59409ef0`, `main` changed only `ci.yml` outside the server's code, so the service file is the one #869 was built with. The image was promoted, not rebuilt.
- **Not in this image:** R1 (#872) and its migration `0052`, merged after #869. Its deploy is its own.
- **Read back:**
  - `myweli-api-00060-bwq` takes 100 % of the traffic, follows the latest revision (no pin) and carries the label `commit: 59409ef`;
  - it runs `sha256:ae809211e2ef…`, read in the registry as the `linux/amd64` child of the index `sha256:11199f83c05a…` that #869's merge run pushed (run 45652903430);
  - `/health` answers 200 with `env: prod`, on `api.myweli.com` and on the service's `status.url`;
  - no log line at WARNING or above from the new revision in its first minutes;
  - `production-checks.yml`, dispatched after the deploy (run 45806803926): 12 checks of 12.
- **Rollback:** `myweli-api-00059-w28` (image `351568e`, A4-api). Safe: no migration.

**Step 4, the read after the first fixed reset:** not yet. The reset is due 2026-11-30 03:30 UTC; the read runs after it, on the owner's word.

---

## 10. Definition of done (for the build)

- [ ] §8.1 red first for the stated reasons, then green; §8.3's mutations red with their texts, C1 and C2 held.
- [ ] Full backend suite green; analyze 0; format clean.
- [ ] `kDemoNeverRestored` and `kDemoRestoredByOwnWriter` named, with the comment at `:143-145` rewritten; `replaceServices` and the snapshot store link this spec.
- [ ] BACKEND.md §7 T69; [backend-demo-review-account.md](backend-demo-review-account.md) §6.2 gains a dated line (the restore did not reach services or hours until B16.2); the maintenance tick's doc comment names `refused:bad_snapshot`; BACKLOG B16.2, this spec's status, the index row and a roadmap entry.
- [ ] Feature branch and PR; CI green; owner-authored, no attribution.

---

## 11. Questions for the owner — answered 2026-11-25, « Approve as recommended » (decisions 250–254)

Numbered from **250**, after the revenue analytics spec's 237–249.

**Q1. How does the reset put the services back?**
- **Recommended: a new writer, `replaceServices`,** used only by the reset: one transaction, the snapshot's list in its order, never taking another salon's service, with a contract on both twins (§5.2). → ✅ **Decision 250.**
- Or the existing service writers, diffed: no new writer, but not atomic, and a curated service a reviewer deleted comes back last.

**Q2. What should the reset leave alone?**
- **Recommended: `featured` and the two ratings, with `id`, `slug` and `status` as today** (§5.1). `featured` is the admin's flag; the ratings are computed from the reviews, which the reset keeps. → ✅ **Decision 251.**
- Or restore the ratings too, through `updateRatings`, so column and document agree, though not with the reviews.

**Q3. Before/after pairs a reviewer adds?**
- **Recommended: restored through their own writer,** to the snapshot's pairs or none, with the key guard of §8.4. → ✅ **Decision 252.**
- Or left as today: a reviewer's pairs stay until the owner recaptures.

**Q4. Read production before the deploy?**
- **Recommended: yes,** read-only, after the build and before the deploy (§9 step 2). A fixed reset undoes any change made since the 2026-10-14 capture, a reviewer's or yours alike; the read shows whether there is one, and you choose whether to recapture first. → ✅ **Decision 253.**
- Or deploy without reading, and let the first fixed reset restore the 2026-10-14 snapshot whatever has changed since.

**Q5. When?**
- **Recommended: build now as one backend PR, on your word;** then Q4's read, then the deploy, each on your word. → ✅ **Decision 254.**
- Or after B16.3 (a taken email), the third of decision 219's defects.

---

## 12. Found next to it

- **The profile PATCH answers with Postgres's stored document, not the salon.** `updateProfile` returns `data` as stored (`pg:400`), and `PATCH /providers/{id}` sends it back (`provider_catalog_service.dart:302`). Its `services`, `availability`, `featured` and `status` are therefore the document's copies:
  - for most salons, the empty lists and `draft` of creation;
  - for the demo salon, the services old resets merged in.

  The in-memory twin answers the live salon. The Pro app replaces its profile model with the answer (`pro_salon_profile_provider.dart:66`), and its profile screen reads none of those four fields; the website's handling was not read. A twin difference the survey did not list, for the providers group of batch 16. Not decided here.
- **The images a reviewer uploads** (a logo, gallery photos, before/after photos, artist photos) are left in storage once the restore stops pointing at them. [backend-upload-orphans.md](backend-upload-orphans.md) is about uploads nobody claims. Whether anything removes a claimed image that a later write dropped was not read. Not decided here.
- **Artists' ratings** ride the `artists` list in the document, so a restore puts back the snapshot's artist ratings while the reviews stay. It is the same class as `rating`, and unreachable while the demo salon has no reviews; Q4's read counts them.
- **C-D1:** when the reset wipes the agenda, disputes on those bookings cascade away in Postgres and stay in memory. That belongs to the disputes group of batch 16 (decision 221), not here.
- **The in-memory store built without an argument is the global seed list itself** (`_all = seed ?? seedProviders`, `providers_repository.dart:225`). `createSalon` appends to it, so the salons one test creates are in every later test of the same file. Found when `demo_reset_test.dart` met the foreign-id refusal (§8.8); its own tests are fixed here. 23 test files build `InMemoryProvidersRepository()` and share it the same way. With A-P6 (B16.11); not decided here.
- **Two sentences go false today, and true again with this build:**
  - the reset's comment, `demo_reset_service.dart:143-145`;
  - T69's « cures defacement » in BACKEND.md §7.

  Both are corrected in the build PR (§10).

---

## 13. Review log

- **2026-11-25, drafted.** Read: the reset and both snapshot stores; both providers twins' readers and writers; every writer the demo account can reach; the five demo locks; the reset's test. Probed on both twins with a throwaway test and a throwaway local database, both deleted after (§2.3).
- **2026-11-25, reviewed once by an independent read-only reader, told to refute it against the code.** Every line reference of §2 checked and right, except « five tables » (four). The key list of §5.1 holds: only `beforeAfters` is missing among the owner's writers. Folded in:
  - **The blocker:** m9 (the delete skipped) cannot fail with an assertion. `provider_services.id` is a global primary key, so the insert throws 23505, in every Postgres restore case too. m9's expected failure is now that error, and C1 exempts it.
  - **Should-fix, eight:**
    - m1 defined so it can fire (the call removed, not only the set);
    - the test's expected values taken as a JSON copy at the capture;
    - a snapshot the new writers cannot take refused before any write (`refused:bad_snapshot`), so it cannot block the salon purge each night; and an absent `services` or `availability` skips its writer rather than wiping it;
    - the production read decodes `data` in both forms;
    - `verified` classified, and checked by the read;
    - « [artists] » added (C-M1 reaches them in memory);
    - « [hours] » compared as sets, since its read has no `ORDER BY`;
    - « plain `INSERT`, never an upsert », a security property with its own case.
  - **The nits:**
    - the demo account's notification preferences and devices named as out of scope;
    - the PATCH answer (§12);
    - distinct reason texts;
    - the first contract moved to `test/providers/`;
    - unique service ids in the stored shape;
    - m2 red on both twins;
    - the timezone order made observable (m11);
    - two more mutations (m12, m14) and the shape check's (m13).
- **2026-11-25, answered:** « Approve as recommended », all five (decisions 250–254, batch 16 in the BACKLOG). Recorded at the same time: decision 249 (revenue analytics) changes the regenerated agenda in the same file (§1).
- **2026-11-25, built** (§8.8), on the owner's « Yes, build B16.2 »: red first on both twins for §8.1's reasons, then green; the full suite 3089 passed; m1–m14 red with their texts, C1 and C2 held.
