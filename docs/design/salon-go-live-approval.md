# A salon goes public only once MyWeli validates it

| | |
|---|---|
| **Status** | **Approved 2026-11-12** (the owner answered every question of §11: decisions 124–132). **Backend merged** (#776, 2026-11-12); the cap of decision 133 merged (#778, `5139f401`, 2026-11-12); the console merged (#779, `8d43009b`, 2026-11-12) and **deployed 2026-11-13** (`deploy-admin.yml`, run 43405932321, `27ecbecc`), before the backend as §9.2 orders; **the website's 4a merged and deployed 2026-11-13** (#782, `03ffc953`; its web details: [web-salon-validation.md](web-salon-validation.md), approved by the owner the same day); **the backend deployed 2026-11-13** on the owner's yes (12:12 UTC, run 43422983978, image `0f53e66`, revision `myweli-api-00049-hq6` at 100 %; migrations 0044 and 0045 recorded). The day's counts were read first, read-only: 5 salons, all drafts, 0 public, 1 draft holding an offer row, 0 for the backfill. It was read back on the owner's test salon: the request answered 202 at 12:37 UTC, was recorded `pending` with its `submitted` event, the salon stayed a draft, the queue counted 1, the log said `admin_notice kind=salon_request … outcome=sent`, and the owner received the e-mail; **the website's 4b merged** (#785, `8825ba60`, 2026-11-13) and read live the same day (`/professionnels` step 3, the CGU clause, the legal date); the apps not built. Reviewed twice by independent readers on 2026-11-12, every finding folded in: five readers (backend, admin console, apps, website, completeness) found 53; two found 26 on the rewrite. **Amended 2026-11-12** (decision 133, after the backend's review): the place-change e-mails to the admin are capped per salon — §5.1, §7, §8.1, §9.1, §11 |
| **Owner** | Sadreddine Daher |
| **Last updated** | 2026-11-12 |
| **PRD ref / phase** | FR-PRO-ONB-001 (go live) · admin (FR-WEB-AD-*) · V1 |
| **BACKLOG** | B0.18 (decisions 120 and 123, recorded in PR #773) |
| **Related** | [pro-salon-lifecycle.md](pro-salon-lifecycle.md) (draft → publish, T50/T51) · [pro-companion-path.md](pro-companion-path.md) (the trial at first publish, no selling in the app) · [salon-state-and-refusals.md](salon-state-and-refusals.md) (the three meanings of `draft`) · [admin-console.md](admin-console.md) · [admin-console-ui.md](admin-console-ui.md) · [pro-kyc.md](pro-kyc.md) (the one admin review that exists) · [backend-web-rebuild-hook.md](backend-web-rebuild-hook.md) · [web-true-sentences.md](web-true-sentences.md) (decision 68) · [pro-android-signup.md](pro-android-signup.md) (B0.17, which feeds salons into this) · [android-play-release.md](android-play-release.md) (the closed test this must precede) |
| **Skills checked** | myweli-dev-guardrails · myweli-backend-guardrails · myweli-web-guardrails · myweli-verification-guardrails |

**The decision (2026-11-12, decision 120).** The owner first answered « even
if they tap put salon online, first the admin (me) should approve, I guess
that is how the app works ». It is not how the app works. Today « Mettre mon
profil en ligne » publishes at once: `SalonProvisioningService.publish` flips
`draft` → `active`. The admin console approves only identity documents (KYC),
which unlock deposits.

Asked again with that fact, the owner chose:

- **every salon, on iOS, Android and the website, goes public only once the
  owner validates it, or the owner refuses it with a reason;**
- **the 90-day trial starts at the validation** (refined by Q2: unless the
  salon chose an offer on the website first, which starts it then, as today);
- **it is built before the closed test.**

Decision 123 makes this validation the guard against salons outside Côte
d'Ivoire.

**Production today:** 0 public salons (`GET /providers` → `total: 0`, read
2026-11-12 13:38 UTC). Drafts were not read. Real data since 2026-11-10.

**Vocabulary.** The salon check is **« validation »** everywhere: in the code
(`validation`, `salon_validations`), on screen, and in the CGU. « Review »
already means customer reviews here (`reviews`, `/admin/reviews`,
`reviewRequest`), and « vérification » is KYC's word.

---

## 1. Goal & scope

**What.** A salon owner asks to go live. The platform owner (the admin) sees the
request in the admin console, with what is needed to judge it, and either:

- **validates it:** the salon becomes public, and its 90-day trial starts if
  no offer choice started it earlier;
- **refuses it,** with a reason the salon reads.

The salon can fix its page and ask again, except after a final refusal
(§4.3).

**Why.** Quality and trust before the first public salons: no fake salon, no
salon outside Côte d'Ivoire, and test salons (B0.17's paid testers, Play's
reviewers) never public.

**In scope:**

- **The backend:** submission, validation and refusal as atomic transitions;
  the trial moved to validation; every other way a salon goes public today
  closed to unvalidated salons (« Lever la suspension », « Marquer payé »,
  the republish of a salon unpublished for non-payment).
- **Notifications:** the admin on each new request; the salon on each
  decision.
- **The admin console** (Flutter Web): a queue, a detail page, the decision,
  a counter.
- **The Pro app** (iOS and Android) and **the website's Pro space:** every
  salon state, the submit wording, the refusal reason.
- **The website's public pages:** `/professionnels` step 3 and a CGU clause.
  « Mon abonnement » and « Équipe » keep their sentences (Q2).
- **The paperwork:** the contract, the threat model, the smoke test, and the
  docs that say « publish is immediate ».

**Out of scope (named):**

- **Re-validation after changes.** Q6 decides what happens when a validated
  salon changes its pin, address or phone.
- **Withdrawing a request.** The owner waits for the decision, and can edit the
  salon meanwhile.
- **Admin two-factor sign-in.** Validation makes the single admin password more
  valuable. 2FA is its own BACKLOG item (R7).
- **What a refused salon keeps.** Its agenda, manual bookings and client
  records keep working, as for any draft (`bookManual` refuses only
  `suspended`). Whether a refusal should also limit that is decision 69's open
  question, not this slice's.
- **KYC.** It stays independent and still unlocks deposits only. The detail
  page shows whether documents were sent (§4.3).

**How it fits.**

- **Backend** (BACKEND.md §1): thin routes → a new `SalonValidationService` →
  repositories behind interfaces (in-memory and Postgres) → DTOs.
- **App:** models → `ProServiceInterface`, with a mock that has the validation
  lifecycle → providers → screens.
- **Web:** the client typed from `openapi.yaml`, one BFF route per call.
- **Admin:** `AdminService`, new providers, and screens under
  `mobile/lib/screens/admin/`.

---

## 2. The model: `status` stays `draft` until validation, and a validation record beside it

### 2.1 Why not a new `status` value

The server's visibility rule is written in hide form and **fails open**:
`hiddenSalonStatuses = {'draft','suspended'}` (`salon_visibility.dart:44-57`).
Discovery repeats it as literals (`postgres_providers_repository.dart:35-37`,
`providers_repository.dart:166-170`). A new value such as `pending` would make
waiting salons **public and bookable** wherever it was not added, and an older
image after a rollback would publish them all.

A separate record beside `status = 'draft'` keeps every public door closed
with no change. Those doors are search, the salon page, the sitemap,
availability, favourites, booking and reschedule; P1 pins the whole list
(§8.1).

### 2.2 Tables (migration 0044, additive)

```
salon_validations (                          -- the current state, one row per salon
  provider_id   text PRIMARY KEY REFERENCES providers(id) ON DELETE CASCADE,
  state         text NOT NULL CHECK (state IN ('pending','approved','refused')),
  submitted_at  timestamptz,                 -- the last request; null when backfilled
  decided_at    timestamptz,
  decided_by    text,                        -- the admin id; never shown to a salon
  refusal_code  text,                        -- §4.3's codes
  refusal_note  text,                        -- ≤ 500 code points; cleared on account erasure
  went_live_at  timestamptz                  -- set once, by the single winner that took it public (§3.2)
)
+ index (state, submitted_at)                -- the queue, oldest first

salon_validation_events (                    -- the history shown on the admin detail
  id, provider_id, kind ('submitted'|'approved'|'refused'), at, by (admin id or null),
  refusal_code, refusal_note
)
+ index (provider_id, at)

providers.suspended_from text NULL           -- the status a suspension interrupted (§3.4)
```

- **`approved` is final for validation.** It survives a billing unpublish
  (status back to `draft`) and a suspension, so those paths never ask for a
  new validation (§3.4).
- **Never in `providers.data`.** The public payload serializes that whole blob,
  which is why billing state got its own table. The validation travels only on
  authenticated reads: `/me/provider`, `/me/salons`, admin.
- **The audit log keeps the admin's decisions** (`salon.approve`,
  `salon.refuse`) with the code only. The note stays in these two tables,
  which erasure clears (§3.4); the audit log is append-only and outlives
  deletion.
