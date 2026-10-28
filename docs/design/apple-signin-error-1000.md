# « Continuer avec Apple » on iOS error 1000 — say how to fix it

| | |
|---|---|
| **Status** | Approved 2026-10-28 — Q1 answered: sentence A (§2.3, §10) |
| **Owner** | Sadreddine Daher |
| **Last updated** | 2026-10-28 |
| **PRD ref / phase** | FR-AUTH-001/002 (sign-in) · V1 · ships with 0.0.2 |
| **BACKLOG** | B0.14, decision 50 (answered « do it » on 2026-10-28) |
| **Related** | [app-store-forms.md](app-store-forms.md) §13.3 (the 2026-10-26 event and the ready reply) · [app-auth-social.md](app-auth-social.md) · [pro-auth-social.md](pro-auth-social.md) · `mobile/lib/services/api/api_auth_service.dart` |
| **Skills checked** | myweli-dev-guardrails · myweli-verification-guardrails |

---

## 1. Goal & scope

**What happened.** On 2026-10-26, three minutes after 0.0.1 was resubmitted, a
device that is almost certainly Apple's tapped « Continuer avec Apple » in
MyWeli Pro twice. Both times iOS answered `ASAuthorizationError` **1000** on
the device, before any request reached our server, and the app said
« Connexion Apple impossible. ». The tester then signed in with the demo
account's e-mail code (BACKLOG B0.1).

**What is wrong with today's sentence.** It is the same for every failure, and
it gives no way forward. Error 1000 usually has a fix the person can make
themselves: an Apple Account signed in on the device.

**Goal.** On that code only, say what to check, in the place the failure is
already said.

**In scope**
- Both apps' Apple entry points, which share `api_auth_service.dart`:
  `signInWithApple()` (MyWeli, `/auth/apple`) and `signInProviderWithApple()`
  (MyWeli Pro, `/auth/provider/apple`).
- `AuthorizationErrorCode.unknown` only.

**Out of scope, and why**
- **The other codes** (`failed`, `invalidResponse`, `notHandled`,
  `notInteractive`, the credential import/export codes): no event, and no fix a
  person can make. They keep « Connexion Apple impossible. ».
- **Android**: no Apple button there. `_showApple` is
  `FeatureFlags.appleSignIn && defaultTargetPlatform == TargetPlatform.iOS`
  on both login screens.
- **The web**: Apple's JS has its own errors, and no event points there.
- **The server**: nothing reached it.
- **Telemetry**: unchanged. `social_sign_in_failed provider=apple code=unknown`
  is still reported, with the enum name only.

### 1.1 What `unknown` covers — read in the plugin, not assumed

`sign_in_with_apple` 8.2.0 (`pubspec.lock`), file
`darwin/.../SignInWithAppleError.swift`:
- `ASAuthorizationError.unknown` (1000) becomes `authorization-error/unknown`.
- **Any code the plugin does not know** (`@unknown default`) keeps the same
  default string, `authorization-error/unknown`.
- `sign_in_with_apple_platform_interface` 2.0.0 maps that string to
  `AuthorizationErrorCode.unknown`.

So `unknown` means **1000, or a newer code this plugin version does not
know**. Its usual cause, a device with no Apple Account signed in, is an
inference: the event carries nothing more. The sentence therefore asks the
person to *check*; it never claims the cause.

## 2. UX & flow

### 2.1 Entry points
- MyWeli Pro: the options step of `ProLoginScreen`, « Continuer avec Apple ».
- MyWeli: the options step of `LoginScreen`, the same button.

### 2.2 Flow and states

| What iOS answers | What the person sees (under the form, `InlineFeedback`, a live region) | Changed? |
|---|---|---|
| `canceled` (they closed the sheet) | nothing | no |
| **`unknown` (1000)** | **the new sentence (§2.3)** | **yes** |
| any other plugin code | « Connexion Apple impossible. » | no |
| not a plugin error | « Connexion Apple impossible. » | no |
| a credential with no identity token | « Connexion Apple impossible. » | no |

The button stays, so after fixing the account the person taps it again; there
is nothing to dismiss. E-mail sign-in stays on the same screen. The sentence
wraps (`InlineFeedback` lays it out in an `Expanded`), and is checked at 200 %
text (§8).

### 2.3 Copy — **Q1: A, chosen 2026-10-28 (§10)**

