# The Pro app never sells — the companion path (App Store 3.1.3(f))

| | |
|---|---|
| **Status** | Approved 2026-10-05 (owner: §11 Q1–Q4, every recommended option) |
| **Owner** | Sadreddine Daher |
| **Last updated** | 2026-10-05 |
| **PRD ref / phase** | PRD §6.2 (salon offers), OQ-3 (store billing) · V1 |
| **ROADMAP entry** | [2026-10-05-pro-companion-path](../roadmap/entries/2026-10-05-pro-companion-path.md) (parent: [2026-09-24-pro-app-store-readiness](../roadmap/entries/2026-09-24-pro-app-store-readiness.md)) |
| **Skills checked** | myweli-dev-guardrails · myweli-backend-guardrails · myweli-verification-guardrails |
| **Decision** | Owner, 2026-10-05: App Store path **(a)** of [app-store-forms.md](app-store-forms.md) §2.4 — the Pro app is a free companion app; no plan choice, no purchase, no call to action to purchase elsewhere — on **both** iPhone and Android (§11 Q3). |

## 1. Goal & scope

**Goal.** Ship MyWeli Pro on the App Store under guideline **3.1.3(f)** ("free
stand-alone companion app to a paid web based tool"): the app must contain
**no purchasing** and **no calls to action for purchase outside the app**. It
may show the salon's current plan state. Choosing or changing an offer happens
on the web, and **the app never says so**.

**Why this is not just hiding a button.** Today choosing an offer *is* how a
salon's one 3-month trial starts (`chooseOffer`, the only writer of
`provider_subscriptions`), and going live requires a live offer. Remove the
picker and an iPhone-only salon can never go live, and the app may not tell it
where to go. So the trial must start **without a choice**: the server starts
it at the salon's first successful publish (§3.1).

**Both apps (§11 Q3).** The rule is not a platform branch: the Flutter Pro app
stops offering plan choice on iOS **and** Android (Google Play's payments
policy has the same steering rule for digital subscriptions — the reason
retained; the current Play policy text was not re-read, UNVERIFIED, as
[play-store-forms.md](play-store-forms.md) §3 records). So the picker,
the Android-only « …sur myweli.com » lines and `store_policy.dart` leave the
Flutter app; the web is the only place an offer is chosen.

**In scope**
- Backend: start the trial on a default tier at first publish when no offer
  exists; demo-lock offer changes and salon creation; the demo reset keeps the
  demo salon on a live Pro offer.
- Mobile (the Pro flavour): every plan-choice / purchase / upsell surface
  mapped on 2026-10-05 (§2.2) becomes a neutral state or disappears.
- Docs: contract, threat model, access module, App Store packet (§2, §8 notes,
  §0/§3 with the verified App Store Connect record).

**Out of scope**
- The web dashboard keeps its offer picker — it is where offers are chosen
  (§5, divergence recorded).
- In-app purchase (path (b)) — not for V1.
- Trial / expiry **emails** (outside the app — 3.1.3 allows communication
  outside the app) and the trial **push titles** (state facts, no link, no
  call to action; body « Ouvrez MyWeli Pro pour les détails. »). Unchanged.
- `SUBSCRIPTION_ENFORCEMENT` and the grace e-mail's « Passé ce délai… »
  accuracy (§11, minors).

## 2. UX & flows

### 2.1 The rule, as a test can read it

In the Pro app, on every platform, no text and no control may:
choose, switch, activate or upgrade an offer; show another tier, a price, a
trial promotion (« 3 mois offerts »), or an entitlement list; or point to a
place (web, support, e-mail, WhatsApp) to obtain or pay for an offer. Showing
the **current** tier, its status, its dates and its seats is allowed.

### 2.2 Surface by surface — before → after (exact copy)

Mapped by a four-sweep audit with one skeptic per sweep and a completeness
critic (2026-10-05, 9 agents); every row below was re-read in code.

**« Mon abonnement »** (`pro_subscription_screen.dart`, Profil → owner only).
The « Today » column is iOS; Android today also shows « Votre offre se gère
depuis votre espace professionnel sur myweli.com », « Réactivez votre offre
sur myweli.com », « Tarif personnalisé » and the ROI line — all gone too.

