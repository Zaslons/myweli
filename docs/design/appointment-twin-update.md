# The bookings store's test twin — update only what Postgres updates

| | |
|---|---|
| **Module** | backend: `appointments` (the repository and its in-memory twin), `clients` (the guest-phone move) |
| **Status** | **Approved 2026-11-24.** The owner answered the five questions of §11 at once, « Approve as recommended »: decisions 214–218 in BACKLOG, batch 15 (B15.1 is the build). Built on the owner's word, in its own backend PR. |
| **Owner** | the project owner: the answers, the build's go, each merge, and the backend deploy it rides with, each on the owner's word |
| **Last updated** | 2026-11-24 |
| **PRD ref / phase** | none: test fidelity, behind the V1 booking flow · V1 |
| **ROADMAP entry** | [2026-11-24-appointment-twin-update-spec.md](../roadmap/entries/2026-11-24-appointment-twin-update-spec.md) |
| **Skills checked** | myweli-dev-guardrails · myweli-backend-guardrails · myweli-verification-guardrails · [BACKEND.md](../BACKEND.md) §1, §5 |
| **Related** | [appointment-currency-stamp.md](appointment-currency-stamp.md) §3.5 and §12 (where this was found) · `backend/test/appointments/appointment_repository_contract.dart` (the twin contract) · `backend/test/clients_phone_change_test.dart` (the guest-phone change) |

---

## 1. Goal & scope

**The defect class.** Most backend tests (the service and handler tests) build in-memory twins of the Postgres repositories directly. Only the repository suites run against Postgres. A twin that accepts what Postgres drops lets a service test pass for code that production would break. That is how a booking's currency went unstored for months (appointment-currency-stamp.md §2.3): the twin kept the field, Postgres never wrote it, and no test compared the two.

**This spec closes that class on one method,** `AppointmentRepository.update`, and on the habits of its in-memory twin that make it lie:

1. **It writes any key, and any value.** Postgres writes six keys, ignores the rest without a word, and throws on some values the twin stores (§2.1).
2. **It hands out its own maps.** Mutating what a read returned changes what it stores, where Postgres builds a fresh map every time (§2.4).
3. **It returns a key Postgres never reads back:** `endsAt` (§2.1).

**In scope:**
- one set of updatable keys, read by both twins;
- what a key outside it, or a value Postgres rejects, does (Q1);
- a dedicated in-memory move for the one caller that relies on the loophole today, the guest-phone change (Q2);
- copies on every in-memory return, in the shape Postgres returns (Q3);
- the twin contract that holds both twins to all of it, red first.

**Out of scope** (§12):
- the other repositories' twins;
- price types (`15000` against `15000.0`) and date normalisation;
- simulating the database's overlap guard in memory (Q4 keeps it documented instead).

**No user-visible change.** No production caller passes a key outside the six or a value Postgres rejects (§2.3), so production behaves the same with any answer to Q1.

---

## 2. What exists today (OBSERVED)

### 2.1 The two updates

**Postgres** (`backend/lib/src/db/postgres_appointment_repository.dart:155-205`) builds its `SET` clause from exactly six keys, one `if` each (`:161-186`):

| Key | Column | The value Postgres takes |
|---|---|---|
| `status` | `status` | any; `NULL` breaks `status text NOT NULL` and is rethrown |
| `appointmentDate` | `appointment_date` | `DateTime.parse(v as String)`: `null` or a non-string throws |
| `endsAt` | `ends_at` | the same as `appointmentDate` |
| `depositScreenshotUrl` | `deposit_screenshot_url` | text or `null` |
| `arrivedAt` | `arrived_at` | `null`, or a parsed string |
| `artistId` | `artist_id` | text or `null` |

- **Any other key is ignored without a word.** With none of the six it returns `byId(id)` (`:187`).
- **A reschedule onto an overlapping slot** trips the exclusion constraint, and it returns `null` (`:199-201`).
- **`endsAt` is written and never read back.** `_toDto` (`:206-232`) has no `endsAt` key, and `openapi.yaml` has none. The column exists for the exclusion constraint. `create` computes it from the duration (`:61`).

