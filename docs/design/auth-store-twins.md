# The sign-in stores agree with Postgres, and a Pro account's Google or Apple link is never replaced (B16.4)

| | |
|---|---|
| **Module** | backend: the two sign-in stores (`provider_auth_repository.dart` and `postgres_provider_auth_repository.dart` for MyWeli Pro; `auth_repository.dart` and `postgres_auth_repository.dart` for the client accounts); then one sentence in the Pro app and one on the website |
| **Status** | **Approved 2026-11-27.** Written on the owner's « Yes, spec B16.4 » and read once by an independent reviewer (§13). The owner answered the five questions of §11 at once, « Approve as recommended »: decisions 284–288 in BACKLOG, batch 16 (#911). **B16.4a (the backend) built 2026-11-28** (§8.7) on the owner's « Yes, build B16.4a »: red first on both twins, then green; read once by an independent reviewer (no blocker; six should-fixes folded in); 30 mutations, all red. Next, each on the owner's word: its merge, the read (decision 287), B16.4b and B16.4c, then B16.4a's deploy. |
| **Owner** | the project owner: the answers, then each build, read, merge and deploy, each on the owner's word |
| **Last updated** | 2026-11-28 |
| **PRD ref / phase** | FR-AUTH (the Pro sign-in) and the admin console's user list · V1 |
| **ROADMAP entry** | [2026-11-27-auth-store-twins-spec.md](../roadmap/entries/2026-11-27-auth-store-twins-spec.md) |
| **Skills checked** | myweli-dev-guardrails · myweli-backend-guardrails · myweli-verification-guardrails · [BACKEND.md](../BACKEND.md) §1, §3, §5 (decision 223), §7 (T32, T33, T35) |
| **Related** | [twin-fidelity-survey.md](twin-fidelity-survey.md) §3.2 (B-P1-a, B-P1-b, B-P2-b, B-P2-c, B-P1-d) and §6 (decisions 221–222) · [account-email-change.md](account-email-change.md) §5.1 (decision 260: a client account's link is never replaced) and §8.4 (B16.3a as built: the code row locked, the transaction re-run) · [pro-auth-social.md](pro-auth-social.md) (the Pro sign-in) · [consumer-search.md](consumer-search.md) §3 (an escaped `LIKE`) |

---

## 1. Goal & scope

**Where this comes from.** The survey found four places where the in-memory twin of a sign-in store answers differently from Postgres, each read by one reader, none probed (survey §3.2). Decision 221 fixes them store by store, B15.1's way: a contract run on both twins, red first. This is the auth group.

**What a probe found** (§2, both twins, a disposable database):
- **B-P1-b, a Pro account's Google or Apple link.** On **both** twins, a second Google account that asserts the same verified address gets into the Pro account. Postgres replaces the first account's link; the twin adds a second one beside it. This is the move decision 260 stopped for client accounts (« a Google or Apple link never replaces an account's existing link »). It was never applied to MyWeli Pro, where it is still live in production.
- **B-P1-a, the e-mail code at a Pro sign-up whose address already has an account.** Postgres keeps the code valid; the twin spends it.
  - **Two defects beside it, in production:**
    - two sign-ups in flight on one address make Postgres throw a unique violation, and the route answers 500 (2 tries in 3). T35 says the code is checked « atomically » with the insert. It is not;
    - the Pro code check counts a wrong guess by writing back a value it read earlier. Guesses sent in parallel therefore cost one attempt between them (read; §2.2).
- **B-P2-b, the client accounts' Google or Apple link.** **Already closed by B16.3a:** both twins now answer the same, and `account_email_contract.dart` pins it on both. One case is added: a sign-in without an address.
- **B-P2-c, the console's user list.** Postgres lists the newest first and matches each field on its own, with `%` and `_` read as wildcards: `q=_` lists every user. The twin lists the oldest first and matches across the joined fields.
- **B-P1-d,** a test-only difference in the same store (decision 222: fixed when the store is touched). Postgres's Pro sign-in returns the account as it was **before** its own write.

**In scope:**
- **the Pro link rule, on both twins:** a Google or Apple link is set only where the account has none for that provider (or already has this one); otherwise the sign-in is refused with a new code (§5.1, Q1);
- **every Pro code path,** on Postgres: the code checked under its row's lock, inside the transaction that spends it, the way B16.3a's build does it for client codes (§5.2, Q2). This covers the sign-in, the sign-up and the invited member's sign-up;
- **a refused sign-up keeps its code,** on both twins;
- **a lost sign-up race answers `409 provider_exists`,** whatever the identity;
- **the console's user list:** one rule on both twins (§5.3, Q3);
- **B-P1-d,** and the client accounts' no-address case pinned (§5.4, §5.5);
- **a read-only production read before the deploy** (§9, Q4): it answers whether any Pro account holds an address it never proved;
- **the contracts on both twins, red first,** and the Postgres-only race cases (§8);
- **the refusal's sentence** in the Pro app and on the website (§5.6).

**Out of scope:**
- B-P1-c, the provider-auth twin handing out its own objects. Tests rely on it, so it is B16.11's own small piece (BACKLOG B16.11).
- The other stores' groups (B16.5–B16.10).
- A way to move a Pro account to a new Google account (§12). Under Q1's recommendation, such a person signs in by e-mail code.
- Folding accents in the console's search (Q3's alternative).

**Architecture.** Mostly the repository layer, on both twins:
- the Pro sign-in's link rule;
- the Pro code check and its place in each transaction;
- the user list's order and match.

Beyond the repositories:
- one new refusal through the existing `providerSessionResponse` (`responses.dart:195-217`);
- the contract (`openapi.yaml`: one 409 on two routes);
- two client sentences.

No migration, no new table or column.

---

## 2. What exists today (OBSERVED)

### 2.1 The probe

**Method:**
- One throwaway test made the same calls on both twins of each store. Postgres ran on a disposable local database with every migration (`myweli-db-local`, database `b16_4_probe`).
- The repository file was deleted after the run and the database dropped. A copy of the probe is kept in the session's scratchpad.
- Addresses were unique per run, in the `.test` TLD.
- Each group carries a **control**, a call both twins must answer alike. They did, so the write happened and each difference is real.

| ID | The calls | In memory | Postgres |
|---|---|---|---|
| **B-P1-b** | Pro account A registered with Google `g1` and address X. Then Google `g2`, X verified. | **into A** (a second link added) | **into A** (`g1` replaced by `g2`) |
| | then `g1`, now asserting another address | **into A** | **`provider_not_found`** |
| | the link stored on A | `g2` (and `g1` still mapped) | `g2` |
| | `g1` asserting X again | into A | into A, the link **moved back** to `g1` |
| control | an e-mail account, then Google with X verified | linked | linked |
| control | Apple with X **unverified** | `provider_not_found` | `provider_not_found` |
| **B-P1-a** | Pro account A by e-mail code on X; a second sign-up on X with a fresh right code | `provider_exists` | `provider_exists` |
| | that same code, then, at the Pro sign-in (`verifyEmailOtp`) | **`otp_none`** (spent) | **signs in A** (kept) |
| | the same through `createMemberAccount` (an invited member) | `provider_exists`, then **`otp_none`** | `provider_exists`, then **signs in A** |
| control | a sign-up with a taken Google sub | `provider_exists` | `provider_exists` |
| control | a wrong code, then the right one, then that code on another address | `otp_invalid`, created, `otp_none` | the same |
| **race** | two e-mail sign-ups in flight, one address, one code (three tries) | created + `otp_none` (×3) | created + **`UniqueViolationException` 23505** (2 of 3), created + `otp_none` (1 of 3) |
| **B-P2-b** | client account A by Google `g1`, X verified; then `g2`, X verified | a **new** account, no address | a **new** account, no address |
| | `g1` afterwards, another address | A | A |
| | Apple with no address at all | a new account, no address | a new account, no address |
| **B-P2-c** | three users created in the order Awa, Bintou, Élodie | Awa, Bintou, Élodie | **Élodie, Bintou, Awa** |
| control | their count | 3 | 3 |
| | page 2 of size 2 | Élodie | **Awa** |
| | `q` = « Awa ‹tag› +225 » (name, then phone) | 1 | **0** |
| | `q` = `_` | 0 | **every user** |
| | `q` = `%` | 0 | **every user** |
| control | `q` « élodie ‹tag› » / « ÉLODIE ‹tag› » | 1 / 1 | 1 / 1 |
| control | `q` « elodie ‹tag› » (no accent) | 0 | 0 |

### 2.2 Each one, in the code

**B-P1-b, the Pro link:**
- **Postgres** (`postgres_provider_auth_repository.dart:141-187`):
  - by sub;
  - else, on a verified address, by `lower(email)`, **whatever the account's own `email_verified`**;
  - then `UPDATE … SET $subColumn = @s, email_verified = true` with no guard on what the column held (`:159-171`).
- **In memory** (`provider_auth_repository.dart:439-474`): the same lookup. It then adds `'$provider:$sub'` to `_bySocial` and overwrites the field (`:449-456`). The old key stays in the map, so the old sub keeps signing in.
- **Neither reads whether the account already has a sub for that provider.** The client accounts' store does since B16.3a (`postgres_auth_repository.dart:330-350`: `WHERE id = @id AND $subColumn IS NULL` at `:341`, else an account of its own).
- **Reach:** `POST /auth/provider/google` (`routes/auth/provider/google.dart:33`) and `/apple` (`apple.dart:41`). Callers: the Pro app's sign-in (iOS and Android), the Android sign-up's first check (`api_auth_service.dart:786-798`), and the website's `/pro/connexion`. The invitation accept calls `loginWithSocial` with a sub only (`invitations/accept.dart:77`), so it never links.

**Pro accounts whose address was never proven.**
- `provider_users.email` exists since `0003`, from the phone era. `email_verified` was added later with `DEFAULT false` (`migrations.dart:556`), so every row older than that migration holds its address unproven.
- Every writer since then sets it to `true`: `register` and `createMemberAccount`, the code sign-in, a link.
- Both Pro lookups by address ignore the flag. That is `loginWithSocial` above, and `verifyEmailOtp` (`:196-198`). An old row with a typed address is therefore B16.3's trap for MyWeli Pro.
- Whether production holds any such row is not visible from the repository. §9's read answers it (Q4).

**B-P1-a, the code at sign-up:**
- **In memory:** `register` (`:534`) and `createMemberAccount` (`:592`) call `_checkOtpIn` with its default `consume: true` (`:550`, `:601`, `:661`), **before** their `provider_exists` check (`:555`, `:606`). So a refused sign-up costs the code. The twin touches a code only on the e-mail path (`:549`, `:600`).
- **Postgres:**
  - `_checkEmailOtp` (`:358-391`) checks on the pool, outside any transaction, and consumes nothing;
  - the `provider_exists` check runs on the pool too (`:248-263`, `:312-327`);
  - the code is deleted inside the creating transaction (`:288`, `:348`) by a `DELETE … WHERE email = @e` that checks nothing. It deletes **for a Google or Apple sign-up too**: a pending code for X does not survive a Google account created on X. That is a second twin difference.

  So a refused sign-up keeps the code. And between the checks and the `INSERT`, a second sign-up on the same address, or with the same sub, passes both checks and then hits `provider_users_email_lower_key` (or a sub index): the race of §2.1. It is not limited to e-mail sign-ups. Code-less races reach the same index:
  - two Google (or Apple) sign-ups with one sub, a double tap on the Android or website sign-up (`register.dart:100`, `:131`);
  - a Google sign-up and an e-mail sign-up on one address;
  - a sign-up racing an invitation accept.
- **The attempt accounting** (`:375-389`) reads `attempts_left`, then writes `left = read − 1`. Wrong guesses sent in parallel all read 5 and all write 4, so they cost one attempt between them. The per-IP limit at the front door (`routes/_middleware.dart:161`) and Cloudflare's edge rule bound it; the code's own budget does not. Read, not probed. B16.3a closed the same hole for client codes by reading the row `FOR UPDATE` (account-email-change.md §8.4).
- **The 500** is read, not observed: the route has no catch around `register` (`routes/auth/provider/register.dart:100`, `:131`, `:178`; its only `try` reads the body, `:30-34`). Since B16.3a the error reporter strips Postgres's `detail` (`lib/src/observability/error_reporter.dart:116-128`), so the 500 no longer sends the address to Sentry.
- **The twin's interface comment** says the code is checked « atomically with creation » (`provider_auth_repository.dart:186-189`), and so does **T35** (BACKEND.md §7). True on the twin (no `await` between check and insert). Not on Postgres.

**B-P2-c, the user list** (`listUsers`, behind `GET /admin/users`, `admin_user_service.dart:18-38`; `analytics_service.dart:37` reads only its `total`):
- **Postgres** (`postgres_auth_repository.dart:678-712`):
  - `name ILIKE @q OR phone_number ILIKE @q OR email ILIKE @q`, with `q` wrapped in `%…%` and nothing escaped (`:690-694`);
  - `ORDER BY created_at DESC` with no tie-break (`:704`).
- **In memory** (`auth_repository.dart:639-661`): one joined string `name phone email`, lower-cased (`:650`), in insertion order.
- **The contract** (`openapi.yaml`, `/admin/users`) states no order.

**B-P1-d, the stale result** (survey §3.2, test-only): both Postgres paths build the returned account from the row read before their own `UPDATE`:
- `loginWithSocial` (`:183`): stale link and `email_verified`;
- `verifyEmailOtp` (`:209`): stale `email_verified` only.

`ProviderAccount.toJson` serialises none of these (`provider_auth_repository.dart:70-84`), so no client sees it. A test reading the result does.

### 2.3 What each client says today

| The answer | Pro app: sign-in and Android sign-up (`api_auth_service.dart:1091-1094`, `pro_sign_up_screen.dart:495-511`) | Website `/pro/connexion` (`ProLoginOptions.tsx`) |
|---|---|---|
| `404 provider_not_found` | « Aucun compte MyWeli Pro n’est associé à cette adresse. Si votre salon vous a invité, connectez-vous avec l’adresse qui a reçu l’invitation. » (`failure_messages.dart:22-24`). On the Android sign-up, the check goes on to `register`. | « Compte introuvable. » and the sign-up link (`:83`, `:247`) |
| any other refusal of Google or Apple | its code's sentence. A code the app does not know gets « Une erreur est survenue. Réessayez. », as the form's line on the Android sign-up | « Connexion Google impossible. » (`:281-284`) · « Connexion Apple impossible. » (`:305-309`) |

So a refusal answered as `provider_not_found` would tell a person whose address **has** an account that it has none. On Android, the sign-up would then call `register`, which answers `provider_exists`. That is why §5.1 needs a code of its own.

---

## 3. API & contract

- **`POST /auth/provider/google` and `POST /auth/provider/apple`** gain one answer:
  - `409 social_link_taken`: the identity's verified address belongs to a Pro account that already has a different Google (or Apple) link.
  - No body beyond the error envelope.
  - The invitation bridge (`google.dart:46-67`) is not reached; it acts on `provider_not_found` only.
- **`POST /auth/provider/register`** and the member sign-up: no new answer. A lost race now answers the existing `409 provider_exists` instead of a 500, whatever the identity.
- **`GET /admin/users`:** its description gains the order, « newest first », and how `q` matches: each field on its own, case ignored, typed characters taken literally.
- **`providerSessionResponse`** (`responses.dart:200-205`) maps `social_link_taken` to 409, beside `provider_exists`.
- **Not changed:** every DTO, and the client account routes.

## 4. Data model

No migration. The existing partial unique indexes (`provider_users_google_sub_key`, `provider_users_apple_sub_key`, `provider_users_email_lower_key`, `migrations.dart:560-565`) already make one sub and one address reach one account. §5.1 and §5.2 rely on them: a write that loses a race to another account hits one of them, the transaction is rolled back whole, and it is re-run against the winner.

---

## 5. Architecture & design

### 5.1 A Pro account's link is never replaced (Q1, decision 260's rule for Pro)

On both twins, `loginWithSocial` for a Pro account:
1. **by sub:** found → signed in, as today;
2. **else, on a verified address, by `lower(email)`:**
   - the account has **no** sub for this provider, or already **this** one → linked (or left as is) and signed in;
   - the account has **another** sub for this provider → **refused, `social_link_taken`**. The account, its link and its sessions are unchanged;
3. **else** `provider_not_found` (and the invitation bridge), as today;
4. an **unverified** address links nothing, as today (T35).

**On Postgres,** in one transaction:

```sql
UPDATE provider_users SET $subColumn = @s, email_verified = true
WHERE id = @id AND ($subColumn IS NULL OR $subColumn = @s)
RETURNING *
```

- **No row → `social_link_taken`.**
- **`OR $subColumn = @s`** covers two first links with the same sub in flight (a double tap). The second waits on the row, then finds its own sub there and signs in. Without it, the rightful owner would be told the account is linked elsewhere.
- **A raced unique violation on a sub index** (the same sub linked to another account in between) rolls the transaction back. It is re-run once or twice, as B16.3a's `_retried` does (`postgres_auth_repository.dart:192-202`), and the re-run finds the sub.

**On the twin:** link only where the field for that provider is null or equal, and keep `_bySocial` and the fields in step.

**Why refuse rather than relink.** Google and Apple identify a person by `sub`, not by address. An address can come to be asserted by another account:
- a Workspace account deleted and recreated;
- a domain that changes hands;
- an Apple ID's shared address moving to another Apple ID.

Today the newcomer takes the Pro account's link, and with it the salon's agenda, clients and income. The account's own Google sign-in then fails, until it asserts the address again and takes the link back: the moved-back row of §2.1.

**What stays open, as today:** whoever holds the inbox signs in by code, and an account with no link for that provider is linked by the first identity that asserts its address verified (T35). The rule closes only the replacement.

**The cost:** a salon whose own Google account was recreated can no longer use Google; it signs in by e-mail code (§12).

**A relink that already happened stays as it is.** The data keeps no trace of one: the column is overwritten and no audit row is written. After the deploy, the newcomer keeps the link, and the old account's next Google sign-in is refused, sent to the e-mail code. §9's read counts the accounts that hold a link, the ones the rule can ever touch. It cannot count past relinks.

### 5.2 Every Pro code path: checked under its row's lock, where it is spent (Q2)

**This is B16.3a's build, not its design.** account-email-change.md §8.4 replaced the single `DELETE … RETURNING` with a row lock and a re-run. On Postgres, every path that redeems a Pro code runs one transaction:
1. **lock and check the code:** `SELECT … FROM provider_email_otp_codes WHERE email = @e FOR UPDATE`. An expired row is deleted (`otp_expired`), a spent budget is `otp_locked`, and a wrong guess decrements `attempts_left` from the locked row (`otp_invalid`, or `otp_locked` at zero). A refusal returns normally, so its accounting commits;
2. **then the path's own reads,** under that lock:
   - **sign-in** (`verifyEmailOtp`, and so the invitation routes): find the account; none → `provider_not_found`, the code **not** deleted;
   - **sign-up** (`register`, `createMemberAccount`): the `provider_exists` check; taken → `provider_exists`, the code **not** deleted;
3. **then the writes:**
   - sign-in: mark the account's address proven;
   - sign-up: the `INSERT`;
   - then the session;
4. **the code deleted last,** only once every check and write passed.

**The `INSERT` loses a race to another account** (a code-less sign-up committed the address or the sub in between) → `UniqueViolationException`. The whole transaction is rolled back, the code's deletion included, and re-run, three runs at most (`_retried`'s rule). The re-run's `provider_exists` check sees the winner. So a lost race answers `409 provider_exists`, and the code survives for the person's sign-in. This holds for **every** identity. For a Google or Apple sign-up there is no code in it.

