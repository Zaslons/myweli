# MyWeli Pro on Android signs salons up again; iOS stays sign-in only

| | |
|---|---|
| **Status** | **Draft, awaiting the owner's answers (§11).** Nothing is built before sign-off. Reviewed twice by independent readers on 2026-11-12, and every finding is folded in: six readers (code, architecture, backend, design system, store documents, completeness) found 61, then three found 26 on the revision |
| **Owner** | Sadreddine Daher |
| **Last updated** | 2026-11-12 |
| **PRD ref / phase** | FR-PRO-AUTH-001 (Pro sign-in and sign-up) · V1 |
| **BACKLOG** | B0.10 (the Android release); this spec's decisions are 116 and up (§11) |
| **Related** | [pro-app-login-only.md](pro-app-login-only.md) (decisions 38–43: sign-in only, both platforms) · [app-review-round-2.md](app-review-round-2.md) (decision 71: the website link went) · [android-play-release.md](android-play-release.md) (decisions 110–115: the release order this slice enters) · [play-store-forms.md](play-store-forms.md) (the listing, Data safety, the closed test) · [app-store-forms.md](app-store-forms.md) §11.3 (the iOS pre-upload read) · [pro-companion-path.md](pro-companion-path.md) (the app never sells, on either platform) · [web-pro-registration.md](web-pro-registration.md) (the website's sign-up) · [pro-auth-social.md](pro-auth-social.md) · [team-access-r3-app.md](team-access-r3-app.md) (the invitations bridge) |
| **Skills checked** | myweli-dev-guardrails · myweli-verification-guardrails (myweli-backend-guardrails: no backend change, §3) |

**The decision behind this spec (2026-11-12, the owner):** « Bring sign-up
back on Android now ». It came after Google Play's payments policy was read.
That policy does not forbid creating a free account in the app; it forbids
sign-up flows that lead to a payment outside Google Play (§6.2).

**Why iOS stays as it is.** Apple refused in-app business registration on
build 587 (19 October), then refused the sign-in's link to the website's
registration on build 698 (3 November), both under guideline 3.1.1. So iOS
**behaves** exactly as Apple approved. Its binary is checked to contain no
sign-up (§8.3).

---

## 1. Goal & scope

**What.** On the Android Pro app, a person with no MyWeli Pro account can
create one without leaving the app, and with it a draft salon. They then
follow the existing « Configurer mon profil » checklist to go live. The
backend has offered this all along (`POST /auth/provider/register`); only the
app stopped calling it (#711, `54b02dac`, 2026-10-26).

**Why now.**

1. **The closed test.** It needs 12 testers opted in for 14 days in a row, and
   the owner chose paid testers (2026-11-12). Under sign-in only, each tester
   would need an invitation from a live test salon:
   - e-mails known in advance;
   - invitations that expire after 7 days;
   - Business seats, which cap a salon at 14 invitees.

   Self sign-up removes all of that (§9.3).
2. **The store.** A salon that finds MyWeli Pro on Play today meets a dead end:
   « Aucun compte MyWeli Pro… ».

**In scope (Android only):**

- an entry from the sign-in screen;
- the sign-up screen;
- the account-creation calls and the session they return;
- the copy, tests, guards and binary reads;
- the Play texts and declarations that become false;
- the decisions this reverses, recorded.

**Out of scope:**

- **« Ajouter un salon »**, a second salon (decision 39). It stays on the
  website (R1).
- **Apple sign-up.** Android never showed the Apple button.
- **Any backend, contract or deploy change** (§3).
- **The website's sign-up**, beyond naming its follow-ups (R9).
- **Decision 108's foreign-salon guard**, which is server-side (Q6).

**What iOS gets.** No new behaviour. The shared start-up, router, salon gate,
sign-in screen, provider and service gain plug points and methods that only
Android uses (§5.2). So the first iOS build that carries them gets a smoke
pass (§8.4); question Q2 decides which build that is.

**How it fits the architecture.** It is a hand port of the deleted screen, not
a revert (§5.5):

- the service methods go back behind `AuthServiceInterface`, with a mock;
- state goes through `ProAuthProvider`'s session path (`_setProvider`);
- the route is `go_router`;
- every Android-only file sits behind an import fence (§5.1).

---

## 2. UX & flows

### 2.1 The principle: the salon first, the identity last, and a sign-in check before anything is created

This is the website's order (`/pro/inscription`) and the deleted app screen's:
salon details first, then « Continuer avec Google » or an e-mail code.

**The new rule.** Neither the website nor the deleted screen had it: before
creating anything, the app runs a **sign-in** with that same identity, the
same Google token or the same code.

| The check answers | What happens |
|---|---|
| **200** | An account exists: they are signed in. The salon they typed is not created, and the screen says so (S3) |
| **202** | They have pending invitations: the invitations show **on the sign-up screen**, with the fields kept. They can join, refuse, or « Créer plutôt mon propre salon » (S4) |
| **404 `provider_not_found`** | The account is created with the same proof |

**Why.** `register` has no invitation bridge (`register.dart` never reads
`TeamService`). Without the check, an invited employee who chose sign-up would
own a new, empty salon and never see the invitation. The backend allows one
proof for both calls:

- **The e-mail code.** A verify with a correct code but no account answers
  404 without touching the code's attempts or expiry, and register consumes
  the code only when it inserts the account
  (`postgres_provider_auth_repository.dart:184-202, :236-284`).
- **The Google token.** An ID token has no replay cache; the invitations
  bridge already presents one twice.

**Why the identity last.** An e-mail code lives 5 minutes from its send, and a
404 verify does not extend it (`postgres_provider_auth_repository.dart:30`).
Asking for the code after the form keeps it fresh. It also allows a permanent,
discoverable entry (E1), and keeps the app and the website on one flow.

**What the order costs (Q1 weighs it against the alternatives):**

- **Typing for nothing.** Someone who already has an account, or has an
  invitation, types the salon fields before learning it.
- **Google twice.** Coming from « Aucun compte » after Google (E2), the person
  meets Google's sheet a second time. Coming after an e-mail code (E3), the
  code they hold is carried, so no second e-mail is needed while it is
  valid (§2.2).

**Residual risks, named:**

- **An invited employee on the wrong address.** If they sign up with an
  address that was not invited, they create a salon. The sentence's
  invitation hint sits right above the action, which is all the app can do.
  The website has the same limit.
- **A former team member with nothing pending.** Their identity still has an
  account, so neither the app nor the website can create a salon with it
  (register answers `provider_exists`). They use another address (S3b).

### 2.2 Entry points (Android only)

On Android, the sign-in screen gets one block at its bottom, supplied by the
Android code. Its sentence is an `InlineFeedback` with `kind: SnackKind.info`,
a live region, so TalkBack announces it.

| # | When | The block shows |
|---|---|---|
| E1 | Options step, with no `provider_not_found` in hand | « Pas encore de compte ? » and a text button « Créer le compte de mon salon » |
| E2 | Options step, after « Continuer avec Google » answered `provider_not_found` | `kNoProAccountMessage` as information, then « Créer le compte de mon salon ». It is scrolled into view, since at 200% text it lands below the fold |
| E3 | Code step, after the code answered `provider_not_found` | the same as E2. The e-mail **and the code**, both just proven, cross into the sign-up (§2.4 row 8) |

**What does not change:**

- **The sentence stays word for word.** On Android, the block shows it, so the
  sign-in's own red `InlineFeedback` does not repeat it. Every other fault
  stays in that red `InlineFeedback`.
- **After the last « Refuser »,** the screen falls back to the options step,
  which shows E2 or E1.
- **On iOS the block does not exist.** The sentence keeps its red style and its
  place. The action lists of app-review-round-2 §4.2 are unchanged.

### 2.3 The happy paths

**Google**, from E1, about 5 taps plus typing:

1. « Créer le compte de mon salon ».
2. The salon fields (§2.4), including one tap on a type chip.
3. « Continuer avec Google », then the account in Google's sheet.
4. The check (404), then the account is created (201).
5. « Accueil » (R5).

**E-mail**, from E1:

1. « Créer le compte de mon salon ».
2. The salon fields.
3. « Votre e-mail », then « Continuer avec e-mail ».
4. The code step, on the same screen: « Code à 6 chiffres », then « Créer mon
   compte ».
5. The check (verify 404), then register (201).
6. « Accueil ».

**E-mail**, from E3:

1. The sign-up opens with « Compte : {e-mail} ».
2. The salon fields.
3. « Créer mon compte »: the check, then register, with the carried code.
4. If that code is no longer valid (`otp_expired`, `otp_none`,
   `otp_invalid`), the identity section switches to the e-mail path, with the
   address filled in. It says « Ce code n’est plus valable. Recevez-en un
   nouveau. »

**On « Accueil »:**

- « Bienvenue, {salon} », then the « Configurer mon profil » card (owners).
- **No snackbar.** On a first visit, « Accueil » opens the notifications
  permission sheet (`_maybeAskPush`). A snackbar under that sheet is hidden by
  its scrim and pruned from TalkBack (SYSTEM §15).

### 2.4 The sign-up screen (`/pro/register`)

One scrolling form: the website's fields, with the deleted app screen's
validation rules.

| Order | Element | Behaviour |
|---|---|---|
| 1 | App bar: `ScreenTitle('Créer mon compte')` | heading level 1 (SYSTEM §13.4). Back pops to the sign-in as it was, and drops any invitations this screen surfaced |
| 2 | Section heading « Votre salon » | heading level 2 |
| 3 | « Nom de l’entreprise » | required: `Validators.requiredField('le nom de l’entreprise')` gives « Indiquez le nom de l’entreprise. ». At most **120 code points** after trimming, the server's measure (`register.dart:54-58` counts runes). A validator enforces it, not a `maxLength` counter (which counts something else): « 120 caractères au plus. ». Hint: « Ex : Salon de Beauté Marie » |
| 4 | « Type d’entreprise » | six `AppChip.choice`: Salon de beauté · Barbier · Spa · Institut de manucure · Massage · Autre. Required, **no default** (the deleted screen's rule): the type drives the checklist, staff being optional for « Autre » and RCCM required unless « Autre ». Its fault, « Choisissez le type d’entreprise. », is an `InlineFeedback` under the chips. The group is wrapped in `Focus(FocusNode(skipTraversal: true))`, so `focusFirstError` reaches it, as the operator chips of `deposit_settings_screen.dart` do. A chip label never wraps, so the 200% test checks for silent truncation (§8.2) |
| 5 | « Téléphone du salon » | `PhoneNumberField` (Côte d'Ivoire by default) + `Validators.phoneNumber`, the server's rule and the app's sentences. Helper: « Le numéro que vos clients appellent. » |
| 6 | « Adresse » | required, two lines: « Indiquez l’adresse de l’entreprise. ». Hint: « Rue, quartier, repère » |
| 7 | « Commune (optionnel) » | `showCommunePicker` (returns the `areaId`); optional, as on the website and the deleted screen (R2). Going live needs one, and « Configurer mon profil » asks for it then |
| 8 | Section heading « Votre identité de connexion », with the sub-line « Elle vous servira à vous connecter à votre espace pro. » | heading level 2; the website's words. **From E3**, the section shows only « Compte : {e-mail} », « Créer mon compte » and a text button « Utiliser une autre adresse », which opens the standard section below |
| 9 | Consent: `LegalConsentText(lead: 'En créant votre compte professionnel')` | « En créant votre compte professionnel, vous acceptez nos Conditions d’utilisation et notre Politique de confidentialité. », both linked to the site (Q5). Passive, no checkbox. It sits **above the first button that can create the account** |
| 10 | « Continuer avec Google » | secondary `AppButton` with the G logo, as on the sign-in. It validates rows 3–7 first, focusing the first fault, and only then opens Google's sheet |
| 11 | « ou », « Votre e-mail », « Continuer avec e-mail » | the sign-in's controls and labels. The button validates rows 3–7 and the e-mail first |
| 12 | Code step, on this screen, replacing row 11 | « Entrez le code reçu par e-mail à {e-mail}. », « Code à 6 chiffres » (and the dev hint off-prod), « Créer mon compte » (primary), « Renvoyer le code (60s) », « Changer d’e-mail ». The sign-in's code step, cooldown included |
| 13 | `InlineFeedback(formFault)` | a live region for outcomes that belong to no field |

Every button is disabled **only** while its request runs (SYSTEM §14 rule 5).
Faults are checked on the action, re-checked on change once shown, and placed
under their field (§14).

### 2.5 States and branches

The sign-up's outcomes and faults stay on the sign-up screen. Toward the
sign-in's state, the provider behaves in two ways:

- **On success, invitation or sign-in,** it clears the sign-in's `error` and
  `errorCode`, as every sign-in does at its start. A later sign-out never
  brings back a stale « Aucun compte ».
- **On failure,** it leaves them untouched, so Back shows the sign-in as it
  was, E2 and E3 included.

| # | State | What the person sees |
|---|---|---|
| S1 | A request runs | that button's spinner; the fields stay visible |
| S2 | Check 404, register **201** | « Accueil » (§2.3). The session goes through `_setProvider` (which resets ProSalonScope and AccountScope, B9.14), then push sync, `refreshMembership` and `loadMySalons`: a sign-in's success steps |
| S3 | Check **200**: the account exists | in place of the form: an info `InlineFeedback`, « Vous aviez déjà un compte MyWeli Pro : vous êtes connecté(e). Le salon saisi n’a pas été créé. », and a « Continuer » button. It lands where a sign-in lands (owner → « Accueil », staff → their shell, a rejoin → invitations), through one shared helper (§5.2) |
| S3b | Check 200, then the membership refresh finds **no membership left and nothing pending** (a former team member) | The provider signs them out, as it does after any sign-in, and returns to the sign-in. The sign-in now picks up the « accès retiré » notice even though it was mounted under the sign-up (§5.2), and shows `RevokedAccessBanner` (« Votre accès à {salon} a été retiré. »). As §2.1 says, that identity cannot create a salon |
| S4 | Check **202**: invitations | on the sign-up screen: « Vous êtes invité(e) », « Cette adresse a reçu une invitation. Rejoignez l’équipe, ou créez plutôt votre propre salon. », the `InvitationCard`s (« Rejoindre » / « Refuser »), and a text button « Créer plutôt mon propre salon ». Each choice behaves as follows: **Rejoindre** accepts with the retained proof, exactly as on the sign-in, and lands as S3 does. **Refuser** removes the card; when none is left, the form comes back as it was. **Créer plutôt mon propre salon** creates the account with the same proof, and the invitations stay pending |
| S5 | `400 invalid_phone` | under « Téléphone du salon »: « Saisissez un numéro de téléphone valide. » (the app's sentence) |
| S6 | `400 invalid_area` | under « Commune (optionnel) »: « Choisissez une commune dans la liste. » |
| S7 | Register's `400 invalid_input` | form level: « Vérifiez les informations du salon, puis réessayez. » The service says which call refused (the check or register), so this is never confused with the check's `invalid_input`, a malformed code, which is S9's « Code incorrect. » |
| S8 | `409 provider_exists` | form level: « Un compte existe déjà pour cette identité. Connectez-vous. » and « Se connecter », which pops to the sign-in. This happens only when another device created the account between the check and register |
| S9 | Code faults (`otp_invalid`, `otp_expired`, `otp_none`, `otp_locked`, or the check's `invalid_input`) | under « Code à 6 chiffres », the sign-in's sentences (`codeFieldFault`), and « Renvoyer le code ». **On the carried code (E3)**, the sentence of §2.3 replaces them |
| S10 | `invalid_email` | under « Votre e-mail », when it is on screen. `otp_resend_limit` is form level, « Trop de demandes de code. Réessayez plus tard. », as on the sign-in |
| S11 | Anything else (`token_rejected`, `invalid_token`, `auth_method_disabled`, 429, 503, a 500) | the sign-in's own sentence for that code (SYSTEM §17: « a refusal whose code has its own sentence keeps it »), else `kGenericErrorMessage` |
| S12 | A failure **after** the account was created: a lost 201 (timeout), or a 500 from salon provisioning | **Retrying recovers it.** On Google, the check answers 200: S3. On e-mail, the consumed code gives S9 (`otp_none`); a new code, then the check answers 200: S3. **The cost:** the server's self-heal creates the salon without the commune, so « Configurer mon profil » asks for it again. Two truly simultaneous creates give a 500 (S11), then S3 on retry |
| S13 | No network | « Pas de connexion. Réessayez. »; the fields are kept |
| S14 | Google's sheet closed | nothing; the form stays as it was |
| S15 | `/pro/register` while signed in (a stale push, a `returnTo`) | redirected to `/pro/dashboard` |

**Edge cases.**

- **A killed app.** On a low-end phone, a person who leaves to read the code
  can return to a restarted app and an empty form. The sign-in's code step has
  the same limit today. Restoring state is out of scope.
- **Long strings.** Names up to 120 code points and the sentences wrap. Chip
  labels do not wrap, so they are checked for silent truncation at 200% text.
- **A salon outside Côte d'Ivoire** can sign up and, as on the website today,
  go live by choosing any Abidjan commune. Nothing stops it (§6.5, Q6).
- **Double taps** are blocked by S1.
- **Low-end Android:** no images, animation or lists on this screen.

### 2.6 Copy

**(a) Strings that exist only in the Android-only code.** Only these become
source and binary witnesses (§8.1 P2, P13), each proven absent from the iOS
program's source before it joins (a vacuity check):

| Group | Strings |
|---|---|
| Entry | « Pas encore de compte ? » (already on the iOS list) · « Créer le compte de mon salon » |
| Screen, headings | « Créer mon compte » · « Votre identité de connexion » · « Elle vous servira à vous connecter à votre espace pro. » · « Utiliser une autre adresse » |
| Fields, hints | « Nom de l’entreprise » · « Type d’entreprise » · « Ex : Salon de Beauté Marie » · « Le numéro que vos clients appellent. » · « Rue, quartier, repère » · « 120 caractères au plus. » |
| Outcomes | « Vous aviez déjà un compte MyWeli Pro » · « Cette adresse a reçu une invitation. » · « Créer plutôt mon propre salon » · « Ce code n’est plus valable. » · « Vérifiez les informations du salon » · « Un compte existe déjà pour cette identité. » · « Choisissez une commune dans la liste. » |
| Consent | the lead « En créant votre compte professionnel » (it also sits in a doc comment of `legal_consent_text.dart`; source scans strip comments) |

`/pro/register` and `/auth/provider/register` are **binary witnesses only**.
The first lives in the fenced code. The second is the register call in the
shared `ApiAuthService` (§5.2), which is in the iOS program's source closure,
so its absence can only be shown in the binary.

**(b) Reused, already shipped on iOS, never witnesses:**

- « Votre salon », « Adresse », « Commune »;
- « Votre e-mail », « Continuer avec e-mail », « Continuer avec Google »,
  « Code à 6 chiffres », « Renvoyer le code », « Changer d’e-mail »,
  « Se connecter », « Continuer »;
- « Vous êtes invité(e) », the invitation cards' labels;
- `kNoProAccountMessage`, `kNoConnectionMessage`, `kGenericErrorMessage`;
- the sign-in's code, e-mail and phone sentences, and the
  `RevokedAccessBanner` sentence;
- « Indiquez … » (`Validators.requiredField`), « Choisissez le type
  d’entreprise. ».

**Rules this copy keeps:**

- **No « inscri ».** That keeps `pro_site_links_test`'s ban and the IPA lists
  free of exceptions.
- **Nothing about money:** no price, offer, trial, « gratuit » or « offert »
  (R4; pro-companion-path §2.1).
- **« vous »**, `’` apostrophes, and plain spaces before « : ? » (SYSTEM
  §17.1).

### 2.7 What happens after (unchanged screens)

All of this exists today for salons created on the website:

- the « Configurer mon profil » card;
- the 8-step checklist;
- « Mettre mon profil en ligne ».

**Two facts the person meets:**

- **Team invitations wait for go-live:** « Vous pourrez inviter votre équipe
  une fois votre salon en ligne. »
- **The first publish starts the 90-day trial,** silently. The success
  message is only « 🎉 Votre profil est en ligne ! ».

Neither changes (R4, §6.2).

---

## 3. API & contract: no change

| Call | When | Contract |
|---|---|---|
| `POST /auth/provider/google` | the check, on the Google path | unchanged: 200 / 202 / 404 `provider_not_found` |
| `POST /auth/provider/email/otp/request`, `…/verify` | the code, then the check, on the e-mail path | unchanged. Verify's 404 leaves the code usable |
| `POST /auth/provider/register` | after a 404 check, or « Créer plutôt mon propre salon » | unchanged: `businessName` (≤120 code points), `businessType` (salon, barber, spa, nailSalon, massage, other), `phoneNumber` (E.164; 10 digits after +225), `address?`, `areaId?`, plus **one** identity (`idToken`, or `email` + `code`). `201` returns a flat `ProviderSession` and provisions a draft salon. Field faults are checked before the identity, so they leave the code usable |

Register has had no commit since `54b02dac`; the website calls it through its
BFF. **Not touched:** `docs/api/openapi.yaml`, `backend/`, deploys.

**Requests per sign-up:**

- **Google:** 2 (the check, then register).
- **E-mail:** 3 (request, verify, register), or 2 from E3 while the carried
  code is valid.
- **The commune picker:** one `/localities` read when it opens.

**Recorded for R9, not changed here:**

- **One proof.** The route takes the first proof present rather than
  enforcing exactly one; the app sends one.
- **Two answers OpenAPI omits:** `503 auth_not_configured` and
  `400 invalid_token`.

---

## 4. Data model: no change

**What one sign-up writes in production** (`salon_provisioning_service.dart:85-131`):

- the account;
- a **draft** salon (name, category from the type, phone, WhatsApp = the phone,
  address);
- an OWNER membership.

**The market facts.** They come from the area when one is chosen. Otherwise
the salon is stamped Abidjan / CI / Africa/Abidjan / XOF.

**What it does not write:**

- no subscription row (the trial starts at the first publish);
- no welcome e-mail;
- no site rebuild.

**Deleting the account** (Profil → « Supprimer mon compte »):

- **What blocks it:** a future booking; and the demo account is locked.
- **The salons it owns** are unpublished, keep their name and history, and
  lose their contacts.
- **The identity** is hard-deleted, so a later sign-in answers
  `provider_not_found`.

---

## 5. Architecture

### 5.1 How the iOS binary stays free of sign-up: an Android entry file and an import fence

**The problem.** Both platforms build `lib/main_pro.dart` today. The release
script chooses the entry by flavour, not platform (`tool/release_build.sh:162-163`).

**Why not a runtime check.** It would make sign-up unreachable on iOS, not
absent. The compiler treats `defaultTargetPlatform` as a constant in iOS
release builds, but nothing here has measured whether that removes a whole
screen and its strings. If it does not:

- the pre-upload read (app-store-forms §11.3) fails;
- the binary carries what Apple refused.

**Why not a compile-time define.** A plain `flutter test` could not reach the
Android branch, so its guards could not fire.

**The design: an import fence.**

- **The iOS entry.** `lib/main_pro.dart` stays the iOS entry. `runProApp`,
  `MyweliProApp`, `proAppProviders` and `_startPush` stay in it, so every test
  that reads its source keeps reading the real wiring.
- **The Android entry.** New `lib/main_pro_android.dart` is thin. It imports
  `import 'main_pro.dart' show runProApp;` plus the Android code, and its
  `main()` is `runProApp(extensions: proAndroidExtensionsFor(defaultTargetPlatform))`.
- **The fenced directory.** Everything Android-only lives in
  `lib/screens/provider/android/`. Under `lib/screens/`, the path-scoped
  guards (`failure_messages_pin_test`, `salon_time_pin_test`,
  `pro_reads_own_salon_test`, the motion pins of `design_system_pin_test`)
  already cover it. No guard there requires a file to be a screen.
- **The fence pin (P1).** `lib/main_pro.dart`'s closure contains no fenced
  file. Across `lib/`, only `lib/main_pro_android.dart` and the fenced files
  import the directory.
- **The release script picks the entry by platform:** `pro` + `android` →
  `lib/main_pro_android.dart`; `pro` + `ios` → `lib/main_pro.dart`. Store
  builds come only from this script, never from an Xcode archive made by hand
  (§5.6).
- **Defence in depth.** `proAndroidExtensionsFor` returns `null` unless the
  platform is Android. A hand-made iOS build from the wrong file would
  therefore show nothing. Its strings would remain, and the iOS read catches
  them.

### 5.2 What the shared code gains

**Rules for the shared files:**

- no sign-up sentence;
- no `/pro/register`;
- they carry machine codes, never sign-up copy;
- the mock's messages reuse the shared table, so no « Inscri… » comes back
  with the port.

| File | Change |
|---|---|
| `lib/main_pro.dart` | `main()` becomes `runProApp()`. `runProApp({ProAppExtensions? extensions})` holds today's body and calls `ProRouter.install(extensions)` before anything reads the router (`ProAuthProvider()`, `_startPush`). It hands the **installed launch paths** to `ProSalonGate` as a parameter, the way `_startPush` already hands them to `landedPushHandler` |
| new `lib/core/pro_app_extensions.dart` | `ProAppExtensions { List<RouteBase> routes; Set<String> launchPaths; ProLoginExtras? login; }`. `ProLoginExtras` holds one builder for §2.2's block: `Widget Function(BuildContext, {required bool noAccount, String? email, String? code})`. No French text, no path literal |
| `lib/core/router/pro_router.dart` | `ProRouter.build(ProAppExtensions?)` is pure; tests use it with their own launch set and never touch the global. `ProRouter.install(ext)` is production-only and throws a `StateError` if `router` was already read. `router` and `launchPaths` are the installed ones, defaulting to today's shape. The class doc's « There is no sign-up screen » becomes « none on iOS » |
| `lib/widgets/provider/pro_salon_gate.dart` | `exemptPaths` today is `static const {...ProRouter.launchPaths, '/pro/invitations'}`, which stops compiling once that set is not const. It becomes a constructor parameter (the launch paths) plus `/pro/invitations`. The reason it matters: right after a 201 the session is live while the membership loads, and the gate would otherwise replace the page at `/pro/register` |
| `lib/screens/provider/auth/pro_login_screen.dart` | **The block.** It reads `context.read<ProLoginExtras?>()`, with the nullable type, so an absent provider gives `null` rather than throwing. With no extras (iOS, and every existing test), it renders today's screen exactly. With them, it shows §2.2's block, and when the block shows `kNoProAccountMessage` its own feedback does not repeat it. **The landing helper.** `_finish`'s rule moves into a shared `proLandingRoute(auth, returnTo)`, used by the sign-in and by S3. **The revoked notice.** It picks up a pending « accès retiré » notice when one arrives while it is mounted under another page (S3b). Today the notice reaches it only in `initState` or after its own sign-ins, which already consume it, so on iOS this changes nothing |
| new `lib/models/provider_sign_up_result.dart`, `lib/models/pro_sign_up_fields.dart` | **The outcomes:** created · signedIn · invited(invitations, proof) · failure(code, message, stage: check or register). **The fields:** `businessName`, `businessType`, `phoneNumber`, `address`, `areaId?` |
| `AuthServiceInterface`, `ApiAuthService` | Three methods: `signUpProviderWithGoogle(fields)` and `signUpProviderWithEmail(email, code, fields)` run the check, then register, with **one** proof; `registerProvider(InvitationProof proof, fields)` registers only (S4's « Créer plutôt mon propre salon »). In the API service, the Google method obtains its token with the sign-in's plugin arm, reported with `_reportSignInFailure`. It uses `return await` inside `try` (Dart 3.13, B13.1). `_messageFor` is **not changed** |
| `MockAuthService` (fidelity) | latency, the three check answers, `provider_exists`, `invalid_phone`, `invalid_area`, code faults, success. **A settable Google e-mail**: today the only mock Google identity has a seeded invitation and always answers 202, so tests and mock builds choose a no-account identity. **Its register creates the draft salon and OWNER membership**, so `getMyProvider` resolves after a mock sign-up |
| `lib/providers/pro_auth_provider.dart` | `signUpSalonWithGoogle(fields)`, `signUpSalonWithEmail(email, code, fields)` and `createOwnSalonInstead(fields)`, which uses the retained invitation proof. **Created or signed in:** clear `error` and `errorCode`, then `_setProvider` → `_syncPush` → `refreshMembership` → `loadMySalons`. Return « signed in » only if `_provider != null` afterwards, which is S3b's distinction. **Invited:** clear `error` and `errorCode`, then hold the invitations and their proof exactly as the sign-in's bridge does. Accept, decline and « Retour » keep their meaning. **Failure:** returned to the screen; the sign-in's `error`, `errorCode` and `isLoading` are untouched |

**Why the account-creation methods can live in shared files.** Their only
callers are in the fenced directory. The iOS program never calls them, so the
compiler's whole-program tree shaking drops them. That is ordinary dead-code
removal, not platform folding, and it is **measured**:
`/auth/provider/register` is a binary witness (§8.3).

### 5.3 The fenced files (`lib/screens/provider/android/`)

- **`pro_android_extensions.dart`**: `proAndroidExtensionsFor(TargetPlatform)`.
  It returns `null` unless the platform is Android. Otherwise it supplies:
  - the `/pro/register` `GoRoute`, with S15's redirect, carrying the E3 e-mail
    and code as in-memory `extra`;
  - `/pro/register` as a launch path;
  - the block's builder.
- **`pro_sign_up_entry.dart`**: §2.2's block and its strings.
- **`pro_sign_up_screen.dart`**: §2.4's screen, its states, and its
  code-to-sentence table.

### 5.4 The path

`/pro/register` is the deleted app path, restored on Android. The website's
`/pro/inscription` is not used: it is an iOS witness, and
`pro_site_links_test` forbids it.

`/pro/register` is an Android launch path for two readers:

- **`ProSalonGate`** stands aside on it (§5.2).
- **A buffered notification tap** waits until the router has left it.

### 5.5 Why a hand port, not `git revert 54b02dac`

The deleted screen (`9f8a724a:mobile/lib/screens/provider/auth/pro_register_screen.dart`,
541 lines) is the starting point. It breaks five later rules:

1. It assigned `_provider` directly; #704 routes every account change through
   `_setProvider`.
2. It returned unawaited futures inside `try`, which is fatal under Dart 3.13.
3. Its title was a bare `Text`; `screen_title_guard_test` requires
   `ScreenTitle`.
4. It used `AuthSwitchPrompt`, deleted by #731.
5. It had no sign-in check.

A revert would also restore « S’inscrire sur myweli.com ».

### 5.6 Dev runs and the Xcode trap

- **Android with sign-up:** `flutter run --flavor pro -t
  lib/main_pro_android.dart`. Without `-t`, Android runs show no sign-up.
  `mobile/android/app/build.gradle.kts`'s comment, `mobile/scripts/run_pro.sh`
  and `docs/DEPLOYMENT.md` say so (§9.4).
- **Xcode builds the `FLUTTER_TARGET` of the last iOS `flutter` command**,
  written into the git-ignored `Generated.xcconfig`. §8.3's control build from
  the Android entry is therefore made in a private copy of the repo, never in
  the main checkout.

---

## 6. Security, privacy and store policy

### 6.1 Apple: iOS behaviour unchanged

- **The iOS binary** is built from `lib/main_pro.dart`. It is checked by the
  pre-upload read (§8.3): no sign-up string, no sign-up path. Its source
  closure does hold the shared account-creation methods, which nothing in it
  calls; tree shaking removes them, and the read measures that.
- **What Apple was told stays true.** The App Store texts and the review
  notes stand: « The app only signs in to existing salon accounts… It has no
  registration ».
- **The bans stand.** `app_review_notes_test`'s bans are unchanged.
- **Records that say « iOS and Android » get dated notes.** For example
  app-store-forms' « (iOS et Android) » and the 2026-10-26 reply. What was
  sent is not rewritten.

### 6.2 Google Play: the rule, and where the flow touches it

Google's Payments policy (help 9858738, §4, read 2026-11-12) forbids « in-app
user interface flows, including account creation or sign-up flows, that lead
users from an app to a payment method other than Google Play's billing system
as part of those flows ». In the Android flow:

- **No money on the flow's own screens.** No price, offer, plan, trial,
  « gratuit » or « offert » from E1 to « Accueil ». A ban list over the fenced
  directory pins it (P11).
- **Two links to the site, in the flow itself.** The consent line (§2.4 row
  9) opens `/cgu` and `/politique-confidentialite`, two of the five site pages
  the app already opens from « À propos ». Those pages keep the site's header
  (logo and « Mon compte »). Signed out, it leads to:
  - « Espace pro »;
  - `/professionnels`;
  - the website's sign-up;
  - `/pro/abonnement`, with « Choisir cette offre » and a monthly FCFA price.

  It is several taps, but it starts inside the sign-up flow that Play's
  sentence names. **Decision 80 covered only `/professionnels`,** which shows
  no amount, and only for Apple. This is new: **Q5**.
- **« Mon abonnement » is unchanged.** State only (tier, trial days left,
  dates, seats), with no button and no price. It is identical on iOS, which
  Apple approved.
- **The trial pushes are unchanged.** Facts with no call to action. « activez
  votre offre » must never appear in one, since pushes come through the app.
- **The subscription e-mails are outside the app,** which Google allows: « Outside
  of your app, you are free to communicate with your users about alternative
  purchase options » (help 10281818).
- **One risk accepted with the decision (R7).** A salon's path to a running
  90-day trial happens in the app: sign-up → publish → `startDefaultTrial`.
  Only payment happens elsewhere. Google's pages do not address this
  (UNVERIFIED how review treats it). The same behaviour shipped on iOS.

**Before step 7,** the owner re-reads both help pages in a browser. They were
read here through a summarizing fetch.

### 6.3 Account deletion (Play's requirement now clearly applies)

Help 13327111 applies « if your app allows users to create an account from
within your app ».

- **In the app: met.** Profil → « Supprimer mon compte », for every role.
- **On the web: weak for Pros.** `/suppression-compte` sends people to the
  consumer « Mon compte ». Decision 73 forbids that page from linking to
  `/pro/*`, because the app opens it. Today play-store-forms §4 and §0.1 still
  say it « couvre les comptes professionnels ».
- **Recommendation R8:** a Pro deletion page that the app never opens. It can
  lead to the Pro sign-in and Profil. It is a web slice before step 7, on the
  critical path (§9.1).
- **The name.** If the Play developer name is not « MyWeli », the page names
  « MyWeli Pro » (play-store-forms §7.3; the developer name is UNVERIFIED).

### 6.4 Sessions, secrets, abuse

- **Tokens:** stored by `_adoptProviderSession` in `flutter_secure_storage`,
  as for a sign-in.
- **The Google token** stays inside the service call that uses it.
- **The e-mail code** leaves memory nowhere. Typed on the sign-up, it stays in
  the screen. At E3, it crosses from the sign-in to the sign-up as GoRouter
  `extra`, in memory, never in a URL.
- **On 202** the proof is held by `ProAuthProvider`, exactly as the sign-in's
  bridge holds it today. It is dropped on accept, on the last decline, on
  « Retour », and when the sign-up is left.
- **None of it** is logged or stored. Sentry's scrubber already drops the
  user, breadcrumbs, request and extras.
- **The server stays the authority** on every field (§3).
- **Abuse surface: none new.** Register is public today through the website.
  The app calls it directly, so its rate-limit bucket is the device's public
  IP: 10 per minute on `/auth/*`, plus Cloudflare's 10 per 10 s. Whether
  carrier-grade NAT in Côte d'Ivoire puts many phones in one bucket is
  UNVERIFIED.
- **The e-mail budget.** E-mail sign-up shares the global budget of 60 code
  e-mails per hour with every consumer and Pro code (`EMAIL_BUDGET_COLD`).
  When it is spent, no mail goes out and the screen looks normal. The
  existing budget alerts watch it during the closed test.
- **Threat model (BACKEND.md §7):** no new endpoint or trust boundary. One
  row gains a note: « Android Pro calls register directly ».

### 6.5 Production rows nobody planned

**Who can create them:**

- **Paid testers** (§9.3, Q3).
- **Play's reviewers,** with their own Google account, on every review,
  production review included. They could even publish: the publish gate
  checks completeness, not KYC.
- **Play's pre-launch robot,** if it can pass a Google sign-in (UNVERIFIED).

**Recommendation (R6):**

- Play's sign-in details ask reviewers to use the demo account (§9.2).
- The watch for published salons runs through production review.
- Rows are purged only on the owner's word.

**Salons outside Côte d'Ivoire.** A salon anywhere can already sign up on the
website and go live with any of the 11 Abidjan areas: nothing in publishing
reads the country or where the pin is. A required commune would not change
that; « Près de moi » would even pick the nearest Abidjan area for a salon in
Dakar. The guard is decision 108's server-side spec, and Q6 asks when.

---

## 7. Performance

- **One route, two screens' worth of widgets and two models**, with no images
  or lists. That is plausibly tens of KB in the Android Dart snapshot,
  measured on the AAB at step 5 against the 30 MB budget (UNVERIFIED until
  then).
- **Cold start is unchanged:** the extensions are plain objects.
- **Requests:** 2 or 3 per sign-up (§3).

---

## 8. Testing plan

Every new or re-scoped guard is watched red once before it is trusted, and the
commit records how. Source scans strip comments before matching.

### 8.1 Pins that change: re-scoped, never deleted

| # | The test today | After | PR |
|---|---|---|---|
| P1 (new) | — | **The fence:** `lib/main_pro.dart`'s closure contains nothing under `lib/screens/provider/android/`, and only `lib/main_pro_android.dart` and the fenced files import it. `proClosure()` (`test/support/pro_closure.dart`, today hard-wired to `lib/main_pro.dart`) takes the entry as a parameter. **Red:** import a placeholder fenced file from `pro_router.dart` | 1 |
| P2 | `pro_login_only_test`, group « nothing in the app signs a business up » (lines 47–112: no route, no screen file, no `registerProviderWith…`/`registerWith…`/`addSalon(` call, the copy list, « Créer un compte »), over **all of `lib/`** | It scans **`lib/main_pro.dart`'s closure**. **The call regex** gains `signUp(Provider\|Salon)With(Google\|Email)`, `registerProvider\(` and `createOwnSalonInstead\(`. These may appear only in their defining shared files, and no other closure file calls them (red: call one from `pro_login_screen.dart`). **The copy list** gains §2.6 (a), after the vacuity check. `add_salon_screen.dart` and `auth_switch_prompt.dart` stay forbidden everywhere | 1 (scope), 2 (regex), 3 (copy) |
| P3 | `pro_login_only_test`, the closure-strings group (lines 114–153) and the widget group (156–end: each step's exact actions on android and iOS, `expectNoPrompt`) | Unchanged: they mount the sign-in with **no extras**, the iOS shape. They stay green untouched | — |
| P4 (new) | — | The sign-in **with** the extras: E1; E2 after a Google 404, the sentence an info live region scrolled into view; E3 after a code 404, with the e-mail and code carried; E1/E2 after the last « Refuser ». Also: Back from a failed sign-up still shows E2/E3; after a successful sign-up and a sign-out, E1 shows, not E2; S3b's banner shows | 3 |
| P5 (new) | — | `proAndroidExtensionsFor(TargetPlatform.iOS) == null`. For Android: non-null, with `/pro/register` in routes and launch paths. A plain `test()` with the platform passed in | 1 (iOS null), 3 (Android) |
| P6 | `pro_site_links_test` over `main_pro.dart`'s closure (`\binscri`, `/pro/inscription`, the five pages, the outbound inventory) | Unchanged, plus a run over `main_pro_android.dart`'s closure: the same bans; still only the five pages; `termsUrl`/`privacyUrl` also read by `legal_consent_text.dart` there | 3 |
| P7 | `pro_login_invitations_test` lines 99, 129 and 131 | Unchanged (no extras); a twin with the extras pins §2.2's block after the last decline | 3 |
| P8 | `social_signin_diagnosis_test`: 9 `_reportSignInFailure(` calls (1 definition, 4 typed arms, 4 catch-alls) / 4 / 4 / 4 | One Google plugin arm more: **11 / 5 / 5 / 5** | 2 |
| P9 | `release_build_test` (entry by flavour); its `flutter` stub logs nothing | `android pro` → `lib/main_pro_android.dart`, `ios pro` → `lib/main_pro.dart`. The stub is changed to log its arguments, so the target is observed | 1 |
| P10 | `route_literals_test` (the `main()` files equal its entries; pushed routes exist) | Gains `main_pro_android.dart` (PR 1). A table from `ProRouter.build(androidExtensions)` contains `/pro/register` (PR 3) | 1, 3 |
| P11 | `pro_subscription_no_pricing_test` (scans `lib/`; bans choosing or activating offers) | Plus a ban list over the fenced directory: gratuit, essai, offre, offert, FCFA, prix, tarif, abonnement, `/mois`, myweli.com (**red:** plant one). The comments that call any platform branch a defect are reworded to « no selling, on any platform ». The consent links come from a shared widget through `AppConfig`, so this pin does not see them; Q5 decides them | 3 |
| P12 | `play_store_forms_test`: the description equal to the App Store's (lines 102–117); the reviewer sign-in text ≤ 500 characters (lines 181–188); §6's pinned numbers (« les N jours d'essai gratuit », « valable N jours », « expire au bout de N jours », « N places, vous compris », « donc N invités au plus »); `onScreen()` reading only `pro_login_screen.dart` and `invitation_card.dart` | The description follows Q4, admitting at most one named difference. The sign-in text stays ≤ 500 under the new line. Each §6 number stays pinned while its text stays; text that goes is deleted with its pin, the pin watched red first. `onScreen()` reads every fenced file, plus `pro_onboarding_screen.dart` if « Mettre mon profil en ligne » is quoted | 4 |
| P13 | `app_review_notes_test` reads app-store-forms §11.3's lists through `scriptList()` | §11.3 gains `gone_android_signup`: §2.6 (a), `/pro/register` and `/auth/provider/register`. A test reads it and checks it does not overlap the witnesses. The expected-count row (« 14 phrases à 0, 6 témoins présents ») grows | 3 |
| P14 | `motion_test`, `content_width_test` and `default_status_bar_style_test` find every `lib/main*.dart` and require `ReduceMotionObserver`, `ContentWidthCap` and `DefaultStatusBarStyle(` in its own source | A root whose `main()` only calls another root's `runProApp` is checked through that root. Each test asserts the delegation (`import 'main_pro.dart' show runProApp` and a `runProApp(` call) | 1 |
| P15 | Source pins on `lib/main_pro.dart`: `pro_salon_not_loaded_test` (builder regex), `pro_cold_start_deep_link_test` (`isSignedIn`), `pro_salon_scope_booking_created_test` (`ProSalonScope.track` count), `route_literals_test:206` and `release_build_test:550-555` (`ProRouter.router`), `pro_reads_own_salon_test` | Unchanged, since the wiring stays in `main_pro.dart`. Each is run against PR 1 to see that it still finds what it pins | 1 |
| P16 | `pro_cold_start_deep_link_test` reads `ProRouter.launchPaths`; the gate's const set | The gate takes the launch paths as a parameter (PR 1). A new case: on `/pro/register`, a 201 with the salon still loading keeps the form, then lands on « Accueil » (PR 3) | 1, 3 |

### 8.2 New tests

- **Unit, the API service:**
  - For each method: the check then register, with the **same** proof.
  - The exact register body: one identity, the fields, and `areaId` omitted
    when null.
  - Outcomes: 200, 202 and 404 → the outcomes; each refusal keeps its `code`
    and its stage.
  - `registerProvider` sends the retained proof.
- **Unit, the provider:**
  - Created and signed in go through `_setProvider`: a
    `pro_account_scope_test` case where an old salon scope is reset by a
    sign-up.
  - Success clears `error` and `errorCode`.
  - A revoked former member returns signed out (S3b).
  - Invited holds the proof.
  - Failure leaves the sign-in's fields untouched.
  - « Créer plutôt mon propre salon » keeps the invitations pending.
- **Unit, the mock:** latency, each answer, the settable Google identity, and
  register's draft salon.
- **Widget, the sign-up screen**, ported from the deleted
  `pro_register_form_test` (664 lines):
  - Field faults: each under its field, with focus and scrolling to the
    first, including the chips when only the type is missing and the person
    has scrolled to the bottom.
  - The 120-code-point cap, with an emoji sequence at the limit.
  - No default type.
  - The consent sentence and its two links.
  - Fields validated before Google's sheet and before a code is sent.
  - The states: S2–S15, with S3, S3b and S4's three choices.
  - E3's carried code, valid then expired.
  - Back, which drops surfaced invitations.
- **Accessibility** (`auth_layout_test`'s harness): the sign-up screen and the
  Android sign-in, at 200% text, at 360, 375 and 390 dp:
  - every target ≥ 48 dp;
  - heading levels;
  - the block's sentence a live region;
  - no overflow;
  - `expectNoUndeclaredTruncation` (a faded chip label);
  - the chips announce « sélectionné ».
- **Goldens**, on Linux through `goldens.yml`:
  - `pro_sign_up_w360_x2`: empty, then with every fault;
  - `pro_sign_up_invited_w360_x2`: S4;
  - `pro_login_android_w360_x2` (E1) and `pro_login_android_not_found_w360_x2`
    (E2);
  - `pro_login_w360_x2` stays **byte-identical**, since it mounts no extras. A
    change there is a defect, not a re-baseline.

### 8.3 The binary reads

1. **iOS: absent.** The app-store-forms §11.3 read of `App.framework/App`
   (UTF-8, UTF-16LE, Latin-1), on the **signed IPA from `release_build.sh`**
   of the first iOS build that carries this change (Q2). Every
   `gone_android_signup` string counts 0, and the witnesses stay present.
   - **The rehearsal,** before PR 3 merges: an unsigned
     `flutter build ios --release --no-codesign --flavor pro -t lib/main_pro.dart`
     with the API defines.
   - **The control, watched red once:** the same rehearsal from
     `lib/main_pro_android.dart`, with the platform check bypassed, in a
     private copy of the repo (§5.6). It must fail.
   - **What is not a valid read:** a generic AOT snapshot. It is compiled
     without `--target-os ios`.
2. **Android: present, the positive control.** The same strings in the AAB's
   `lib/arm64-v8a/libapp.so`, each ≥ 1, at step 5 next to the TLS gate.
3. **What the two prove together:** tree shaking removed the shared
   account-creation methods from iOS, measured.

### 8.4 Device passes

**Android:** android-play-release §5 gains rows 11–16. They run on the
internal-track build installed from Play, on the Galaxy A73 (SM-A736B/DS,
Android 14) and on the oldest device available.

| # | Check | Observed by |
|---|---|---|
| 11 | Google sign-up, fresh account | the server log: `/auth/provider/google` 404, then `/auth/provider/register` 201, Dart user agent; « Accueil » |
| 12 | E-mail sign-up from E3 with the carried code; then one from E1 | verify 404, register 201, Dart user agent |
| 13 | Sign-up with an address that already has an account | S3, no new salon |
| 14 | No Apple button anywhere | screen |
| 15 | The fresh account: « Configurer mon profil » opens the checklist; « Mon abonnement » says « Pas encore d’offre active » | screen |
| 16 | Delete that fresh account end to end | Profil → « Supprimer mon compte »; the next sign-in answers `provider_not_found` |

These are real production rows. The owner names the test addresses before the
pass.

**iOS smoke pass,** on TestFlight, for the first iOS build that carries the
refactor:

- a cold start;
- Google, Apple and e-mail sign-in;
- the `provider_not_found` dead end unchanged, with no block;
- an invitation accepted from the sign-in;
- a notification tap from a cold start;
- sign-out.

---

## 9. Rollout

### 9.1 Order: before the AAB, in four PRs

**Before step 5.** The sign-up must merge before step 5 of android-play-release
§4 (the AAB). Otherwise the closed track promotes a build without it, and a
second build mid-test redoes the device pass.

**Step 3a.** The new step is labelled **3a**, so no step number moves:
decision 113 and play-store-forms cite steps 5, 7 and 9.

**The four PRs:**

| PR | What | Proof that nothing else moved |
|---|---|---|
| 1 | The fence with **null** extensions: `runProApp(extensions)`, `ProRouter.build`/`install`, the gate's launch-path parameter, the sign-in's empty slot, `proLandingRoute`, the revoked-notice pickup, `main_pro_android.dart`, the release script by platform; P1, P2 (scope), P5 (iOS), P9, P10 (entries), P14, P15, P16 (parameter) | **No behaviour change:** `pro_login_w360_x2` byte-identical, P3 green untouched, and a baseline iOS strings read |
| 2 | The service, provider and mock methods with their unit tests; P2 (regex), P8 | — |
| 3 | The fenced screens, the sign-in's block, the copy, goldens and accessibility; P2 (copy), P4–P7, P10, P11, P13, P16 (the 201 case); the iOS rehearsal and control | — |
| 4 | The documents and Play texts (§9.2, §9.4); P12 | — |

**Also before step 5:** the B13.3 package PRs (#772 lottie;
cached_network_image), if they are to ride in 0.0.2.

**Production** moves by PRs 1–4, the R8 web page, and Q5's choice if it
needs a web change.

**iOS:** Q2. Decision 111 asks only for the same **version**. The build number
is the commit count, and the version floors are per platform, so each store's
build is valid either way.

### 9.2 Play texts and declarations that change (play-store-forms)

| Where | Today | After |
|---|---|---|
| §1 description | « MyWeli Pro s’adresse aux salons qui ont déjà un compte MyWeli et à leur équipe. », equal to the App Store's (decision 113) | Q4 |
| §2 sign-in details for reviewers (English, ≤ 500 characters, 463 today) | the demo account | + an English line within the limit, for example « Please use this demo account; do not create a salon. », shortening another line if needed (R6) |
| §4 Data safety, account creation | not stated in §4 | stated: the methods, « dans l'app (Android) et sur le Web ». §0.1, the dated record of 2026-10-28, gets a note, not a rewrite |
| §4 « Numéro de téléphone » | Facultatif | **Obligatoire**; purposes + « Gestion du compte » |
| §4 « Adresse » | Facultatif | **Obligatoire** (the form requires it) |
| §4 « the three tell the same story » | | names the one legitimate difference with the App Store label |
| §4, §0.1, §7.3, the deletion URL | `/suppression-compte`, « couvre les comptes professionnels » | per R8 |
| §6 point 3; §6.1, the salons bullet and « Pas de testeurs achetés »; §6.2 step 5 (the test salon, its seats); §6.3 (« créez le compte de votre salon sur https://myweli.com/pro/inscription »); §6.5 the guide | the website sign-up and invitations | sign-up in the app. Paid testers recorded (decision 117); the test salon optional (decision 60 amended). Real salons keep « les 90 jours d'essai gratuit » (decision 62 stands). Q3's rule in a **separate paragraph for paid testers**. Every quoted label is on screen (P12) |

Data safety must be right from the closed test onward, so these edits are
typed at step 7.

### 9.3 The closed test with paid testers

- **Capacity:** no longer bound by 14 invitees, e-mails known in advance, or
  7-day expiries.
- **Countries:** decision 114's « Côte d'Ivoire plus the testers' countries »
  needs the service's countries, which are UNVERIFIED (ask Testers Community,
  already on the owner's list). The testers' paragraph says the commune may
  stay empty.
- **Production rows.** Each tester creates a real draft salon. The marker is
  Testers Community's e-mail list. After the test, salons stay as unpublished
  drafts; any purge or suspension asks the owner first.
- **Publishing:** Q3.
- **E-mail budget:** 60 per hour, shared (§6.4).

### 9.4 Documents to correct (dated notes, PR 4)

- **BACKLOG:**
  - decisions 116–123 (§11);
  - the build items;
  - R8, R9.
- **PRD FR-PRO-AUTH-001:** sign-in only on iOS; Android also signs up.
- **LAUNCH:** the « login-only on both platforms » lines.
- **pro-app-login-only.md, app-review-round-2.md:** « 2026-11-12: Android signs
  up again, iOS unchanged ». app-review-round-2 §14's « An iOS-only branch » is
  amended by decision 116.
- **app-store-forms.md:**
  - §11.3's new list and its count;
  - dated notes on « (iOS et Android) » and on the 2026-10-26 reply.
- **android-play-release.md:**
  - §1's « Not a feature »;
  - §4 steps 3a and 9;
  - §5 rows 11–16;
  - the iOS smoke pass.
- **play-store-forms.md:** §9.2.
- **web-pro-registration.md:** its drift note (the address became required).
- **Dev commands:**
  - `mobile/android/app/build.gradle.kts`'s comment;
  - `mobile/scripts/run_pro.sh` (it chooses the entry by the device's
    platform, or takes it as an argument);
  - `docs/DEPLOYMENT.md`'s Android lines.

---

## 10. Definition of done

- [ ] `flutter analyze --fatal-infos --fatal-warnings` = 0; `dart format` clean; the full `flutter test` green; goldens green on Linux; coverage not down.
- [ ] P1–P16 re-scoped, kept or added, each watched red once (§8.1).
- [ ] The binary reads of §8.3 done, with their numbers in the PRs.
- [ ] The Android rows 11–16 and the iOS smoke pass done (§8.4).
- [ ] The documents of §9.4 corrected; the decisions recorded.
- [ ] No backend, contract or deploy change. If one turns out to be needed, it stops here and comes back as a question.
- [ ] Feature branches + PRs; CI green; authored as the owner.

---

## 11. Decisions and open questions

**Already answered (2026-11-12), to record:**

- **116.** In-app salon sign-up returns **on Android only**; iOS stays sign-in
  only.
  - **On Android it supersedes:** decision 38 (« both platforms »); decision
    41's « no button » after a sign-in without an account; decision 71's « one
    behaviour, no iOS-only branch » clause; and app-review-round-2 §14's « An
    iOS-only branch ».
  - **What stands:** the website link's removal (71); « Ajouter un salon »
    web-only (39); pro-companion-path Q3 (no price, offer or steering, on any
    platform).
  - **Why now:** decision 38's own trigger (« if MyWeli ever sells through the
    stores ») did not reopen it. The owner's decision of 2026-11-12, after Play's
    payments policy was read, did.
- **117.** The closed test uses paid testers (Testers Community). It replaces
  play-store-forms §6.1's « Pas de testeurs achetés », and decision 60's test
  salon becomes optional.
  - **Accepted risk:** Google's production-access questions about real use may
    be harder to answer from paid testers (UNVERIFIED).

**For the owner (one answer each):**

- **Q1 (→ 118) The order of the sign-up.**
  - **The salon first, the identity last (recommended).** The website's order.
    - A permanent « Pas encore de compte ? Créer le compte de mon salon ».
    - The e-mail code comes last, so it is fresh. From an e-mail sign-in that
      found no account, the code already received is reused.
    - Costs: someone with an account or an invitation types the salon fields
      for nothing (the screen then signs them in or shows the invitation).
      After Google found no account, Google's sheet opens a second time.
  - **The identity first, the salon after.** Google or e-mail, then the form.
    - Nobody types for nothing.
    - Costs: the e-mail code (5 minutes from its send) often expires while
      the form is filled, so a second e-mail is likely. It differs from the
      website.
  - **Google first, the e-mail code last.** Google is checked at once; the
    e-mail address is asked first and its code sent after the form.
    - Costs: two orders on one screen; it differs from the website.
- **Q2 (→ 119) Which commit does iOS 0.0.2 ship from?**
  - **Before this work (recommended):** the commit after the 0.0.2 version
    bump. iOS ships sooner, with decision 109's Flutter 3.47 proof (O2).
    Apple sees none of the plug points in 0.0.2; the iOS read and smoke pass
    happen at the next iOS build.
  - **The same commit as Android:** one pair of artifacts. iOS 0.0.2 waits for
    PRs 1–4.
- **Q3 (→ 120) How do paid testers' salons stay off the public site?**
  Production has no public salon yet, so a tester's would be the first one
  shown on myweli.com.
  - **Their own instructions and a daily check (recommended):** a paragraph
    for paid testers only says never to tap « Mettre mon profil en ligne ».
    Real salons stay free to publish and keep their 90-day trial (decision
    62). During the test and production review, the owner checks the admin
    console daily and suspends any tester or reviewer salon that went live.
    No code; a fake salon could be public for up to a day.
  - **The server holds them:** salons created during the test cannot publish
    until approved. A backend slice, which delays the test.
  - **Let them publish, suspend after:** no rule for testers. Fake salons are
    public during the test, then suspended.
- **Q4 (→ 121) Play's description.**
  - **A Play-only sentence (recommended):** Play says « MyWeli Pro s’adresse
    aux salons et à leur équipe : créez le compte de votre salon dans
    l’application, ou rejoignez l’équipe qui vous invite. » The App Store
    text, which Apple approved, stays. Decision 113's guard admits that one
    difference.
  - **One rewording for both stores:** for example « MyWeli Pro s’adresse aux
    salons et à leur équipe. » It is true on both, but it changes the App
    Store text Apple reviewed with the 3.1.1 reply.
- **Q5 (→ 122) The consent line's links, inside the sign-up (§6.2).**
  - **Keep the links (recommended):** the same two pages the app already
    opens from « À propos », the ones Apple approved with build 719. The path
    to a price is several taps and runs through the site's own navigation.
    If Play objects, the next option is ready.
  - **Open those pages without the site's navigation:** a web change. Pages
    opened from either app show no header and no footer links, which closes
    the path on both stores. A web slice before step 7.
  - **No links in the sign-up:** the consent sentence names the two documents
    without linking them; they stay in « À propos ».
- **Q6 (→ 123) Decision 108's foreign-salon guard.** For example, the map pin
  inside Côte d'Ivoire before the first publish, enforced by the server.
  - **Not a blocker (recommended):** the same gap exists today on the website
    and iOS. An admin can suspend. The guard gets its own spec next.
  - **Before Android production:** Play's « every country » opens a direct
    path for salons anywhere, so the guard ships first and production waits.

**Recommendations taken unless the owner says otherwise:**

- **R1** Sign-up only; « Ajouter un salon » stays on the website.
- **R2** The website's fields: name, type (chosen, no default), phone, address
  (required), commune (optional, not a guard: §6.5).
- **R3** Google and the e-mail code; no Apple on Android.
- **R4** No price, offer, trial or « gratuit » anywhere in the flow; « Mon
  abonnement » unchanged.
- **R5** After sign-up, « Accueil », with no snackbar (§2.3).
- **R6** Play's reviewers are asked to use the demo account. The
  published-salon watch runs through production review. Their rows are
  purged only on the owner's word.
- **R7** Accept that a salon's path to a running trial happens in the app
  (§6.2).
- **R8** A Pro deletion page for Play, as a web slice before step 7 (§6.3).
- **R9** The website follow-ups, each its own slice:
  - the sign-in check and the carried code on `/pro/inscription`, matching the
    app;
  - its four defects: `invalid_input` invisible on the Google path, no
    120-character cap, no resend cooldown, the address not re-checked on
    submit;
  - the two answers missing from OpenAPI.

**Engineering choices made here (§5), not owner questions:**

- an Android entry file and an import fence under
  `lib/screens/provider/android/`, rather than a runtime gate or a define;
- the path `/pro/register`;
- the check and register run by one service call, with one proof;
- sign-up outcomes kept out of the sign-in's error state;
- a hand port in four PRs.

**UNVERIFIED, named:**

- how Play review treats a trial started by an in-app publish (§6.2);
- carrier-grade NAT and rate-limit buckets (§6.4);
- the Play developer name (§6.3);
- the testers' countries (§9.3);
- whether Play's robot can pass a Google sign-in (§6.5);
- the snapshot's growth (§7).
