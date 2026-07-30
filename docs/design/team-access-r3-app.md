# Team access R3 — the pro app's team & offers UI

| | |
|---|---|
| **Status** | Built (2026-07-12) |
| **Owner** | Sadreddine |
| **Last updated** | 2026-07-12 |
| **PRD ref / phase** | Module `access` (docs/modules/access.md §5.1–5.2, §10 A2/R2 "screens = R3/R5") · pre-launch |
| **ROADMAP entry** | docs/ROADMAP.md — « Team access R3 » |
| **Skills checked** | myweli-dev-guardrails (app slice — no backend change) |

## 1. Goal & scope

R1/R2a/R2b (PRs #222/#223/#224) shipped the whole server side of team access: memberships,
salon offers and the invitation lifecycle. **R3 makes it usable in the pro app** — the five
user-facing pieces the flows need:

1. **Équipe screen** — the owner lists members, invites (email → role → artist link),
   resends, changes roles, revokes.
2. **Login « Invitations » step** — an invited person signs in with the NORMAL login
   (Google / email code) and gets « {Salon} vous invite » instead of « compte
   introuvable »; accepting creates the bare member account and a live session.
3. **Authed invitations surface** — a signed-in pro sees pending invitations
   (Profil → « Invitations », badge) and can accept/decline.
4. **Offer picker on « Mon abonnement »** — the pricing pivot's user-facing half:
   choose Pro / Business / Réseau (3 mois offerts), see trial/paid/grace/expired
   states, seats, and the manual-payment contact path.
5. **Publish-gate mirror** — the onboarding checklist gains the « Choisissez votre
   offre » step (server gate key `offer`).

**Out of scope (R4):** role-shaped experiences (Manager/Réception trimming,
Collaborateur « Ma journée »), the revoked-mid-session global handler, a
membership-aware `/me/provider`. Until R4, every member lands in the
owner/manager-shaped app; the server remains the authority (403s on forbidden
calls). **R5** = web parity, **R6** = multi-salons.

**No backend changes.** Everything consumed here is live and contract-verified.

## 2. UX & flows

### 2.1 Owner — Équipe (`/pro/team`, entry: Profil → « Équipe », icône groupe)

- **States**: loading (LoadingIndicator) · error (EmptyState + Réessayer) · empty
  (« Invitez votre équipe » — « Chaque membre a son propre accès. Les collaborateurs
  ne voient que leur propre planning. » CTA « Inviter un membre ») · list.
- **Header**: seats « {used} / {cap} places » + fine progress bar (offer state).
- **Rows**: initials avatar · email · role chip (Propriétaire or, Manager plein,
  Réception/Collaborateur contour) · staff → « Employé : {artistName} » · pending →
  badge « Invitation envoyée » + « Expire le {date} » ; expirée → badge « Expirée »
  (rouge). Owner row pinned first, inert.
- **Invite (bottom sheet, 3 étapes)**: e-mail (validé, minuscule) → rôle (3 cartes,
  résumés en français clair) → si Collaborateur : « Associer à un employé » (picker
  des fiches + « + Créer une fiche » inline, nom seul). Succès → snackbar
  « Invitation envoyée à {email} ». `offer_required`/`seat_limit` → message + CTA
  vers `/pro/subscription`.
- **Actions (sheet on row tap)**: « Changer le rôle » · « Renvoyer l'invitation
  ({n} restants) » (pending seulement) · « Révoquer l'accès » → confirmation
  destructive « {email} perdra immédiatement l'accès à {salon}. Son compte MyWeli
  n'est pas supprimé. »

### 2.2 Invitee — the login bridge (critical path)

Login (Google ou code e-mail) → 202 `{invitations}` → étape « Invitations » dans le
même écran de connexion : carte(s) « {salonName} vous invite comme {roleLabel} » +
expiration → « Rejoindre » (compte membre créé sans salon, session, snackbar
« Bienvenue dans l'équipe de {salonName} ! », dashboard) / « Refuser » (carte retirée;
liste vide → retour au flux « Créer un compte » actuel). L'identité déjà prouvée est
RÉUTILISÉE : idToken Google conservé en mémoire, ou e-mail+code (le code survit au 202
côté serveur et n'est consommé que par l'accept). Plusieurs invitations : la première
acceptation authentifie et route au dashboard; les autres restent accessibles via
Profil → « Invitations » (chemin simple, assumé).

### 2.3 Authed — Profil → « Invitations » (`/pro/invitations`)

Visible seulement si count > 0 (badge). Cartes identiques; accept → « Vous avez
rejoint {salonName} » (pas de changement de navigation — le sélecteur multi-salons
est R6); decline retire la carte. Vide → « Aucune invitation en attente ».

### 2.4 Offer picker — « Mon abonnement » (rebuild)

- **Setup (404 `no_offer`)**: « Choisissez votre offre — 3 mois offerts » +
  « Votre salon reste gratuit pendant la configuration, mais une offre est
  nécessaire pour le publier. » + 3 cartes.
- **Cartes** (décisions utilisateur 2026-07-12): prix d'ancrage barrés — Pro
  70 000 FCFA/mois · Business 120 000 · Réseau « Sur devis » (sélectionnable;
  notes « Multi-salons — bientôt disponible » · « Tarif personnalisé »). Places :
  5 / 15 / 15 par salon. Checklists d'avantages (config). « 3 mois offerts ».
- **États**: trial (jours restants + date de fin) · paid (« jusqu'au {date} ») ·
  **grace** (bannière URGENTE ambre « Votre offre a expiré — {date} avant la
  dépublication » + CTA WhatsApp) · **expired + unpublishedForBilling** (bannière
  rouge « Salon dépublié — contactez-nous pour réactiver » + CTA WhatsApp).
- Changement d'offre : « Le changement d'offre conserve votre période d'essai. » ;
  `trial_used` → « Votre essai gratuit a déjà été utilisé. » + « Nous contacter ».
- Barre de places {used}/{cap}. Garde : `providerId == null` → écran réservé au
  propriétaire (les membres n'ont pas d'offre à gérer — R4 affinera).

### 2.5 Publish-gate mirror

Onboarding : étape « Choisissez votre offre » (3 mois offerts) → `/pro/subscription`;
bloque « Mettre mon profil en ligne » tant que l'offre n'est pas vivante
(trial/paid/grace). Un publish refusé 409 avec `missing: ['offer']` → snackbar
« Choisissez votre offre avant la mise en ligne. » + action « Choisir ».

## 3. API & contract (consumed, unchanged)

`GET/POST /me/provider/members` · `PATCH /me/provider/members/{id}` ·
`POST …/revoke|resend` · `GET /me/provider/invitations` ·
`POST /me/provider/invitations/{id}/accept|decline` ·
`POST /auth/provider/invitations/accept|decline` (proof: `idToken` | `email`+`code`;
200/201 ProviderSession) · 202 `{invitations}` sur `/auth/provider/google` et
`/auth/provider/email/otp/verify` · `GET/PUT /providers/{id}/subscription`
(404 = setup; 409 `trial_used`). DTOs: `TeamMember`, `TeamInvitation`,
`SalonSubscription` — modèles Dart champ-à-champ.

## 4. Data model

App-side only — three new Equatable models mirroring the DTOs
(`team_member.dart`, `team_invitation.dart`, `salon_subscription.dart`) plus
`provider_login_result.dart` (sealed `InvitationProof`). No storage change: the
invitation proof lives in memory only (never persisted — short-lived credential).

## 5. Architecture & patterns

`models → services (interface + mock + api) → providers → screens` respected:

- **`ProTeamServiceInterface`** (new trio) — members CRUD + authed invitee methods;
  API on `RefreshingHttpClient` (`myweli_provider_session`); mock enforces every
  gate with the SAME machine codes over `MockData.teamMembers/teamInvitations`.
- **Auth bridge** — the 3 pro login methods return `ProviderLoginResult`
  (signedIn | invited | failure); public accept/decline live on
  `AuthServiceInterface` (session persistence is the auth service's job; accept
  succeeds on 200 AND 201). Apple: no 202 in the contract → never `.invited`.
- **Subscription rework** — `getSalonSubscription(providerId)` + `chooseOffer`
  replace the legacy `/me/subscription` read (endpoint stays for web). Mock
  defaults to the SETUP state so the whole arc is demo-able offline.
- Providers: `ProTeamProvider` (new) · `ProAuthProvider` (+ pending invitations +
  proof) · `ProSubscriptionProvider` (rework). DI/router/main_pro wiring per the
  existing idiom.

## 6. Security & authz

- The invitation **proof** is never persisted (memory only); the email code is
  consumed only by accept (mirrors the server, T37).
- UI gating (`providerId == null` guards, hidden rows) is **convenience only** —
  the server enforces `members.manage`/ownership on every call (T36/T38).
- No secrets/PII in logs; errors branch on machine codes with French copy
  (`core/utils/team_error_messages.dart`, shared by mock and api so copy can't
  drift).

## 7. Errors (machine code → French copy)

| code | copy |
|---|---|
| member_exists | Cette personne est déjà dans l'équipe. |
| offer_required | Choisissez d'abord votre offre pour inviter votre équipe. (+ CTA) |
| seat_limit | Toutes les places de votre offre sont occupées. (+ CTA) |
| invite_rate_limited | Trop d'invitations envoyées aujourd'hui. Réessayez demain. / (resend) Budget de renvois épuisé pour cette invitation. |
| owner_protected | Le propriétaire ne peut pas être modifié. |
| invitation_expired | Cette invitation a expiré. Demandez au salon de la renvoyer. |
| artist_required | Choisissez la fiche employé du collaborateur. |
| artist_not_found | Fiche employé introuvable. Actualisez et réessayez. |
| trial_used | Votre essai gratuit a déjà été utilisé. Contactez-nous pour activer votre offre. |

Role summaries (invite cards): Manager « Gère les rendez-vous, le catalogue et les
disponibilités. Ne voit pas les revenus. » · Réception « Gère le planning et le
fichier clients. Pas de catalogue ni de réglages. » · Collaborateur « Voit
uniquement son propre planning. »

## 8. Testing

Unit: model parses (+fallbacks) · mock gates for EVERY code · `ProTeamProvider`
flows · auth 202 bridge on both routes (code NOT consumed; proof retention; accept
persists on 200 and 201; decline-to-empty fallback) · subscription
setup→choose→trial, clock-keeping switch, trial_used, grace/expired · onboarding
offer step + publish `offer_required`. Widget: Équipe list/empty/error + actions +
revoke copy · invite sheet 3 steps (+ inline fiche create + offer_required CTA) ·
login invitations step (accept → dashboard; decline fallback) · offer picker states
· authed invitations screen. Patterns: serviceLocator override, `settle()` pump
(BrandLoader never settles), `MockData.resetTeam()` per test.

## 9. Rollout

One PR on `feat/team-access-r3-app`: mock default becomes the setup state
(intentional — demos the R2a arc); bare member accounts show an empty business
name until R4 (known); docs (this spec + README index + module §10 + ROADMAP) in
the same PR. R4 (role-shaped app) follows.

## 10. Open questions

- Entitlement wording on the offer cards is provisional config
  (`SubscriptionPlans`) — one-line review with the user at PR time.
- Launch prices replace the anchors in one config file when pricing is confirmed
  (OQ-2).
