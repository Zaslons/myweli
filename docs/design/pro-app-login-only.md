# The Pro app signs salons in, it does not sign them up (App Store 3.1.1)

| | |
|---|---|
| **Status** | Approved 2026-10-26 (owner: §9, every question answered) |
| **Owner** | Sadreddine Daher |
| **Last updated** | 2026-10-26 |
| **PRD ref / phase** | FR-PRO-AUTH-001 (registration moves to the web), access R6 (« Ajouter un salon ») · V1 |
| **BACKLOG** | B0.11 (batch 0, the release track) |
| **Related** | [pro-companion-path.md](pro-companion-path.md) (3.1.3(f): the app never sells) · [app-store-forms.md](app-store-forms.md) (review notes, §2 3.1.1 analysis) · [pro-auth-social.md](pro-auth-social.md) (login-only sign-in) · [team-access-r6-multi-salons.md](team-access-r6-multi-salons.md) (« Ajouter un salon ») |
| **Skills checked** | myweli-dev-guardrails · myweli-verification-guardrails |

## 1. Why — Apple's rejection of 0.0.1

App Review of **MyWeli Pro 0.0.1 (587)**, 19 October 2026 (iPad Air 11-inch
M3, submission `45ed9726-1418-435b-b3e2-76726422c5d3`), cited one guideline:

> **Guideline 3.1.1 — Business — Payments — In-App Purchase.** « The app
> includes an account registration feature for businesses and organizations,
> which is considered access to external mechanisms for purchases or
> subscriptions to be used in the app. » Next step: « Remove the account
> registration features for business and organizations. »

The companion path (2026-10-05) took every *purchase* surface out of the Pro
app and kept registration — its own flow began « Register → onboarding ».
Apple has drawn the line at registration itself: a salon that signs up in the
app goes on to pay MyWeli outside it. Nothing else was cited — no 5.1.1(ix)
(KYC under an individual account), no 2.1 (demo).

## 2. What the code had (read on main, `9f8a724`)

- **Sign-in was already login-only.** Apple, Google or an e-mail code with no
  account returns `provider_not_found` and creates nothing
  (`AuthServiceInterface`, « a provider is never auto-created »).
- **Two in-app routes create a business**, both on the web too:
  - `/pro/register` — `ProRegisterScreen` (« Inscription Pro »: name, type,
    phone, address, then « S’inscrire avec Google / Apple » or by e-mail);
    reached from the login screen's « Créer un compte » (shown on
    `provider_not_found`) and « Pas encore de compte ? S’inscrire » (always).
  - `/pro/salons/nouveau` — `AddSalonScreen` (R6, a live Réseau account
    creates another salon); reached from the salon picker's « Ajouter un
    salon » row (handled by the dashboard and « Profil ») and the « Mon
    abonnement » card.
- **The web has both**: `/pro/inscription` and `/pro/salons/nouveau`.
- **The review notes sent the reviewer into registration**: « …please create a
  fresh account (below) and delete that one », « Créer un compte » → « Inscription
  Pro ».
- **Three sentences tell a person without an account to sign up**:
  `api_auth_service.dart` maps `provider_not_found` to « Aucun compte
  professionnel pour ce numéro. Inscrivez-vous. » (stale besides: sign-in is
  by e-mail, not number); `ProAuthProvider` and the mock say « Compte
  introuvable. Créez votre compte. ».
- **The consumer app** has no salon sign-up link. Not changed.

## 3. The decisions (owner, 2026-10-26)

Researched first — Google Play's Payments policy, and how peers do it
(sources in §10):
- **Google Play** allows « consumption-only » apps (« a user could log in when
  the app opens and access content paid for somewhere else ») and forbids
  in-app purchase or steering; it does not address in-app account creation.
- **Planity Pro** (closest competitor): « destinée aux responsables et employés
  des salons » who are Planity clients; salons join through an online form.
  The owner observed that the app shows « S’inscrire sur Planity Pro », which
  opens the browser on their website, and « Prendre rendez-vous en ligne »,
  which leads to the consumer app. Planity sells into **EU** storefronts,
  where Apple's StoreKit External Purchase Link Entitlement (DMA) allows
  linking out; the **US** storefront allows it since the April 2025 order.
  **Côte d’Ivoire is neither** — the most likely reason Planity can and we
  were refused.