**In memory** (`backend/lib/src/appointments/appointment_repository.dart:185-201`):
- it merges **every** key but `currency` (`a.addAll(Map.of(changes)..remove('currency'))`, B14.1), whatever the value;
- it returns the stored map itself;
- it never returns `null` for an existing booking;
- after a reschedule, its reads carry `endsAt`, which a Postgres read never does.

The interface promises neither: « Merge [changes] into the stored appointment » (`:33-35`).

### 2.2 The probe

A throwaway test (not committed) created the same booking in both twins, then called `update` with seven keys: `status` and six that Postgres does not write. It ran against a disposable local Postgres 16 database, which was dropped afterwards.

| Key passed to `update` | In memory, read back | Postgres, read back |
|---|---|---|
| `clientPhone: +2250700000002` | `+2250700000002` | `+2250700000001` (unchanged) |
| `clientName: Koffi` | `Koffi` | `Awa` (unchanged) |
| `notes: après` | `après` | `avant` (unchanged) |
| `totalPrice: 1` | `1` | `15000.0` (unchanged) |
| `providerId: provider2` | `provider2` | `provider1` (unchanged) |
| `madeUpKey: x` | `x` | absent |
| `status: confirmed` (control) | `confirmed` | `confirmed` |

The control discriminates: the one key both twins write changed in both. Every other row differs.

**Aliasing, same probe:** after the caller set `notes` on the map `byId` returned, the next `byId` read `MUTATED-BY-CALLER` in memory and `avant` in Postgres.

### 2.3 Who calls `update`, and with what

Every call in `lib/` and `routes/`, found by searching for `.update(` and reading each one. The independent review (§13) searched again, including closures, tear-offs, `tool/` and `main.dart`, and found no other.

| Caller | Keys | All in the six? |
|---|---|---|
| `deposit_service.dart:115` | `depositScreenshotUrl` (the promoted key) | yes |
| `pro_appointment_service.dart:106` (arrived) | `arrivedAt` (an ISO string) | yes |
| `pro_appointment_service.dart:150` (status) | `status` | yes |
| `appointment_lifecycle_service.dart:198`, `_moveTo`: the client's reschedule and the salon's | `appointmentDate`, `endsAt`; plus `artistId` on the salon's path when it is non-empty | yes |
| `appointment_lifecycle_service.dart:54` → `:226` (cancel) | `status` | yes |
| **`clients_repository.dart:312`** (`InMemoryClientsRepository.changeGuestPhone`) | **`clientPhone`** | **no: relies on the loophole** |

**The one outlier is deliberate.** `InMemoryClientsRepository` takes the in-memory twin by type, and its own comment says why (`clients_repository.dart:126-127`): « its `update` merges any field, where the Postgres one ignores `clientPhone` ». The Postgres clients repository moves those bookings itself, with SQL inside its own transaction (`postgres_clients_repository.dart:236-238`: `UPDATE appointments SET client_phone = @new WHERE provider_id = @pid AND user_id = 'manual' AND client_phone = @old`).

**Every value is one Postgres accepts:** each date is an ISO string, and no caller passes `null` for `status` or a date.

**In `test/`:** a scan of every literal `update(id, {…})` map found 13 calls, and one key outside the six: `currency`, which the contract's immutability test passes on purpose (`appointment_repository_contract.dart:207`, the key at `:211`). The review found nothing that passes a map built elsewhere. The demo reset seeds through `bookManual`, not `update`.

### 2.4 Aliasing: two near-misses, no live defect

- **Every in-memory read hands out its stored maps:** `create` stores the caller's map and returns it (`:130-133`); `byId`, `listForUser`, `listForProvider` and `confirmedInWindow` return the stored maps; `update` returns the map it just changed.
- **Two places in production code work around it, and say so:**
  - `deposit_service.dart:96-101`, the deposit claim:
    > **Captured BEFORE the update.** `InMemoryAppointmentRepository.update` mutates and returns the very map `byId` handed out, so reading the column afterwards yields the NEW key under the fake and the OLD one under Postgres — a delete wired that way would target the object it just promoted, and only in tests.
  - `appointment_lifecycle_service.dart:88-91`, the reschedule:
    > Read BEFORE the move: a repository may hand back the very map it then updates in place (the in-memory one does), and reading after would report the new date as the old one.
