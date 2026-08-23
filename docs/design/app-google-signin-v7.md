# `google_sign_in` v7 — the migration, and the cancel it would have broken

| | |
|---|---|
| **Status** | Built and **device-verified** (2026-08-15) — §9 |
| **Owner** | Sadreddine Daher |
| **Last updated** | 2026-08-15 |
| **PRD ref / phase** | FR-AUTH — social sign-in · V1 |
| **ROADMAP entry** | Launch readiness — dependency currency |
| **Skills checked** | myweli-dev-guardrails |

Companion to [app-auth-social.md](app-auth-social.md), which owns the flow itself.
This spec covers only what the v6 → v7 change does to it.

## 1. Goal & scope

Dependabot [#346](https://github.com/Zaslons/myweli/pull/346) bumps `google_sign_in`
6.3.0 → 7.2.0 and **does not compile**: v7 removed the unnamed constructor and
`signIn()`.

v7 is a redesign — a process-wide `GoogleSignIn.instance`, an explicit
`initialize()`, `authenticate()` in place of `signIn()`, and a split between
**authentication** (identity, ID token) and **authorization** (scopes, access
token).

**In scope:** the three call sites, the cancel contract, and a test seam.
**Out of scope:** anything about the flow's UX, which is unchanged; the
authorization half, which this app has never used.

**The luck that makes this small:** the entire Dart surface is one import and two
constructions in one file, and both read exactly one field — `idToken`.
`accessToken`, `serverAuthCode`, `email`, `displayName`, `photoUrl` and `id` are
never touched. v7's `GoogleSignInAuthentication` carries **only** `idToken`
(`token_types.dart:18`) — the access token moved to the authorization client —
so the one thing v7 took away is the one thing we never wanted.

## 2. The two questions that could have blocked it

Both were answered from the plugins' native source, not from memory, and both
resolve favourably. They are recorded because "it compiles" would not have
settled either.

### 2.1 Does the backend receive anything different? **No.**

`GoogleIdTokenVerifier` checks `aud` against `GOOGLE_CLIENT_IDS`, so a changed
audience is a 401 for every Google user, on a backend that is already deployed.

- **Android** — v6 `requestIdToken(serverClientId)`; v7
  `GetSignInWithGoogleOption.Builder(serverClientId)`. Both mint an ID token whose
  `aud` is the **web** client.
- **iOS** — the configuration code is functionally identical between versions, and
  both return `user.idToken.tokenString`. Neither sends a nonce, so the backend's
  deliberate `rejectUnsolicitedNonce: false` stays correct and the 2026-07-03 iOS
  nonce fix is not re-opened.
- **The wire format is untouched:** `{'idToken': <jwt>}` to `/auth/google`,
  `/auth/provider/google`, `/auth/provider/register` and the two invitation routes.

**The one way this could still change:** if `serverClientId` fails to reach
`initialize()`. Android's `aud` would then become whatever `default_web_client_id`
resolves to, and any mismatch is a 401 `token_rejected` — which the app collapses
into the generic « Connexion impossible. Réessayez. », with no server-side signal
distinguishing it from a forged token. **That single argument is the most
important line in the diff.**

### 2.2 Does the upgrade sign anyone out? **No.**

The session is *our* JWT pair in `flutter_secure_storage`, issued by our backend.
After login nothing in the repo consults Google again — `signOut`, `disconnect`,
`isSignedIn`, `signInSilently`, `currentUser` and `onCurrentUserChanged` appear
nowhere in `mobile/`, and `logout()` only clears the local store. Android v7
abandons the old Play-services state for Credential Manager, but no code reads it.

## 3. The actual work: cancel semantics

v6 `signIn()` returned **null** when the user dismissed the sheet. v7
`authenticate()` returns a **non-nullable** account and **throws**
`GoogleSignInException(code: canceled)` instead.

Every call site wraps its body in a bare `catch (_)` that answers
`code: 'google_failed'`. The providers suppress the banner only for exactly
`'cancelled'` — so a compile-only fix ships **a red « Connexion Google
impossible. » every time a user closes the Google sheet**, on the consumer login,
the pro login and the pro registration. `app-auth-social.md:49` states the
requirement in one phrase: *"Google-cancel = silent"*.

That is the whole reason this is a migration and not a version bump, and no test
in the repo would have caught it.

**The fix is not new** — it is the shape the Apple path 30 lines below already
uses: a typed `on …Exception` arm that checks for the cancel code, then the
generic arm. After this the two social paths read identically.

## 4. One behaviour change, chosen deliberately

`_googleIdToken()` returns `String?` and conflates two outcomes — *cancelled* and
*signed in but no ID token*. Both pro callers report `'cancelled'`, so a genuine
token failure currently shows the user **nothing at all**.

v7 splits them for free: cancel throws, no-token still returns null. So the pro
paths now answer `no_id_token` with « Connexion Google impossible. » where they
previously failed silently. That is a change in what a user sees, and it is the
correct resolution — it matches the consumer path, which has always distinguished
them.

## 5. Architecture

`GoogleSignIn.instance` is process-global, so `initialize()` must run **exactly
once** and complete before `authenticate()`. It is memoized in a static future,
cleared on failure so a transient error can be retried.

**Lazy, inside the service — not at bootstrap.** `google_sign_in_web` throws a
hard `StateError` on a second `init` and asserts `serverClientId == null`. CI
builds the Flutter package for web (`--target lib/main_admin.dart`); that target
never constructs `ApiAuthService`, so the Google path is unreachable from it —
*provided the initializer stays inside the service*. Hoisting it to a shared
bootstrap would hand the admin web build a `StateError`.

`scopeHint: const ['email']` reproduces today's behaviour exactly: Android ignores
`scopeHint`, iOS forwards it as `additionalScopes` — which is what v6 did with
`scopes: ['email']`. Dropping it is probably fine and is a gratuitous change to
the consent request.

**A test seam.** `GoogleIdTokenProvider` is a `typedef` injected through the
constructor, defaulting to the real native flow — the same pattern
`ApiImageUploadService` uses for `ImageCompressor`. Before this, `flutter test`
never executed a single line of the Google path.

## 6. Configuration — nothing new

`AppConfig.googleServerClientId` is a `String.fromEnvironment` whose default is
the real web client, and no workflow sets the define — so that default is what
every build ships. Its own comment says it: *"A public identifier, not a secret."*
It moves from the v6 constructor argument to `initialize(serverClientId:)`. Same
value, same file, no new secret, no CI change, no Gradle/Podfile/plist/manifest
edit. Version floors are already satisfied (`minSdk 24`, iOS 15.0, Dart ^3.12.0).

`clientId` is deliberately **not** passed: ignored on Android, and on iOS it
resolves from the bundled plist exactly as it does today.

## 7. Security

No change to what is sent, what is verified, or where tokens are stored. The ID
token is used immediately and never persisted; our own session lives in
`flutter_secure_storage`. No threat-model row changes — T‑auth's mitigations are
about the backend's verification, which is untouched.

## 8. Tests

**Newly provable, because of the seam:** cancel → `'cancelled'` with an empty
message (the silent contract, on all three entry points); any other exception code
→ `google_failed`; `null` → `no_id_token`; happy path → the exact request body and
a parsed session; and the pro invited-bridge carrying `GoogleInvitationProof`.

Before this change, `api_auth_service_test.dart` contained zero occurrences of
"google" and every Google test drove `MockAuthService`.

## 9. Rollout — what CI cannot prove

`flutter analyze` and `flutter test` are the only gates, and they cover
compilation plus everything above the seam. They **cannot** cover: that
`initialize()` runs once and completes before `authenticate()`; that the token
still carries `email` + `email_verified` with an `aud` inside `GOOGLE_CLIENT_IDS`;
that Android's Credential Manager flow works on a real device; or that the iOS
SPM bump to GoogleSignIn 9.x builds. There is no iOS build in CI at all, and
backend CI runs with a placeholder `GOOGLE_CLIENT_IDS`.

### Verified on device, 2026-08-15

**Consumer iOS and consumer Android both sign in successfully** against
production, on the owner's real handsets — the ID token is accepted, so the
`aud` really is inside `GOOGLE_CLIENT_IDS` and `initialize()` really does
complete before `authenticate()`. Android is the one that mattered: v7 moved
that platform to Credential Manager, an entirely different native flow, while
iOS changed comparatively little.

The **silent cancel** was verified separately on the iOS simulator: tapping
« Continuer avec Google » then dismissing the Google prompt returns to the login
screen with no error banner — the regression a compile-only port would have
shipped.

**Pro Android was not run, and is now low risk rather than unverified.** Both
pro entry points call the *same* `_nativeGoogleIdToken()` static as the consumer
path, so the SDK-level flow proven on consumer Android is literally the same
code. What differs is only which backend route the resulting token is posted to
— pure Dart, covered by the unit tests. Before this change they were two
separately-constructed `GoogleSignIn` instances; the migration is what made them
one.

**A note for whoever tests this next:** on a dev machine with no
`android/key.properties`, `flutter run --release` will refuse to install
(release is deliberately left unsigned), and only the **debug** SHA-1 is
registered with Google. On Android, **debug is the correct build to test** — a
release build would fail sign-in in a way indistinguishable from a cancel.

---

**Device procedure** (`app-auth-social.md:73`), on **consumer Android, consumer
iOS, pro Android** at minimum:

```
flutter run --release --dart-define=USE_API_BACKEND=true
```

**Test the release build, and treat "nothing happened" as a failure.** Android's
Credential Manager returns *canceled* for several misconfigurations — wrong
signing SHA, wrong package name server-side, missing `serverClientId` — and the
plugin cannot distinguish them from a real dismissal. Because we correctly make
cancel silent, a release misconfiguration looks exactly like a user closing the
sheet: no banner, no log.

## 10. Not in this change — pre-existing, named so it is not mistaken for fallout

~~The iOS **pro** flavour's `GoogleService-Info.plist` has no `CLIENT_ID`, so the
plugin's configuration is never assigned, the Dart `serverClientId` is silently
dropped, and GIDSignIn falls back to `Runner/Info.plist`'s consumer client.
**v6 does exactly the same** — this change neither causes nor fixes it. If pro
iOS sign-in fails, verify against a pre-bump build before blaming this. Whether
pro iOS is meant to offer Google sign-in at all is undocumented.~~

**Fixed in #499 (2026-08-22)** — struck rather than deleted, because the
paragraph is why the defect survived this long: named as pre-existing, it read
as somebody else's problem. Pro now has its own iOS OAuth client
(`…o68qiuiv…`), its `GoogleService-Info.plist` carries `CLIENT_ID`, and
`Runner/Info.plist` hardcodes **neither** flavour's — `GIDClientID` and the
redirect scheme are per-configuration build settings written by
`ios/tool/setup_flavours.rb`. `ios_google_client_test.dart` pins that the two
flavours carry different clients and that `Info.plist` names none.

The last sentence's open question is answered too: pro **does** offer Google
sign-in (`pro_login_screen.dart` renders the button unconditionally), which is
what made the fallback a store-rule 2.1 rejection rather than dead code. See
[app-auth-social.md](app-auth-social.md) §5.