- **Booksy Biz** keeps in-app sign-up by selling its subscription through
  Apple's in-app purchase. **Spotify, Netflix** are « reader apps », an
  exemption business software does not have.

| # | Question | Answer |
|---|---|---|
| Q1 | Login-only on iOS only, or both platforms? | **Both** — one behaviour, no iOS-only branch; revisit only if MyWeli ever sells through the stores (the Booksy model). |
| Q2 | « Ajouter un salon » in the app? | **Removed** — creating a business is what Apple named; Réseau owners add salons on the web. |
| Q3 | Team invitations (an employee joins an existing salon)? | **Kept** — nothing is bought, no business is created. |
| Q4 | What a sign-in with no account says | **A neutral sentence + the invitation hint** (§4.2). |
| Q5 | An « S’inscrire » link that opens myweli.com, as Planity does? | **Yes — the owner takes the risk** knowingly: the EU/US link-out rules do not cover CI, and reviewers have asked apps to remove registration links too. If App Review objects, removing the link is one widget (§8). |
| Q6 | « Prendre rendez-vous » for clients who installed the wrong app? | **Later**, to the MyWeli consumer app's store page once it is published — nothing outbound to booking in this resubmission. |

## 4. UX & flows — before → after (exact copy)

### 4.1 « Connexion » (`pro_login_screen.dart`)

| Where | Before | After |
|---|---|---|
| Bottom of the options step | « Pas encore de compte ? » / **« S’inscrire »** → `/pro/register` (in-app form) | « Pas encore de compte ? » / **« S’inscrire sur myweli.com »** → the system browser at `{siteBaseUrl}/pro/inscription` (`openExternalUrl`, external application) |
| `provider_not_found` (Apple, Google, e-mail code) | the server's sentence + button **« Créer un compte »** → `/pro/register` | the sentence of §4.2 · **no button** (the bottom link above stays where it is) |
| All invitations declined | « Compte introuvable. Créez votre compte. » | the sentence of §4.2 |

The link says where it goes (« sur myweli.com ») because it leaves the app —
a person should know a browser is about to open.

### 4.2 The no-account sentence

> « Aucun compte MyWeli Pro n’est associé à cette adresse. Si votre salon vous
> a invité, connectez-vous avec l’adresse qui a reçu l’invitation. »

One sentence, everywhere the app learns there is no account: the API
mapping of `provider_not_found`, `ProAuthProvider` after the last invitation
is declined, the mock. It sits in `InlineFeedback` (a live region — read by
VoiceOver/TalkBack). It never points to the web itself: the bottom link does
that, once, for everyone.

### 4.3 What leaves the app

- **`/pro/register`** and `ProRegisterScreen` (« Inscription Pro ») — deleted,
  with `registerWithGoogle/Apple/Email` (`ProAuthProvider`) and
  `registerProviderWithGoogle/Apple/Email` (`AuthServiceInterface`, its mock,
  its API service). The server's registration endpoints stay — the web uses
  them.
- **`/pro/salons/nouveau`** and `AddSalonScreen` — deleted, with
  `ProAuthProvider.addSalon` and `ProServiceInterface.addSalon` (mock, API).
  `POST /me/salons` stays — the web uses it.
- **The salon picker's « Ajouter un salon » row** and the dashboard's and
  « Profil »'s handling of its `'add'` result.
- **« Mon abonnement »'s « Ajouter un salon » card** (a live Réseau offer).
- **Nothing else changes**: the salon picker and switching, onboarding (it
  configures a salon that already exists), invitations, KYC, « Mon
  abonnement »'s state.

### 4.4 Flows

- **A new salon.** Opens MyWeli Pro → « S’inscrire sur myweli.com » → the
  browser, `/pro/inscription` → signs up there → back in the app, signs in
  with the same Apple, Google or e-mail → lands on « Accueil » with its
  onboarding checklist, as a web-created salon always did.
- **An invited employee.** Signs in with the invited address → the
  « Invitations » step → joins. Unchanged.
- **Someone with no account and no invitation.** Signs in → §4.2's sentence.
- **A Réseau owner adding a salon.** On the web (`/pro/salons/nouveau`); the
  new salon appears in the app's salon picker at the next refresh.

### 4.5 States & edge cases

- **No browser / launch failure**: `openExternalUrl` shows « Impossible
  d’ouvrir le lien. » (its existing behaviour).