- **No live instance found:**
  - in `lib/` and `routes/`, no code writes into a booking map it got from the store; the enrichments copy first (`{...a}`, `clients_service.dart:541`);
  - no code edits a map after passing it to `create`;
  - in `test/`, no test does either. Every write into a returned map belongs to the **salons** store (`providers.byId(...)`, e.g. `reviews_test.dart:61`, `salon_validation_bypasses_test.dart:129`), whose tests rely on it. That store is out of scope (§12).
- **What the search cannot see:** a write through a variable two hops away from the read. The contract test of §8.3 is the guard for that, not the search.

### 2.5 What CI runs

**CI runs both twins.**
- The backend job starts the runner's own Postgres and sets `DATABASE_URL` for `dart test` (`.github/workflows/ci.yml:136-161`). It has done so since B3c (#44, 2026-06-23).
- On the last `main` run (`45391087644`, at `78a6b1e0`), the twin contract passed in `appointment_repository_test.dart` (in memory) and in `postgres_repositories_test.dart` (Postgres), out of 2974 passed and 2 skipped.
- **The test files run concurrently against that one database** (`postgres_admin_provider_account_test.dart:43-50`).

**Two places say the opposite:**
- `docs/BACKEND.md` §5: « CI — which runs a bare `dart test` with no database — never executes them »;
- `backend/test/db/postgres_repositories_test.dart:981-983`: « CI runs `dart test` with no `DATABASE_URL` and every postgres-tagged suite self-skips ».

Both were written in #397 (2026-08-16), seven weeks after CI started setting the variable, so **they were false when written**. The defect they explain, an assertion that passed only once per database, escaped CI for another reason: each CI run starts from a fresh database. This PR corrects BACKEND.md. The build PR corrects the test comment, because this PR changes no code (§10).

---

## 3. API & contract

**None.** No route, DTO or `openapi.yaml` change. `update` is internal, and `endsAt` stays out of every response, as it is in production today.

## 4. Data model

**None.** No migration, no column, no backfill.

---

## 5. Architecture & design

### 5.1 One set of updatable keys

```dart
/// The keys `AppointmentRepository.update` writes: exactly the six the
/// Postgres `SET` builder knows. Both twins read this set.
const Set<String> kAppointmentUpdatableKeys = {
  'status', 'appointmentDate', 'endsAt',
  'depositScreenshotUrl', 'arrivedAt', 'artistId',
};
```

- **Where:** next to the interface, in `appointment_repository.dart`.
- **The Postgres builder keeps its six `if`s,** because each key has its own cast. A test checks that every key in the set reaches its column (§8.4).
- **`currency` stays out:** the stamp is immutable (multi-pays §4; appointment-currency-stamp.md §3.4).
- **`endsAt` is in the set but never read back,** on either twin (§5.4).

### 5.2 What `update` refuses (Q1)

**Recommended: refuse, in both twins, before any write,** what Postgres would ignore or reject.

```dart
/// Throws ArgumentError for a key outside [kAppointmentUpdatableKeys], or a
/// value the Postgres builder cannot store. Both twins call it first.
void checkAppointmentChanges(Map<String, dynamic> changes) { … }
```

**What it refuses:**
- **a key outside the set:** Postgres ignores it today;
- **`status` that is not a non-empty string:** `NULL` breaks `NOT NULL`;
- **`appointmentDate` or `endsAt` that is not a string `DateTime.tryParse` accepts:** Postgres's `as String` and `DateTime.parse` throw today;
- **`arrivedAt` that is neither `null` nor such a string;**
- **`depositScreenshotUrl` or `artistId` that is neither `null` nor a string.**

**What follows from that:**
- Where Postgres already threw (a `null` date, `null` status), it now throws `ArgumentError` earlier, and the HTTP answer is the same 500.
- Where it stayed silent (an unknown key), it now throws.
- The in-memory twin throws in exactly the same cases.
- **Nothing is half-written:** the check runs before any SQL and before any in-memory write.