Words chosen to match the iPhone: **« Réglages »** is iOS Settings in French;
**« compte Apple »** is Apple's French name since iOS 18 (formerly
« identifiant Apple »). The wording is gender-neutral: « qu’un compte Apple est
connecté », not « que vous êtes connecté(e) ». The apostrophes are typographic
(’), as in `kNoProAccountMessage`.

- **A (recommended):** « Connexion Apple impossible sur cet appareil. Vérifiez
  dans Réglages qu’un compte Apple est connecté, puis réessayez. »
  - Says it is this device.
  - Says what to check, without claiming the cause.
- **B:** « Connexion Apple impossible. Connectez-vous à votre compte Apple dans
  Réglages, puis réessayez. »
  - Shorter.
  - States the fix as if the cause were known.
- **C:** A, ending « …est connecté, ou continuez avec votre e-mail. »
  - Offers a way out.
  - But someone whose Apple account hides their address (a `privaterelay`
    e-mail) has no e-mail sign-in to the same account.

## 3. API & contract

None. The response keeps code `apple_failed`. The providers act on one code
only, `cancelled`, and the screens show `error` as it is.

## 4. Data model

None.

## 5. Architecture

- **One constant** in `core/constants/failure_messages.dart`, the home of
  failure sentences.
- **One private helper** in `ApiAuthService` that picks the sentence for a code.
  Both Apple `catch` arms use it, so the two apps cannot drift apart.
- **The mock auth service is unchanged**: it opens no Apple sheet.

## 6. Security & privacy

No new data. The logged line is unchanged: a closed enum name, never Apple's
free-text message.

## 7. Performance

None.

## 8. Tests (red first)

- **Unit** (`test/unit/api_auth_apple_error_test.dart`), for both entry
  points, one case per `AuthorizationErrorCode.values`:
  - `canceled` gives `cancelled` and an empty message;
  - `unknown` gives the new sentence;
  - every other code gives « Connexion Apple impossible. ».
  - Iterating the enum means a code the plugin adds later is covered without
    editing the test.
  - **No request is sent** in any case: the HTTP client fails the test if
    called.
  - A non-plugin exception still gives the generic sentence.
- **Widget** (`test/widget/apple_error_1000_test.dart`):
  - the real `ApiAuthService`, its Apple seam throwing `unknown`, behind the
    real `ProAuthProvider` and `ProLoginScreen`, on iOS;
  - `debugDefaultTargetPlatformOverride`, reset in a `finally` (memory:
    test-platform-blind-spots);
  - the sentence appears inside `InlineFeedback`, at 100 % and at 200 % text,
    with no overflow.
  - The same for `LoginScreen` and `AuthProvider`.
- **Mutations, on committed work**:
  - (1) `unknown` falls back to the generic sentence: unit and widget tests
    go red.
  - (2) only the Pro arm uses the helper: the client cases go red.
  - (3) the helper also catches `failed`: the per-code test goes red.

## 9. Rollout

- Lands on main and **ships with 0.0.2**. Build 698, under review, is not
  touched, so app-store-forms §13.3's reply still describes what Apple has.
- Nothing to change in App Store Connect.

## 10. Questions — answered

- **Q1 — the sentence (§2.3).** ✅ **A**, on 2026-10-28.
  - **The owner asked first** whether the error could be fixed so that it
    never appears, and said to do what is best in the long term.
  - **The answer: not from our side.**
    - iOS raises 1000 on the device, before our app or server gets anything.
    - What we control is verified: the entitlement is in build 698, the App ID
      has Sign in with Apple turned on, and the owner's own sign-in on 698
      reached the server.
  - **The usual cause is a device setting**, an iPhone with no Apple Account
    signed in.
    - Installing from the App Store needs an Apple Account, but only for
      purchases; that sign-in does not guarantee one under Réglages. Real users
      almost always have both, and review devices are the exception.
    - No app can sign a phone in to an Apple Account.
    - iOS offers no reliable way to check beforehand and hide the button.
  - **The one way round it was weighed and not chosen:** a web sign-in with
    Apple as a fallback inside the app. It needs a new server flow, it is not
    how iOS apps are expected to sign in with Apple, and it would put review at
    risk.
  - **So the long-term answer is A**, chosen under the owner's « do what is
    better »:
    - it says what to check without claiming the cause;
    - e-mail sign-in stays on the same screen;
    - Sentry keeps counting `code=unknown`, which shows whether real users ever
      hit it.
