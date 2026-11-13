# MyWeli Pro on Android signs salons up again; iOS stays sign-in only

| | |
|---|---|
| **Status** | **Approved 2026-11-12 (the owner answered §11's six questions: decisions 116–123).** Not built. Reviewed three times by independent readers on 2026-11-12, every finding folded in: six readers (code, architecture, backend, design system, store documents, completeness) found 61; three found 26 on the revision; two found 18 on the third. **A prerequisite came out of the answers:** salons now wait for the owner's approval before going public (decision 120), a new feature with its own spec (B0.18), built before the closed test |
| **Owner** | Sadreddine Daher |
| **Last updated** | 2026-11-13 (dated notes for decisions 134–136: §2.7, §5.5, §9.1, §9.3, §9.4, §11) |
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
- **Decision 108's foreign-salon guard.** Decision 123 makes the owner's approval (B0.18) the guard.

**What iOS gets.** No new behaviour. The shared start-up, router, salon gate,
sign-in screen, provider and service gain plug points and methods that only
Android uses (§5.2). So the first iOS build that carries them gets a smoke
pass (§8.4). Decision 119: that is not iOS 0.0.2, which is built before this work.

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

**What the order costs (decision 118 chose it over identity first, and over Google first with the e-mail last):**

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
- **A former team member who was invited again.** The check answers 200, and
  the session opens the rejoin gate (« /pro/invitations ») on its own, as any
  sign-in does. That screen does not say the typed salon was not created.
  This case is rare, and it is accepted.

### 2.2 Entry points (Android only)

On Android, the sign-in screen gets one block at its bottom, supplied by the
Android code. Its sentence is an `InlineFeedback` with `kind: SnackKind.info`,
a live region, so TalkBack announces it.

| # | When | The block shows |
|---|---|---|
| E1 | Options step, with no `provider_not_found` in hand | « Pas encore de compte ? » and a text button « Créer le compte de mon salon » |
| E2 | Options step, after « Continuer avec Google » answered `provider_not_found` | `kNoProAccountMessage` as information, then « Créer le compte de mon salon ». It is scrolled into view, since at 200% text it lands below the fold |
| E3 | Code step, after the code answered `provider_not_found` | the same as E2. The e-mail **and the code that the 404 verify used** cross into the sign-up (§2.4 row 8). The sign-in keeps that pair when the verify answers; it does not read the field when the button is tapped, because the field stays editable |

**What does not change:**

- **The sentence stays word for word.** On Android, the block shows it, so the
  sign-in's own red `InlineFeedback` does not repeat it. Every other fault
  stays in that red `InlineFeedback`.
- **After the last « Refuser »,** the screen falls back to the options step,
  which shows E2 or E1.
- **Coming back from the sign-up, the sign-in is shown fresh.** That covers
  Back, « Se connecter », and anything that returns there: the options step,
  its feedback cleared (E1). The block's button awaits the page it pushed,
  then asks the sign-in to reset itself.
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
4. If that code is no longer usable (`otp_expired`, `otp_none`,
   `otp_invalid`, `otp_locked`), the identity section switches to the e-mail
   path, with the address filled in. It says « Ce code n’est plus valable.
   Recevez-en un nouveau. » A new code also resets the attempts.

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
| 1 | App bar: `ScreenTitle('Créer mon compte')` | heading level 1 (SYSTEM §13.4). Back pops to the sign-in, shown fresh (§2.2), and drops any invitations and proof this screen held. **While a request runs, and on S3, Back is held** (`PopScope(canPop: false)`): the session may already be live, and a signed-in person must never land on the sign-in. On S3, Back acts as « Continuer ». The screen exists only on Android, so this changes nothing on iOS |
| 2 | Section heading « Votre salon » | heading level 2 |
| 3 | « Nom de l’entreprise » | required: `Validators.requiredField('le nom de l’entreprise')` gives « Indiquez le nom de l’entreprise. ». At most **120 code points** after trimming, the server's measure (`register.dart:54-58` counts runes). A validator enforces it, not a `maxLength` counter (which counts something else): « 120 caractères au plus. ». Hint: « Ex : Salon de Beauté Marie » |
| 4 | « Type d’entreprise » | six `AppChip.choice`: Salon de beauté · Barbier · Spa · Institut de manucure · Massage · Autre. Required, **no default** (the deleted screen's rule): the type drives the checklist, staff being optional for « Autre » and RCCM required unless « Autre ». Its fault, « Choisissez le type d’entreprise. », is an `InlineFeedback` under the chips. The group is wrapped in `Focus(FocusNode(skipTraversal: true))`, so `focusFirstError` reaches it, as the operator chips of `deposit_settings_screen.dart` do. A chip label never wraps, so the 200% test checks for silent truncation (§8.2) |
| 5 | « Téléphone du salon » | `PhoneNumberField` (Côte d'Ivoire by default) + `Validators.phoneNumber`, the server's rule and the app's sentences. Helper: « Le numéro que vos clients appellent. » |
| 6 | « Adresse » | required, two lines: « Indiquez l’adresse de l’entreprise. ». Hint: « Rue, quartier, repère » |
| 7 | « Commune (optionnel) » | `showCommunePicker` (returns the `areaId`); optional, as on the website and the deleted screen (R2). Going live needs one, and « Configurer mon profil » asks for it then |
| 8 | Section heading « Votre identité de connexion », with the sub-line « Elle vous servira à vous connecter à votre espace pro. » | heading level 2; the website's words. **From E3**, the section shows only « Compte : {e-mail} », « Créer mon compte » and a text button « Utiliser une autre adresse », which opens the standard section below |
| 9 | Consent: `LegalConsentText(lead: 'En créant votre compte professionnel')` | « En créant votre compte professionnel, vous acceptez nos Conditions d’utilisation et notre Politique de confidentialité. », both linked to the site (decision 122). Passive, no checkbox. It sits **above the first button that can create the account** |
| 10 | « Continuer avec Google » | secondary `AppButton` with the G logo, as on the sign-in. It validates rows 3–7 first, focusing the first fault, and only then opens Google's sheet |
| 11 | « ou », « Votre e-mail », « Continuer avec e-mail » | the sign-in's controls and labels. The button validates rows 3–7 and the e-mail first |
| 12 | Code step, on this screen, replacing row 11 | « Entrez le code reçu par e-mail à {e-mail}. », « Code à 6 chiffres » (and the dev hint off-prod), « Créer mon compte » (primary), « Renvoyer le code (60s) », « Changer d’e-mail ». The sign-in's code step, cooldown included |
| 13 | `InlineFeedback(formFault)` | a live region for outcomes that belong to no field |

Every button is disabled **only** while its request runs (SYSTEM §14 rule 5).
Faults are checked on the action, re-checked on change once shown, and placed
under their field (§14).

### 2.5 States and branches

The sign-up's outcomes and faults show on the sign-up screen. Two rules keep
the sign-in truthful afterwards:

- **The provider clears the sign-in's feedback on every sign-up success.**
  That is `error` and `errorCode`, as every sign-in does at its start, so a
  later sign-out never brings back a stale « Aucun compte ».
- **Anything that returns to the sign-in finds it fresh: E1** (§2.2).

The sign-up also uses the provider's existing actions: the code request, and
the invitation's accept and decline. Those write the sign-in's feedback
fields. The sign-up reads them right after each call, as the sign-in does, and
the reset on return makes the leftovers harmless.

| # | State | What the person sees |
|---|---|---|
| S1 | A request runs | that button's spinner; the fields stay visible |
| S2 | Check 404, register **201** | « Accueil » (§2.3). The session goes through `_setProvider` (which resets ProSalonScope and AccountScope, B9.14), then push sync, `refreshMembership` and `loadMySalons`: a sign-in's success steps |
| S3 | Check **200**: the account exists | in place of the form: an info `InlineFeedback`, « Vous aviez déjà un compte MyWeli Pro : vous êtes connecté(e). Le salon saisi n’a pas été créé. », and a « Continuer » button (Back acts as it). It lands where a sign-in lands (owner → « Accueil », staff → their shell) through one shared helper (§5.2). **Two exceptions.** A re-invited former member's session opens the rejoin gate on its own before S3 shows (§2.1). After a register whose answer was lost (S12), a 200 is S2, not S3, since that salon exists |
| S3b | Check 200, then the membership refresh finds **no membership left and nothing pending** (a former team member) | The provider signs them out, as it does after any sign-in, and returns to the sign-in. The sign-in now picks up the « accès retiré » notice even though it was mounted under the sign-up (§5.2), and shows `RevokedAccessBanner` (« Votre accès à {salon} a été retiré. »). As §2.1 says, that identity cannot create a salon |
| S4 | Check **202**: invitations | on the sign-up screen: « Vous êtes invité(e) », « Cette adresse a reçu une invitation. Rejoignez l’équipe, ou créez plutôt votre propre salon. », the `InvitationCard`s (« Rejoindre » / « Refuser »), and a text button « Créer plutôt mon propre salon ». **Rejoindre** accepts with the retained proof, exactly as on the sign-in, and lands as S3 does. **Refuser** removes the card; when none is left, the form comes back as it was, with no message. **Créer plutôt mon propre salon** creates the account with the same proof. The invitations stay pending on the server; in the app, the proof and invitations are dropped on the 201. **Its first request carries the salon fields**, so its refusals bring the form back with the fault where S5–S13 put it, a code fault opening the code step. **The choice is remembered** until the screen is left: a corrected submit registers directly, without the check, with the held proof or a new code. Accept and decline refusals show under the cards, in the sign-in's sentences |
| S5 | `400 invalid_phone` | under « Téléphone du salon »: « Saisissez un numéro de téléphone valide. » (the app's sentence) |
| S6 | `400 invalid_area` | under « Commune (optionnel) »: « Choisissez une commune dans la liste. » |
| S7 | Register's `400 invalid_input` | form level: « Vérifiez les informations du salon, puis réessayez. » The service says which call refused (the check or register), so this is never confused with the check's `invalid_input`, a malformed code, which is S9's « Code incorrect. » |
| S8 | `409 provider_exists` | form level: « Un compte existe déjà pour cette identité. Connectez-vous. » and « Se connecter », which pops to the sign-in, shown fresh (E1). This happens only when another device created the account between the check and register |
| S9 | Code faults (`otp_invalid`, `otp_expired`, `otp_none`, `otp_locked`, or the check's `invalid_input`) | under « Code à 6 chiffres », the sign-in's sentences (`codeFieldFault`), and « Renvoyer le code ». **On the carried code (E3)**, the four `otp_*` codes switch to the e-mail path with §2.3's sentence; the carried pair is the one that was proven, so a malformed code cannot occur |
| S10 | `invalid_email` | under « Votre e-mail », when it is on screen. `otp_resend_limit` is form level, « Trop de demandes de code. Réessayez plus tard. », as on the sign-in |
| S11 | Anything else (`token_rejected`, `invalid_token`, `auth_method_disabled`, 429, 503, a 500) | the sign-in's own sentence for that code (SYSTEM §17: « a refusal whose code has its own sentence keeps it »), else `kGenericErrorMessage` |
| S12 | A failure **after** the account was created: a lost 201 (timeout), or a 500 from salon provisioning | **Retrying recovers it.** On Google, the check answers 200. On e-mail, the consumed code gives S9 (`otp_none`); after a new code, the check answers 200. Either 200 is **S2**, because this screen remembers that a register went out whose answer was lost, and the salon does exist. **The cost:** after a provisioning 500, the server's self-heal creates the salon without the commune, so « Configurer mon profil » asks for it again. Two truly simultaneous creates give a 500 (S11), then a 200 on retry |
| S13 | No network | « Pas de connexion. Réessayez. »; the fields are kept |
| S14 | Google's sheet closed | nothing; the form stays as it was |
| S15 | `/pro/register` while signed in (a stale push, a `returnTo`) | redirected to `/pro/dashboard` |

**Edge cases.**

- **A killed app.** On a low-end phone, a person who leaves to read the code
  can return to a restarted app and an empty form. The sign-in's code step has
  the same limit today. Restoring state is out of scope.
- **Long strings.** Names up to 120 code points and the sentences wrap. Chip
  labels do not wrap, so they are checked for silent truncation at 200% text.
- **A salon outside Côte d'Ivoire** can sign up, and its go-live request
  waits for the owner, who refuses it (§6.5, decision 123).
- **Double taps** are blocked by S1.
- **Low-end Android:** no images, animation or lists on this screen.

### 2.6 Copy

**(a) Strings that exist only in the Android-only code.** These form the
**absence list**: the source pin (§8.1 P2) and the iOS read's
`gone_android_signup` (P13). Each is proven absent from the iOS program's
source before it joins (a vacuity check). « Witnesses », as in app-store-forms
§11.3, keeps its meaning there: strings that must stay **present**.

| Group | Strings |
|---|---|
| Entry | « Pas encore de compte ? » (already on the iOS list) · « Créer le compte de mon salon » |
| Screen, headings | « Créer mon compte » · « Votre identité de connexion » · « Elle vous servira à vous connecter à votre espace pro. » · « Utiliser une autre adresse » |
| Fields, hints | « Nom de l’entreprise » · « Type d’entreprise » · « Salon de beauté » · « Institut de manucure » · « Téléphone du salon » · « Commune (optionnel) » · « Ex : Salon de Beauté Marie » · « Le numéro que vos clients appellent. » · « Rue, quartier, repère » · « 120 caractères au plus. » · « Choisissez le type d’entreprise. » |
| Outcomes | « Vous aviez déjà un compte MyWeli Pro » · « Cette adresse a reçu une invitation. » · « Créer plutôt mon propre salon » · « Ce code n’est plus valable. » · « Vérifiez les informations du salon » · « Un compte existe déjà pour cette identité. » · « Choisissez une commune dans la liste. » |
| Consent | the lead « En créant votre compte professionnel » (it also sits in a doc comment of `legal_consent_text.dart`; source scans strip comments) |

`/pro/register` and `/auth/provider/register` are on the **binary absence
list only**. The first lives in the fenced code. The second is the register
call in the shared `ApiAuthService` (§5.2), which is in the iOS program's
source closure, so its absence can only be shown in the binary.

**(b) Reused, already shipped on iOS, never on the absence list:**

- « Votre salon », « Adresse », « Commune »;
- « Votre e-mail », « Continuer avec e-mail », « Continuer avec Google »,
  « Code à 6 chiffres », « Renvoyer le code », « Changer d’e-mail »,
  « Se connecter », « Continuer »;
- « Vous êtes invité(e) », the invitation cards' labels;
- `kNoProAccountMessage`, `kNoConnectionMessage`, `kGenericErrorMessage`;
- the sign-in's code, e-mail and phone sentences, and the
  `RevokedAccessBanner` sentence;
- « Indiquez … » (`Validators.requiredField`);
- the chip labels the app already uses: « Barbier », « Spa », « Massage »,
  « Autre ».

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

*2026-11-13:* B0.18's Pro-app PR renames that button « Demander la mise en
ligne » (decision 132), and it merges before the 0.0.2 bump (decision 134), so
before any of this spec's PRs unless that decision's fallback is taken. Where
this spec quotes « Mettre mon profil en ligne » for the app after B0.18 (here,
§6.2's R7 path, P12), read « Demander la mise en ligne » once that PR is on
`main`; §11's quote, in decision 120, is history.

**Two facts the person meets:**

- **Team invitations wait for go-live:** « Vous pourrez inviter votre équipe
  une fois votre salon en ligne. »
- **Going live changes with B0.18 (decision 120).** Today the first publish
  makes the salon public and starts the 90-day trial, silently, with only
  « 🎉 Votre profil est en ligne ! ». After B0.18, « Mettre mon profil en
  ligne » asks for the owner's approval; the salon goes public, and its trial
  starts, at the approval. That screen's states and copy belong to B0.18's
  spec, on both platforms.

The sign-up itself adds nothing about the trial or the offer (R4, §6.2).

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

- no subscription row (the trial starts at the first go-live: at the owner's
  approval once B0.18 ships);
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
| `lib/main_pro.dart` | `main()` becomes `runProApp()`. `runProApp({ProAppExtensions? extensions})` holds today's body and calls `ProRouter.install(extensions)` before anything reads the router (`ProAuthProvider()`, `_startPush`) |
| new `lib/core/pro_app_extensions.dart` | `ProAppExtensions { List<RouteBase> routes; ProLoginExtras? login; }`. `ProLoginExtras` holds one builder for §2.2's block: `Widget Function(BuildContext, {required bool noAccount, String? email, String? code, required VoidCallback onReturned})`. `onReturned` is the sign-in's reset, called when the sign-up it pushed comes back. No French text, no path literal |
| `lib/core/router/pro_router.dart` | `ProRouter.build(ProAppExtensions?)` is pure, for tests, which never touch the global. `ProRouter.install(ext)` is production-only and throws a `StateError` if `router` was already read. `router` is the installed one, defaulting to today's shape. **`launchPaths` stays a const set, unchanged.** The class doc's « There is no sign-up screen » becomes « none on iOS » |
| `lib/widgets/provider/pro_salon_gate.dart`, `landedPushHandler` | **Unchanged.** A page **pushed** above `/pro/login` is read as `/pro/login` by both. go_router keeps the configuration's `uri` on push (`match.dart:607-614`), and the router reports that `uri` back. `/pro/login` is already exempt from the gate and is a launch path for the push handler. So the sign-up must be entered by push, never by `go`, and P16 pins that |
| `lib/screens/provider/auth/pro_login_screen.dart` | **The block.** It reads `context.read<ProLoginExtras?>()`, with the nullable type, so an absent provider gives `null` rather than throwing. With no extras (iOS, and every existing test), it renders today's screen exactly. With them, it shows §2.2's block, and when the block shows `kNoProAccountMessage` its own feedback does not repeat it. **The E3 pair.** It keeps the e-mail and code its 404 verify used, for E3. **The reset.** `onReturned` resets it to the options step and asks the provider to clear its feedback (§2.2). **The landing helper.** `_finish`'s rule moves into a shared `proLandingRoute(auth, returnTo)`, used by the sign-in and by S3. **The revoked notice.** A provider listener, at notify time, picks up an « accès retiré » notice set while the sign-in is not the top page, and applies `_land`'s rule: the options step plus the banner (S3b). Today the notice reaches the sign-in only in `initState` or after its own sign-ins, which already consume it, and nothing is ever pushed above it on iOS, so this changes nothing there |
| new `lib/models/provider_sign_up_result.dart`, `lib/models/pro_sign_up_fields.dart` | **The outcomes:** created · signedIn · invited(invitations, proof) · failure(code, message, stage: check or register). **The fields:** `businessName`, `businessType`, `phoneNumber`, `address`, `areaId?` |
| `AuthServiceInterface`, `ApiAuthService` | Three methods: `signUpProviderWithGoogle(fields)` and `signUpProviderWithEmail(email, code, fields)` run the check, then register, with **one** proof; `registerProvider(InvitationProof proof, fields)` registers only (S4's « Créer plutôt mon propre salon »). In the API service, the Google method obtains its token with the sign-in's plugin arm, reported with `_reportSignInFailure`. It uses `return await` inside `try` (Dart 3.13, B13.1). `_messageFor` is **not changed** |
| `MockAuthService` (fidelity) | latency, the three check answers, `provider_exists`, `invalid_phone`, `invalid_area`, code faults, success. **A settable Google e-mail**: today the only mock Google identity has a seeded invitation and always answers 202, so tests and mock builds choose a no-account identity. **Its register creates the draft salon and OWNER membership**, so `getMyProvider` resolves after a mock sign-up |
| `lib/providers/pro_auth_provider.dart` | `signUpSalonWithGoogle(fields)`, `signUpSalonWithEmail(email, code, fields)`, and `createOwnSalonInstead(fields)`, which uses the retained invitation proof. **Created or signed in:** clear `error` and `errorCode`, then `_setProvider` → `_syncPush` → `refreshMembership` → `loadMySalons`. Return « signed in » only if `_provider != null` afterwards, which is S3b's distinction. **On `createOwnSalonInstead`'s 201,** also drop `_pendingInvitations` and `_invitationProof`; `logout` does not clear them. **Invited:** clear `error` and `errorCode`, then hold the invitations and their proof exactly as the sign-in's bridge does; accept and decline keep their meaning. **Failure:** returned to the screen. **`clearFeedback()`:** new, for the sign-in's reset. The sign-up drops held invitations and proof on Back (in `PopScope`) or on success, never in `dispose`, where a notify would hit a locked tree |

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
  - the block's builder, whose button **pushes** the route and calls
    `onReturned` when it comes back.
- **`pro_sign_up_entry.dart`**: §2.2's block and its strings.
- **`pro_sign_up_screen.dart`**: §2.4's screen, its states, and its
  code-to-sentence table.

### 5.4 The path

`/pro/register` is the deleted app path, restored on Android. The website's
`/pro/inscription` is not used: it is an iOS witness, and
`pro_site_links_test` forbids it.

**It needs no launch-path entry.** It is always pushed above `/pro/login`, so
the salon gate and the buffered notification handler read the location as
`/pro/login`, which both already treat as a launch page (§5.2).

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

A revert would also restore « S’inscrire sur myweli.com ». *Corrected
2026-11-13: it would not.* #711 (`54b02dac`) **added** that link, and #731
removed it. A revert of #711 would restore « S’inscrire », « Créer un compte »
and « Ajouter un salon » (`/pro/salons/nouveau`), on iOS too: the in-app
registration Apple refused under 3.1.1 on build 587. It does not even apply:
a dry run (`git apply --check -R`) against `main` at `d19655bd` fails on 17
files.

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
  no amount, and only for Apple. The owner kept the links knowingly
  (**decision 122**). Showing those pages without the site's menus is the
  ready next step if Google objects.
- **« Mon abonnement » is unchanged.** State only (tier, trial days left,
  dates, seats), with no button and no price. It is identical on iOS, which
  Apple approved.
- **The trial pushes are unchanged.** Facts with no call to action. « activez
  votre offre » must never appear in one, since pushes come through the app.
- **The subscription e-mails are outside the app,** which Google allows: « Outside
  of your app, you are free to communicate with your users about alternative
  purchase options » (help 10281818).
- **One risk accepted with the decision (R7).** A salon's path to a running
  90-day trial starts in the app: sign-up → « Mettre mon profil en ligne » →
  the owner's approval (B0.18) → `startDefaultTrial`. Only payment happens
  elsewhere. Google's pages do not address this (UNVERIFIED how review treats
  it). Today's version, the trial started by the publish itself, shipped on
  iOS.

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
  « Créer plutôt mon propre salon »'s 201, and when the sign-up is left by
  Back.
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

- **Paid testers** (§9.3).
- **Play's reviewers,** with their own Google account, on every review,
  production review included.
- **Play's pre-launch robot,** if it can pass a Google sign-in (UNVERIFIED).

**None of them can make a salon public.** Since decision 120, a salon goes
public only once the owner approves it (B0.18, built before the closed test),
and the owner does not approve test or review salons.

**R6, kept:**

- Play's sign-in details ask reviewers to use the demo account (§9.2).
- Rows are purged only on the owner's word.

**Salons outside Côte d'Ivoire.** Today a salon anywhere can sign up on the
website and go live with any of the 11 Abidjan areas: nothing in publishing
reads the country or where the pin is. A required commune would not change
that; « Près de moi » would even pick the nearest Abidjan area for a salon in
Dakar. **Decision 123:** the owner's approval (B0.18) is the guard; they
refuse a salon outside Côte d'Ivoire.

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
| P4 (new) | — | The sign-in **with** the extras: E1; E2 after a Google 404, the sentence an info live region scrolled into view; E3 after a code 404, carrying the pair its verify used even when the field was then edited; E1/E2 after the last « Refuser ». Also: coming back from the sign-up after a failure, after S4, after S8's « Se connecter » shows E1; after a sign-up and a sign-out, E1, not E2; S3b started from E3 shows the options step and the banner | 3 |
| P5 (new) | — | `proAndroidExtensionsFor(TargetPlatform.iOS) == null`. For Android: non-null, with `/pro/register` in its routes. A plain `test()` with the platform passed in | 1 (iOS null), 3 (Android) |
| P6 | `pro_site_links_test` over `main_pro.dart`'s closure (`\binscri`, `/pro/inscription`, the five pages, the outbound inventory) | Unchanged, plus a run over `main_pro_android.dart`'s closure: the same bans; still only the five pages; `termsUrl`/`privacyUrl` also read by `legal_consent_text.dart` there | 3 |
| P7 | `pro_login_invitations_test` lines 99, 129 and 131 | Unchanged (no extras); a twin with the extras pins §2.2's block after the last decline | 3 |
| P8 | `social_signin_diagnosis_test`: 9 `_reportSignInFailure(` calls (1 definition, 4 typed arms, 4 catch-alls) / 4 / 4 / 4 | One Google plugin arm more: **11 / 5 / 5 / 5** | 2 |
| P9 | `release_build_test` (entry by flavour); its `flutter` stub logs nothing | `android pro` → `lib/main_pro_android.dart`, `ios pro` → `lib/main_pro.dart`. The stub is changed to log its arguments, so the target is observed | 1 |
| P10 | `route_literals_test` (the `main()` files equal its entries; pushed routes exist) | Gains `main_pro_android.dart` (PR 1). A table from `ProRouter.build(androidExtensions)` contains `/pro/register` (PR 3) | 1, 3 |
| P11 | `pro_subscription_no_pricing_test` (scans `lib/`; bans choosing or activating offers) | Plus a ban list over the fenced directory: gratuit, essai, offre, offert, FCFA, prix, tarif, abonnement, `/mois`, myweli.com (**red:** plant one). The comments that call any platform branch a defect are reworded to « no selling, on any platform ». The consent links come from a shared widget through `AppConfig`, so this pin does not see them; decision 122 keeps them | 3 |
| P12 | `play_store_forms_test`: the description equal to the App Store's (lines 102–117); the reviewer sign-in text ≤ 500 characters (lines 181–188); §6's pinned numbers (« les N jours d'essai gratuit », « valable N jours », « expire au bout de N jours », « N places, vous compris », « donc N invités au plus »); `onScreen()` reading only `pro_login_screen.dart` and `invitation_card.dart` | The description follows decision 121, admitting exactly that one named difference. The sign-in text stays ≤ 500 under the new line. Each §6 number stays pinned while its text stays; text that goes is deleted with its pin, the pin watched red first. `onScreen()` reads every fenced file, plus `pro_onboarding_screen.dart` if « Mettre mon profil en ligne » is quoted | 4 |
| P13 | `app_review_notes_test` reads app-store-forms §11.3's lists through `scriptList()` | §11.3 gains `gone_android_signup`: §2.6 (a), `/pro/register` and `/auth/provider/register`, **in the same PR as the test**. The test reads it and checks it does not overlap the witnesses (the strings that must stay present). The expected-count row (« 14 phrases à 0, 6 témoins présents ») grows | 3 |
| P14 | `motion_test`, `content_width_test` and `default_status_bar_style_test` find every `lib/main*.dart` and require `ReduceMotionObserver`, `ContentWidthCap` and `DefaultStatusBarStyle(` in its own source | A root whose `main()` only calls another root's `runProApp` is checked through that root. Each test asserts the delegation (`import 'main_pro.dart' show runProApp` and a `runProApp(` call) | 1 |
| P15 | Source pins on `lib/main_pro.dart`: `pro_salon_not_loaded_test` (builder regex), `pro_cold_start_deep_link_test` (`isSignedIn`), `pro_salon_scope_booking_created_test` (`ProSalonScope.track` count), `route_literals_test:206` and `release_build_test:550-555` (`ProRouter.router`), `pro_reads_own_salon_test` | Unchanged, since the wiring stays in `main_pro.dart`. Each is run against PR 1 to see that it still finds what it pins | 1 |
| P16 (new) | — | **The sign-up is entered by push, never by `go`**: the gate and the push handler then read `/pro/login` (§5.2). A widget case: on the pushed sign-up, a 201 with the salon still loading keeps the form, then lands on « Accueil ». **Red:** switch the block's entry to `context.go('/pro/register')` and watch the gate replace the form | 3 |

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
  - « Créer plutôt mon propre salon »: its 201 drops the held invitations and
    proof (they stay pending on the server); its refusals bring the form back,
    and the choice is remembered.
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
  - The states: S2–S15, with S3 (Back held and acting as « Continuer »),
    S3b, S4's three choices and their refusals, and S12's 200 landing as S2.
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
   of the first iOS build that carries this change (decision 119: after 0.0.2). Every
   `gone_android_signup` string counts 0, and the witnesses stay present.
   - **The rehearsal,** in PR 3 (with the list it reads): an unsigned
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
| 1 | The fence with **null** extensions: `runProApp(extensions)`, `ProRouter.build`/`install`, the sign-in's empty slot and reset, `proLandingRoute`, the revoked-notice pickup, `main_pro_android.dart`, the release script by platform; P1, P2 (scope), P5 (iOS), P9, P10 (entries), P14, P15 | **No behaviour change:** `pro_login_w360_x2` byte-identical, P3 green untouched, and a baseline iOS strings read |
| 2 | The service, provider and mock methods with their unit tests; P2 (regex), P8 | — |
| 3 | The fenced screens, the sign-in's block, the copy, goldens and accessibility; app-store-forms §11.3's `gone_android_signup` and its count; P2 (copy), P4–P7, P10, P11, P13, P16; the iOS rehearsal and control | — |
| 4 | The documents and Play texts (§9.2, §9.4); P12 | — |

**Also before step 5:** the B13.3 package PRs (#772 lottie;
cached_network_image), if they are to ride in 0.0.2.

**Production** moves by PRs 1–4, B0.18 (approval) and B0.19 (the Pro
deletion page).

**iOS (decision 119): 0.0.2 is built before PR 1 merges.** `release_build.sh`
builds only from `origin/main`'s head, so the iOS 0.0.2 IPA is built with
`./tool/release_build.sh ios pro` after step 3's version bump merges and
**before PR 1 merges**. PR 1 waits for that build; the upload still waits for
the owner's yes. Decision 111 asks only for the same **version**. The build
number is the commit count, and the version floors are per platform, so the
two stores' different build numbers are both valid.

**Approval first (decision 120).** B0.18 (salons go public only once the owner
approves them) has its own spec and is built before the closed test's
step 8.

**2026-11-13: three PRs, and the order around them (decisions 134, 135).**

- **Three PRs, not four** (an engineering choice, not an owner question):
  - **A** = PR 1, the fence with null extensions, no behaviour change;
  - **B** = PRs 2 and 3: the service, provider and mock methods, the screens,
    the copy and the goldens (it may still be reviewed in two commits);
  - **C** = PR 4, the documents and the Play texts (P12). C is needed at
    **step 7**, not step 5: it waits for B0.18's button rename (« Demander la
    mise en ligne ») and B0.19's URL. So « Before step 5 » above means A and B.
- **The order on `main`:** B0.18's Pro-app PR → the 0.0.2 bump → a merge hold
  → the iOS 0.0.2 IPA (decision 119, unchanged, so it now carries B0.18's app)
  → the R8 (shrinker) PR (decision 135) → A → B; C after B0.19. So **A waits
  for the iOS 0.0.2 build**, which follows B0.18's app and the bump. A's P9
  reuses the `flutter` stub's argument log the R8 PR adds.
- **Fallback the owner accepted:** if B0.18's app PR stalls, the bump ships
  alone first; then iOS 0.0.2 predates B0.18, and B0.18's app still merges
  before step 5. (android-play-release §4, steps 3 and 3a.)

### 9.2 Play texts and declarations that change (play-store-forms)

| Where | Today | After |
|---|---|---|
| §1 description | « MyWeli Pro s’adresse aux salons qui ont déjà un compte MyWeli et à leur équipe. », equal to the App Store's (decision 113) | Play only (decision 121): « MyWeli Pro s’adresse aux salons et à leur équipe : créez le compte de votre salon dans l’application, ou rejoignez l’équipe qui vous invite. » The App Store text stays |
| §2 sign-in details for reviewers (English, ≤ 500 characters, 463 today) | the demo account | + an English line within the limit, for example « Please use this demo account; do not create a salon. », shortening another line if needed (R6) |
| §4 Data safety, account creation | not stated in §4 | stated: the methods, « dans l'app (Android) et sur le Web ». §0.1, the dated record of 2026-10-28, gets a note, not a rewrite |
| §4 « Numéro de téléphone » | Facultatif | **Obligatoire**; purposes + « Gestion du compte » |
| §4 « Adresse » | Facultatif | **Obligatoire** (the form requires it) |
| §4 « the three tell the same story » | | names the one legitimate difference with the App Store label |
| §4, §0.1, §7.3, the deletion URL | `/suppression-compte`, « couvre les comptes professionnels » | per R8 |
| §6 point 3; §6.1, the salons bullet and « Pas de testeurs achetés »; §6.2 step 5 (the test salon, its seats); §6.3 (« créez le compte de votre salon sur https://myweli.com/pro/inscription »); §6.5 the guide | the website sign-up and invitations | sign-up in the app. Paid testers recorded (decision 117); the test salon optional (decision 60 amended). Real salons keep « les 90 jours d'essai gratuit », which starts at the owner's approval (decisions 62, 120). A **separate paragraph for paid testers** says their salon stays private: it is not approved. Every quoted label is on screen (P12) |

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
  drafts; any purge or suspension asks the owner first. *Corrected
  2026-11-13: there is no such list.* Decision 117 (2) says so: testers join
  through Testers Community's Google Group, and their salons are recognised at
  validation (B0.18) and refused « Salon de test » (`test_salon`, final).
  Testers who never ask to go live carry **no marker**. How to recognise them
  (for example a « TEST » prefix in the salon name, asked in the guide, or the
  sign-up window) is for the testers plan, owed before step 8 with Testers
  Community's answers. The countries are decided too: every available one,
  decision 117 (1).
- **Publishing:** a tester's salon may ask to go live; the owner does not
  approve it, so it stays private (decision 120, B0.18).
- **E-mail budget:** 60 per hour, shared (§6.4).

### 9.4 Documents to correct (dated notes, PR 4)

- **BACKLOG:** recorded in this spec's PR: decisions 116–123 and items
  B0.17 (this build), B0.18 (approval) and B0.19 (the Pro deletion page).
- **PRD FR-PRO-AUTH-001:** sign-in only on iOS; Android also signs up.
- **LAUNCH:** the « login-only on both platforms » lines.
- **pro-app-login-only.md, app-review-round-2.md:** « 2026-11-12: Android signs
  up again, iOS unchanged ». app-review-round-2 §14's « An iOS-only branch » is
  amended by decision 116.
- **app-store-forms.md:** dated notes on « (iOS et Android) » and on the
  2026-10-26 reply. §11.3's new list and its count land in PR 3, with P13.
- **android-play-release.md:**
  - §1's « Not a feature »;
  - §4 step 3a;
  - step 5: the `libapp.so` presence read and the size measurement;
  - step 7: preconditions (the help pages re-read, B0.19's page);
  - step 8: B0.18 built;
  - step 9: self sign-up;
  - §5 rows 11–16;
  - the iOS smoke pass;
  - the iOS 0.0.2 build before PR 1.
  - *2026-11-13:* the docs PR of decisions 134–136 already did step 3a, the
    iOS 0.0.2 build before A, step 7's B0.19 precondition and step 8's
    « deployed » (done that day), with pointers to rows 11–16. PR C keeps the
    rest: §1's « Not a feature », step 5's `libapp.so` read and size, step
    7's help pages re-read, step 9, rows 11–16 themselves and the iOS smoke
    pass.
- **BACKEND.md §7:** the T35 row (register with an inline identity) gains
  « Android Pro calls register directly ».
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

**Answered by the owner (2026-11-12), the questions as they were asked:**

- **118. The order:** « Salon first », the recommendation, over « Identity
  first » and « Google first, e-mail last ». §2 is written for it.
- **119. iOS 0.0.2's commit:** « Before this work », the recommendation. The
  iOS 0.0.2 IPA is built after the version bump and before PR 1 merges
  (§9.1). The iOS read and smoke pass go with the first iOS build after it.
- **120. Paid testers' salons:** **« Yes, build approval ».** It was asked
  twice. The first answer, « even if they tap put salon online, first the
  admin (me) should approve, I guess that is how the app works », assumed
  approval existed. It does not: « Mettre mon profil en ligne » publishes at
  once, and the admin console approves only identity documents (KYC), which
  unlock deposits. So it is a **new feature**:
  - every salon, on iOS, Android and the website, goes public only once the
    owner approves it, or the owner refuses it with a reason;
  - the 90-day trial starts at the approval;
  - it has its own spec (B0.18) and is built before the closed test.
- **121. Play's description:** a Play-only sentence, the recommendation
  (§9.2).
- **122. The consent links:** keep them, the recommendation (§6.2).
- **123. Decision 108's guard:** « Approval covers it », the recommendation:
  the owner refuses a salon outside Côte d'Ivoire.

**Recommendations, taken (the owner did not object):**

- **R1** Sign-up only; « Ajouter un salon » stays on the website.
- **R2** The website's fields: name, type (chosen, no default), phone, address
  (required), commune (optional, not a guard: §6.5).
- **R3** Google and the e-mail code; no Apple on Android.
- **R4** No price, offer, trial or « gratuit » anywhere in the flow; « Mon
  abonnement » unchanged.
- **R5** After sign-up, « Accueil », with no snackbar (§2.3).
- **R6** Play's reviewers are asked to use the demo account. Their rows are
  purged only on the owner's word. With approval (B0.18), their salons never
  go public.
- **R7** Accept that a salon's path to a running trial starts in the app
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
- a hand port in four PRs (three since 2026-11-13, §9.1).

**UNVERIFIED, named:**

- how Play review treats a trial whose path starts in the app (§6.2);
- carrier-grade NAT and rate-limit buckets (§6.4);
- the Play developer name (§6.3);
- the testers' countries (§9.3);
- whether Play's robot can pass a Google sign-in (§6.5);
- the snapshot's growth (§7).