- **Rollback.** The migration is additive, so it is rollback-safe by the
  reversibility guard's rules. An older image ignores the new tables, but its
  publish would still flip a draft live directly (§9.3).

### 2.3 A salon's states

| `status` | validation | Offer row | What it is | Public? |
|---|---|---|---|---|
| `draft` | none | none | never asked | no |
| `draft` | `pending` | none | waiting for the admin | no |
| `draft` | `pending` or `refused` | **exists** | chose an offer on the website before this ships; its clock runs (§3.6) | no |
| `draft` | `refused` | — | refused, with a reason; can ask again unless the code is final | no |
| `draft` | `approved`, never live (`went_live_at` null) | any | a validation interrupted before it took the salon public; a retry finishes it | no |
| `active` | `approved` | live | live | **yes** |
| `draft` | `approved`, was live | lapsed, `unpublished_at` set | unpublished for non-payment | no |
| `draft` | `approved`, was live | live | back to `draft` after a suspension was lifted for another reason (§3.4) | no |
| `draft` | `approved`, was live | — | its owner deleted their account | no |
| `suspended` | any | — | suspended by the admin | no |

---

## 3. Backend

### 3.1 Submitting: `POST /providers/{id}/publish` (owner, `salon.publish`)

The route and its authorization stay. The service splits today's `publish` into
**submit** (owner) and **validate** (admin). In order:

1. **The demo lock**, unchanged and first. The demo salon can never be pending,
   so validate needs no lock of its own and the lock inventory is unchanged.
2. **`suspended`** → 403 `provider_suspended`, unchanged.
3. **The area self-heal, then a re-read of the salon.** This fixes a latent bug:
   Postgres `updateProfile` returns the raw blob, whose `services` and
   `weeklySchedule` are stale, so the gate could answer a false 409 on a first
   try.
4. **The go-live gate,** unchanged: 409 `incomplete` + `missing`. `offer` is
   added only when an offer row exists and is no longer live.
5. **The branch on the validation state:**

   | State | What happens | Answer |
   |---|---|---|
   | `approved`, was live, `draft`, a **live offer row** | **republish**: a conditional `UPDATE providers SET status='active' WHERE id=@id AND status='draft'`, clear `unpublished_at` (as `markPaid` does, so the scheduler can unpublish it again), the rebuild `salon.republished` | **200** with the salon |
   | `approved`, was live, `draft`, no live row | none | **409** `offer` (the billing pointer) |
   | `approved`, never live | none: the admin's validation is finishing (§3.2) | **202**, the validation's state |
   | already `active` | idempotent | **200** |
   | none | `INSERT … ON CONFLICT (provider_id) DO NOTHING RETURNING` | **202** |
   | `refused`, code not final | `INSERT … ON CONFLICT (provider_id) DO UPDATE … WHERE state = 'refused' RETURNING` | **202** |
   | `refused`, code final (§4.3) | none | **409** `validation_refused_final` |
   | already `pending` | no new event, no notification | **202**, same body |

   **The 202 body:** `{ "validation": { "state": "pending", "submittedAt": … } }`.
   Only a row that came back means a new request. That request is recorded as a
   `submitted` event and notifies the admin (§5.1), so a double tap cannot send
   the admin two e-mails. **When an upsert returns no row** (the admin decided
   at that very moment), the validation is re-read and the answer follows its
   real state: 200 when live, 202 when pending.