**Two e-mail sign-ups in flight with one code** create one account. The second waits on the code's row lock; when the first commits, the row is gone, and it answers `otp_none`. If a fresh code was asked between them, the second's code is the old one: `otp_invalid`, one attempt of the fresh code spent. Never a 500.

**Only the e-mail path touches a code.** A Google or Apple sign-up leaves a pending code for its address alone, on both twins: the twin's behaviour. Today Postgres deletes it (`:288`, `:348`). The code proves the inbox, which signs into the new account anyway.

**The twin:** checks with `consume: false`, and removes the code only after the account is created. It has no `await` in between, so it cannot race, as today.

### 5.3 The console's user list (Q3)

One rule, on both twins:
- **Order:** newest first. A tie is broken by the id, also descending, in **byte order**. On Postgres: `ORDER BY created_at DESC, id COLLATE "C" DESC`. Under the database's default collation, `_` can be ignored at the first level, so ids could sort differently from Dart's `compareTo` (survey C-X2, unconfirmed); `"C"` removes the question. **On the twin:** `createdAt` descending, then `id.compareTo` descending.
- **`q`:** matches name, phone or e-mail, **each on its own**, ignoring case. On Postgres: `col ILIKE @q ESCAPE '\'`, with `q`'s `\`, `%` and `_` escaped before it is wrapped in `%…%`. There is no `unaccent` here, so the full-width trap of consumer-search.md §3 does not arise. On the twin, `toLowerCase().contains` per field. Accents count as typed, as today on both twins.
- **Unchanged:** `status`, the page and `total`.