**Why refuse rather than ignore:**
- Ignoring is what Postgres does today, and silence is exactly what hid the currency.
- A refusal turns the first test that passes such a key or value red, on both twins, instead of letting one twin keep it.
- In production it becomes a logged 500 with the standard envelope, instead of a write that silently didn't happen.

**Today's production callers are unaffected** (§2.3).

**The contract's immutability test changes shape:** « an update never changes `currency` » becomes « an update with `currency` is refused, and the stamp is unchanged ».

**The alternatives** (Q1):
- **ignore it in both twins:** the twins agree on keys, and silence stays; they still have to agree on values;
- **`assert`:** red in tests, silent in production, because the released binary is compiled without asserts.

### 5.3 The guest-phone move gets its own in-memory method (Q2)

`InMemoryAppointmentRepository` gains a method that is **not on the interface**:

```dart
/// The in-memory twin of `PostgresClientsRepository.changeGuestPhone`'s
/// UPDATE (postgres_clients_repository.dart:236-238): the salon's own
/// manual bookings carrying [from] move to [to]. Synchronous on purpose:
/// the caller's checks and every write happen with nothing yielding in
/// between, the twin of the row lock. Returns how many moved.
int moveGuestPhone({
  required String providerId,
  required String from,
  required String to,
});
```

- **It matches the SQL exactly:** `providerId` equal, `userId == 'manual'`, `clientPhone == from`. No other row moves.
- **`from` is a non-null `String`, so the caller keeps its guard.** A phone-less card adopts no one (`oldPhone != null`, `clients_repository.dart:309`), as the Postgres twin guards before its `UPDATE`.
- **`InMemoryClientsRepository.changeGuestPhone` changes in three places:**
  - it calls the new method instead of `Future.wait([... update(...)])` (`:304-313`);
  - it deletes the `listForProvider` read and its comment (`:271-273`), which nothing else uses. An unused local fails `dart analyze`;
  - with that `await` gone, nothing yields between the checks and the writes, so the comment at `:304-307` (« `update` has no await inside ») goes too.
- **Why not on the interface:** the Postgres twin must move the bookings inside the **same transaction** as the client card (`runTx`, `postgres_clients_repository.dart:177`). A method on `AppointmentRepository` would run on another connection, outside that transaction. The clients repository already takes the in-memory appointments twin by type (`dependencies.dart:529`), so nothing new leaks.
- **The existing tests are the guard:** `clients_phone_change_test.dart:680` onwards must stay green unchanged, apart from wiring. The review checked that none of them depends on the `Future.wait` yield; the race test fires before the write.

### 5.4 Copies on every in-memory return, in Postgres's shape (Q3)

- **What returns a copy:** `create` stores a copy of what it is given and returns another; `byId`, `listForUser`, `listForProvider`, `confirmedInWindow` and `update` return copies.
- **How deep:** maps and lists are copied recursively (`serviceIds` is a list), so no nested object is shared either.
- **The shape:** each copy omits `endsAt`, the one stored key Postgres's `_toDto` never returns (§2.1). Nothing reads it (searched in `lib/` and `routes/`: only the reschedule writes it).
- **Writes stay inside the twin:** `update`, `moveGuestPhone`, `anonymizeUser` and `wipeForProvider` change the stored map, never one handed out.
- **The two workarounds keep their reads-before** (`deposit_service.dart:96-101`, `appointment_lifecycle_service.dart:88-91`), which stay correct. Each comment gains one line: the twins now agree.
- **Cost:** a few map copies per call, in tests and the no-database dev mode only. Production runs Postgres.

### 5.5 What stays different, said plainly (Q4)