**No trial on submit; the rebuild only on the republish branch.**
`SalonProvisioningService` stays in the rebuild wiring list for that branch,
whose reason is now `salon.republished` (markPaid's). `salon.published` is
retired; `salon.approved` replaces it (§7, T68).

**What released builds show for a 202 (Q8).** The released Pro app (0.0.1, and
0.0.2, built before this ships: decision 119) treats only a 200 as success,
then says « 🎉 Votre profil est en ligne ! ». A 200 for a request would tell a
waiting salon it is online. So these builds show their generic « Une erreur
est survenue. Réessayez. » instead. The request is in fact recorded, and the
decision reaches them (§5.2). After a final refusal, a new tap answers 409,
which these builds word as « Complétez les étapes requises avant la mise en
ligne. »; the feed row and the e-mail carry the real reason. This lasts until
the Pro floor is raised for an iOS build that knows the new answers (§9.2).

### 3.2 Validating: `POST /admin/salons/{id}/validation/approve` (admin)

The body carries the state the admin saw: `{ "from": "pending" | "refused" }`.
Validating takes two single-winner steps, each a compare-and-set.

1. **The checks,** each a 409 with nothing written:
   - not `suspended` (`provider_suspended`);
   - the gate re-run now, since the salon may have changed while waiting
     (`incomplete` + `missing`);
   - an offer row that exists but is no longer live (`offer`).

   They run before the writes. The gate is Dart code over several tables, so a
   window remains in which the owner could edit; the decision stands on what
   the admin and the checks saw.
2. **The decision, one transaction:** `UPDATE salon_validations SET state =
   'approved', decided_at = now(), decided_by = @admin WHERE provider_id = @id
   AND state = @from RETURNING`, then the `approved` event. No row → 409
   `validation_not_pending`. A refuse that landed first, or a second click,
   loses here. The winner alone appends the audit row `salon.approve`.
   - **From « Refusés »** (`from: refused`): the admin corrects a refusal.
3. **`startDefaultTrial`:** insert-if-absent, the tier derived now (pro, or
   réseau when the owner has a live Réseau salon), then the liveness re-check.
   A salon that chose an offer on the website already has its row and keeps
   its clock (§3.6).
4. **Going live, one transaction:** `UPDATE salon_validations SET went_live_at
   = now() WHERE provider_id = @id AND state = 'approved' AND went_live_at IS
   NULL RETURNING`, with `UPDATE providers SET status = 'active' WHERE id = @id
   AND status = 'draft'` and a check that an active owner exists. If either
   update returns no row, the transaction rolls back and the call answers 409
   with the reason (suspended meanwhile, no owner).
5. **Only the winner of step 4** fires the rebuild (`salon.approved`) and the
   salon's notice (§5.2).

**Two clicks, two tabs, a crash.**

- **A double click or a race against a refuse:** one winner at step 2, a 409
  for the other, which writes nothing more.
- **A crash between step 2 and step 4** leaves `approved` with `went_live_at`
  null: not public. The detail page then shows « Validation à terminer » and
  the same button, which calls `approve` with `from: approved`, a third
  allowed value that skips step 2 and runs steps 3–5.
- **A crash after step 4** leaves the salon live without its rebuild and
  notice. The next rebuild (any later one, or the next deploy) adds its page;
  the notice is lost. Named, rare.

### 3.3 Refusing: `POST /admin/salons/{id}/validation/refuse` (admin)

- **The body:** `{ "code": <§4.3 code>, "note"?: string }`.
- **The precondition:** a compare-and-set from `pending` only. No row → 409
  `validation_not_pending`.
- **Its checks,** each a 400:
  - the code from the closed list, else `invalid_input`;
  - `note_required` when the code is `other` and the note is empty;
  - `note_too_long` beyond 500 code points.
- **What it writes:** `refused`, the code, the note, the `refused` event, and
  the audit row `salon.refuse`, with the code only.
- **Then:** the salon's notice (§5.2). `status` stays `draft`; if a rollback
  ever left it `active` (§9.3), refuse sets `draft` conditionally and requests
  a rebuild, so a refused salon is never public.

### 3.4 Every other way to `active`, closed to unvalidated salons

| Path | Today | After |
|---|---|---|
| **« Réactiver » → « Lever la suspension »** (`AdminProviderService.restore`) | sets `active` unconditionally, with no precondition. A never-validated draft, a salon unpublished for non-payment or an erased owner's salon becomes public by suspend → restore, or by a direct POST | **Refused** (409 `not_suspended`) unless the salon is `suspended`. Suspend records `suspended_from`, only when the salon is not already suspended (a second suspend keeps the first value). Restore goes back to `active` only when `suspended_from` is `active`, the validation is `approved` and went live, a live offer row exists, `unpublished_at` is null, and an active owner exists. Otherwise it goes to `draft`; unknown (salons suspended before 0044) → `draft`. It answers with the result and its **reason** (not validated, offer not live, unpaid, no owner, earlier state unknown), which the console words (§4.4). The rebuild fires only on `active` |
| **« Marquer payé »** (`markPaid`) republish | republishes a salon unpublished for non-payment when the gate passes; it checks neither suspension nor anything else | only when the validation is `approved` and the salon is not `suspended` |
| **Submit's republish branch** (§3.1) | — | `approved`, was live, `draft`, a live offer row; conditional on `status='draft'`; clears `unpublished_at` |
| **Account erasure** | owned salons → `draft` | also deletes a `pending` validation, and clears `refusal_note` in both tables (the code stays). An `approved` validation stays with the salon |

### 3.5 Reads

- **`GET /me/provider`:** a fourth top-level key, `validation`, beside
  `account`, `provider` and `membership`. It is
  `{ state, submittedAt?, decidedAt?, wentLive, offerLive?, refusal?: { code,
  note?, final } }`, or `null` when never asked. `wentLive` tells « finishing »
  from « was live »; `offerLive` (for a validated salon not live) tells « Plus
  en ligne : impayé » from « Remettre en ligne » (§6.1). **`Provider` is
  unchanged:** it is also the public schema.
- **`GET /me/salons`:** each `SalonMembership` gains the same `validation`.
- **The admin queue:** `GET /admin/salon-validations?state=pending|refused|approved&page&pageSize`
  → `{ items, page, pageSize, total }`.
  - **Order:** `pending` oldest first, by `submitted_at`.
  - **Suspended salons are left out** of « En attente » and of its count; they
    come back when the suspension is lifted. The salon list still shows them.
  - **Each item:** the salon id, name, commune and city, country code,
    submitted or decided time, the owner's contact (e-mail, or phone when there
    is none), and the number of KYC documents sent.
- **The admin detail:** `GET /admin/salons/{id}/validation` returns:
  - **the salon** as the admin provider detail reads it: photos, services,
    hours, address, area, country, pin, phone;
  - **the owner:** account id, name, contact, account age, KYC status and
    document count, other salons owned;
  - **the validation and its events.**
- **The overview:** `GET /admin/analytics/overview` gains
  `providers.pendingValidation`, the same number as the queue's `total` (one
  definition for the sidebar and the dashboard).
- **`/me/subscription`'s legacy bridge** (a trial counted from account age) is
  called by no client; only its stale text is corrected.

### 3.6 The trial: at validation, or at an earlier offer choice (Q2: « As today »)

`startDefaultTrial` moves from submit to validate: **when a salon never chose
an offer, its 90 days start when the admin validates it.**

**The website's offer choice stays as it is** (owner's answer to Q2,
2026-11-12; decision 68 stands). « Choisir cette offre » (`PUT
/providers/{id}/subscription`) creates the offer row and starts the 90 days at
the choice, before validation if the salon chooses first. Team invitations and
« Ajouter un salon » (Réseau) need a live offer, so they open with that choice,
validated or not. The owner accepted the cost, said with the question: the
trial can run out while the salon waits.

So:

