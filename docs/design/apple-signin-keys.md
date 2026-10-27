# Sign in with Apple keys — one per app, so account deletion revokes everywhere

| | |
|---|---|
| **Status** | Approved 2026-10-27 (owner: §11, Q1–Q4 answered as recommended) · **PR 1 (code) built**; the two keys exist (step 1); the pre-deploy probe measured useless and removed (§5, §9 step 2); the two secrets in Secret Manager (step 3, read back); **PR 2 (manifest) built** — the deploy remains |
| **Owner** | Sadreddine Daher |
| **Last updated** | 2026-10-27 |
| **PRD ref / phase** | Account deletion (App Store 5.1.1(v)) · V1 |
| **BACKLOG** | B6.7 (built inactive in #679), the owner's « Sign in with Apple key » step |
| **Related** | [backend-integrity-batch6.md](backend-integrity-batch6.md) §13 (the exchange and the revocation, as built) · [auth-social-email.md](auth-social-email.md) (Apple sign-in) · [web-pro-apple.md](web-pro-apple.md) (the web's Services ID) · [DEPLOYMENT.md](../DEPLOYMENT.md) Phase C · BACKEND.md T79 |
| **Skills checked** | myweli-backend-guardrails · myweli-verification-guardrails |

---

## 1. Goal & scope

**Goal.** Turn on what B6.7 built: when a person deletes their MyWeli or MyWeli
Pro account, the server revokes their Sign in with Apple authorization, so the
app leaves « Apps using Apple ID » (App Store 5.1.1(v)). The code exists and is
deployed **inactive**; it waits for a key.

**Why this is not « create one key and paste it ».** DEPLOYMENT.md Phase C says
to create one key on « the app's primary App ID », with every Apple client
« grouped under it ». **They are not grouped.** Read through the App Store
Connect API on 2026-10-27 (`bundleIdCapabilities`, `APPLE_ID_AUTH`):

| Client | What it is | Sign in with Apple configuration |
|---|---|---|
| `com.myweli.app` | MyWeli (consumer), iOS | `PRIMARY_APP_CONSENT` — **its own primary** |
| `com.myweli.pro` | MyWeli Pro, iOS | `PRIMARY_APP_CONSENT` — **its own primary** |
| `com.myweli.signin` | the website's Services ID (« MyWeli Web Sign-In », client **and** Pro pages) | attached to **`com.myweli.app`** — read by the owner in the portal on 2026-10-27 (§9 step 1; Services IDs are not in the API) |

Apple's documentation (developer.apple.com/help/account): you create a key and
« associate it with a primary App ID. You can associate two keys with each
primary App ID » (*Create a Sign in with Apple private key*); and on ungrouping:
« Authentication will continue to function. However, we recommend that you
create a new Authentication Key for each app enabled with Sign in with Apple »
(*Group apps for Sign in with Apple*). **Apple's model is a key per primary.**
What Apple does **not** document is whether a key is refused for a client of
another primary — and **it cannot be measured before a real sign-in** (§9 step
2: no fake request discriminates, read with controls on 2026-10-27). So the
design follows Apple's documented model, and the first real Apple sign-in per
client after the deploy is the test (§9 step 7). With **one** key, if Apple
refuses it across primaries, one app's tokens are never exchanged nor revoked —
and the app in review is the Pro one.

**In scope.** The decision (two keys or grouping); the server reading one key
per primary and choosing it by client; a log line that names Apple's error
word, so a real sign-in tells a key that does not cover its client
(`invalid_client`) from a refused code; the manifest; the docs that are wrong
today (DEPLOYMENT.md Phase C, T79); the owner's portal steps.

**Out of scope.** Apple's server-to-server notifications (§11, Q4); a second
Services ID for the Pro web (§11, Q2); anything on Android — the Apple button is
iOS-only in both apps (`_showApple`: `defaultTargetPlatform ==
TargetPlatform.iOS`), so Android never produces an Apple sign-in.

## 2. How Apple sign-in works today — read on main, 2026-10-27

**Who signs in, with which client.**

| Surface | Route | Client (`aud` of the identity token) | Sends Apple's code |
|---|---|---|---|
| MyWeli iOS | `POST /auth/apple` | `com.myweli.app` | yes (`_appleCode`, `api_auth_service.dart`) |
| MyWeli Pro iOS | `POST /auth/provider/apple` | `com.myweli.pro` | yes (same helper) — build 698 included |
| Web, client space | `POST /auth/apple` (BFF) | `com.myweli.signin` | yes, with `redirectUri` = `<origin>/connexion` (`apple-bff.ts`) |
| Web, Pro sign-in | `POST /auth/provider/apple` (BFF) | `com.myweli.signin` | yes, same |
| Web, Pro sign-up | `POST /auth/provider/register…` (BFF) | `com.myweli.signin` | yes, same |

**How an Apple identity finds its account.** By `apple_sub` first, then — only
when Apple says the e-mail is verified — by e-mail (T33/T35); the consumer side
creates an account, the Pro side never does (`provider_not_found`).
**The identifier does not depend on any of this:** Apple's TN3159 calls user
identifiers and private relay addresses « developer team-scoped ». The same
person has the same `sub` in MyWeli, MyWeli Pro and on the web, grouped or not.
Its return URL is registered: Apple's `/auth/authorize` for `com.myweli.signin`
opens its sign-in page with `redirect_uri=https://myweli.com/connexion`, and
answers « invalid_request — Invalid web redirect url. » to the same request
with an unregistered path (the control), read on 2026-10-27.

So **neither option below touches account matching** — consistent with the
owner's report that, on build 698, a web sign-up followed by « Continuer avec
Apple » in the Pro app landed on « Accueil » (app-store-forms §11.6).

**The exchange (sign-in).** After a successful sign-in, `keepAppleSignInCode`
reads the client from the verified token's audience and calls Apple's
`/auth/token` with a `client_secret` signed by the key (`sub` = that client).
It keeps the refresh token in `apple_tokens` under (kind, account, **client**) —
only if Apple's answer names the same `sub`. Awaited, bounded at 5 s, never
throws: **a sign-in is never Apple's to fail**; at worst it is up to 5 s
slower when Apple is slow.

**The revocation (deletion).** Both deletion paths
(`provider_account_service.dart:173`, `user_erasure_service.dart:190`) call
`revokeAll`: each kept token is revoked **with its own client**, then every row
is erased whatever Apple answers. Never throws; the deletion always proceeds.

**The boot.** No key → inactive, a `NOTICE` at each production boot (what
production prints today). Some of the three variables, or an unreadable key →
the server refuses to start, so a bad revision never takes traffic.

**What already fits two keys.** The token table stores the client per token,
and both calls already name the client — only « which key signs for this
client » is missing. That is the whole server change.

## 3. Two keys or grouping — the long-term choice

| | **Two keys (recommended)** | **Group Pro under MyWeli** |
|---|---|---|
| Apple's model | Grouping is for versions of **one** app (Apple's example: the iOS version of a Mac app). MyWeli and MyWeli Pro are two products for two audiences. | Bends that model. |
| What people see | « MyWeli » and « MyWeli Pro » as two entries in Settings → Apple ID → Sign in with Apple; consent per app. | One entry; consent once covers both. A developer forum report says the grouped app vanished from that list and its revocation misbehaved — unconfirmed by Apple. |
| Deleting an account | Revokes only that product's authorization (for app sign-ins). | Revokes the group: deleting a consumer account also cuts the same person's Pro authorization (they consent again at the next Pro sign-in). |
| « Stop using Apple ID » in Settings | Stops one app. | Stops both. |
| Identifiers | Unchanged (team-scoped). | Unchanged (team-scoped). |
| The Pro app in review | No change to any App ID. | Changes the Pro App ID's Sign in with Apple configuration during review; editing capabilities usually invalidates its provisioning profiles (the next build regenerates them). |
| Server work | Small: one key per primary, chosen by client (§5). | None. |
| A leaked key | Affects one product; each primary rotates on its own (two keys allowed per primary). | Affects both. |
| Changing course later | Grouping later stays possible. | Ungrouping later converts each app to a primary — and Apple then recommends a new key per app: the two-key work, plus a migration. |

**Recommendation: two keys, apps stay separate primaries.** The only cost is a
small, testable server change; everything people see and every revocation stays
scoped to the product they used.

**The website's one Services ID.** It serves both the client and the Pro pages
and sits under the **MyWeli** primary (read 2026-10-27). Consequence, with two
keys: a token kept from a web sign-in is revoked with the MyWeli key
(`APPLE_APP_KEY_CLIENTS=com.myweli.app,com.myweli.signin`,
`APPLE_PRO_KEY_CLIENTS=com.myweli.pro`). When a person deletes a Pro account
they created on the web, the revocation cuts their MyWeli-group authorization
too — they consent again at their next
MyWeli Apple sign-in; same identifier, same account. Harmless, and stated here
so it is not a surprise. A second Services ID for the Pro web (under the Pro
primary) would remove it — §11, Q2, recommended later, not now.

## 4. Configuration (the contract between the manifest and the server)

| Variable | Kind | Example | Meaning |
|---|---|---|---|
| `APPLE_TEAM_ID` | plain | `5VWKJD956A` | the team (read from the signed IPA's entitlements) |
| `APPLE_APP_KEY_ID` | plain | 10 characters | the key on the **MyWeli** primary |
| `APPLE_APP_PRIVATE_KEY` | secret (`secretKeyRef`, pinned) | the `.p8` | |
| `APPLE_APP_KEY_CLIENTS` | plain | `com.myweli.app` (+ `com.myweli.signin` if under it) | the clients this key signs for |
| `APPLE_PRO_KEY_ID` | plain | 10 characters | the key on the **MyWeli Pro** primary |
| `APPLE_PRO_PRIVATE_KEY` | secret (`secretKeyRef`, pinned) | the `.p8` | |
| `APPLE_PRO_KEY_CLIENTS` | plain | `com.myweli.pro` (+ `com.myweli.signin` if under it) | |

**Boot rules** (each refusal names the variable, never a value):
1. No `APPLE_*` key variable at all → **inactive**, the existing `NOTICE`.
2. A slot is all three of `_KEY_ID`, `_PRIVATE_KEY`, `_KEY_CLIENTS`, or none →
   otherwise **refused**.
3. Any slot set → `APPLE_TEAM_ID` required → otherwise **refused**.
4. Each listed client must be in `APPLE_CLIENT_IDS`; no client in both slots →
   otherwise **refused** (a typo would otherwise silently keep nothing).
5. A client of `APPLE_CLIENT_IDS` covered by no slot → **started**, with a
   `NOTICE` naming it (lets one key go live before the other).
6. The old single-key names (`APPLE_KEY_ID`, `APPLE_PRIVATE_KEY`) → **refused**,
   pointing at the new ones. They were never deployed; refusing them stops a
   half-migrated manifest from looking configured.

## 5. Architecture

- `apple_tokens.dart`: `AppleSignInKey` stays (one key, signs a client secret).
  New `AppleSignInKeys` — `fromEnv` applies §4, `forClient(clientId)` returns
  the key or null, `isActive` = at least one key, `uncovered(clientIds)` for
  the boot `NOTICE`.
- `AppleTokenService` takes `AppleSignInKeys`. `keepFromCode`: no key for the
  client → log `apple_token SKIPPED … cause=no_key_for_client client=<id>`
  (a client id is not a secret) and keep nothing. `revokeAll`: each token with
  its client's key; a token whose client has none → `apple_revoke SKIPPED …`;
  **every row erased in every case**, as today.
- `dependencies.dart`: wires `AppleSignInKeys.fromEnv`; the boot `NOTICE`
  covers « no key » and « client X has no key ».
- The `FAILED` lines carry the client and **Apple's error word**
  (`appleErrorWord`: a short lowercase word or `-`, never the rest of the
  body): at the first real sign-in, `invalid_client` means the key does not
  cover that client — the only test of a key there is (§9 step 2).
- *A pre-deploy probe was built and removed the same day:* asking `/auth/token`
  with an invalid code answered `invalid_grant` and `/auth/revoke` with an
  invalid token answered `200` **for every control** — a wrong Key ID, a wrong
  Team ID, a client that does not exist, a secret signed by the other key.
  Apple refuses the code (or accepts the revocation) before it authenticates
  the client, so no fake request tells a covering key from a wrong one.
- Layering unchanged: routes untouched; no contract change (no endpoint, no
  DTO); no migration (`apple_tokens` already keys tokens by client).

## 6. Security

- The `.p8` files go **from the owner's download straight into Secret Manager**
  (the owner runs `gcloud secrets create … --data-file=`); Claude never prints,
  pastes or commits them. After upload: the owner keeps an offline copy in a
  password manager and deletes the downloads.
- *2026-10-27:* the two keys' contents reached the session transcript — the
  files were attached to the chat with « @ », which reads them in. Offered a
  revoke-and-recreate (nothing used them yet), **the owner chose to keep
  them**. Next time: a secret file is named by its folder, never attached.
- Secrets pinned (`key: '1'`), as `service_files_test.dart` requires; the
  runtime service account gets `secretAccessor` on exactly these two.
- T79 changes from « the key » to « one key per primary, chosen by the token's
  client »; a client with no key keeps and revokes nothing (logged), the boot
  refuses an unknown or doubly-claimed client.
- Logs: unchanged discipline — never the code, a token, the secret; the new
  lines carry a client id (public: it is in every identity token) and Apple's
  error word, filtered to a short lowercase word.

## 7. Performance

Unchanged: one extra call to Apple per Apple sign-in once active (bounded at
5 s), one per kept token at deletion.

## 8. Testing plan (red first, mutations on committed work)

- `AppleSignInKeys.fromEnv`: each boot rule of §4 — inactive; a half slot
  refused per missing variable; no team refused; unknown client refused; a
  client in both slots refused; the old names refused; an uncovered client
  reported; a key that does not read refused.
- `forClient`: each client resolves to its own slot's key, none for others.
- `AppleTokenService`: the exchange signs with **the client's** key (the
  secret's `kid` and `sub` read back from the request a fake Apple receives);
  a client with no key sends nothing and logs `no_key_for_client`; revocation
  signs each token with its client's key; uncovered tokens are skipped **and
  still erased**.
- Boot: the `NOTICE` names an uncovered client; the inactive `NOTICE` stays.
- Manifest: `service_files_test.dart` — the two private keys by pinned
  `secretKeyRef`; the six plain values present together; every listed client in
  `APPLE_CLIENT_IDS`.
- The error word: `invalid_client` and `invalid_grant` logged with the client;
  an `error_description`, a non-JSON body, a long or odd « word » never logged.
- Mutations: pick the wrong slot; drop the « erase in every case »; accept a
  client in both slots; accept an unknown client; skip the team check; log
  Apple's whole body, or no word at all.

## 9. Rollout — who does what, in order

1. **Owner, Apple Developer portal** (nothing changes for users):
   - Identifiers → *Services IDs* → `com.myweli.signin` → Sign In with Apple →
     *Configure*: **note its Primary App ID** (`com.myweli.app` or
     `com.myweli.pro`). Read only — change nothing.
   - Keys → **+** → name « MyWeli — Sign in with Apple » → tick *Sign in with
     Apple* → *Configure* → Primary App ID **`com.myweli.app`** → Save →
     Continue → Register → **Download** (offered once) → note the Key ID.
   - Same again: « MyWeli Pro — Sign in with Apple », Primary App ID
     **`com.myweli.pro`**.
   - Tell Claude the two Key IDs, where the two `.p8` files are, and the
     Services ID's primary.
2. ~~Claude: the probe~~ — **measured useless, 2026-10-27** (§5): with the two
   real keys, every client — and every control (wrong Key ID, wrong Team ID, a
   client that does not exist, the other key's signature) — answered
   `invalid_grant` on `/auth/token` and `200` on `/auth/revoke`. What it did
   prove: both `.p8` files read as Apple keys. Coverage is tested at step 7.
3. **Owner: two commands** — `gcloud secrets create APPLE_APP_PRIVATE_KEY
   --data-file=<path>` and the same for `APPLE_PRO_PRIVATE_KEY`. Then Claude,
   on the owner's go, grants the runtime service account `secretAccessor` on
   both and reads the grants back. — ✅ **2026-10-27:** the owner ran all four
   (both creates and both grants). Read back: each secret has one version, `1`,
   enabled; `myweli-run` is its only reader; each version's SHA-256 equals its
   download's, and differs from the other download's (the control) — compared
   without either key being printed; `98-verify-secret-pins.sh` lists both as
   current.
4. **PR 1 — code** (this spec, §5, §8), mergeable any time: without the
   manifest it changes nothing in production (the inactive `NOTICE` stays).
5. **PR 2 — manifest**, after steps 1–3: the five plain values and two
   `secretKeyRef`s. Merging does not deploy (production is `workflow_dispatch`).
   **Merge after PR 1:** main's code before it reads `APPLE_TEAM_ID` alone as
   half a key and would refuse to boot. `apple_keys_manifest_test.dart` runs
   the manifest's real values through `AppleSignInKeys.fromEnv` on every push.
6. **Deploy — after Apple's decision on 0.0.1** (BACKLOG B0.1: nothing the
   reviewer relies on changes during review; this adds a call to Apple inside
   every Apple sign-in), on the owner's go, with the merge's `image_tag`.
7. **Read back — this is where the keys are tested:** the revision Ready at
   100 %; no `NOTICE` at boot; then **one real Apple sign-in per client** — the
   Pro app (`com.myweli.pro`, the Pro key), myweli.com (`com.myweli.signin`, the
   MyWeli key), and the MyWeli app (`com.myweli.app`) once a consumer build
   exists: each must leave no `apple_token FAILED` line and add a row to
   `apple_tokens` (counted, never read); `error=invalid_client` would mean
   that client's key does not cover it. Then the owner deletes a throwaway
   Apple account: the row is gone and the app has left their Settings → Apple
   ID list (owner-observed — `/auth/revoke` answers `200` even to a wrong key,
   §5, so its status proves nothing).

**Docs in PR 1:** DEPLOYMENT.md Phase C (the grouping sentence is wrong; the
new steps), BACKEND.md T79, backend-integrity-batch6.md §13 (a pointer here),
`.env.example`, BACKLOG, a roadmap entry.

## 10. Definition of done

Both keys exist and read; the server picks the key by client, every boot rule tested and
watched red; the manifest pinned; deployed after Apple's decision; the boot
`NOTICE` gone; one real exchange per client observed (no `invalid_client`), and
one real revocation seen leave the owner's Apple ID list.

## 11. Open questions — answered by the owner, 2026-10-27

- **Q1. Two keys (apps stay separate) or group Pro under MyWeli?**
  *Recommended: two keys* (§3). — ✅ **Two keys.**
- **Q2. The web's single Services ID** serves both spaces under one primary
  (§3, last paragraph). Keep it, or add a Pro Services ID now?
  *Recommended: keep it; revisit if the cross-revocation ever matters.* — ✅
  **Keep one for now.**
- **Q3. When to deploy?** *Recommended: after Apple's decision on 0.0.1*
  (B0.1). Creating the keys, the secrets and both PRs can all happen now. — ✅ **After Apple's decision.**
- **Q4. Apple's server-to-server notifications** (Apple tells us when someone
  stops using Apple ID with an app, or deletes their Apple account) — configured
  per primary, not built. *Recommended: a later BACKLOG item, not part of this.*
  — ✅ **Later, in the BACKLOG.**