| Difference | Why it stays | Where it's said |
|---|---|---|
| An overlapping reschedule: Postgres returns `null` (exclusion constraint), in memory never | The service checks the slot first; the constraint catches only a race between two requests, which a single-threaded fake cannot produce. `create` already documents the same gap (`:5-9`). | The interface's `update` doc, which gains the sentence `create` has |
| Price type: Postgres `15000.0` (`numeric`), in memory whatever was passed | No code casts a price `as int` (searched in `lib/` and `routes/`) | §12 |
| Dates: Postgres returns UTC ISO strings, in memory what was passed | Every writer passes UTC today | §12 |

### 5.6 Layering

No layer moves:
- services call `update` exactly as now;
- the set and its check live with the interface;
- the guest-phone move stays inside the clients repository's in-memory twin, as its Postgres twin's SQL stays inside its own.

---

## 6. Security & authz

- **No authz change.** `update` is reached only after the services' ownership checks, as today.
- **Integrity, a small gain:** a future caller can no longer write a key one twin keeps and the other drops, such as `clientPhone`, `providerId` or `totalPrice`. Today the in-memory twin would let a test « prove » a price change that production silently refuses to store.
- **Threat model (BACKEND.md §7):** no new endpoint or trust boundary, so no new row.

## 7. Performance

- **Postgres:** one set difference and a few type checks before the SQL. That is nothing next to a round trip.
- **In memory:** copies are proportional to what each read returns. In tests that is microseconds.

---

## 8. Testing plan — red first, on committed code

The contract file (`appointment_repository_contract.dart`) runs on both twins: in memory in `appointment_repository_test.dart`, on Postgres in `postgres_repositories_test.dart`, and CI runs both (§2.5). Every test below goes in the contract unless it says otherwise.

### 8.1 The five readable keys round-trip

`update` with each of `status`, `appointmentDate`, `depositScreenshotUrl`, `arrivedAt` and `artistId` alone, then `byId`, reads the new value. Green today on both twins; it is the control for §8.2. `endsAt` is not readable (§8.4 covers it).

### 8.2 What Postgres would drop or reject is refused (Q1 as recommended)

- **Each key outside the set:** `clientPhone`, `clientName`, `notes`, `totalPrice`, `providerId`, `currency` and an invented key. Each is sent **with** `status`, and:
  - `update` throws `ArgumentError`;
  - the booking is unchanged: `byId` still reads the old `status`, which proves nothing was half-written.
- **Each bad value:** `status: null`, `appointmentDate: null`, `appointmentDate: 'not a date'`, `endsAt: 42`, `arrivedAt: 'yesterday'`, `artistId: 7`. Same two expectations.
- **Red today on both twins:**
  - in memory, the unknown key or the bad value is stored;
  - Postgres ignores the key and writes the `status`, or throws something other than `ArgumentError` after building the query.
- **The immutability test** is rewritten into this form (§5.2).

### 8.3 What a twin hands out is not what it stores, and has Postgres's shape

- **For each of `create`, `byId`, `listForUser`, `listForProvider`, `confirmedInWindow` and `update`:**
  - mutate the returned map, a nested `serviceIds` entry included;
  - read again: the stored value is unchanged.
- **The same for the map passed to `create`:** mutating it afterwards changes nothing stored.
- **After an `update` carrying `endsAt`,** no read returns an `endsAt` key, on either twin.
- **Red today in memory, green on Postgres.**
- **The recording wrapper (`_Recording`, `:252-310`)** deep-copies because of this. Once both twins copy, its comment changes, and its copying stays as a belt.

### 8.4 Every key in the set reaches its column (Postgres suite)

- For each key in `kAppointmentUpdatableKeys`, an `update` with that key alone changes its column, read back with SQL (`SELECT ends_at, …`), not through the DTO. This is the only way to see `endsAt`.
- **The other direction is not tested, and does not need to be.** A seventh `if` added to the builder without its key in the set can never run: the refusal fires first, so the new key is refused. The test its author writes for it turns red at once.

### 8.5 The guest-phone move

- **Unit, in memory:**
  - only the salon's own `manual` bookings carrying the old phone move;
  - another salon's booking with the same phone, a client booking (`userId` not `manual`) and a booking with another phone stay put;
  - it returns the count that moved.