- **Validate keeps an existing row's clock.** `trial_ends_at` is never
  rewritten (T54's invariant).
- **The scheduler sends billing notices only to validated salons that went
  live** (R10). Without this, a waiting salon with a running trial would read
  « Votre salon reste visible pendant 7 jours », false for a salon never
  public. Such a salon still sees its countdown in « Mon abonnement ».
- **A trial that runs out while waiting:** submit and validate answer 409
  `offer`. The admin's path is « Marquer payé », then validate; the console
  says so (§4.3). The day of the deploy, the number of drafts holding an offer
  row is read.
- **The website's sentences stay true:** « Votre essai de 3 mois démarre dès
  que vous choisissez une offre ou, sans choix, à la mise en ligne de votre
  salon. » (« la mise en ligne » is now the validation), « Pour inviter votre
  équipe, choisissez votre offre : vos 3 mois d’essai démarrent à ce
  moment-là. », and `true-sentences.test.tsx`'s ban.

### 3.7 Backfill, and seeds

- **Migration 0044** marks `approved` (with no notification) every salon that
  is `active`, and every `draft` whose offer row has `unpublished_at` (a
  `LEFT JOIN provider_subscriptions`). That means:
  - no queue flood, and nothing hidden;
  - no rebuild;
  - trials untouched.
- **Suspended salons get no row** and lift to `draft` (§3.4).
- **The backfill marks them `approved` with `went_live_at` set.**
- **The same backfill also runs as a boot step, only where the dev seed runs**
  (`Env.dev`, right after it): the seed inserts `active` salons after the
  migrations, and the CI smoke runs on it. It is not a production boot step:
  there it would silently validate whatever an older image published during a
  rollback (§9.3). The in-memory repository seeds validated rows for its seeded
  active salons.
- **The day of the deploy,** the counts are read again: public salons
  (`GET /providers`), drafts, and drafts with offer rows.

### 3.8 Errors and the contract

**New codes:**

- `validation_not_pending`, `validation_refused_final`, `not_suspended`: all
  409;
- `note_required`, `note_too_long`: both 400.

**`docs/api/openapi.yaml`** changes in the same PR:

- publish: 202 and its body, and the new meaning;
- the top-level `validation` on `/me/provider`, and `SalonMembership.validation`;
- the admin routes, and restore's 409;
- the overview key;
- every « the trial starts at the first publish » text (publish, the
  subscription 404, `POST /me/salons`, register).

Both generated clients are regenerated; the web's `schema.ts` is diffed in CI.

---

## 4. The admin console (Flutter Web, `main_admin.dart`)

### 4.1 Where

- **Sidebar:** « Salons à valider » under « Modération », with a count.
  - **The count's source:** a new `AdminSalonValidationCountProvider`,
    registered in `main_admin.dart`, which reads
    `GET /admin/salon-validations?state=pending&pageSize=1` → `total`.
  - **When it loads:** at sign-in and after every decision.
  - **Read with a fallback:** `context.watch` with a silent fallback (no badge)
    when the provider is absent, on error, or on a 404 before the backend
    deploy. Existing widget tests that pump a screen without it keep passing.
- **Dashboard:** a « Salons à valider » stat card that opens the queue.
- **Routes:** `/admin/salon-validations` and `/admin/salon-validations/:id`
  (the console's paths are English).
- **A link from the e-mail lands on the request.** The console uses hash URLs,
  so the link is `#/admin/salon-validations/{id}`. **New work:** the login
  redirect carries `?from=` (only `/admin/...` paths are accepted), and the
  post-login redirect honours it; today it always goes to `/admin/dashboard`.
  Whether a Cloudflare Access re-authentication keeps the fragment is checked
  once with a real link (UNVERIFIED).

### 4.2 The queue

- **Tabs** (`AdminSegmentedControl`): « En attente » (oldest first) ·
  « Refusés » · « Validés », 50 per page with previous/next (the audit screen's
  pattern).
- **Rows** (`AdminDataTable`): Salon · Commune, ville · Pays · Demandé le ·
  Propriétaire (e-mail ou téléphone) · Documents KYC (« aucun » or a count).
  Suspended salons are not in « En attente » (§3.5).
- **The four states:** loading; empty (« Aucun salon en attente. »); error with
  « Réessayer »; the list.
- **After a decision,** the row leaves the tab at once, and the count reloads.

### 4.3 The detail, and the decision

Two columns, as the KYC detail.

**Left, the salon:**

- name and type, the photos, the services and their prices, the hours;
- the address, commune and city, country code;
- **the pin's coordinates, with « Ouvrir dans OpenStreetMap »** (a link, through
  `url_launcher`). The console has no usable map key: the CARTO key is
  restricted to the apps, and the console is built without one. A link needs
  none and still tells Dakar from Abidjan;
- **the phone with its country prefix.**

The pin and the phone are decision 123's evidence.

**Right, the owner:**

- name and contact, account age;
- **KYC:** « aucun document » or « N documents · {status} ». Its link shows only
  when documents exist, because almost every account reads « pending » by
  default without having sent anything;
- the other salons they own;
- the request's history: submissions, decisions, codes and notes.

**The sticky bar:** « Refuser » (destructive) and « Valider la mise en ligne »,
the latter disabled on a suspended salon.

**Refusing (Q1).** A new dialog: a list of codes, then a note field (500
characters at most, counted as the server counts them). The note is required
for « Autre ». The salon reads:

| Code | The salon reads | Final? |
|---|---|---|
| `incomplete_info` | « Certaines informations du salon sont incomplètes ou peu claires. » | no |
| `photos` | « Les photos ne montrent pas assez clairement le salon et son travail. » | no |
| `unconfirmed` | « Nous n’avons pas pu confirmer l’existence de ce salon. » | no |
| `outside_ci` | « MyWeli n’est pas encore disponible dans votre pays. Si votre salon est en Côte d’Ivoire, écrivez-nous depuis « Aide & Support ». » | **yes** |
| `test_salon` | « Ce salon est un salon de test : il ne sera pas mis en ligne. » | **yes** |
| `other` | the note alone (required) | no |

- **A final code** removes « Renvoyer pour validation »; the server answers
  409 `validation_refused_final`. Only the admin can still validate it, from
  « Refusés ».
- **The note's rules,** printed under the field: no personal data, and never
  an instruction to pay (pro-companion-path §2.1).

**Feedback.**

- **Validate:** a success snackbar, then back to the queue.
- **A 409** shows its sentence in the bar. `AdminService` keeps `missing` from
  the body, and each key gets a French label:
  - « Le salon n’est plus complet : photos, horaires. »;
  - « Cette demande a déjà été traitée. »;
  - « L’offre du salon n’est plus active : marquez-la payée, puis validez. »;
  - « Salon suspendu : levez d’abord la suspension. ».
- **Every code these routes emit** gets a case in `AdminService`.

### 4.4 Elsewhere in the console

- **« Réactiver » becomes « Lever la suspension »** (list and detail). Its
  snackbar follows the returned status and reason: « Salon remis en ligne »,
  or « Suspension levée — le salon reste hors ligne : » followed by « non
  validé », « offre inactive », « dépublié pour impayé », « sans
  propriétaire » or « état antérieur inconnu ». The audit label changes too.
- **Validation labels** have their own mapping (`ValidationLabels`): « En
  attente de validation », « Validé », « Refusé », with chip kinds. The shared
  `StatusLabels` resolves `pending` through the booking enum first, so it
  cannot carry them, and they must not relabel every KYC and booking « En
  attente ». `kAuditActions` gains `salon.approve` and `salon.refuse`, and
  labels the four codes it renders raw today.
- **The detail of a validation interrupted before going live** (§3.2) shows
  « Validation à terminer » and the same button.
- **The photos.** The public bucket's CORS lists only `myweli.com`: it
  answers a preflight from `admin.myweli.com` 403, with no
  `Access-Control-Allow-Origin` (probed 2026-11-12). Decided: the HTML image
  strategy, no cloud change — the browser draws each photo as a plain
  `<img>`, which needs no CORS. #779 built it with its own `Image.network`;
  since #777 the photos go through `AdminRemoteImage`, the console's one way
  to draw a remote image (SYSTEM.md §11.2, §19), with the tile's own
  placeholder and « Photo indisponible », and no « Actualiser »: the links are
  public, so a re-read cannot give a new one
  ([admin-remote-images.md](admin-remote-images.md) §4.1). Whether the live
  console renders them is still UNVERIFIED (§11).

---

## 5. Notifications

### 5.1 To the admin: each new request, and each change to a validated salon's place

- **The e-mail:** sent to `ADMIN_EMAIL`, already in production's environment,
  where today it only seeds the admin account. The owner confirmed it is an
  inbox they read (Q3, 2026-11-12).
- **Content:** « Nouveau salon à valider : {Salon} », the commune, the country,
  and the hash link (§4.1).
- **When:** class `warm`, sent only for a new request (§3.1).
- **Never in the way:** best effort, so a failed send never turns a recorded
  request into an error, and an unset address does nothing. The outcome is
  logged without the address.
- **Plus the console's count** (§4.1).
- **A validated salon that changes its place (Q6, 2026-11-12; capped by
  decision 133 the same day).** When a save on a salon whose validation is
  `approved` changes its pin, address, commune or phone, the admin hears of it
  at the same address. The salon stays online; the owner can suspend it.
  Where: the catalogue's profile update compares the saved values with the
  new ones (`ProviderCatalogService`), best effort, class `warm`. Until
  decision 133 it was one e-mail per save, so saving a value back and forth
  filled the admin's inbox and spent the hourly `warm` budget every other
  warm e-mail shares (T82). Now, per salon:
  - **The first change of a quiet hour** (no such e-mail for that salon in
    the last hour, nothing owed) is e-mailed at once, as Q6 wrote it:
    « {Salon} a modifié son emplacement » (or « son adresse », « son
    téléphone »), the old and new values of that save, and the link to the
    salon.
  - **The changes in the hour after it** are recorded, not e-mailed: how
    many, since when, which kinds (`salon_place_notices`, migration 0045, one
    row per salon).
  - **Once that hour has passed, one summary** goes, sent by the existing
    15-minute reminders cron (`POST /internal/cron/reminders`; no Scheduler
    job of its own): « {Salon} a encore modifié … », the values the last
    e-mail reported → the salon's values at that moment, how many changes
    since when (Abidjan time), and a value back where it was says so. It
    opens a new hour: a salon that keeps saving sends at most one e-mail an
    hour. A change after the hour while a summary is still owed joins it.
    The claim is conditional on the saves the tick read before it read the
    salon: a save landing in between waits for the next tick, so no summary
    marks a value as reported without showing it.
  - **A suspended salon's saves** record nothing and e-mail nothing: the
    admin already acted. A summary owed by a salon suspended, no longer validated
    or gone by the time it is due is dropped.
  - **Single winner both ways:** two saves at once in a quiet hour send one
    e-mail (the salon's row is locked), two ticks one summary (a conditional
    claim) — Cloud Run runs several instances.
  - **Never in the way:** when the cap cannot be read, the e-mail goes as it
    did before the cap; a failed summary step never fails the reminders, and
    a failed reminders step does not stop the summaries (the tick still
    fails). The cron is not the only way out of the cap: a summary it has not
    sent 30 minutes past its hour (the job paused, its door broken, the step
    failing) is sent by the salon's next save. The row holds the phone and
    address last reported, so account erasure deletes it.
  - **What the cap does not report:**
    - a change made while the salon is suspended, unless the next e-mail is
      a summary (a change after the lift, within the hour of the last
      e-mail): an immediate e-mail reports only its own save and takes the
      salon's other values as reported, so the salon's place is read in the
      console before « Lever la suspension ». The same holds for another save
      landing in the instant before the one that sends it: a later summary
      calls that value « identique au dernier e-mail »;
    - while the cron is stopped, the pending changes of a salon that saves
      nothing more, until the cron is back. Nothing alerts on the summaries
      yet: the tick answers 200 whatever they do.

### 5.2 To the salon, on each decision

To the owner (the `salon.publish` holder) only:

| | Validated | Refused |
|---|---|---|
| **Push** (facts only; route `/pro/onboarding?salon={id}`, `providerId`, event `salon.validation.approved`/`refused`) | « {Salon} est en ligne » · « Vos clients peuvent maintenant trouver votre salon et réserver. » | « Mise en ligne de {Salon} refusée » · the code's sentence (§4.3) |
| **In-app feed row** (type `salonValidation`; old clients show it as `general` with its body) | the same | the code's sentence and the note: on old builds too, the reason is readable here |
| **E-mail** (`warm`, a new template in the subscription family, every string HTML-escaped, T73) | validated, and the trial's end date | the reason, and what to do next (not for a final code) |

**Rules:**

- **An e-mail is sent only to an address containing « @ ».** The membership's
  `email` is written as `account.email ?? account.phoneNumber` in three places,
  and the scheduler and `SalonNotifier` « e-mail » whatever is there. One
  helper at the membership read (`emailOrNull`) serves every sender
  (`_notifyOwner`, `SalonNotifier`, this notice) and the admin queue's contact
  column.
- **The trial and the app.** The e-mail may name the trial. The app and the
  push never promote it (pro-companion-path §2.1).
- **« The four events » sentences** (the push prompt, the blocked-push banner,
  the feed's empty state) **do not change.** They are shown to every member,
  while this news goes to owners only, and they do not become false.

---

## 6. The Pro app (iOS and Android) and the website's Pro space

### 6.1 States and words, the same on both

| State | Badge / row line | Banner title | Banner text | Button |
|---|---|---|---|---|
| never asked | « Brouillon — pas encore en ligne » | — | the checklist; the hint « Complétez les étapes essentielles pour demander la mise en ligne. » | « Demander la mise en ligne » (enabled when the checklist is complete) |
| `pending`, or `approved` not yet live (the admin's validation finishing) | « En cours de validation » | « En cours de validation » | « Nous examinons votre salon avant sa mise en ligne. Nous vous préviendrons dès que c’est fait. » (no delay promised: Q4) | none: « Demande envoyée le {date} » |
| `refused`, not final | « Mise en ligne refusée » | « Mise en ligne refusée » | the code's sentence; the note on its own line; « Modifiez votre salon, puis renvoyez-le pour validation. » | « Renvoyer pour validation » |
| `refused`, final | « Mise en ligne refusée » | « Mise en ligne refusée » | the code's sentence; the note | none |
| live | « En ligne » | — | as today | none |
| `approved`, was live, offer lapsed (`offerLive` false) | « Plus en ligne » | « Votre salon n’est plus en ligne » | the billing sentence of « Mon abonnement » | the billing pointer |
| `approved`, was live, offer live (`offerLive` true) | « Plus en ligne » | « Votre salon n’est plus en ligne » | « Vous pouvez le remettre en ligne. » | « Remettre en ligne » (200) |
| `suspended` | « Suspendu » | « Votre salon est suspendu » | « Contactez MyWeli pour en savoir plus. » (new: the existing sentence is « …Contactez MyWeli pour le réactiver — vos rendez-vous sont intacts. », which the surfaces of a server before B0.18 keep — corrected 2026-11-13, web-salon-validation.md §3.1) | none |

- **After a request:** « Demande envoyée. Nous vous préviendrons de la
  décision. ». Today's « 🎉 Votre profil est en ligne ! » (app) and « 🎉 Votre
  salon est en ligne ! … » (website) are said only for a 200 that is live.
- **No « vérif » in this copy.** That word is KYC's, and a test bans it here.

### 6.2 Where it shows, and when it refreshes

| Surface | App | Website |
|---|---|---|
| The checklist | « Configuration »: a banner above the steps (the KYC banner's pattern) | `GoLiveCard`: one branch per state |
| Home | the « Configurer mon profil » card's subtitle follows the state (live: « Votre salon est en ligne ») | `AujourdhuiClient`: the card for `draft`, branching inside |
| Salon switcher | the picker row: **the state on its own line**, because at 200% text a « role · state » line cuts the state off | the sidebar badge |
| Preview | unchanged (« Réserver (après la mise en ligne) » stays true) | `/pro/apercu`'s banner gains the states |
| Notice tap | `/pro/onboarding?salon={id}`: the screen switches salon first and checks the result; on a refused or offline switch it goes to « Accueil ». (The booking detail ignores that result, so it is not copied as is; the feed-row path is tested apart from the push path, which has its own fallback.) | **New work:** `/pro` reads `?salon=` and switches once, with the booking detail's once-only guard and its refused and offline messages; `proWebRouteFor` maps the route to it; the service worker learns the `salon.validation.*` events and their URL pattern; the dashboard re-reads on a push |

**Refresh points.** The state comes from `/me/provider` (`validation`) and
`/me/salons`. They are re-read:

- after a submit, whether 200 or 202 (`refreshMembership` + `loadMySalons`);
- when « Configuration » loads;
- on a notice tap.

When unknown (an offline cold start), the card keeps its draft subtitle.

**Who sees it.** Owners (`salon.publish`), as today's go-live card. Every new
field is reset on a salon switch. Every step stays editable while pending; the
decision reads the salon as it is then.

### 6.3 The rule « profile complete » on both surfaces (R8)

The app (`pro_onboarding_provider.dart:137-145`) and the website
(`onboarding.ts:54-58`) tick « profile » on description + address + commune.
The server also wants a commune from the list (`validArea`). The button could
be enabled, then refused with every row ticked. Both surfaces read the
server's rule.

### 6.4 The website's public pages, after the backend deploy (PR 4b)

With Q2 answered « As today », « Mon abonnement » and « Équipe » keep their
sentences, which stay true (§3.6). Only two public pages change, and only once
the backend deploy has been read live:

- **`/professionnels` step 3** (owner-approved word for word on 2026-10-19):
  « Demandez la mise en ligne : une fois votre salon validé, vos clients
  peuvent réserver » (Q9).
- **CGU §7 (Q7, answered: add it):** « Avant sa mise en ligne, chaque salon
  est validé par MyWeli, qui peut refuser de le publier, notamment s’il n’est
  pas situé en Côte d’Ivoire. ».
  - Its neighbours say that identity documents serve « uniquement à vérifier
    votre compte », hence « validé », not « vérifié ».
  - `LEGAL_UPDATED_AT` and `infra/legal/registration-manifest.json` move
    together (a test pins them equal).
  - None of the five pages' word bans is hit.
  - Not while a store review freezes the five pages.

**In 4a with the Pro space:** the app's and the website's Pro data exports
gain the validation state and reason.

### 6.5 Mock world

`MockProService` gains the lifecycle:

- submit → pending;
- a test hook stands in for the admin: validating starts the mock trial;
  refusing takes a code and a note;
- a never-asked, a pending, a refused and a finishing fixture;
- the mock's publish no longer starts the trial.

---

## 7. Security & the threat model

- **AuthZ.** Submit is for the owner (`salon.publish`), unchanged. Validate and
  refuse live under `/admin/*`: deny by default, `role == admin`, covered by
  path. The decision and the going-live are each a single-winner
  compare-and-set (§3.2), so a decision cannot be replayed, doubled or
  crossed.
- **Input.** The code comes from a closed list; the note is trimmed, capped at
  500 code points, escaped in every e-mail (T73), and plain text in the apps.
- **The note.** No personal data and no payment instruction; the dialog says
  so. It is cleared on account erasure, and is never copied into the audit
  log.
- **Never public.** The validation lives outside `providers.data` and travels
  only on authenticated reads.
- **BACKEND.md §7:**
  - **T82 (new) — salon validation:** spoofing, bypassing or replaying the
    admin's decision. The mitigations:
    - the admin boundary;
    - compare-and-set transitions;
    - every `active` writer checks `approved` (restore, markPaid, submit's
      republish);
    - the demo lock first in submit;
    - audit rows with the actor;
    - the place-change e-mails capped per salon (decision 133, §5.1): at
      most one an hour, none for a suspended salon; the summaries never wait
      on the cron alone.
  - **T17:** gains validate/refuse and « Lever la suspension »'s
    preconditions.
  - **T50/T51:** pending and refused are `draft`, hidden by the same rule.
  - **T54:** the trial starts at validation, unless an offer choice started it
    earlier (decision 68 stands).
  - **T68:** `salon.published` is retired; `salon.approved` (validate)
    replaces it; submit's republish now uses `salon.republished`, as markPaid
    does. Five seams, as today.
  - **T69:** unchanged.
- **The admin credential.** Validation now gates every salon behind one
  password, with no second factor on the API (Cloudflare Access covers only
  the console's bundle). Named; 2FA is R7.

---

## 8. Testing

Each new guard is watched red once, and the commit says how.

### 8.1 Backend

- **P1, every public door stays closed.** A `pending` and a `refused` salon are:
  - absent from `GET /providers`, the sitemap, by-slug, `GET /providers/{id}`,
    availability and favourites;
  - refused by consumer booking and reschedule (`provider_not_published`).

  **Red:** a pending fixture set to `active`.
- **Submit:**
  - none → 202 and an event; a double submit → one event and one admin e-mail;
  - refused → pending; a final code → 409;
  - `approved`, was live, `draft`, live offer → 200 live, `unpublished_at`
    cleared, and later unpublished again by the scheduler; no live row → 409
    `offer`; `approved` never live → 202 (finishing);
  - an upsert that returns no row because the admin decided at that moment →
    the answer follows the real state;
  - active → 200;
  - the demo 403 first; suspended 403; the gate's 409;
  - no trial and no rebuild on a 202;
  - the re-read after the self-heal (the stale-blob case, on Postgres).
- **Validate:**
  - each 409;
  - with no offer row, the trial starts at validation (`trialEndsAt` =
    validation + 90 days, the
    tier derived then);
  - status active; rebuild `salon.approved`; one audit row; one notice;
  - a refused salon validated from « Refusés »;
  - **races:** validate + refuse together → one winner (the `from` state);
    double validate → one audit row and one notice; two « finish » calls → one
    going-live, one rebuild, one notice;
  - a failure injected between the decision and the going-live → not public,
    « Validation à terminer », finished by `from: approved`;
  - a salon suspended between the checks and the going-live → 409, nothing
    public;
  - non-admin 403; no token 401.
- **Refuse:**
  - every code; `note_required`, `note_too_long`;
  - the audit row holds the code only;
  - the notice;
  - a note with markup escaped in the e-mail.
- **The bypasses:**
  - restore on a non-suspended salon → 409; a second suspend keeps the first
    `suspended_from`;
  - restore → `draft`, with its reason, for a never-validated salon, a salon
    unpublished for non-payment, an erased owner's salon, and a salon
    suspended before 0044;
  - validated + live + offer + owner → suspend → restore → active;
  - the two existing tests rewritten: `admin_provider_test`'s « restore lifts
    the suspension » (its `provider1` gains an owner and an offer row) and
    `site_rebuild_notifier_test`'s « RESTORE asks for a rebuild » (asserted on
    the active branch only);
  - markPaid does not republish an unvalidated or a suspended salon;
  - erasure deletes a pending validation and clears notes.
- **The scheduler** sends no notice to a salon not validated-and-live.
- **The « @ » guard:** a phone-registered owner gets the push and the feed row
  and no send, for this notice, `_notifyOwner` and `SalonNotifier`; watched
  red.
- **The place-change e-mail (Q6, capped by decision 133):** a save on a
  validated salon that changes the pin, address, commune or phone sends one
  in a quiet hour; a save that changes nothing of these, or on an
  unvalidated or a suspended salon, sends none and records nothing. The cap:
  - the repository's contract on both twins: the first save of a quiet hour
    sends, the hour after records, the window's edge, three saves at once →
    one e-mail (on a new row, and on an existing one — on Postgres under a
    held lock, so the race happens every run), two ticks at once → one
    summary (the same), the claim conditional on the saves its caller read,
    the claim opens a new hour, a summary 30 minutes overdue answered as
    such, drop and forget;
  - the summary's words pinned literally, « identique au dernier e-mail »
    for a value back where it was, at most one e-mail an hour over three
    hours of saves, suspended / not validated / gone dropped, a save landing
    between the tick's read and its claim sent by the next tick, the cron
    stopped → the overdue summary sent by the next save;
  - the reminders cron's new count, a throwing summary step that leaves
    the reminders' counts standing, and a throwing reminders step that still
    fails the tick once the summaries have run;
  - erasure deletes the row; on Postgres, the cascade too.
- **Q2 « As today »:** the offer choice before validation still starts the
  clock; validate keeps it.
- **Migration 0044 and the dev-only boot backfill:**
  - `active` and unpublished-for-non-payment salons are validated and marked
    live, nothing else;
  - the boot step runs only where the seed runs, and is idempotent;
  - the reversibility test passes.
- **`salon_subscription_test`'s « publish starts the trial » group** moves to
  validate (the Réseau tier derived at validation; the race is now validate
  against a choice).
- **Wiring and contract:**
  - `site_rebuild_wiring_test` gains `SalonValidationService` and keeps
    `SalonProvisioningService`;
  - contract tests for publish, the admin routes, the overview and restore;
  - `companion_path_contract_test`'s pinned strings move.
- **The funnel smoke:** the admin login moves before A18. Then:
  - submit → 202;
  - the CI-seeded admin validates;
  - live, with the trial (A18 and A21c–A21d rewritten);
  - A17's offer choice before validation stays (Q2 « As today »), and A19
    checks validate kept that clock;
  - a refuse → resubmit path.

### 8.2 Admin console

- **`AdminService`:** every new method has a `MockClient` test, and every code
  is worded, `missing` included.
- **Providers:**
  - the queue, the detail (the B9.8 stale-detail guard) and the count;
  - widget tests for the badge, and for its absence when the provider is
    missing.
- **The refusal dialog:** a code is required; the note is required for `other`
  and capped.
- **Bookkeeping:**
  - routes in `route_literals_test`;
  - the `SalonId` birth-pin allowlist;
  - `ValidationLabels` and audit labels, without touching the shared
    `pending` label;
  - « Lever la suspension »'s snackbars, one per reason;
  - the login's `from` target (only `/admin/...`), and the e-mail's hash link.
- **Goldens:** the queue and the detail (Linux).

### 8.3 Pro app

- **Every state of §6.1** on « Configuration », the home card and the picker,
  with `TargetPlatformVariant` on both platforms.
  - **The refused banner:** each code's sentence and a note; final codes with
    no button.
  - **Submit:** 200 versus 202; the snackbar.
- **At 360 dp and 200% text:**
  - the banner in each state;
  - the two button labels;
  - the picker row, with no truncation (the existing predicate).
- **A two-salon owner** taps a notice for the inactive salon → it switches,
  then shows the decision; a refused or offline switch → « Accueil ». The
  feed-row path and the push path are tested apart.
- **The provider:** keeps `validation`, resets it on a switch; the refresh
  after submit.
- **The mock lifecycle.** The tests that pinned « publish starts the trial »
  (`pro_onboarding_screen_test`, `multi_salon_test`,
  `pro_onboarding_provider_test`, `onboarding_test`) are rewritten and watched
  red on the old rule.
- **The « vérif » ban** on the validation copy.
- **Goldens:** `pro_dashboard*` regenerated (the card's subtitle).
- **R8's rule** on the app's checklist.

### 8.4 Website

- **Unit:**
  - `GoLiveCard`'s branches; a new dashboard test for every state (none exists
    today); the sidebar badge; the preview banner;
  - the `profile` rule;
  - the notification route mapping, and `/pro?salon=` switching once, with a
    two-salon case;
  - `pro-api-network.test.ts`'s table gains every new wrapper;
  - the legal date and manifest.
- **E2E on the stub** (port 8787, shared across sessions):
  - publish answers 202 and no longer mints a trial;
  - `p1` stays never-asked, so the go-live e2e reads submit → 202 → pending;
  - a control route stands in for the admin (validate, refuse, seed a state,
    reset);
  - the refused-by-country path on a fixture no other spec asserts (not `p3`,
    which `salons.spec.ts` expects as a draft), reset after;
  - axe on the pending and refused cards.

---

## 9. Rollout

### 9.1 PRs

1. **Backend:**
   - migration 0044 and the dev-only boot backfill;
   - submit, validate and refuse;
   - the bypasses;
   - the reads;
   - notifications, the place-change e-mail (Q6) and the « @ » helper;
   - then, in its own PR on top of it, the place-change e-mails' cap
     (decision 133);
   - the scheduler's check;
   - the contract, the threat model, the smoke.
2. **Admin console:** the queue, the detail, the decision, the count, « Lever
   la suspension », the login's `from` target.
3. **Pro app:** the states, the copy, the routes, the mock, R8, the tests, on
   both platforms. It merges **before android-play-release's step 5**, so the
   closed test's AAB carries it.
4. **Website, in two parts:**
   - **4a,** ships first: the client branches that read both servers (200 =
     live, 202 = pending), the Pro space's states keyed on a `validation` value
     only the new server sends (absent → today's screens), `/pro?salon=`, the
     service worker, R8, the exports. It makes no new claim.
   - **4b,** merged only once the backend deploy has been read live (and not
     while a store review freezes the five pages): the CGU clause and
     `/professionnels` step 3.
5. **Docs** (§9.4).

### 9.2 Deploys, each on the owner's yes

1. **Website 4a** (merging deploys it): it reads both servers.
2. **Admin console** (`deploy-admin.yml`, a manual dispatch): it must be live
   **before** the backend, so that requests have a screen to be decided on.
3. **Backend** (`workflow_dispatch` with the image tag):
   - before it, the day's counts are read (§3.7);
   - after it, one real request is read back as 202, and the admin e-mail as
     received (Q3).
4. **Website 4b.**
5. **The closed test's step 8** happens only after steps 2–3:
   android-play-release step 8 gains that precondition. B0.17's spec said
   « B0.18 built »; it means deployed.
6. **The Pro floor.** Once an iOS build that knows 202 is live on the App
   Store, the admin console's client-version floor is raised for iOS. Android's
   first release already knows it.

### 9.3 Named residuals

- **Old Pro builds** (iOS 0.0.1, 0.0.2) show a generic error on a request that
  did go through, and « Complétez les étapes requises… » after a final
  refusal, until step 6 (Q8). The decision still reaches them by push, feed
  row (with the reason) and e-mail.
- **Rollback.** An older backend image ignores the new tables, and its publish
  flips a draft live directly. A rollback is therefore a decision, taken with
  this named. After a roll-forward, one query lists `active` salons with no
  validated-and-live row; each is validated or refused by hand (refuse puts it
  back to `draft`, §3.3).
- **A crash right after going live** loses that salon's notice (§3.2).
- **A waiting salon whose website trial runs out** gets no billing notice
  (R10) and needs « Marquer payé » before it can be validated (§3.6).
- **Test salons** in the queue are refused with `test_salon` (final), which
  keeps the count meaning real requests.

### 9.4 Documents to correct (in the PRs)

- **Product records:**
  - **PRD:** FR-PRO-ONB-001's validation step; an admin validation requirement;
    OQ-3 and the pricing note's trial start.
  - **BACKLOG:** the answers to Q1–Q9; decision 68 stands (Q2), and decision
    120's trial wording is refined to « at validation, unless an offer choice
    started it earlier ».
  - **MODULES:** §15's trust scope; §9's trial.
  - **`modules/access.md`:** `salon.publish` = ask to go live.
- **Design specs:**
  - pro-salon-lifecycle; salon-state-and-refusals;
  - pro-companion-path (its Q2, re-decided: at validation when no offer was
    chosen);
  - admin-console and admin-console-ui;
  - backend-web-rebuild-hook (the table: `salon.approved`, `salon.republished`);
  - backend-q1-funnel-smoke.
- **Operations docs:**
  - **LAUNCH:** §6.2; §6.4's first-salon check gains a validation.
  - **DEPLOYMENT:** both log reasons.
- **Store docs:**
  - **app-store-forms:** §2.4, §11.1. The review notes' « …when the salon goes
    live » stays true, since going live is now the validation.
  - **play-store-forms:** the guide says test salons are refused as such; §6.2
    step 5's friends' salon (decision 60) still works (Q2 « As today »).
- **android-play-release:** step 5 (B0.18's app part merged), step 8 (the
  backend and console deployed, a 202 read back), step 9.
- **pro-android-signup:**
  - « Mettre mon profil en ligne » → « Demander la mise en ligne » in §2.7, §6.2
    and P12;
  - its §9.1/§9.4 « B0.18 built » → deployed;
  - the order of B0.17 PR 4 (Play texts) against this PR 3.
- **BACKEND §7:** T17, T50, T51, T54, T68, T82.
- **The design index.**

---

## 10. Definition of done

- [ ] Backend: format, `dart analyze --fatal-infos --fatal-warnings` = 0, tests green, the contract and threat model updated, the smoke passes with a validation.
- [ ] Admin console, Pro app: `flutter analyze` = 0, tests green, goldens on Linux.
- [ ] Website: typecheck, lint, unit and e2e green, schema regenerated, axe clean.
- [ ] Every guard of §8 watched red once.
- [ ] Deploys in §9.2's order, each on the owner's yes; the counts read; a 202 and the admin e-mail read back.
- [ ] The documents of §9.4 corrected; a roadmap entry.
- [ ] Feature branches + PRs; CI green; authored as the owner.

---

## 11. The owner's answers (decisions 124–133)

**Answered on 2026-11-12** (the questions as asked; recorded as decisions
124–132 in the BACKLOG):

- **Q1. Refusal reasons:** « List + optional note », the recommendation
  (§4.3). « Hors Côte d'Ivoire » and « salon de test » are final.
- **Per salon:** asked after the owner's question « someone that choose the
  reseau offre will need to do the validation for each salon? ». Answer:
  « Each salon », the recommendation. A Réseau owner's every salon waits for
  validation.
- **Q2. The offer choice before validation:** **« As today »** (over « Choose
  after validation », the recommendation, and « Record now, clock at
  validation »). Decision 68 stands: a choice starts the 90 days, before
  validation if it comes first, and opens team invitations and « Ajouter un
  salon ». Without a choice, the 90 days start at validation (§3.6).
- **Q3. New requests:** « Yes, use my admin e-mail », the recommendation:
  `ADMIN_EMAIL` is an inbox the owner reads.
- **Q4. The delay:** « No delay promised », the recommendation.
- **Q6. Changes after validation:** « E-mail me on such changes », the
  recommendation (§5.1).
- **Q7. The CGU:** « Add the sentence », the recommendation (§6.4).

- **Q8. Old iOS builds after a request:** « Accept until the update », the
  recommendation. Old builds show a generic error after a request that went
  through, and « Complétez les étapes requises… » after a final refusal, until
  an iOS build that knows the answers is live and the floor is raised (§9.2,
  §9.3).
- **Q9. The words:** « Yes, use these words », the recommendation: §6.1's
  states and buttons, §4.3's reasons, §5.2's pushes, `/professionnels` step 3,
  as shown to the owner.
- **Decision 133, an amendment (2026-11-12). The place-change e-mails:**
  asked after the backend's review found that Q6's « one e-mail per save »
  let an owner or a manager fill the admin's inbox, and spend the hourly
  budget every other warm e-mail shares, by saving a value back and forth
  (T82). The shape proposed: « a cap of a few place-change e-mails per salon
  per hour, merged into one, skipped while the salon is suspended ». The
  owner's answer: « yes cap the e-mails » (§5.1). The summary's words are new
  and wait for the owner's approval in its PR.

**Recommendations, taken (the owner did not object):**

- **R1** `status` stays `draft` until validation, with a validation table
  beside it (§2).
- **R2** The decision and the going-live are each a single-winner
  compare-and-set; « Validation à terminer » finishes an interrupted one
  (§3.2).
- **R3** Validate re-runs the gate; refuse needs a code; the admin can
  validate a refused salon (§3.2–§3.3).
- **R4** « Lever la suspension » and « Marquer payé » never publish an
  unvalidated salon (§3.4).
- **R5** KYC stays independent; the detail shows whether documents exist.
- **R6** The owner can edit while pending, and resend after a refusal that is
  not final.
- **R7** Admin 2FA as its own BACKLOG item.
- **R8** « Profile complete » follows the server's area rule on the app and
  the website (§6.3).
- **R9** The console shows the pin's coordinates with an OpenStreetMap link,
  not a map (no key on the web).
- **R10** The scheduler sends billing notices only to salons validated and
  live (§3.6).
- **R11** Salons already public on the deploy day (0 today) are validated
  automatically by the backfill (§3.7).

**UNVERIFIED, named:**

- ~~the production counts on the deploy day~~ — read 2026-11-13 before the
  deploy: 5 salons, all drafts, 0 public, 1 draft holding an offer row, 0 for
  the backfill;
- ~~that mail to `ADMIN_EMAIL` arrives~~ — read back 2026-11-13: the owner
  received « Nouveau salon à valider » for their test salon's request;
- whether the live console renders the salon's photos (CORS, §4.4);
- which admin console build is live today;
- the production value of `SUBSCRIPTION_ENFORCEMENT` (default off);
- Apple's and Google's views on moderation before publication (not read;
  inferred harmless, since iOS review uses the locked demo account).
