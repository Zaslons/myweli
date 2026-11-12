# Admin KYC queue: real submissions only, oldest first; PDF documents readable

| | |
|---|---|
| **Module** | admin (console + `/admin/kyc*`), with the Pro KYC data it reads ([MODULES.md](../MODULES.md)) |
| **BACKLOG** | B0.20 |
| **Status** | **Approved 2026-11-12** — the owner's answers: O1 **B**, O2 **guard both**, O3 **« Document PDF » tile, new tab**, O4 **read-only now** (§13). **Built the same day** on `fix/admin-kyc-queue`, not merged, not deployed; what building found is in §4.2, §4.5, §4.6 and §12. |
| **Last updated** | 2026-11-12 |
| **Found** | 2026-11-12, while mapping the admin console for B0.18 (salon go-live approval); outside that slice |
| **PRD ref / phase** | FR-WEB-AD-001 (KYC approval queue) · V1 |
| **ROADMAP entry** | [2026-11-12-admin-kyc-queue.md](../roadmap/entries/2026-11-12-admin-kyc-queue.md) |
| **Skills checked** | myweli-backend-guardrails · myweli-dev-guardrails · myweli-verification-guardrails |
| **Related** | [admin-console.md](admin-console.md) §3, §8, §13 · [admin-console-ui.md](admin-console-ui.md) §3 · [pro-kyc.md](pro-kyc.md) · [web-pro-kyc.md](web-pro-kyc.md) · [BACKEND.md](../BACKEND.md) §7 T15, T17 · [salon-go-live-approval.md](salon-go-live-approval.md) §4.3 · [admin-remote-images.md](admin-remote-images.md) (#777, B0.21: how the console draws an image document) |

How to read it: every claim names where it was read. **Observed** means read
in the code or run here on 2026-11-12. **UNVERIFIED** means it was not —
production data above all: nothing in this spec was read from production.

## 1. What is wrong

### 1.1 The queue and its count hold accounts that never submitted anything (observed)

- `provider_users.verification_status` is `text NOT NULL DEFAULT 'pending'`
  (`backend/lib/src/db/migrations.dart:109`). Neither INSERT sets it: the
  salon registration (`backend/lib/src/db/postgres_provider_auth_repository.dart:261-266`)
  and the bare team-member account (`:327-331`, `business_name = ''`). The
  in-memory account defaults to `'pending'` too
  (`backend/lib/src/auth/provider_auth_repository.dart:33`).
- **A third source:** the weekly demo reset erases a reviewer's KYC with
  `submitKyc(accountId, const [])` (`backend/lib/src/demo/demo_reset_service.dart:206`),
  which writes `kyc_docs = []` **and** `verification_status = 'pending'`
  (`postgres_provider_auth_repository.dart:462-463`). So the demo account is
  back in the queue with no document after every reset that follows a KYC try.
- `POST /me/kyc` refuses an empty list (`backend/lib/src/kyc_service.dart:47`),
  so creation and the demo reset are the only ways to be `pending` with no
  document.
- `GET /admin/kyc` → `AdminKycService.queue` → `listByVerificationStatus('pending')`
  (`backend/lib/src/admin/admin_kyc_service.dart:37-62`;
  `postgres_provider_auth_repository.dart:473-497`; in memory
  `provider_auth_repository.dart:286-299`), `ORDER BY created_at DESC`.
  Each item's `submittedAt` is the **account's** `createdAt`
  (`admin_kyc_service.dart:53`), although every stored document carries its
  own server-set stamp (`kyc_service.dart:88`).
- `GET /admin/analytics/overview` counts the same set as
  `verification.pending` (`backend/lib/src/admin/analytics_service.dart:36-37, 68-72`),
  which the dashboard shows as « KYC en attente »
  (`mobile/lib/screens/admin/admin_dashboard_screen.dart:82`).

**Effect:** the queue lists every Pro account, team members included, newest
account first, with « 0 documents » and a « Soumis le » that is the day the
account was made. A real submission sinks under newer empty accounts, and the
count on the dashboard is the number of accounts, not of files to review.

**Production, read on 2026-11-12 at 14:30 UTC (O4, owner's go):** through the
Cloud SQL Auth Proxy, `BEGIN READ ONLY … ROLLBACK` with
`default_transaction_read_only=on`, aggregates only. `provider_users` holds
**2 rows, both `pending`, both with `kyc_docs = []` (an array), neither a bare
member**; **0 KYC documents** in all, so 0 PDFs and 0 unparsable stamps. Today's
queue therefore shows 2 empty rows and « KYC en attente » reads 2; under B both
read 0.

### 1.2 Approve and reject accept any account, in any state (observed)

`approve` and `reject` (`admin_kyc_service.dart:83-124`, routes
`backend/routes/admin/kyc/[accountId]/approve.dart`, `reject.dart`) check
nothing but existence. [admin-console.md](admin-console.md) §8 planned
« non-pending transitions handled »; no check and no test exists
(`backend/test/admin_test.dart`, group `AdminKycService`). Once the queue is
fixed, no screen leads to a never-submitted account, but the API would still
verify one: the « Vérifié » badge fans out to its salons and deposits unlock
(`provider_catalog_service.dart:747-750`) on an account with no document.

### 1.3 A PDF document cannot be read in the console (mechanism observed; not seen on admin.myweli.com)

- KYC accepts PDF: `_kycTypes = {..._imageTypes, 'application/pdf': 'pdf'}`
  (`backend/lib/src/upload_signing_service.dart:76`); the Pro app's picker
  offers `pdf` (`mobile/lib/screens/provider/onboarding/pro_kyc_screen.dart:185`),
  the website's too (`web/lib/pro/kyc.ts:60`). The object key ends in `.pdf`,
  chosen by the server (`upload_signing_service.dart:182`), and the signed
  upload pins the content type.
- The console drew every document with `TimedCachedImage`
  (`mobile/lib/screens/admin/admin_kyc_detail_screen.dart:239-281` at the
  time), a `CachedNetworkImage` whose `errorWidget` is a grey box with
  `Icons.image_not_supported` (`mobile/lib/widgets/common/timed_cached_image.dart:111-116, 193`).
  The tap-to-zoom dialog drew the same widget. Since #777 an image document
  and its zoom go through `AdminRemoteImage` instead
  ([admin-remote-images.md](admin-remote-images.md), B0.21): R2 sends the
  console no CORS header, so `TimedCachedImage` could not draw a photo there
  either.
- **Probes run here (2026-11-12), a valid one-page PDF beside a PNG control:**
  - Flutter's engine decoder (`flutter test`, `ui.instantiateImageCodec`):
    PNG decoded 643×1024; PDF threw `Exception: Invalid image data`.
  - Chromium 152 (the app's browser pane), the decoders Flutter Web can reach:
    PDF → `createImageBitmap` `InvalidStateError`, `<img>` error event,
    `ImageDecoder.isTypeSupported('application/pdf')` false. PNG → all three
    decode 643×1024.
- **Not observed:** the tile itself on admin.myweli.com. Production holds no
  KYC document at all (§1.1), so there is no PDF to open there.

**Effect (inferred from the above):** an admin sees « image not available » for
a PDF ID card or RCCM, with no way to open it, and may reject a valid
submission as unreadable.

### 1.4 Two smaller console faults on the same screens (observed)

- The document tile prints the type's wire id, `idCard`, `businessRegistration`
  (`admin_kyc_detail_screen.dart`, `'${doc['type'] ?? 'Document'}'`). The
  French labels exist in the Pro app (`pro_kyc_screen.dart:379-390`) and on the
  web (`web/lib/pro/kyc.ts:11-16`).
- A missing date prints nothing in the queue (`admin_kyc_queue_screen.dart:31-34`).
  Today it cannot happen; with §4.3 it can, rarely.

## 2. Every reader of `verification_status`

The brief: a never-submitted account must not suddenly read differently. This
table is what each reader does with the value, and what a new value `'none'`
(option A, §3) would do. Option B changes no value, so it changes no row here.

| Reader | Where (observed) | Rule | With `'none'` (A) |
|---|---|---|---|
| Deposits gate | `backend/lib/src/provider_catalog_service.dart:747-750` | `!= 'verified'` → refuse | same as today |
| Badge inheritance on a new salon | `backend/lib/src/access/salon_directory_service.dart:182, 193` | `== 'verified'` | same |
| Badge fan-out | `admin_kyc_service.dart` `_fanOutBadge` | writes on approve/reject | same |
| `GET /me/kyc`, `GET /me/provider` | `kyc_service.dart:118`, `ProviderAccount.toJson` | passes the value through | clients receive `'none'` |
| Pro app model (0.0.1, released on iOS) | `mobile/lib/models/provider_user.dart:119-121`, `kyc_document.dart:65-67` | unknown value → `orElse: pending` | reads `pending`: **same** |
| Pro app KYC banner | `pro_kyc_screen.dart:248-253` | pending → « Vérification en attente · Soumettez vos documents pour être vérifié. » | same (via the fallback) |
| Pro app profile row | `mobile/lib/screens/provider/profile/pro_profile_screen.dart:430-439` | pending → « En attente de vérification » | same |
| Pro app onboarding step | `mobile/lib/core/utils/onboarding.dart:45-52` | submitted + pending → in progress, else to do | same |
| Pro app deposit screen | `deposit_settings_screen.dart:242-243` | `== verified` | same |
| Pro app data export | `mobile/lib/core/utils/data_export.dart:105` | writes the enum name | writes `pending` |
| Web KYC banner | `web/components/pro/VerificationClient.tsx:119-135` | verified / rejected / else pending banner | same (falls through) |
| Web profile hint | `web/components/pro/ProfilClient.tsx:369-373` | verified / rejected / else « En attente » | same |
| Web onboarding step | `web/lib/pro/onboarding.ts:76-79` | pending + documents → « En cours », else to do | same |
| Web deposits, submit button | `AcompteClient.tsx:122`, `web/lib/pro/kyc.ts:46-57` | `== / != 'verified'` | same |
| Web data export | `web/lib/pro/export.ts:32` | passes the value through | **writes `none`** |
| Web types | `web/lib/api/pro.ts:57`, generated `web/lib/api/schema.ts` | `'pending' \| 'verified' \| 'rejected'` | must add `'none'` |
| Console status chip | `mobile/lib/screens/admin/widgets/status_chip.dart:21-41` | unknown → neutral « — » | needs a label |
| Overview counts | `analytics_service.dart:68-72` | counts per value | `pending` drops to real submissions |

So under A the released app and the website would still read a never-submitted
account as today, through their fallbacks (observed in code, not run); the
website's export would print `none`.

## 3. The choice: a new state (A) or a narrower queue (B)

**A — a distinct initial state `'none'`.** A migration sets the column default
to `'none'` and backfills `UPDATE provider_users SET verification_status = 'none'
WHERE verification_status = 'pending' AND kyc_docs = '[]'`; the demo reset
writes `'none'`; the contract's two enums gain `none`; the console chip gets a
label; the web types widen. The queue stays `status = 'pending'`.

**B — the queue is « pending with at least one document ».** No value changes.
The queue, its count and the overview's `pending` use one definition: status
`'pending'` **and** a non-empty `kyc_docs`. The demo reset's empty `pending`
leaves the queue by itself.

| | A — new state | B — narrower queue (recommended) |
|---|---|---|
| Production data | backfill UPDATE of real rows (needs your go + a count first) | none |
| Migration | yes (default + backfill) | none |
| Contract | two enums gain `none` | descriptions, one new field (`format`, §4.6), one 409 |
| What any client shows | unchanged by fallback, except the web export (`none`) | unchanged, nothing to reason about |
| Rollback of the code | safe (old code ignores `'none'` rows in its queue) | trivial |
| What `pending` means | « submitted, awaiting review » everywhere | « not verified yet »; the queue adds « with documents » |
| Fits a later « non soumis » wording in the Pro apps | directly | equally, from the documents (`GET /me/kyc` returns them) |

**Recommendation: B.** It meets the goal exactly, touches no production row,
changes nothing a salon sees, and closes the demo-reset source for free. A is a
cleaner word for the state, but no reader needs it today: every rule in §2 is
« verified or not », and « has submitted » is already in the data. A can still
be done later without undoing B.

## 4. Design (B)

### 4.1 One definition of « awaiting review »

An account awaits review when `verification_status = 'pending'` **and**
`kyc_docs` holds at least one document. Its **submission time** is the latest
`submittedAt` among its documents. Every document of one submission is stamped
in the same loop, kept ones included (`kyc_service.dart:74-90`), so this is
the time of the last submission; a resubmission after a refusal re-enters the
queue at its new time.

### 4.2 Repository

`ProviderAuthRepository` gains
`listKycQueue({int page = 1, int pageSize = 20})` → `({items, total})`.
`listByVerificationStatus` stays for the `verified` / `rejected` counts.

Postgres (no migration), as built in `postgres_provider_auth_repository.dart`:

```sql
-- kyc_docs as an ARRAY, or NULL (see « Found while building » below)
docs := CASE jsonb_typeof(kyc_docs)
          WHEN 'array'  THEN kyc_docs
          WHEN 'string' THEN CASE WHEN pg_input_is_valid(kyc_docs #>> '{}', 'jsonb')
                              THEN CASE WHEN jsonb_typeof((kyc_docs #>> '{}')::jsonb) = 'array'
                                        THEN (kyc_docs #>> '{}')::jsonb END END END
-- awaiting review
verification_status = 'pending' AND COALESCE(jsonb_array_length(docs), 0) > 0
-- page, oldest submission first
ORDER BY (SELECT max(CASE WHEN d->>'submittedAt'
                            ~ '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?Z$'
                          THEN (d->>'submittedAt')::timestamptz END)
            FROM jsonb_array_elements(docs) d) ASC NULLS LAST,
         id COLLATE "C" ASC
LIMIT @ps OFFSET @off
```

The `CASE` guards are deliberate: `CASE` is the one construct whose evaluation
order Postgres guarantees, so neither `jsonb_array_length` nor a cast is
reached by a row it would throw on, which would turn the whole queue into a
500. The stamp pattern is `kycStampPattern`, shared with the Dart side, so both
backends agree on which stamps count: Postgres would **accept** `'yesterday'`
as a timestamp where Dart refuses it, and would **throw** on `'not a date'`
(22007). A well-shaped impossible date (month 13) would still throw; no writer
produces one. `COLLATE "C"` makes the tie-break the in-memory `compareTo`'s.

**Found while building: every submission was stored as a jsonb STRING.**
`submitKyc` passed `jsonEncode(docs)` to a `:jsonb` parameter, and the driver
encodes a String again, so the column held `"[{…}]"`, a string whose text is
the list (read in a Postgres 16 test database). The app never noticed:
`_kycDocs` decodes both forms. The first SQL to read inside the column, this
queue, saw no documents at all. Most `:jsonb` writers in `backend/lib/src/db`
pass `jsonEncode(…)` the same way (`providers.data` is a string too); only
`salon_clients.tags`, the one column SQL already read inside, passed the List
(and, since #778 merged in, `salon_place_notices.reported` / `pending_fields`,
migration 0045).
So:

- `submitKyc` now passes the List: new submissions are arrays.
- The queue reads both forms (above), because rows written by today's code,
  before the deploy or by an old revision during it, stay strings. No
  migration. Production held no document of either form on 2026-11-12 (§1.1).

In memory: the same filter, sorted by the parsed latest stamp (unparsable last),
then `id`.

### 4.3 Service and DTO

`AdminKycService.queue` calls `listKycQueue`. Each item:
`{accountId, businessName, businessType, submittedAt, docCount}` as today, with
`submittedAt` = the submission time (§4.1), or `null` when no document carries
a parsable stamp (none should; never the account's creation time, which is the
bug). The console prints « — » for `null`.

### 4.4 Overview

`verification.pending` = `listKycQueue(pageSize: 1).total`, the same definition
as the queue, so the dashboard's « KYC en attente » and the queue can never
disagree. `verified` and `rejected` are unchanged. No new field: never-submitted
accounts are simply not « en attente ».

### 4.5 Approve and reject only a pending submission (O2)

Both return `invalid_state` (409, already mapped by `resultResponse`, `backend/lib/src/responses.dart:66-67`)
unless the account awaits review (§4.1). No audit row and no badge change on a
refusal. The console:

- maps `invalid_state` in the shared `AdminService` to a neutral « Cette action
  n’est plus possible. » (that map serves every admin endpoint, and its rule is
  that every code an endpoint emits has a case), and in `AdminKycProvider` to
  « Ce dossier n’est plus en attente de vérification. », then reloads the file,
  which is stale. B0.18's salon routes, which also answer `invalid_state`,
  word it for the salon in `AdminService.salonSentenceFor` (split out when
  #779 was merged into this branch, 2026-11-12: #779 had worded
  `invalid_state` for the salon in the shared map); the shared case stays
  neutral;
- shows the action bar only while the detail's `awaitingReview` is not `false`
  (an older backend without the field keeps today's bar), and « Aucune
  soumission en attente. » in its place otherwise.

Revoking a verified salon is not this; if ops ever needs it, it is its own,
deliberate action. **Found while building:** `admin_test.dart` rejected a
salon right after approving it, to prove the badge turns off. No screen ever
offered that (the detail was reached from the queue or by URL), and the guard
now refuses it; the tests prove the badge turns off through approve → resubmit
→ reject instead. **Since #779** (merged into this branch on 2026-11-12) the
detail is also opened from a salon request's « Ouvrir le dossier KYC », shown
whenever the owner has a document, whatever their KYC status: an owner already
verified or refused arrives there too. The guard and the hidden bar cover that
path; without them, « Rejeter » would have been one click from revoking a
verified owner's badge.

### 4.6 PDF documents (O3)

**Server.** Each `docs[]` entry of `GET /admin/kyc/{accountId}` gains
`format: 'pdf' | 'image'`, from the key's extension, which the server chose at
signing (§1.3). The client never parses keys. An older console ignores the
field. The detail also gains `awaitingReview` (§4.5).

**Console tile** (same 220×160 box, `AppTheme.radiusMedium`, as images):

- Fill `AppColors.surfaceVariant`; centred `Icons.picture_as_pdf_outlined` at
  `AppTheme.iconL` in `AppColors.textSecondary`, « Document PDF » under it
  (`AppTextStyles.bodySmall`). Below the tile, the French type label, as for
  images (§1.4).
- The whole tile is the target (well over 48 dp), click cursor on web.
  Semantics: button, « Ouvrir « Pièce d’identité (CNI / passeport) » (PDF) dans
  un nouvel onglet ». **Found while building:** `excludeSemantics` on that node
  also dropped the `InkWell`'s tap, a button a screen reader announces and
  cannot press; the name now sits above the `InkWell` and only the visible
  content is excluded (a test watched it fail).
- Click → the app's `openExternalUrl` (`core/utils/external_link.dart`, no new
  `url_launcher` import). On the web, `url_launcher_web` 2.4.3 (the locked
  version) calls `window.open(url, '', 'noopener,noreferrer')`, a new tab with
  no opener (read in its source, lines 71-87), and `url_launcher` 6.3.3 awaits
  nothing before it, so the tab opens inside the click. The browser's own PDF
  viewer shows it. If the launch reports failure: snack « Impossible d’ouvrir le
  document. »
- **The link lives 5 minutes** (`_docTtl`, `admin_kyc_service.dart:35`). Images
  load at once and stay in memory; a PDF is fetched only when clicked. So the
  tile remembers when the detail was loaded: after 4 min 30 s it reads
  « Lien expiré — Actualiser » with `Icons.refresh`, and a click reloads the
  detail (fresh links). A timer drives the label; the click checks the clock
  itself, because a background tab's timers are throttled. Reloading inside the
  click and then opening was rejected: a tab opened after an `await` is what
  popup blockers stop (Safari above all).
- Images keep their thumbnail and lightbox, now with the French label.

### 4.7 Copy (new)

« Document PDF » · « Lien expiré — Actualiser » · « Impossible d’ouvrir le
document. » · « Aucune soumission en attente. » · « Ce dossier n’est plus en
attente de vérification. » · « Cette action n’est plus possible. » (shared) ·
queue date fallback « — ». Type labels reuse
« Pièce d’identité (CNI / passeport) », « Photo du visage », « Registre de
commerce (RCCM) », « Justificatif d’adresse ».

## 5. API & contract (`docs/api/openapi.yaml`)

- `GET /admin/kyc`: description → « accounts awaiting review
  (`pending` with at least one document), oldest submission first »;
  `submittedAt` → « the latest submission's time », nullable.
- `GET /admin/kyc/{accountId}`: document `docs[].format` and
  `awaitingReview`.
- `POST /admin/kyc/{accountId}/approve`, `/reject`: add
  `409 invalid_state`.
- `GET /admin/analytics/overview`: `verification.pending` described as the
  queue's total.
- No enum changes. [admin-console.md](admin-console.md) §3 gets a pointer here.
- `web/lib/api/schema.ts` regenerated (CI fails on drift) with the locked
  `openapi-typescript` 7.13.0, first proven to reproduce `main`'s file byte for
  byte; descriptions, a nullable `submittedAt` and two `409`s. No web code
  reads these endpoints.

## 6. Data model

None. No migration, no backfill, no production row written. New KYC
submissions are stored as a jsonb array instead of a jsonb string (§4.2); old
rows keep their form. (Option A's migration is in §3 for the record only.)

## 7. Security & threat model

- Admin-only, unchanged trust boundary (T17). The guard (§4.5) closes « an
  admin action verifies an account with no evidence »: T17 gains that line.
- The PDF opens in a new tab **on R2's origin**, not admin.myweli.com, so the
  document can reach nothing of the console; `noopener,noreferrer`
  (confirmed in `url_launcher_web` 2.4.3, §4.6). The signed link is already in the
  admin's browser today (images); a new tab adds it to history for its 5
  minutes. T17 records both.
- A hostile PDF meets the browser's sandboxed viewer rather than our code.
  Inferred, not tested.
- Nothing new logged; no PII in the new field.

## 8. Performance

The queue's `ORDER BY` reads each pending row's small `kyc_docs` array:
nothing at V1 volume (hundreds of accounts, UNVERIFIED in production). If
pending submissions ever reach thousands, add a `kyc_submitted_at` column with
a partial index; not before.

## 9. Tests (as built; each new one watched red on `main` first)

**Backend, unit (`backend/test/admin_test.dart`, `backend/test/analytics_test.dart`),**
11 new, all red on `main`'s four lib files and green on the fix: a salon that
never submitted and a bare member are not in the queue; oldest submission
first, whatever the account age, an unstamped document last with
`submittedAt: null`; `submittedAt` is the stamp, not `createdAt`; a resubmission
after a refusal re-enters at its new time (this one first passed on `main` by
coincidence, the account order matching the expected one, and was rewritten so
only the submission times decide); the demo reset's empty `pending` leaves;
pagination; approve/reject refuse a never-submitted, a verified and a refused
account with no audit row and no badge; the detail's `format` and
`awaitingReview`; the 409 through both routes in the standard envelope; the
overview's `pending`. An empty reason stays `invalid_input` and an unknown
account `not_found` (green on both: a guard against reordering). The two tests
that rejected right after approving now go through a resubmission (§4.5).

**Backend, Postgres 16** (DB-gated, `backend/test/db/postgres_repositories_test.dart`,
run against a private `postgres:16` container): the filter, the order (two
stamps in one second), a never-submitted account, a bare member, a verified
one, a non-array `kyc_docs`, the legacy string form (valid, invalid JSON, `"[]"`),
`'yesterday'` and `'not a date'` stamps, pagination, new writes stored as
arrays. Four mutations watched red: the string branch removed, the cast without
`pg_input_is_valid` (the test fails; the error itself not read), the writer back to
`jsonEncode`, the stamp cast without the shape check (`'yesterday'` reorders,
`'not a date'` raises 22007). **Full backend suite on that database: 2 317
passed, 2 skipped** (on `185565df`, before `main` was merged in; the merged
tree's Postgres groups run in CI only).

**Console (`mobile/test/widget/admin_kyc_detail_pdf_test.dart`,
`mobile/test/unit/admin_service_test.dart`),** 9 of the 11 widget tests and the
service test red on `main`'s four console files: the PDF tile
and no image widget for it, French labels, button semantics with a tap action;
the image path unchanged; the click opens the signed link (url_launcher's method
channel); the 4 min 30 s expiry by timer and by a late click; no buttons when not
awaiting review; the 409 sentence and reload; 200 % text on this screen; the
queue's « — ». The button tests open a file without a PDF, so they fail on
`main` for what they check, not because `main`'s PDF image never settles. Two
mutations watched red: `excludeSemantics` back on the tile, the tile's content
too big at 200 %. The older-backend test (buttons kept without the field) and
the queue's date test are green on both, as guards should be.

**After deploy (owner's go):** the queue and the overview read back in
production. A PDF on admin.myweli.com waits for a real PDF submission:
production holds no KYC document.

## 10. Rollout

- One branch and PR from `main` (backend + console + contract + this spec).
- Backend deploy = the manual dispatch with an `image_tag`; console deploy =
  `deploy-admin.yml`, also manual. **Both on your go.** On their own they
  could go in either order (the console falls back to today's image tile when
  `format` is absent). Merged after #776 and #779, they ship inside B0.18's
  backend and console, so they follow its order
  ([salon-go-live-approval.md](salon-go-live-approval.md) §9.2: website 4a →
  admin console → backend).
- No flag: an admin-only read and two refusals.

## 11. Definition of done

- [x] `dart analyze` / `flutter analyze` 0 · format clean · backend suite green
      on Postgres 16 (before `main` was merged in; the merged tree: CI) · each
      new test seen failing first. Mobile suite: §9.
- [x] Contract (+ regenerated web types), T17, [admin-console.md](admin-console.md)
      §3 pointer, roadmap entry; this spec → Built. BACKLOG **B0.20**, added
      once #773 had put B0.17–B0.19 and decisions 116–123 on `main`; the four
      answers stay in §13, unnumbered, so B0.18's spec takes the next numbers.
- [x] `docs/design/admin-kyc-queue-submitted.md` named in the code it governs.
- [ ] Feature branch + PR, CI green, no Claude attribution.

## 12. Seen, left out (not built here)

- **The Pro surfaces call a never-submitted account « en attente ».** The
  profile row says « En attente de vérification » (`pro_profile_screen.dart:432`),
  the website « En attente » (`ProfilClient.tsx:373`), before any document was
  sent; the banners say « Vérification en attente » with « Soumettez vos
  documents… ». Pre-existing and unchanged by B. A wording such as « À
  compléter » is a Pro UX decision and, for the app, a release.
- **A verified salon that resubmits keeps its badge while `pending`.**
  `POST /me/kyc` does not check the status (`kyc_service.dart:43-48`; both
  clients hide the button once verified), and the badge only moves on approve
  or reject, so through the API a verified account can go back to `pending`
  with the « Vérifié » badge still on its salons and deposits refused.
- **The console's sidebar overflowed at 200 % text** (61, 27 and 14 px,
  `widgets/admin_scaffold.dart`), on every console screen. Fixed by #779
  (`Flexible` name, reworked nav tile), merged into this branch on 2026-11-12:
  the KYC detail at 200 % now reports no overflow at all, and its test judges
  the whole page again, the console's frame included (a mutation of #779's
  `Flexible` turns it red: 61 px).
- **Other `jsonb` columns are double-encoded too** (§4.2): harmless while only
  Dart reads them, a trap for the next SQL that reads inside one. Migration
  0021's `UPDATE providers SET slug = data->>'slug'` would read NULL from a
  string-form row (not checked against production).
- **The image tile has no accessible name** (seen reviewing the merge with
  #779, 2026-11-12). The image branch of `_DocTile` is a bare
  `GestureDetector`, unchanged from `main`: `labeledTapTargetGuideline` fails
  on it under #779's `consoleTheme` as macOS and Windows (a probe outside the
  branch; the PDF tile passes, and every target here is ≥ 48 dp). The fix is a
  `Semantics(button: true, label: 'Agrandir « … »')` above it, the image in
  `ExcludeSemantics`, and that guideline in this screen's test. Its own small
  change.
- **A decision taken from a salon request lands on the KYC queue** (seen
  reviewing the merge with #779). « Approuver » and « Rejeter » go to
  `/admin/kyc` ([admin-console-ui.md](admin-console-ui.md) §3), written when
  the queue was the only way in, so the admin loses the request they came from.
  Popping back instead would show the request's old KYC status: its push is
  not awaited and nothing re-reads it. Pop when possible and re-read the
  request on return; an owner's UX call, not taken here.
- **Approving a set that changed while the admin read it.** If a salon
  resubmits between the admin opening the file and pressing « Approuver », the
  new set is approved unseen. Closing it means approve carries the submission
  time it was shown. Rare; its own small change.

## 13. Open questions (sign-off)

**Answered by the owner on 2026-11-12:** O1 « B: narrower queue », O2 « Yes,
guard both », O3 « « Document PDF » tile, new tab », O4 « Yes, read-only now ».
All four were the recommendations.

- **O1 — A or B?** *Recommended: B* (§3).
- **O2 — Refuse approve/reject unless a submission awaits review?**
  *Recommended: yes* (§4.5).
- **O3 — PDFs: open in a new tab from a « Document PDF » tile, with the
  « Lien expiré — Actualiser » state?** *Recommended: yes.* Alternatives: a PDF
  viewer inside the console (a new dependency, pdf.js, for one tile), or a
  download.
- **O4 — May I read production, read-only?** Through the Cloud SQL Auth Proxy
  as before ([DEPLOYMENT.md](../DEPLOYMENT.md):304), in a `READ ONLY`
  transaction, aggregates and account ids only, nothing written:
  - accounts by `verification_status` × has documents × bare member
    (`business_name = ''`) × `jsonb_typeof(kyc_docs)`: today's queue against B's;
  - documents in all, of them `.pdf`, and stamps that do not parse;
  - if a PDF sits in a pending submission: up to three account ids, so that,
    with you signed in to admin.myweli.com in the browser pane (Cloudflare
    Access and the admin password stay yours), I open that detail and look at
    the tile. No approve, no reject.
