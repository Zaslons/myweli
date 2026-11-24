# A salon's category reaches the column discovery filters on (B16.1)

| | |
|---|---|
| **Module** | backend: `providers` (the Postgres repository's `updateProfile`, one migration) |
| **Status** | **Approved 2026-11-24.** The owner answered the four questions of §11 at once, « Approve as recommended »: decisions 224–227 in BACKLOG, batch 16 (#857). **B16.1 built 2026-11-24** (§8.8), on the owner's « Yes, build B16.1 », in its own backend PR, #860; not merged. The merge, the deploy and the read after, each on the owner's word. |
| **Owner** | the project owner: the answers, the build's go, the merge, the deploy and the read after it, each on the owner's word |
| **Last updated** | 2026-11-24 |
| **PRD ref / phase** | FR-DISC (discovery by category) · V1 |
| **ROADMAP entry** | [2026-11-24-provider-category-column-spec.md](../roadmap/entries/2026-11-24-provider-category-column-spec.md) |
| **Skills checked** | myweli-dev-guardrails · myweli-backend-guardrails · myweli-verification-guardrails · [BACKEND.md](../BACKEND.md) §1, §5 (decision 223) |
| **Related** | [twin-fidelity-survey.md](twin-fidelity-survey.md) §2.1 (where this was found, A-P1) and §6 (decisions 219–220) · [pro-salon-lifecycle.md](pro-salon-lifecycle.md) L1 (since when a salon edits its category) · [appointment-currency-stamp.md](appointment-currency-stamp.md) §3.3 (the decode of `providers.data`) |

---

## 1. Goal & scope

**The defect.** A salon's category lives in two places: its document (`providers.data`) and a `category` column. Discovery's category filter reads the column. Only salon creation writes it; a salon that changes its category in its profile changes the document alone. So once that salon is public, discovery lists it under its old category and hides it under its new one, in both apps and on the website, while its own page shows the new one.

**It has already happened once in production** (§2.4): one of the 9 salons has column `salon` and document `barber`. All 9 are drafts today, so the filter lists none of them now. Whether that salon was ever public before, and so ever listed under the wrong category, was not read.

**In scope:**
- `updateProfile` keeps the `category` column in step with the document, as it already does for name, description, address and commune (§5.1);
- one migration that copies each salon's document category into its column, once (§5.2);
- a contract on both twins: a profile change reaches every filter that reads a column `updateProfile` keeps (§5.3, decision 223);
- the read after the deploy (§9).

**Out of scope:**
- the demo salon's reset (B16.2). This fix makes the reset's restore reach the category column too, which is one of survey §2.2's five; the rest stay B16.2 (§12 adds a sixth, `rating`);
- the free-text search's wildcards (A-P3, B16.8). The contract's text cases use plain letters, so the twins agree on them;
- any client change. The apps and the website already send the category; §12 names two client gaps found on the way (the website's `nail`, the app's three chips), each its own fix.

**Architecture.** Repository layer only: one more column in `PostgresProvidersRepository.updateProfile`'s sync list, and one migration. No route, service, contract (`openapi.yaml`) or DTO changes. The in-memory twin needs no change: it filters on the document, which is what the fix makes Postgres agree with.

---

## 2. What exists today (OBSERVED)

### 2.1 The two places, and who writes each

- **The column:** `category text`, nullable, indexed (`migrations.dart:52`, `:60`).
- **The filter reads the column:** `query(category:)` adds `category = @category` (`postgres_providers_repository.dart:39-41`).
- **Creation writes both:** `createSalon` inserts the column and the document with the same value (`:700-709`). The seed does the same (`migrations.dart:1597-1604`).
- **A profile change writes the document only:** `updateProfile` merges the changes into `data` and syncs `name`, `description`, `address` and `commune` into their columns (`:350-381`, the list at `:369`). Not `category`.
- **The in-memory twin reads the document:** `p['category'] != category` (`providers_repository.dart:229-231`). So it filters as the salon's page reads, and Postgres does not.

### 2.2 Who changes a salon's category

- **The salon, from its profile:** `PATCH /providers/{id}` (`routes/providers/[id]/index.dart:61`) → `ProviderCatalogService.updateProfile`, where `category` is in the editable list (`provider_catalog_service.dart:192-205`, since pro-salon-lifecycle L1) and must be one of `salon`, `barber`, `spa`, `nails`, `massage` (`:421-424`).
- **The demo reset:** it sends the captured document back through `updateProfile` (`demo_reset_service.dart:143-148`), category included.
- **No other caller** of `updateProfile` sends a category (`provider_account_service.dart:187`, `salon_provisioning_service.dart:163`, `:285`, `salon_directory_service.dart:210`, `:220`, `admin_kyc_service.dart:178`: contact erasure, market fields, `verified`).
- **At creation,** the category comes from the account's business type (`SalonProvisioningService.categoryFor`, `salon_provisioning_service.dart:108-114`): `salon` and `other` become `salon`. A salon registered as « salon » or « other » and then set to « barber » in its profile fits the production case of §2.4; which of the two it was is not read.

### 2.3 Who reads the filter

- **The apps:** the home category chips call `GET /providers?category=` (`mobile/lib/services/api/api_provider_service.dart:36`); they offer `barber`, `salon` and `spa` only (`mobile/lib/widgets/home/category_chips.dart:12-17`).
- **The website:** the area × category landing pages (`web/lib/api/providers.ts:61-70`, `listProviders`), the category and city landing pages (`web/components/landing/TaxonomyLandingView.tsx:134`), `/recherche?category=`, and the home page's category links (`web/app/page.tsx:36-38`).
- **Nothing else reads the column:** no raw SQL in `lib`, `routes` or `tool` selects or filters on it (checked by the review, §13).

### 2.4 Proven twice

- **On both twins (survey §3.1, A-P1):** `updateProfile('provider3', {'category': 'nails'})` on a `barber` salon, then the filter. The document reads `nails` on both twins (the control). Listed under `nails`: in memory yes, Postgres **no**. Under `barber`: in memory no, Postgres **yes**.
- **In production (decision 220, read 2026-11-24, 20:38:53–20:39:01 UTC, read-only):** batch 14's method: the Cloud SQL Auth Proxy, stopped after; the database URL in environment variables only; the session `default_transaction_read_only=on`, every query in `BEGIN READ ONLY … ROLLBACK`; a probe write refused. The query was run first on a throwaway local database with one row per case (both document forms, a match, a mismatch, a null on each side, an unreadable document), where the probe write passed without the setting and was refused with it; that database was dropped. Aggregates only:

  | | |
  |---|---|
  | the column | `category`, `text`, nullable |
  | salons, and documents that decode (decoded `id` = row `id`) | 9 · 9 |
  | `draft`, column = document | 8 |
  | `draft`, column ≠ document | **1: column `salon`, document `barber`** |
  | any other status, null, or unreadable document | none |

  No salon is public, so the filter shows none of them today. When that salon goes live, it would be listed under `salon` (« Coiffure » on the website) and not under `barber` (« Barbier »).

### 2.5 Why no test saw it

- The Postgres filter test reads the seed, where column and document agree (`postgres_repositories_test.dart:1158-1165`).
- The catalog's category test checks the document through `byId` (`provider_catalog_test.dart:1386-1397`), and runs on the in-memory twin.
- No test changes a category and then filters on Postgres. Survey §4: the providers store has a contract on both twins for its suspension only.

---

## 3. API & contract

No change. `GET /providers?category=` and `PATCH /providers/{id}` keep their shapes; only which salons the filter returns becomes right.

## 4. Data model

**No schema change.** One data migration, `0050_provider_category_from_document` (the next free id when written; renumbered if another merges first), with one statement, `kProviderCategoryFromDocument` (§5.2). It is an `UPDATE`, not DDL, so it is not `rollback-unsafe`: an older image reads and writes the same columns as before.

---

## 5. Architecture & design

### 5.1 `updateProfile` keeps the category column (Q1)

`category` joins the columns `updateProfile` syncs, in the same `UPDATE` as the document, inside the transaction that already holds the row `FOR UPDATE`. The list becomes a named constant with its reason, so the next column added to `providers` has one place to go:

```dart
/// The `providers` columns `updateProfile` syncs from the changes it is given,
/// in the same UPDATE as `data`, so a filter never disagrees with what
/// `updateProfile` wrote to the salon's page. Not every column that copies a
/// document field: `slug` never changes after creation, and `rating` has its
/// own writer, `updateRatings`. docs/design/provider-category-column.md §5.1.
const kProviderDocumentColumns = ['name', 'description', 'address', 'commune', 'category'];
```

A `null` category is written as `NULL` in both places, the document's rule. No caller sends one: the catalog refuses it (§2.2), and the demo reset restores a captured string. The migration of §5.2 is stricter on purpose: it never writes `NULL`.

**Rejected:**
- **A generated column** (`GENERATED ALWAYS AS (…) STORED`) could never drift. But it needs the column dropped and added again, which is `rollback-unsafe`: an older image's `createSalon` names `category` in its `INSERT` and would fail, so no salon could register after a rollback. And the expression would have to decode the double-encoded document (§5.2) on every write.
- **The filter reading the document:** the document is stored as JSON text inside `jsonb` (§5.2), so every category query would decode every row, with no index.

### 5.2 The salons already wrong: one migration (Q2)

```sql
UPDATE providers p
   SET category = d.doc ->> 'category'
  FROM (SELECT id,
               CASE jsonb_typeof(data)
                 WHEN 'string' THEN
                   CASE WHEN pg_input_is_valid(data #>> '{}', 'jsonb')
                        THEN (data #>> '{}')::jsonb END
                 ELSE data
               END AS doc
          FROM providers) d
 WHERE p.id = d.id
   AND jsonb_typeof(d.doc -> 'category') = 'string'
   AND p.category IS DISTINCT FROM d.doc ->> 'category'
```

- **The decode is batch 14's** (`kAppointmentCurrencyBackfill`, `migrations.dart`): every runtime-written document is a JSON string inside `jsonb`, so `data ->> 'category'` alone reads `NULL` (all 8 production documents were in that form on 2026-11-20, batch 14; `postgres_repositories_test.dart:1491-1497` pins the form). Nested `CASE`s, so the cast only sees text `pg_input_is_valid` accepted: one unreadable document is skipped instead of failing the migration, and with it every deploy.
- **It copies only a category that is JSON text:** a document with no category, a JSON `null`, a number or a boolean leaves the column as it is, so a doubtful row never loses its listing. §9's read reports such a row as `doc_null`, apart from `differs`.
- **It changes only rows that differ, and running it twice changes nothing.**
- **The document is the truth:** it is what the salon chose and what its page shows. The value is copied as it is, without checking it against the catalog's five; every path that writes it already checks (§2.2).
- **Tested before this spec** on a throwaway local database, in this final form (eleven rows: both forms matching, both forms differing, a null column, no key, a JSON `null`, a number, unreadable text, a JSON array, a JSON scalar, an object-form array): the first run changed the three rows it should (both differing forms and the null column) and nothing else; the second changed none; neither failed. The database was dropped. `id` is the primary key and `data` is `jsonb NOT NULL` (`migrations.dart:50`, `:57`), so neither a duplicate nor a NULL document can occur.
- **Exported as a constant,** so it can be run by hand after a rollback (§9).

### 5.3 The contract on both twins (Q3, decision 223)

A new contract, `test/providers/profile_filters_contract.dart`, run on the in-memory twin (`test/providers/profile_filters_test.dart`) and, `DATABASE_URL`-gated, on Postgres (the `PostgresProvidersRepository` group of `postgres_repositories_test.dart`). One case per column, **written out by hand**, through the filter that reads it:

| Column | Changed by `updateProfile` | Then |
|---|---|---|
| `category` | `barber` → `nails` | `query(category: 'nails')` lists it; `query(category: 'barber')` does not |
| `commune` | one commune → another | `query(commune:)` lists it under the new one only |
| `name`, `description`, `address` | each to a fresh plain word | `query(q:)` finds it by the new word, and no longer by the old |

- **Through the interface only:** each case creates its own salon with `createSalon`, makes it `active` with `setStatus` (the filters hide drafts), and the Postgres run deletes it after. The `providers` table keeps its seed, so cases assert « lists this id » and « does not list this id », never counts.
- **Plain letters for `q`:** no `%` or `_`, and no word inside another, so A-P3 (B16.8) cannot decide a case.
- **The cases are not generated from `kProviderDocumentColumns`.** A case built from the list would vanish with the column it tests, and the contract would stay green on exactly the mutation it is for. Instead, one more test checks that the set of columns the cases cover equals `kProviderDocumentColumns`: a column removed from the list turns both its case and that test red, and a column added later fails until it gets a case.
- **Each case reads the document first:** `byId` returns the new value, on both twins, before any filter is asked. A red after that line can only be the column.

### 5.4 Layering

Repository only (`lib/src/db/postgres_providers_repository.dart`) and the migration list (`lib/src/db/migrations.dart`). No service, route or DTO change.

---

## 6. Security & authz

No new surface. Who may change a category is unchanged: `PATCH /providers/{id}` under `profile.manage`, with the catalog's validation (§2.2). The migration copies values that already passed it. No threat-model delta.

## 7. Performance

One more column in an `UPDATE` that already runs. The migration reads 9 rows today and locks only the rows it changes (one, as read on 2026-11-24).

---

## 8. Testing plan — red first, on committed code

### 8.1 The contract (§5.3)
On the in-memory twin: green before the fix (it reads the document). On Postgres: the `category` case **red before the fix**, the others green; then green after. The `category` case asserts in this order, and its red is the second line: `byId` reads `nails` (the control) → **« listed under the old category »** (`query(category: 'barber')` still lists it) → « not listed under the new category ». The coverage test (§5.3) is green before and after.

### 8.2 The migration (Postgres suite)
Rows inserted directly, the forms of §5.2's test: a string document that differs, an object document that differs, a match, a null column, a document without category **and a non-null column**, a numeric category, an unreadable document, a JSON array.
- **Every row is inserted as `draft`** and deleted by id in `addTearDown`. The column's default is `active` (`migrations.dart:351`), and an unreadable `active` row would be returned by `query()` and `listForAdmin` and make `_data` throw (`postgres_providers_repository.dart:660`) in every later test; `providers` is never truncated (BACKEND.md §5).
- **After `kProviderCategoryFromDocument`:** each column as §5.2 says; `data` and every other column unchanged.
- **Run again:** zero rows changed.
- **Red first:** written before the constant exists, it fails to compile, so its first red is a stub constant that changes nothing.

### 8.3 Mutations, on committed code, each with the failure text required
| | Mutation | Must turn red |
|---|---|---|
| m1 | `category` removed from `kProviderDocumentColumns` | the Postgres contract's category case (« listed under the old category »), **and** the coverage test |
| m2–m5 | `commune`, `name`, `description`, `address` removed, one at a time | the Postgres contract's case for that column, and the coverage test |
| m6 | the migration's decode replaced by plain `data` | the string-form row of §8.2 not aligned |
| m7 | the `jsonb_typeof(…) = 'string'` guard removed | the document without category nulls its non-null column; the numeric category is copied as `'5'` |
| m8 | the `pg_input_is_valid` guard removed | the unreadable document fails the statement |
| C1 | control: with m1, the Postgres category case's first line (`byId` reads `nails`) | stays green: the document was written, so the red is the column |

### 8.4 The rest
The full backend suite on a fresh local database; `dart analyze --fatal-infos --fatal-warnings` 0; `dart format` clean; the migration reversibility test green with no `rollback-unsafe` line.

### 8.8 As built (B16.1, 2026-11-24)

Branch `fix/b16-1-category-column` from `main` (`257f62d9`). Two commits: the tests red first (`2eb5bfb8`), then the fix (`81438f3e`).

- **Red first,** on a fresh local database, for the stated reasons:
  - in memory: the five cases green (the twin reads the document), the coverage test red;
  - on Postgres: « [category] listed under the old category », after the control line (`byId` reads `nails`) passed; commune, name, description and address green; the coverage test red; « [migration] b16_str_differs ».
- **The code:**
  - `kProviderDocumentColumns` (`postgres_providers_repository.dart`), with `category`;
  - `kProviderCategoryFromDocument` and migration `0050_provider_category_from_document` (`migrations.dart`);
  - the in-memory twin's `query` comment;
  - DEPLOYMENT.md's rollback line (§9).
- **Green:**
  - the contract 6/6 in memory, and the Postgres providers group 23/23 (the contract and the migration test included); `0050` recorded in `schema_migrations`;
  - the full backend suite on a fresh local database: **3001 passed, 2 skipped**, exit 0 (the migration reversibility test included: no `rollback-unsafe` line);
  - analyze 0, format clean.
- **Mutations,** on committed code, with a clean tree and each edit checked to change its file. Both targets were green unmutated first (C0). m1–m8 were each red with the texts of §8.3: m1–m5 red on their case and on the coverage test, m6 on « [migration] b16_str_differs », m7 on « [migration] b16_no_key », m8 on « invalid input syntax for type json ». C1 held: under m1, the category case's control line was never red.
- **Where the build differs from §8, and why:**
  - **The coverage test is red before the fix,** where §8.1 said green before and after: the red commit names the constant with its four columns, so the test sees `category` missing. Stricter, and it is the mutation m1 at rest.
  - **The migration test runs in one transaction, rolled back at the end,** instead of `draft` rows deleted in `addTearDown` (the review offered both, §13): its rows, an unreadable document among them, are never visible to another test file running against the same database.
  - **The SQL ends with a parenthesis** (`(d.doc ->> 'category')`), because Dart's `'''` cannot close right after a quote.
- **Found by the Onglerie session (2026-11-24), not here:** §12's « a nail salon never gets an area landing page or a sitemap entry » is wrong. Area pages and sitemap entries come from the locality tree since 2026-08-20/21; they exist and list no salon. That session corrects §12 in its own PR.
- The throwaway local databases were dropped.

---

## 9. Rollout & scope discipline

1. **Build,** in its own backend PR, on the owner's word (Q4). Merge on the owner's word.
2. **Deploy,** on the owner's word. It rides with whatever else is merged and not yet deployed (B15.1 at least). The migration runs at boot, before the revision serves.
3. **Read after, read-only, on the owner's word:** the same aggregate read as §2.4, expecting **no salon whose column differs**, plus `0050` in `schema_migrations`.

**Timing.** The migration fixes the wrong salon whenever it runs. If that salon is validated and goes live before the deploy, it is listed under `salon` until then.

**Rollback.** Safe: no schema change. An older image stops syncing the column again, so a category changed while it serves drifts again, and the migration will not rerun after the roll-forward (its id is recorded). DEPLOYMENT.md's rollback section gains one line: after rolling forward, run §2.4's read, and if a salon differs, run `kProviderCategoryFromDocument` by hand in Cloud SQL Studio.

**Residual.** During a deploy, the old revision can still answer a profile change after the new one's migration ran. That category drifts until the constant is run by hand; it never runs again by itself. Step 3's read is taken once the old revision no longer serves, so it shows any such row.

---

## 10. Definition of done (for the build)

- [ ] §8.1–§8.2 red first for the stated reason, then green; §8.3's mutations red with their text, C1 green.
- [ ] Full backend suite green; analyze 0; format clean.
- [ ] `kProviderDocumentColumns` and the migration constant each link this spec; the in-memory twin's `query` comment says the two twins filter on the same value.
- [ ] DEPLOYMENT.md's rollback line (§9); BACKLOG B16.1, this spec's status, the index row and a roadmap entry updated.
- [ ] Feature branch and PR; CI green; owner-authored, no attribution.

---

## 11. Questions for the owner — answered 2026-11-24, « Approve as recommended » (decisions 224–227)

Numbered from **224**, after the survey's 219–223.

**Q1. The fix: `updateProfile` writes the `category` column with the document?**
- **Recommended: yes,** in the same `UPDATE`, as name, description, address and commune already are (§5.1). → ✅ **Decision 224.**
- Or a generated column: it cannot drift, but it is `rollback-unsafe` and breaks registration under an older image.
- Or the filter reads the document: no index, and every query decodes every row.

**Q2. The salon already wrong: fix it with a migration?**
- **Recommended: yes,** `0050`, at the deploy: each salon's column set from its document where they differ (§5.2). Today that is the one draft salon of §2.4. → ✅ **Decision 225.**
- Or by hand in Cloud SQL Studio, once.

**Q3. The contract's reach: every column `updateProfile` keeps, on both twins?**
- **Recommended: all five** (§5.3). The sync list is where this defect lived, and a column added to it later gets its case. → ✅ **Decision 226.**
- Or the category only.

**Q4. When?**
- **Recommended: build now as one backend PR, on your word,** then deploy on your word, ideally before that salon is validated (§9), then the read after. → ✅ **Decision 227.**
- Or wait and deploy it with B16.2.

---

## 12. Found next to it

- **The survey's « unknown » (§2.1) is answered:** the defect needs a salon to change its category after creation. One of nine has; none is public today.
- **The demo reset (B16.2):** after this, its restore reaches the category column too. Services, availability, `featured` and `status` remain, and **a sixth, `rating`:** the restore sends the whole captured document, `rating` included (only `id`, `slug` and `status` are left out, `demo_reset_service.dart:59`), so the document's rating goes back to the snapshot while the `rating` column, which orders discovery, keeps what `updateRatings` last wrote (`postgres_providers_repository.dart:411`); reviews are not wiped. For B16.2's spec.
- **Another writer of a synced field:** at boot, `backfillSalonMarketIfNeeded` (`migrations.dart:1940`) rewrites an old document's `commune` to its area's name without touching the column. It only acts on documents written before multi-pays' market fields. For B16.8 (the providers group), with a read of whether any production document still needs it.
- **The app's home chips offer three categories:** `barber`, `salon`, `spa` (`category_chips.dart:12-17`). A `nails` or `massage` salon cannot be reached through the app's category filter at all. A product gap, not this defect.
- **The website asks for a category that does not exist: `nail`.** Out of scope here, a website defect of its own, found while listing §2.3's readers:
  - `web/lib/landing.ts:17` maps « Onglerie » to `apiKey: 'nail'`; the profile PATCH's enum (`openapi.yaml:1819`), the catalog's validation (`provider_catalog_service.dart:422`), the seed (`providers_repository.dart:825`), `categoryFor`, the app (`mobile/lib/core/constants/salon_categories.dart:9`) and the website's own Pro profile (`web/lib/pro/profile.ts:9`) all say `nails`. The backend has no alias. The filter's parameter is a plain string with no enum (`openapi.yaml:1737`), which is why `'nail'` type-checks.
  - So on the website, the « Onglerie » landing pages (`TaxonomyLandingView.tsx:134` too), `/recherche?category=nail` and the home page's « Onglerie » link can never list a salon; and `getLandingParams` (`web/lib/api/providers.ts:128`) finds no slug for `nails`, so a nail salon never gets an area landing page (`dynamicParams = false`, `app/[slug]/[city]/[area]/page.tsx:30`) or a sitemap entry.
  - Since M4 (#127). No salon is public today, so those pages would be empty anyway; from the first public nail salon, they would stay empty when they should not.
  - Read from the code, not run against a live page. Its fix is one value and a test, in its own web PR.

---

## 13. Review log

- **2026-11-24, drafted** from a read of both twins and every caller (§2.1–§2.3), the survey's two-twin probe (A-P1), the production read of decision 220 (§2.4), and the migration statement tested on a throwaway local database (§5.2), dropped after. Found while listing the readers: the website's `nail` (§12).
- **2026-11-24, reviewed once by an independent read-only reader, told to refute it against the code.** No blocker; every line reference of §2 checked and right; the twins agree on the contract's cases; the migration decodes both forms and is not `rollback-unsafe`. Four should-fixes, all folded in:
  - cases generated from `kProviderDocumentColumns` would vanish with the column they test, so m1–m5 could not fire: the cases are written by hand, with a coverage test (§5.3, §8.3);
  - the constant's comment claimed every column that copies a document field; `slug` and `rating` do too, and are said to be left out (§5.1);
  - `rating` is a sixth field the demo reset leaves out of step (§12, for B16.2);
  - §8.2's directly inserted rows would default to `active`, and an unreadable one would break every later test: inserted as `draft`, deleted by id (§8.2).
  - And seven details: the assertion order that fixes §8.1's red text; C1 replaced by a control that can fail; the migration now copies only a JSON-text category, re-tested on eleven rows (§5.2); `backfillSalonMarketIfNeeded` as a writer of `commune` (§12); the `nail` citations made exact and two more readers named (§12); the app's three chips (§2.3, §12); three inferences reworded as such (§1, §2.2, §9).
- **2026-11-24, answered:** « Approve as recommended », all four (decisions 224–227, batch 16 in the BACKLOG).