- **Through `changeGuestPhone`:** a phone-less card moves no booking, including the salon's phone-less walk-ins.
- **Red first:** the method does not exist.
- **`clients_phone_change_test.dart`** stays green on its existing assertions, which proves the refactor kept the behaviour.

### 8.6 Mutations, on committed code, each with the failure text required

| # | Mutation | Must turn red, and why |
|---|---|---|
| m1 | In memory: the check removed (back to merge-all) | §8.2, in memory: the key comes back |
| m2 | Postgres: the check removed (back to ignore) | §8.2, Postgres: no `ArgumentError` |
| m3 | The check stops validating `status` | §8.2: `status: null` accepted in memory |
| m4 | In memory: `byId` returns the stored map | §8.3 `byId` |
| m5 | In memory: `create` stores the caller's map | §8.3, the `create` argument |
| m6 | In memory: a shallow copy (`Map.of`) instead of a deep one | §8.3, the nested `serviceIds` |
| m7 | In memory: copies keep `endsAt` | §8.3, `endsAt` returned |
| m8 | `moveGuestPhone` without the `providerId` filter | §8.5: another salon's booking moved |
| m9 | `moveGuestPhone` without the `userId == 'manual'` filter | §8.5: a client booking moved |
| m10 | `'artistId'` dropped from `kAppointmentUpdatableKeys` | §8.1 and §8.4: the artist change refused |

**Controls that must stay green:**
- C1: with m1 applied, the five-key round trip (§8.1);
- C2: with m4 applied, the Postgres run of §8.3.

### 8.7 The rest

- `dart format` clean;
- `dart analyze --fatal-infos --fatal-warnings` = 0;
- the full backend suite with `DATABASE_URL`, then CI green.

---

## 9. Rollout & scope discipline

**This PR:** the spec, its index row, a roadmap entry, and BACKEND.md §5's CI sentence corrected (§2.5).

**The build, one backend PR, in its order:**
1. the tests red first, recorded;
2. the code;
3. the comments of §10, and a roadmap entry.

**Merge on the owner's word.** It builds an image and deploys nothing.

**No deploy of its own (Q5).**
- What changes in production is the Postgres check, and only for a key or value no caller passes.
- It rides the next backend deploy, which is dispatched on the owner's word as always. Its read-back adds nothing: `/health` and the revision suffice.

**Rollback:** safe at any step. Nothing is stored differently, and an older revision simply goes back to ignoring unknown keys.

---

## 10. Definition of done (for the build)

- [ ] §8.2–§8.5 committed red first and watched red on committed code; §8.1 green as the control.
- [ ] m1–m10 red with their named failure text; C1 and C2 green; each mutation asserted to have changed the file.
- [ ] Format clean, analyze = 0, full suite with `DATABASE_URL` green, CI green.
- [ ] Every comment that described the old behaviour rewritten:
  - the interface's `update` doc (`appointment_repository.dart:33-35`), which also gains the overlap sentence (§5.5);
  - the in-memory `update`'s own comment (`:191-195`, « the full six-key whitelist would break … »);
  - `postgres_appointment_repository.dart:13-14` (« `update` has no branch for it »): immutability is now a refusal;
  - `clients_repository.dart:126-127`, `:271-273` and `:304-307`;
  - `deposit_service.dart:96-101` and `appointment_lifecycle_service.dart:88-91`;
  - the contract's header (`appointment_repository_contract.dart:19`, « stores the caller's own map ») and `_Recording` (`:252`);
  - `postgres_repositories_test.dart:981-983`, the false CI sentence (§2.5).
- [ ] `// Design: docs/design/appointment-twin-update.md` beside the key set, its check and `moveGuestPhone`.
- [ ] Feature branch and PR; commits authored as the owner, with no attribution; merge on the owner's word.

---

## 11. Questions for the owner — answered 2026-11-24, « Approve as recommended » (decisions 214–218)

Numbered from 214, because A3's spec (#851) holds 204–213.