**Not chosen (Q3's alternative):** folding accents and spaces like the salon search, so « elodie » finds « Élodie ». A small change to the console, not a twin fix.

### 5.4 B-P2-b: already closed

B16.3a gave the client accounts' store the never-relink rule on both twins (§2.1's B-P2-b rows agree). `account_email_contract.dart`'s [never relinked] case pins the link half. **Added:** a sign-in with no address creates an account with none, on both.

### 5.5 B-P1-d: the result is the row as written

Postgres's `loginWithSocial` and `verifyEmailOtp` return the row their own `UPDATE … RETURNING *` wrote (decision 222). §5.1's statement already does it for the link. An `UPDATE` that returns no row, because the account was deleted between the read and the write, answers `provider_not_found`.

### 5.6 The refusal's sentence (B16.4b in the Pro app, B16.4c on the website)

The sentence names the button that was used:
- **Google:** « Votre compte MyWeli Pro est relié à un autre compte Google. Connectez-vous avec celui-là, ou avec un code reçu par e-mail. »
- **Apple:** « Votre compte MyWeli Pro est relié à un autre identifiant Apple. Connectez-vous avec celui-là, ou avec un code reçu par e-mail. »

**In the app:**
- The API service maps `409 social_link_taken` on its Google calls to the Google sentence, and on its Apple calls to the Apple one.
- The sign-in screen shows it as `provider_not_found`'s sentence is shown: the form-level line in a live region (SYSTEM.md §14–§15), with no link.
- The Android sign-up shows it as its form's line (`pro_sign_up_screen.dart:509-511`). Its check stops there and never calls `register`.