| State | Today (iOS) | After (both apps) |
|---|---|---|
| Setup (no offer — GET 404) | « Choisissez votre offre — 3 mois offerts » · « Votre salon reste gratuit pendant la configuration, mais une offre est nécessaire pour le publier. » · 3 offer cards with « Choisir » | Title « Pas encore d’offre active » · body « Votre offre démarre à la mise en ligne de votre salon. » · nothing else |
| Trial | banner « Essai gratuit — N jours restants » / « Offre Pro · se termine le {date} » + 3 cards (« 3 mois offerts », entitlements, « Changer d’offre ») + « Le changement d’offre conserve votre période d’essai. » | banner unchanged · seats bar « {used} / {cap} places » · **no cards** |
| Paid | « Offre {tier} active » / « Jusqu’au {date} » (or the dead « Paiement à jour ») + cards | « Offre {tier} active » / « Jusqu’au {date} » · seats bar · no cards |
| Grace | « Votre offre a expiré » / « Jusqu’au {date} avant la dépublication de votre salon. » + primary « Aide & Support » | « Votre offre a expiré » / « Période de grâce jusqu’au {date}. » · **no button** |
| Expired | « Offre expirée » or « Salon dépublié » / « Vos données sont intactes. » (+ unpublished line) + « Aide & Support » | same titles and lines · **no button** |
| Live Réseau | card « Ajouter un salon » / « Chaque salon a sa propre offre et son propre essai. » | card « Ajouter un salon » / « Un salon de plus dans votre compte. » |
| Footer | « Vos données ne sont jamais bloquées. » + secondary « Aide & Support » | « Vos données ne sont jamais bloquées. » · no button |
| After a choose | snackbars « Offre X choisie — 3 mois offerts ! » / « Vous êtes maintenant sur l’offre X. », and `_TrialUsedNotice` | unreachable — removed |