**Q1. What `update` cannot store: refuse it, in both twins?**
- **Recommended: refuse** (`ArgumentError`, before any write) both a key outside the six and a value Postgres rejects. The twins agree, and a mistake turns the first test red instead of passing in one twin. No production caller sends either today. → ✅ **Decision 214.**
- Or **ignore** unknown keys in both, and check only values: the twins agree, but silence stays, the trait that hid the currency.
- Or **`assert`**: red in tests, silent in production.

**Q2. The guest-phone move: a dedicated in-memory method?**
- **Recommended: yes**, `moveGuestPhone`, mirroring the Postgres SQL exactly. It stays off the interface, because the Postgres move must share the client card's transaction (§5.3). → ✅ **Decision 215.**
- Or keep it on `update` with a test-only escape: the loophole survives under another name.

**Q3. Copies on every in-memory return, in Postgres's shape?**
- **Recommended: yes, deep copies without `endsAt`,** so a caller can never change what is stored by editing what it was handed, and never reads a key production doesn't send. That's how Postgres behaves, and it retires the two workarounds' reason to exist (§2.4). → ✅ **Decision 216.**
- Or keep aliasing and document it: the next near-miss stays possible.

**Q4. The overlapping reschedule (`null` from Postgres only)?**
- **Recommended: document it on the interface,** as `create` already does. The service's own slot check runs first; only a race reaches the constraint. → ✅ **Decision 217.**
- Or simulate the exclusion constraint in memory: more fake logic to keep in sync with the real one.

**Q5. When?**
- **Recommended: build it now, after your go, as its own PR.** It needs no deploy of its own: production gains only the check, for keys and values no caller sends, at the next backend deploy. → ✅ **Decision 218.**
- Or wait for the next backend batch.

---

## 12. Found next to it

- **BACKEND.md §5 said CI never runs the Postgres suites. It does** (§2.5). This PR rewrites the clause: CI runs them on a fresh database, with the files running concurrently against it, and only a developer's local Postgres runs them twice against the same one. The rule the clause introduces, that the suites must be re-runnable against the same database, still holds. The same false sentence in `postgres_repositories_test.dart:981-983` is code, so the build PR fixes it (§10).
- **Out of scope: the salons store's twin also hands out live maps,** and its tests rely on that to set up state: `reviews_test.dart:61`, `salon_validation_bypasses_test.dart:129`, and the availability fixtures in `appointments_test.dart` and `appointment_lifecycle_test.dart`. Copying there would break them. It needs its own look.
- **Out of scope: price types.** Postgres returns `numeric` columns as doubles (`15000.0`), and the in-memory twin keeps whatever was passed. No code casts a price `as int` today; a future one would pass in memory and crash on Postgres.
- **Out of scope: other twins.** Whether the other in-memory repositories store keys their Postgres twins drop was not surveyed. The method of §2.2 (one probe, both twins, a control key) is how to look.

---

## 13. Review log

- **2026-11-24, drafted** from a read of both twins, every caller (§2.3), a throwaway two-twin probe on a disposable local database (§2.2, dropped after), and the last `main` CI log (§2.5).
- **2026-11-24, read once by an independent reviewer,** told to refute it: 1 blocker, 5 should-fix, 3 nits. All folded in:
  - **blocker:** `endsAt` is written and never read back by Postgres, so the draft's « six-key round trip, green on both twins » was false. Now: five readable keys (§8.1), `endsAt` checked with SQL (§8.4), and the in-memory copies drop it (§5.4, §8.3, m7);
  - a second aliasing workaround (`appointment_lifecycle_service.dart:88-91`, §2.4);
  - three comments the build makes false (§10);
  - the false CI sentence also in a test file, and CI's shared concurrent database (§2.5, §12);
  - the guest-phone caller's unused read and its `oldPhone` guard (§5.3, §8.5);
  - the value checks Postgres makes and the twin doesn't (§2.1, §5.2, §8.2);
  - the reschedule row, three line numbers, and §1's framing.
  - **The review confirmed:** the six keys, the complete caller list (it searched closures, tear-offs, `tool/` and `main.dart` too), the 13 test calls, that nothing would start throwing, and that no code relies on aliasing.
- **2026-11-24, approved:** the owner answered §11 at once, « Approve as recommended » (decisions 214–218).