**On the website:** `/pro/connexion` shows it as the form's error, announced, in place of « Connexion Google impossible. » or « Connexion Apple impossible. », with no sign-up link.

**Until each client ships it:** the released Pro app says « Une erreur est survenue. Réessayez. », and the website its « … impossible. » line. Both are vague but not false. Each client's build follows its own guardrails: the e-mail code is one tap away on every screen, 200 % text, the line announced.

### 5.7 Layering

Repositories, plus one status in `providerSessionResponse`. No service or route gains a rule. The routes already pass the repository's result through.

---

## 6. Security & authz

- **T35 corrected** (BACKEND.md §7):
  - a Pro link is set only where the account has none for that provider; a different identity asserting the address is refused (`social_link_taken`), never relinked;
  - every Pro code is checked under its row's lock, in the transaction that spends it;
  - a refused sign-up keeps its code;
  - a lost race answers `provider_exists`;
  - the false « atomically » sentence goes.
- **T33:** its « a sub is never replaced » covers client accounts only (BACKEND.md:484). It gains « and MyWeli Pro accounts (T35, B16.4) ».
- **T32:** Pro codes gain the same serialised attempt budget as client codes (§2.2). The row stays open until B16.4a is deployed.
- **`social_link_taken` tells the caller that an account exists at that address.** Only a caller whose Google or Apple identity asserts the address **verified** can get it: Google refuses an unverified address, and Apple's addresses are always verified (`id_token_verifier.dart:128-152`). That is the bar at which the sign-in would have linked, and today the same caller gets into the account. So it tells nothing new (decision 262's principle, T32).
- **No route, no authz change.** The user list stays behind the admin session.