General help stays where it is: Profil → « Aide & Support » (every role,
every screen's normal help entry — not an offer surface).

**Onboarding** (`pro_onboarding_screen.dart`, `core/utils/onboarding.dart`)

| Today | After |
|---|---|
| Step « Choisissez votre offre » / « 3 mois offerts » → `/pro/subscription`, required to go live | Step **removed** from the checklist and from the go-live keys; « N étapes sur M » recomputes |
| Publish 409 `missing: [offer]` → snackbar « Choisissez votre offre avant la mise en ligne. » + action « Choisir » | Only reachable now for a salon whose offer **expired** (the server starts the trial otherwise): snackbar « La mise en ligne est indisponible : l’offre de votre salon n’est plus active. » · no action |
| Publish 403 `demo_account_locked` → « Une erreur est survenue. » | « Compte de démonstration — cette action est désactivée. » (the sentence the review notes already promise) |

The `api_pro_service.dart` message for `offer_required` changes with it: the
screen falls back to `onboarding.error` in other branches, so both places
carry the new sentence (the audit's refuted-then-confirmed trap).

**Invite a member** (`invite_member_sheet.dart`, `team_error_messages.dart`)

| Code | Today | After |
|---|---|---|
| `offer_required`, salon in setup | « Choisissez d’abord votre offre pour inviter votre équipe. » + « Choisir mon offre » | « Vous pourrez inviter votre équipe une fois votre salon en ligne. » · no button (see §11 Q4) |
| `offer_required`, offer expired | same | « Les invitations sont indisponibles : l’offre de votre salon n’est plus active. » · no button |
| `seat_limit` | « Toutes les places de votre offre sont occupées. » + « Changer d’offre » | same sentence · no button |
| `demo_account_locked` | « Une erreur est survenue. Réessayez. » | « Compte de démonstration — cette action est désactivée. » |

`InlineFeedback` is a live region — VoiceOver reads the sentence, so the
sentence itself must be neutral, not only the button gone.

**Add a salon** (live Réseau accounts only)

| Today | After |
|---|---|
| « …sa propre configuration : fiche, catalogue, équipe, offre et période d’essai. » | « …sa propre configuration : fiche, catalogue, équipe. » |
| « Réservé à l’offre Réseau. Le badge « Vérifié »… » | unchanged (states the plan the account has) |
| API `reseau_required` / `salon_limit` → « Une erreur est survenue. » | « L’ajout de salons n’est pas disponible avec l’offre actuelle. » / « Nombre maximal de salons atteint. » — also replaces the mock table's CTAs (« Passez à l’offre Réseau… », « Contactez-nous pour aller plus loin. ») |

Salon picker « Offre Réseau — un salon de plus dans votre compte »: unchanged
(state, shown only to a live Réseau account).

### 2.3 Flows

**iPhone-only salon, start to live.** Register → onboarding checklist without
an offer step → complete profile, pin, ≥3 services, ≥3 photos, hours →
« Mettre mon profil en ligne » → the server starts the 3-month trial on the
default tier and publishes → « Mon abonnement » shows « Essai gratuit — 89
jours restants ». No screen ever mentions choosing.
*(Corrected 2026-10-05: 89, not 90. The server sets `trialEndsAt` to exactly
publish + 90 days, and the app counts whole days left, truncated
(`SalonSubscription.trialDaysLeft`, `Duration.inDays`), so a read even a
second later gives 89. It gives 90 only if the phone's clock runs behind the
server's.)*

**Trial ends.** The existing J-14/J-7/J-1/grace e-mails and pushes run (they
are outside the binary or state-only). In the app: the grace then expired
states above, with no button. The salon pays through the existing « Nous
contacter » channel the e-mails carry; the admin marks it paid.

**Salon chose on the web first.** Unchanged: the web choice starts the trial
on the chosen tier; the app shows it.

### 2.4 States & edge cases
- **Expired salon re-publishing** (only with enforcement on): 409 `offer` →
  the neutral snackbar; never a second trial (§3.1 keeps one trial per salon).
- **Race web choice vs publish:** insert-if-absent (§3.1) — whoever writes
  first sets the trial; a later web choice just switches the tier, keeping the
  clock.
- **Demo account:** cannot change offer or create salons (§3.2); the reset
  keeps it on a live Pro offer, so the reviewer always sees « Offre Pro
  active ».
- **Old app builds** (Android internal testers): still choose before
  publishing — the row exists, the auto-start never fires. Compatible.
- **200 % text, VoiceOver:** removed controls reduce the screen; the new
  sentences are plain `Text` in existing components (no new widget).

## 3. API & contract

### 3.1 Publish starts the trial when no offer exists
`POST /providers/{id}/publish` — after the demo lock and the publish gate:
- every gate key passes **and** the salon has **no** subscription row →
  create the row (default tier, `trialEndsAt = now + 90 days`), then flip to
  `active`;
- a row exists but is not live (`expired`) → `missing: ['offer']` as today;
- *(added in review, 2026-10-05)* a `suspended` salon → 403
  `provider_suspended`, checked right after the demo lock, before the gate and
  before any trial start. Publish used to flip **every** non-active status to
  `active`, so an owner could undo an admin suspension (T17) in one call, and
  with this section that same call would also have minted a trial. Only the
  audited admin restore lifts a suspension. The defect predates this work;
  the publish-time trial made it worse;
- the row write is **insert-if-absent** in both repositories (Postgres
  `ON CONFLICT (provider_id) DO NOTHING`; in-memory must not replace an
  existing row) — today's `DO UPDATE SET tier` would let a racing publish
  overwrite a web choice.

**Default tier:** `reseau` when the owner account already owns another salon
whose Réseau offer is still live **at that publish** (the salon was added
under Réseau), else `pro`. A salon added under Réseau whose sibling's offer
lapsed before its first publish starts on `pro`.

`openapi.yaml`: the publish description and the 409 `offer` semantics; the
subscription GET 404 description (« setup — the trial starts at the first
publish or at the first choice »).

### 3.2 Demo locks
- `PUT /providers/{id}/subscription` → 403 `demo_account_locked` for the demo
  account's salon (its credential is public, and the web dashboard accepts
  it).
- `POST /me/salons` → 403 `demo_account_locked` for the demo account.

### 3.3 Demo reset
`DemoResetService` ensures the demo salon **has** a row (create if absent),
pins `tier = 'pro'`, `paidUntil = now + 30 days` — today it only updates an
existing row, so a demo recreated without a choice would show the setup state.

*Built with one deviation (2026-10-05): the **snapshot capture**
(`POST /admin/demo/snapshot`) pins the offer the same way, not only the reset.
A capture restarts the 7-day reset clock, so with the reset as the only
writer, a demo salon recreated and captured would have shown the setup state
for up to 7 days. With the capture pinning too, it shows « Offre Pro active »
from the moment it is captured. A row the capture creates gets the ordinary
`trialEndsAt = now + 90 days` as a fallback, so it still reads as live if the
resets ever stop (`demo_reset_service.dart` `_pinDemoOffer`; test « a demo
with NO offer row gets one at capture »).*

## 4. Data model
No migration. `provider_subscriptions` unchanged; one new write path (§3.1)
and the demo-reset upsert (§3.3).

## 5. Architecture & patterns
- Backend: the trial start lives in `SalonSubscriptionService`
  (`startDefaultTrial(providerId)`), called by `SalonProvisioningService.
  publish` — routes stay thin; the repository interface gains
  `createIfAbsent`.
- Mobile: **no platform branch** — the picker code, the Android-only copy and
  `store_policy.dart` are deleted, not gated (§11 Q3). The onboarding
  checklist simply has no offer step. Mocks mirror the server: the mock
  publish starts the trial when no offer exists, the mock team service keeps
  `offer_required` / `seat_limit`.
- Web: unchanged — **documented divergence** from "web mirrors app flow": the
  web is where offers are chosen and keeps forcing the choice before go-live.

## 6. Security & authz
- The auto-start runs only inside `publish`, which is owner-only
  (`Cap.salonPublish`) and only after the full publish gate — minting a trial
  still needs a complete salon, exactly as one tap on « Choisir » does today.
- Demo locks close two public-credential holes (tier switch survives the
  weekly reset; creating real draft salons).
- Threat model: T54 (offer state flips) gains the publish-time start; T69
  (demo account) gains the two locks.

## 7. Performance
One extra read + at most one insert on the first publish. Nothing else.

## 8. Testing plan
**Backend** — service + route tests: publish with no row → 200, row created
on `pro`, 90 days; Réseau-owner second salon → `reseau`; expired row → 409
`offer`, no new trial; existing row untouched; insert-if-absent race (both
repos); demo locks on PUT subscription and POST /me/salons (403); demo reset
creates and pins. Smoke funnel: keep A17–A19 (the web path) and add publish
without a choice → 200 + GET shows `trial`/`pro`.

**Mobile** — widget tests, the key ones run on **both** platforms
(`TargetPlatformVariant` with Android and iOS — no branch should exist, and the
variant proves it): « Mon abonnement » in setup / trial / paid / grace /
expired / live Réseau shows the after-copy and **nowhere** shows « Choisir »,
« Changer d’offre », « 3 mois offerts », « Choisissez votre offre »,
« Business » / « Réseau » cards, « Aide & Support », « myweli.com »;
onboarding has no offer step and can go live with every other step done;
the refused publish shows the neutral sentence and no action; the invite
sheet's four codes; the demo-locked messages; add-salon copy. A source pin
over the Pro screens forbids the removed strings outside the web. The
existing iOS tests that rely on « Changer d’offre » are rewritten, not
deleted. Every new guard is watched red by mutation on committed work.

**Built artifact** — rebuild the unsigned Pro app and grep its
`App.framework` strings for the forbidden phrases (the binary is what Apple
reviews).

*Pinned 2026-10-05.* The check is only meaningful under these conditions:

- **The build.** It must be built the way the store build is, with the API
  defines, for example `flutter build ios --release --no-codesign --flavor
  pro -t lib/main_pro.dart --dart-define=USE_API_BACKEND=true
  --dart-define=API_BASE_URL=https://api.myweli.com`. Without the defines,
  tree shaking reduces the app to the misconfigured-build screen (the
  reviewer measured about 5.6 MB, with no app strings at all), and every
  phrase counts 0 for the wrong reason.
- **The file.** Grep `Runner.app/Frameworks/App.framework/App` (the AOT
  snapshot), not `flutter_assets`. Pubspec assets are shared across flavours,
  so the consumer story art `promo_weekend.svg` (« Offre limitée »,
  « Voir l’offre ») ships in the Pro bundle too. It is a salon promotion for
  consumers, not a Pro offer.
- **The encodings.** Search the bytes as UTF-8, UTF-16LE and Latin-1. Dart
  stores a string with a character outside Latin-1, such as the apostrophe
  in « Changer d’offre », as UTF-16.
- **The phrases that must count 0.** The `removed` list of
  `mobile/test/infra/pro_subscription_no_pricing_test.dart`, plus the other
  removed sentences and the 3.1.1 price strings: « Le changement d’offre »,
  « Votre salon reste gratuit », « Chaque salon a sa propre offre »,
  « Contactez-nous », « Paiement à jour », « Choix impossible », « /mois »,
  « Sur devis », « Nous contacter », « FCFA par mois », « Abonnement
  Mensuel », « 3,500 ».
- **Not on the list, because they stay legitimately.** These are not the
  widget-test « nowhere » list above, which is scoped to « Mon abonnement »:
  « Choisir » alone (« Choisir une commune », « Choisir une date »),
  « Aide & Support » (the Profil help row), « myweli.com » (the site base URL
  and the legal links), and « Business » / « Réseau » (the label of the
  **current** tier).
- **The control.** The new sentences must each count at least 1. That proves
  the app's strings are actually in the file.

*Run 2026-10-05, 18:03 build (`App`, 11.5 MB, defines as above), re-read
independently on the same file.* Every phrase on the 0 list counts 0. Each of
the nine new sentences counts 1 (« Pas encore d’offre active », « Votre offre
démarre à la mise en ligne de votre salon. », « Période de grâce jusqu’au »,
« La mise en ligne est indisponible », « Compte de démonstration — cette
action est désactivée. », « Vous pourrez inviter votre équipe », « Les
invitations sont indisponibles », « L’ajout de salons », « Nombre maximal de
salons atteint. »). The legitimate phrases count « Choisir » 5, « Aide &
Support » 1, « myweli.com » 7, « Business » 4, « Réseau » 3. The reviewer also
calibrated the scan on the pre-change Pro build (16:06), where « Choisir mon
offre », « Changer d’offre » (UTF-16) and « Tarif personnalisé » each counted
1. That binary has since been overwritten, so this calibration was not re-read
here. The check runs again on the IPA that is submitted
([app-store-forms.md](app-store-forms.md) §11.3).

## 9. Rollout & scope discipline
1. PR #550 merged (owner's go).
2. One PR, separate commits: backend (§3) · mobile (§2) · docs.
3. Staging deploys on merge; **production needs the owner's go** and a
   working billing account. The backend change is backward compatible (old
   apps always choose first).
4. The production backend must run §3.1 **before** the build is submitted.
   The notes ask App Review to create a fresh account. Registration opens
   « Accueil », and from there the reviewer can open « Configurer mon
   profil » and take the salon live. Against the old backend, that publish
   returns 409 `missing: ['offer']`, and the app shows « …l’offre de votre
   salon n’est plus active. » for an offer that never existed.
   *(Corrected 2026-10-05: this said the fresh account "goes through
   onboarding". It does not; onboarding is optional, reached from the
   « Configurer mon profil » card. See app-store-forms.md §8.)*
5. Then §11 of app-store-forms.md: signed IPA, TestFlight, screenshots,
   review notes with the 3.1.3(f) sentence.

## 10. Definition of done
- [ ] Backend + mobile + docs per §3/§2, contract and T54/T69 updated.
- [ ] `dart analyze` / `flutter analyze` 0, format clean, all tests green,
      CI green.
- [ ] Each new guard watched red; mutations on committed work.
- [x] The rebuilt Pro binary contains none of the forbidden strings. The
      phrase list, the build defines and the encodings are pinned in §8.
      *Run on the 2026-10-05 18:03 unsigned build: 22 phrases at 0, 9
      control phrases present.* The check runs again on the IPA that is
      submitted (app-store-forms.md §11.3).
- [ ] app-store-forms.md §2 marked decided, §8 SUBSCRIPTION sentence in place,
      byte count re-checked.

## 11. Open questions (for the owner)
Answered by the owner on 2026-10-05 — every recommended option:

- **Q1 → merged.** PR #550 squash-merged as `f6ffb585`; this work branches
  from it (`feat/pro-companion-path`).
- **Q2 → at the first publish.** (Alternatives were:
  at salon creation (burns trial days during setup; e-mails abandoned drafts)
  · only through support (iPhone-only salons hit a wall the app cannot
  explain).)
- **Q3 → both apps.** (Rationale:
  Google Play's payments policy has the same steering rule for digital
  subscriptions; one behaviour, and the picker code leaves the Flutter app) ·
  iOS only (Android keeps the picker and « …sur myweli.com » until the Play
  submission).)
- **Q4 → after go-live.** The server rule stays (invites need a live offer);
  the app's sentence is neutral. (The alternative — setup salons inviting up
  to the Pro cap — would have changed the rule on every platform.)

**Minors noticed, not in this slice:** the Pro entitlement list advertises
WhatsApp/SMS reminders while messaging is off in production (web still shows
it); the grace e-mail promises unpublishing that enforcement-off never does;
owners registered by phone get notice "e-mails" addressed to a phone string;
`markPaid` starts paid months during a running trial; App Store Connect asks
for the EU trader status (DSA) and has new age-rating social-media questions.