- **Offline**: the browser shows its own offline page; the app is unchanged.
- **Old builds** (TestFlight, Android internal) keep the in-app form; the
  server endpoints are unchanged, so they keep working.
- **Accessibility**: the link is the existing `AuthSwitchPrompt` (≥ 48 dp,
  200 % text); the sentence is in an existing live region.

## 5. Architecture

App only — models, services, providers, screens. No endpoint, contract,
migration or web change: the web already registers salons and adds them. The
URL is `AppConfig.siteBaseUrl` + `/pro/inscription` (a getter, like the legal
links), opened by `openExternalUrl`.

## 6. Security & authz

Nothing new trusted or exposed: the app loses two write paths; the server
keeps refusing what it refused. The demo account's lock on salon creation
stays (server).

## 7. Testing — red first

- **Source pins** (`pro_login_only_test.dart`, on `lib/`): no route
  `/pro/register` or `/pro/salons/nouveau` in `pro_router.dart`; the two
  screen files gone; no `registerProviderWith…`, `registerWith…` or
  `addSalon(` anywhere in `lib/`; none of « Créer un compte », « Inscription
  Pro », « S’inscrire avec », « Ajouter un salon », « Inscrivez-vous »,
  « Créez votre compte » in the Pro surfaces (the consumer app's own
  registration keeps its copy).
- **Widget**: the login's « S’inscrire sur myweli.com » opens
  `https://myweli.com/pro/inscription` in an external application (a fake
  `url_launcher` platform) and pushes no route; `provider_not_found` shows
  §4.2's sentence and no « Créer un compte »; the salon picker shows no « Ajouter
  un salon » row even for an account that may add one; « Mon abonnement » on
  a live Réseau offer shows no add card.
- **Unit**: `provider_not_found` maps to §4.2's sentence (API); the mock says
  the same.
- **Cross-surface**: `web/app/pro/inscription/page.tsx` exists — the link's
  destination is a real page.
- Tests that built accounts through `register…` or a second salon through
  `addSalon` seed them instead (the mock's data), so the behaviours they
  prove still hold.
- **Mutations** on committed work; the suite; goldens on Linux.

## 8. Rollout

- **The resubmission**: a new build of **0.0.1** (decision 1), after the
  device checks (B0.2) — which gain « S’inscrire sur myweli.com opens the
  browser at the sign-up; a salon created there signs in to the app ».
- **Review notes** (app-store-forms §8): no « create a fresh account »; the app
  serves salons that have a MyWeli account, created at myweli.com; to test
  deletion end to end, create an account there, sign in, then Profil →
  « Supprimer mon compte ».
- **The Resolution Center reply** (drafted in app-store-forms, the owner
  sends it): what was removed, and — said plainly, not hidden — the link to
  the website.
- **If App Review objects to the link**: remove the `AuthSwitchPrompt` (one
  widget, one test line) and resubmit; the rest of this slice stands.
- **Later** (Q6): « Prendre rendez-vous » → the consumer app's store page, once
  it is published.

## 9. Definition of done

Pins and widget tests red first, then green; mutations red; `flutter analyze`
0; the suite; goldens unchanged or reviewed; PRD FR-PRO-AUTH-001, BACKLOG
B0.11, app-store-forms (review notes, §2, the Resolution Center reply), the
related specs and a roadmap entry updated.

## 10. Sources (read 2026-10-26)

- [Apple Developer Forums — 3.1.1 « registration for businesses » rejections](https://developer.apple.com/forums/thread/131193), [another](https://developer.apple.com/forums/thread/671027), [a WebView app](https://developer.apple.com/forums/thread/684850)
- [Google Play — Understanding the Payments policy](https://support.google.com/googleplay/android-developer/answer/10281818?hl=en)
- [Planity Pro on the App Store](https://apps.apple.com/fr/app/id1192719904) · [Booksy Biz on the App Store](https://apps.apple.com/app/id725335996) · [Fresha help center](https://www.fresha.com/help-center/academy/launch-your-workspace/getting-started/lessons/100243)
- [StoreKit External Purchase Link (EU) — 2024 terms](https://mjtsai.com/blog/2024/08/08/) · [The US storefront after the April 2025 order](https://www.gsmarena.com/apple_banned_from_monetizing_and_restricting_external_payment_links_in_apps_in_the_us-news-67609.php)