## 7. Performance

- **One more predicate** on an `UPDATE` by primary key.
- **A sign-up holds one row lock** (its code's) for the length of its transaction.
- **The user list:** its sort gains a tie-break, over a handful of rows (nine client accounts at B16.3's read).

Nothing measurable.

---

## 8. Testing plan — red first, on committed code

### 8.1 Contracts, each on both twins (BACKEND.md §5, decision 223)
- **`pro_social_link_contract.dart`:**
  - [never relinked] A by Google `g1` and X; then `g2` with X verified → `social_link_taken`. `g1` still signs in, even asserting another address. A's link is `g1`;
  - the same with Apple;
  - [links an empty column] an e-mail account, then Google with X verified → linked, and the **result** shows the link (B-P1-d);
  - [same sub again] a link, then the same sub with X verified → signed in, not refused;
  - [unverified] links nothing.

  On today's code: [never relinked] red at its first line on both twins.
- **`pro_signup_code_contract.dart`:**
  - [kept on a refusal] `register`, then `createMemberAccount`, on a taken X with a right code → `provider_exists`, and that code then signs in A. Red on the twin (`otp_none`);
  - [spent by the creation] an e-mail sign-up creates A on X; **that same code on X** at the sign-in → `otp_none`;
  - [attempts] a wrong code → `otp_invalid` and one attempt fewer; then the right code creates the account;
  - [a social sign-up leaves the code] a pending code for X, then a Google sign-up on X; the code then signs into the new account. Red on Postgres (deleted today).
- **`user_list_contract.dart`:**
  - [order] newest first;
  - [tie] two users inserted in **ascending** id order, their creation time set equal by a seam (SQL on Postgres; a test seam on the twin, as B16.3's `plant`), come in descending id order;
  - [page 2];
  - [each field on its own];
  - [wildcards] fixtures whose names hold a literal `%`, `_` and `\`; `q` = each one finds only its own;
  - [case] and [accents as typed], both controls.

  On today's code: red on the twin for order and fields, on Postgres for the wildcards.
- **`account_email_contract.dart`** gains [no address] (§5.4).

### 8.2 Postgres only: the races, each forced, not hoped for
These follow B16.3a's [race insert] (`postgres_repositories_test.dart:2410-2442`): a side pool holds an uncommitted write, and `blockedOn` waits until the repository's statement is blocked on it. The twin cannot race, so these are the batch's own defect class: a test that passes while production differs.
- **[race insert]:** a code on X. The side pool inserts a Pro account at X, uncommitted. The e-mail sign-up with that code passes its `provider_exists` check, then blocks on the `INSERT`. The side commits. → `provider_exists`, no throw, **and the code then signs in the side's account** (the rollback kept it). Red today: a throw.
- **[race sub]:** the side pool holds an uncommitted Google sign-up with sub `g`. A second Google sign-up with `g` and another address blocks on the sub index. The side commits. → `provider_exists`, no throw. Red today.
- **[double link]:** an e-mail account at X. The side pool holds the link of `g` to it, uncommitted. The same `g` with X verified blocks on the row. The side commits. → signed in, not `social_link_taken`.
- **[one code, two sign-ups]:** two e-mail sign-ups with one code, the first holding the code's row lock → one created, the other `otp_none`.
- **[parallel guesses]:** five wrong guesses in flight on one code cost five attempts, and the right code then answers `otp_locked`. Red today: one attempt spent.

### 8.3 Handlers
`/auth/provider/google` and `/apple` answer `409 social_link_taken`, and the invitation bridge is not reached on it.

### 8.4 Mutations, on committed code, each with the failure text required

| | Mutation | Must turn red |
|---|---|---|
| m1 | Postgres's link without the sub guard | [never relinked] on Postgres: « A's link must stay `g1` » |
| m2 | the twin's link without its null check | [never relinked] on the twin |
| m3 | the guard without `OR $subColumn = @s` | [double link], and [same sub again] |
| m4 | `social_link_taken` answered as `provider_not_found` | the contract on both twins, and the handler test |
| m5 | the twin spends the code at the check again | [kept on a refusal] on the twin |
| m6 | Postgres deletes the code before the `INSERT`, in its own statement on the pool | [race insert]: the code no longer signs in |
| m7 | no re-run on a raced unique violation | [race insert] and [race sub]: a throw |
| m8 | the code's deletion skipped after a sign-up | [spent by the creation] |
| m9 | the code check outside the lock (today's `_checkEmailOtp`) | [parallel guesses] |
| m10 | a social sign-up deletes the pending code again | [a social sign-up leaves the code] on Postgres |
| m11 | the twin's list in insertion order | [order] on the twin |
| m12 | Postgres's tie-break removed | [tie] on Postgres |
| m13 | Postgres's `q` unescaped | [wildcards] on Postgres |
| m14 | the twin's joined haystack back | [each field on its own] on the twin |
| m15 | `loginWithSocial` returns the row read before the `UPDATE` | [links an empty column]'s result on Postgres |
| C1 | control: under m1, [links an empty column] | stays green: the link still happens where the column is empty |

**A mutation that does not apply is no result**, never a pass. The harness asserts each applies exactly once.

### 8.5 The clients (B16.4b, B16.4c)
- **The Pro app:**
  - the API service maps `409 social_link_taken` to the Google sentence on Google calls, and to the Apple one on Apple calls;
  - widget tests show the line on the sign-in screen and on the Android sign-up at 200 % text, announced. The sign-up never calls `register` after it;
  - a mutation drops each mapping.
- **The website:** a unit test of the mapping for both buttons, and the e2e of `/pro/connexion` with the refusal stubbed.

### 8.6 The rest
- the full backend suite on a fresh local database;
- `dart analyze --fatal-infos --fatal-warnings` 0;
- `dart format` clean;
- `openapi.yaml` linted, and the website's types regenerated (no drift).

### 8.7 As built (B16.4a, 2026-11-28)

Branch `feat/b16-4a-auth-stores`, from `main` (`47e46cfd`). Built on the owner's « Yes, build B16.4a »:
- the tests red first (`96ce0569`);
- the build (`2db35b2d`);
- the review's fixes (`343686c5`).

**Red first, on today's code** (`96ce0569`), each for its stated reason:
- **In memory, 11 red:**
  - [never relinked] google and apple: another identity got in;
  - [unproven holder];
  - [kept on a refusal] register and createMemberAccount: the twin spent the code;
  - the user list's [order], [tie], [page 2] and [each field on its own];
  - the Google and Apple routes answered 200, not 409.
- **On Postgres, 11 red:**
  - [never relinked] google and apple;
  - [links an empty column]: the result's link was null (B-P1-d);
  - [unproven holder];
  - [a social sign-up leaves the code]: the code was deleted;
  - [tie], and [wildcards] (`q=%` listed every user);
  - [race insert], [race sub] and [one code, two sign-ups]: each threw `UniqueViolationException`, the 500;
  - [parallel guesses]: four wrong guesses in flight cost one attempt.
- **Green on both, as they must be:** the controls, and [double link] (m3's target).

**The code** (`2db35b2d`):
- **The Pro sign-in, both twins** (§5.1):
  - by sub;
  - else, on a verified address, the account that **proved** it, read `FOR UPDATE`;
  - another sub there → `social_link_taken`;
  - else `UPDATE … SET $sub = @s WHERE id = @id RETURNING *`.

  The whole sign-in runs in `retriedTransaction(raced: true)`.
- **Every Pro code path on Postgres** (§5.2): `_checkEmailOtp` is gone, replaced by `_inspectEmailCode` (the row `FOR UPDATE`, the attempt decremented from the locked row) inside the spending transaction.
  - `register` and `createMemberAccount` share `_createAccount`: the code, then `provider_exists`, then the `INSERT`, then the code spent on the e-mail path only, then the session. The whole account creation runs in `retriedTransaction(raced: true)`.
  - The sign-in: the code, then the proven account (none → `provider_not_found`, the code kept), then the code spent.
- **The twin:** checks with `consume: false` and spends after the creation. Its sign-in links only to a proven holder and refuses another sub.
- **The user list, both twins** (§5.3): newest first, then `id COLLATE "C"`, both descending; each field `ILIKE @q ESCAPE '\'`, with `q`'s `\`, `%` and `_` escaped. The twin sorts the same way and matches each field on its own.
- **`retriedTransaction`** (`lib/src/db/transaction_retry.dart`): B16.3a's re-run rule, now shared by both stores; the client store's `_retried` calls it.
- **`providerSessionResponse`:** `social_link_taken` → 409.
- **Docs:**
  - `openapi.yaml`: the 409 on both Pro routes, register's 409, the list's order and match;
  - `web/lib/api/schema.ts` regenerated;
  - BACKEND.md T32, T33 and T35;
  - `pro-auth-social.md`'s link rule;
  - the interface comments.
- **Test-only seams:** `plantCreatedAtForTest`, `plantUnprovenEmailForTest`.

**Where the build departs from §5:**
- §5.1's guard is in Dart over a locked holder, not in the `UPDATE`'s `WHERE`, after the review. Its effect is the same, plus two things the `WHERE` could not do:
  - an account deleted between the read and the write is not found, rather than answered « linked elsewhere »;
  - a link written by another transaction in between is seen ([race relink]).
- The link `UPDATE` no longer sets `email_verified = true`. The account it reaches has already proved the address, so the write could change nothing.
- The code sign-in has no `UPDATE` at all. It read an account and marked it proven, but it now finds only accounts already proven. That makes its half of B-P1-d moot: it returns the row it read, which is current.
- `[same sub again]` stays a control, so §8.4's m3 row was wrong to name it. Sequentially, the by-sub lookup always signs in first, so m3 can only fire through the [double link] race.
- §8.3's « the invitation bridge is not reached » is not pinned: the route test seeds no pending invitation, because its context builds an empty membership store on each call. The bridge reads `provider_not_found` only, so a 409 cannot reach it by construction, and m4b and m4c pin the 409 itself.
- The twin now throws on a provider other than google or apple, as Postgres does. Before, it linked any provider string.
- **[tie, collation] runs only where the database's default collation is not byte order.**
  - Locally it runs: `docker-compose.yml`'s database is `en_US.utf8`, and m21 is red there.
  - CI's cluster takes the runner's `C.UTF-8`, where the tie-break cannot differ, so CI skips the case with its reason. Watched to skip on a throwaway `C` database.
  - Production's collation is not visible from the repository, so decision 287's read now reads it too (§9).
- **Twin differences left, below any caller:**
  - at the exact instant of expiry, the twin uses `isAfter` and Postgres `<=`;
  - Dart's `toLowerCase` and Postgres's `ILIKE` can differ on letters such as « İ ».

**Green:**
- the full backend suite on a fresh local database: 3,400 passed, 2 skipped on the build, and **3,413 passed, 2 skipped** after the review's fixes;
- `dart analyze --fatal-infos --fatal-warnings` 0;
- `dart format` clean.

**Independent review** (read-only, told to refute the build against the spec and the code): no blocker; six should-fixes, each checked in the code, then folded in (`343686c5`):
1. Decision 287 was built as if the read were already clean, and it leaves an unproven holder's address with no way in, neither sign-in nor sign-up. The deploy gate is now written into T35, the interface comment and this spec (§9), and [unproven holder] pins the dead end (the sign-up answers `provider_exists`).
2. Nothing pinned the code being checked before the account lookup, and swapping them would allow address enumeration: [the code first], both twins, `register` and `createMemberAccount`.
3. The rewritten expiry had no Postgres test: [expired], both twins, with a negative validity.
4. An account deleted between the holder's read and the write would answer `social_link_taken`: the holder is now read `FOR UPDATE`, and [race relink] is new.
5. The sign-in's re-run was untested: [race link sub].
6. Overstated docs: T32 said « implemented », the invitation accept's 409 lacked `provider_exists`, and §10's records were not yet in the diff.

Its nits were folded in as well:
- `COLLATE "C"` gets a Postgres-only [tie, collation] case, using ids whose `en_US` order differs from byte order (the premise is asserted);
- `blockedOn` counts only this database's sessions;
- the spec is named in the comments.

**30 mutations, on the committed build, every one red for its reason** (`b164a_mut.py`: each pair asserted to apply exactly the stated number of times, the tree clean before and after). m14 was first « not applied », because the formatter had re-wrapped its line; re-aimed, it went red. After the review, m1, m3, m15 and m16a were re-aimed at the locked holder, six were added, and all 30 were re-run:

| | Mutation | Red, with its text |
|---|---|---|
| m1 | Postgres's « another sub » check removed | [never relinked] google and apple: « expected false, actual true », and [race relink] (C1, [links an empty column], green) |
| m2 | the twin's link without its check | [never relinked] google and apple (C1 green) |
| m3 | the check without « or this same sub » | [double link]: « expected true, actual false » ([same sub again] green) |
| m4a, m4b | `social_link_taken` answered as `provider_not_found` (each twin) | [never relinked]: « expected 'social_link_taken', actual 'provider_not_found' »; m4b also both routes |
| m4c | the 409 mapping removed | both routes (400) |
| m5 | the twin spends at the check | [kept on a refusal] register and createMemberAccount |
| m6 | Postgres spends before the `provider_exists` check | [kept on a refusal] register and createMemberAccount |
| m7 | no re-run on a raced violation | [race insert], [race sub]: a throw |
| m8a, m8b | the creation does not spend the code (each twin) | [spent by the creation] register and createMemberAccount: « expected 'otp_none', actual null » |
| m9 | the code read without `FOR UPDATE` | [parallel guesses]: « expected 'otp_locked', actual 'otp_invalid' » |
| m10 | a social sign-up deletes the pending code | [a social sign-up leaves the code] |
| m11 | the twin's list in insertion order | [order], [tie], [page 2] ([wildcards] green) |
| m12a, m12b | the tie-break removed (each twin) | [tie]: « expected T3, T2, T1, actual T1, T2, T3 » ([order] green) |
| m13 | Postgres's `q` unescaped | [wildcards]: « % » listed all four ([case] green) |
| m14 | the twin's joined haystack | [each field on its own]: « expected empty, actual ['Awa'] » |
| m15 | the link returns the holder's row, read before the `UPDATE` | [links an empty column] ([never relinked] google green) |
| m16a–d | an unproven holder found (Postgres and twin; Google and code) | [unproven holder] |
| m17 | the shared re-run off | [race insert] (Pro), [race sub], [race link sub], and B16.3a's client [race insert] |
| m18a, m18b | the account looked up before the code (each twin) | [the code first], both paths: « expected 'otp_none', actual 'provider_exists' » |
| m19 | Postgres's expiry branch removed | [expired] |
| m20 | no re-run in the sign-in | [race link sub]: a throw |
| m21 | `COLLATE "C"` removed | [tie, collation]: « expected zz-ab, zz-a_c, actual zz-a_c, zz-ab » ([tie] green) |
| m22 | the holder read without `FOR UPDATE` | [race relink]: g2 relinked A |

**Not done here, each on the owner's word:**
- the merge;
- decision 287's read before the deploy. If it finds an unproven Pro address, the deploy waits for the owner's choice;
- B16.4b (the Pro app's sentence) and B16.4c (the website's);
- the deploy, once B16.4c is live and the read is clean.

---

## 9. Rollout & scope discipline

1. **B16.4a, the backend** (§5.1–§5.5): one PR, on the owner's word; merged on the owner's word.
2. **The read, before its deploy,** on the owner's word (Q4). The B16.3 method:
   - the Auth Proxy, a session read-only by default, and `BEGIN READ ONLY … ROLLBACK`;
   - a probe write that must be refused;
   - counts only.

   It counts on `provider_users`:
   - accounts holding an address with `email_verified = false`:
     - **none:** B16.4a also finds a Pro account by address only where it proved it, on both twins (decision 260's first half), and nothing changes for anyone;
     - **any:** the deploy waits, and the owner chooses with the numbers in hand;
   - accounts with a Google link, and with an Apple link: those the new refusal can ever touch;
   - Sentry's 30 days: any unique violation on `provider_users`, the race's 500;
   - the database's default collation, a key name, which says whether §5.3's byte-order tie-break changes anything in production (B16.4a's build, §8.7).

   It cannot count past relinks (§5.1).
3. **B16.4b, the Pro app's sentence:** its own PR. It reaches people with the next Pro build.
4. **B16.4c, the website's sentence:** its own PR. Its merge is a production deploy.
5. **B16.4a's deploy,** on the owner's word, once B16.4c is live and the read is clean.

   **Read back:**
   - `/health`;
   - `POST /auth/provider/google` with a bad token answers as before;
   - the production monitor;
   - Sentry over the next day.

**Rollback.** Safe: no schema change. An older image relinks again and races again, as today.

**Scope.** V1 only. No new screen and no flag. The Pro app's change is one sentence.

## 10. Definition of done (for each build)

- [ ] §8's contracts and races red first on today's code, for the stated reason, then green; §8.4's mutations red with their text; C1 green.
- [ ] The full suite (backend, or app, or website) green; analyze or lint and typecheck 0; format clean.
- [ ] B16.4a also updates:
  - `openapi.yaml`;
  - T32, T33 and T35;
  - `pro-auth-social.md`'s link rule;
  - the interface comment of `provider_auth_repository.dart:186-189`;
  - a link to this spec from each repository method it changes.
- [ ] BACKLOG B16.4, this spec's status, the index row and a roadmap entry updated.
- [ ] Feature branch and PR; CI green; owner-authored, no attribution.

---

## 11. Questions for the owner — answered 2026-11-27, « Approve as recommended » (decisions 284–288)

Numbered from **284**, after the A5 spec's 279–283.

**Q1. A Pro account already linked to a Google (or Apple) account: may another Google account that asserts the same verified address take its place?**
- **Recommended: no, never relinked, on both twins** (§5.1). This is decision 260's rule, applied to MyWeli Pro. → ✅ **Decision 284.**
  - The sign-in is refused with `409 social_link_taken`. The Pro app and the website say which link it is and point to the e-mail code (§5.6).
  - Cost: a salon whose Google account was recreated signs in by code from then on.
  - A relink that already happened stays, and the old account is then sent to the code (§5.1).
- Or keep today's relink, and the twin follows Postgres: one link per provider, the old one stops working until it asserts the address again. No client change. The takeover of §5.1 stays.
- Or never relinked, answered as `provider_not_found`. No client change, but both clients then say there is no account at an address that has one, and the Android sign-up answers « account exists » (§2.3).

**Q2. The Pro e-mail code: where is it checked and spent?**
- **Recommended: under its row's lock, in the transaction that spends it, in every Pro code path,** as B16.3a's build does for client codes (§5.2). → ✅ **Decision 285.**
  - A refused sign-up keeps its code, on both twins.
  - A lost race answers `provider_exists`, whatever the identity: never a 500.
  - Parallel wrong guesses each cost an attempt.
  - Only the e-mail path touches a code.
- Or only the twin follows Postgres (it keeps the code), and Postgres stays as it is: the race stays a 500, and the attempt budget can be outrun.
- Or spent at the check, on both twins (the twin's behaviour): a refused sign-up costs the code.

**Q3. The admin console's user list: one rule on both twins?**
- **Recommended: Postgres's order** (newest first), with a tie broken by the id in byte order. → ✅ **Decision 286.**
  - `q` matches name, phone or e-mail each on its own, case ignored.
  - `%`, `_` and `\` are taken as typed; accents as typed, as today (§5.3).
- Or the same, with accents and spaces folded as the salon search does: « elodie » finds « Élodie ».

**Q4. Read production before B16.4a's deploy?**
- **Recommended: yes,** read-only, counts only, after the build, on your word (§9 step 2). → ✅ **Decision 287.** It counts:
  - whether any Pro account holds an address it never proved. None → B16.4a also requires a proven address to find an account by it. Any → the deploy waits for your choice;
  - how many accounts hold a Google or an Apple link;
  - Sentry's 30 days for the race's 500.
- Or deploy without reading. A Pro account holding an unproven address would then stay B16.3's trap, unseen.

**Q5. When, and in how many PRs?**
- **Recommended: as a P2** (a takeover path in production, rarely reachable), **in three PRs, each built and merged on your word** (§9). → ✅ **Decision 288.** The PRs:
  - B16.4a, the backend;
  - B16.4b, the Pro app's sentence, which reaches people with the next Pro build;
  - B16.4c, the website's sentence, whose merge is a production deploy.

  Q4's read comes after B16.4a's build. B16.4a's deploy comes on your word, once B16.4c is live and the read is clean.
- Or the backend alone now, with the clients' sentences later.

---

## 12. Found next to it

- **No way to move a Pro account to a new Google or Apple account.** Under Q1's recommendation, a salon whose Google account was recreated keeps its e-mail code. Moving the link would need a signed-in step: proof by code, then « relier ce compte Google ». Not decided here.
- **The invitation decline spends the code when an account exists.** `invitations/decline.dart:55-60` calls `verifyEmailOtp` « WITHOUT consuming it ». That is true only when there is no account. With one, the call consumes the code, marks the address proven and mints a session that nobody receives. Not changed here: B16.4a keeps `verifyEmailOtp`'s answers. For the access module's next pass.
- **The Pro app's `provider_exists` sentence talks about a number:** « Un compte existe déjà pour ce numéro. Connectez-vous. » (`api_auth_service.dart:1093-1094`). Pro accounts have been found by address since the auth overhaul, and the Android sign-up has its own sentence for it. A stale sentence, for the next Pro copy pass.
- **The console's search ignores accents only as typed:** « elodie » does not find « Élodie », on either twin (§2.1's controls). Q3's alternative.
- **Production's collation is not visible from the repository.** The case-folding controls pass on the local Postgres 16 and on CI's; Cloud SQL's `LC_CTYPE` is unverified. The byte-order tie-break of §5.3 does not depend on it.

---

## 13. Review log

- **2026-11-27, drafted:**
  - the four survey rows read on both twins, with every caller;
  - one throwaway probe on both twins (§2.1), its database dropped;
  - found by the probe: the Pro relink in production (B-P1-b on both twins, not only a twin difference), the sign-up race's 500, and that B-P2-b was closed by B16.3a.
- **2026-11-27, reviewed once by an independent read-only reader, told to refute it against the code.** It confirmed every line reference of §2 and the §6 disclosure argument. **Three blockers, each checked in the code, then folded in:**
  - §5.2 copied B16.3a's **design**, a single `DELETE … RETURNING`, which its build dropped for a row lock and a re-run (account-email-change.md §8.4; `postgres_auth_repository.dart:146-157`, `:192-202`, `:217-252`). Today's Pro attempt accounting can be outrun by parallel guesses. §5.2 now copies the build; T32 gains a line;
  - the losing request's answer was mispredicted: `otp_none`, or `otp_invalid` after a fresh code, never `provider_exists` from the index. The index is reached by code-less races: a double-tapped Google sign-up, Google and e-mail on one address, an invitation. The re-run now covers every identity;
  - the old race test could not fire under its mutation: a same-code pair never reaches the `INSERT`. Replaced by forced races on a side pool (§8.2), B16.3a's method.

  **Should-fixes, folded in:**
  - `OR $subColumn = @s` for a double-tapped first link, and a re-run on a raced sub;
  - [spent by the creation] tests the same code on the same address;
  - where the `provider_exists` check sits, and that the code is deleted last;
  - Postgres deleting a pending code on a Google or Apple sign-up, a second twin difference;
  - the Android sign-up's check and the website's Apple line as client surfaces;
  - a past relink frozen by the rule, said in Q1;
  - T33;
  - the Pro accounts whose address was never proven (`migrations.dart:556`), now Q4's read.

  **Nits, folded in:**
  - line references;
  - B-P1-d's empty `RETURNING`;
  - both sort keys descending;
  - `ILIKE … ESCAPE`;
  - fixtures that make the wildcard and tie cases able to fail;
  - the handler test that guarded nothing new, dropped.

  **Added to §12:** the invitation decline's spent code.
- **2026-11-27, answered:** « Approve as recommended », all five (decisions 284–288, batch 16 in the BACKLOG).
- **2026-11-28, B16.4a built** (§8.7): red first on both twins, then green; read once by an independent reviewer (no blocker, six should-fixes folded in); 30 mutations, all red.
