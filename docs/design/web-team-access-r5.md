# Web team access R5 — /pro/equipe, the invitation bridge, the offer picker & the role-shaped web

| | |
|---|---|
| **Status** | R5a Built (2026-07-12) — R5b next |
| **Owner** | Sadreddine |
| **Last updated** | 2026-07-12 |
| **PRD ref / phase** | Module `access` §5.4 (web parity) · pre-launch |
| **ROADMAP entry** | docs/ROADMAP.md — « Team access R5a / R5b » |
| **Skills checked** | myweli-web-guardrails (+ dev-guardrails cross-cutting) |

## 1. Goal & scope

R1–R4 shipped the whole team program server-side and in the Flutter app. R5 is the
**web parity slice** (§5.4: « Same flows on /pro/equipe (list, invite modal,
actions) and the invitation step in /pro/connexion; Collaborateur web =
own-calendar view »), in two PRs:

- **R5a — owner surfaces**: `/pro/equipe` (roster table, 3-step invite dialog,
  member actions), the **202 invitation bridge** in `/pro/connexion` (+ the
  public accept/decline), the **offer picker** on `/pro/abonnement` (replacing
  the legacy read), the publish-checklist `offer` key, the authed
  `ProInvitationsCard` on the dashboard, and the catalogue tab rename
  (« Équipe » → « Employés » — the artists tab must not collide with the
  members page).
- **R5b — role-shaped web**: a membership context over the `(dash)` layout,
  the capability-filtered sidebar, dashboard/journal/detail gating, the
  Collaborateur **own-calendar** view, the slim member Profil (identity +
  « Supprimer mon compte » — deletion parity for everyone), and the
  revoked-mid-session sign-out (`?motif=acces-retire` banner).

Flow parity with the app (team-access-r3-app.md §2 · r4 §3); **web-own desktop
design** — a dense table and a dialog where the app uses lists and bottom
sheets. All API access through the generated typed client + the pro BFF
(httpOnly cookies, no tokens in JS). No backend change: the contract already
carries every endpoint and DTO.

## 2. UX & flows (mirrors, with desktop deltas)

### 2.1 /pro/equipe (R5a)
Desktop table — Membre (initiales + e-mail) · Rôle (chip: Propriétaire ton or ·
Manager plein · Réception/Collaborateur contour) · Employé (« {artistName} »
pour un Collaborateur) · Statut (« Invitation envoyée · expire le {date} » /
« Expirée » rouge / « Accès révoqué ») · Actions (menu : « Changer le rôle » ·
« Renvoyer l'invitation ({n} restants) » (pending) · « Révoquer l'accès » avec
confirmation « {email} perdra immédiatement l'accès à {salon}. Son compte
MyWeli n'est pas supprimé. »). Propriétaire épinglé, inerte. En-tête : places
« {used} / {cap} » + barre. Quatre états (vide : « Invitez votre équipe » +
« Chaque membre a son propre accès. Les collaborateurs ne voient que leur
propre planning. »).

**Invite dialog** (`role="dialog"`, 3 étapes) : e-mail (validé, minuscule) →
3 cartes de rôle avec les résumés français verrouillés → Collaborateur ⇒
sélection de fiche + « Créer une fiche » inline. Erreurs = la table R3
(member_exists, offer_required (+CTA « Choisir mon offre »), seat_limit (+CTA),
invite_rate_limited, artist_required/not_found…). Succès → toast
« Invitation envoyée à {email}. »

### 2.2 Le pont de connexion (R5a)
`proLoginViaBackend` reconnaît le **202 {invitations}** (aujourd'hui il le
classe 502) et le passe SANS poser de cookies. `ProLoginOptions` gagne l'étape
`invitations` : cartes « {salonName} vous invite comme {roleLabel} » +
« Rejoindre » (accept public avec la preuve retenue en mémoire — credential
Google ou e-mail+code non consommé — 200/201 posent les cookies comme un
login) / « Refuser » (liste vide → retour aux options). Multi-invitations
post-connexion : `ProInvitationsCard` sur le tableau de bord (visible si > 0).

### 2.3 L'offer picker (R5a)
`/pro/abonnement` reconstruit sur GET/PUT `/providers/{id}/subscription` :
setup (404) → « Choisissez votre offre — 3 mois offerts » + 3 cartes (ancrages
barrés 70 000 / 120 000 FCFA/mois · Réseau « Sur devis » sélectionnable,
« Multi-salons — bientôt disponible » · « Tarif personnalisé »; places
5/15/15; avantages; ROI sur Pro) · bannières trial / paid / **grâce (ambre,
urgent : « Votre offre a expiré — {date} avant la dépublication » + WhatsApp)**
/ **expiré+dépublié (rouge : « Salon dépublié — contactez-nous pour
réactiver »)** · barre de places · `trial_used` · « Le changement d'offre
conserve votre période d'essai. ». Checklist de mise en ligne : étape
« Choisissez votre offre »; publish 409 `missing:['offer']` → message + CTA.

### 2.4 Le web par rôle (R5b)
Contexte membership (fetch /api/pro/me au montage + à CHAQUE navigation — la
sonde de révocation) → sidebar filtrée par capacité (Aujourd'hui/Rendez-vous
toujours · Clients clients.view · Catalogue catalogue.manage · Disponibilités
availability.manage · Avis profile.manage · Revenus finances.view · Abonnement
subscription.manage · Équipe members.manage · Profil pour TOUS) + bloc
identité membre (e-mail + chip + salon). Dashboard : rangée argent seulement
avec finances.view; GoLiveCard/Configurer réservés owner. Collaborateur :
« {salonName} — votre planning », journal mono-colonne (le serveur filtre),
pas de création/drag, actions Terminé/Absent uniquement. Profil membre =
vue personnelle (identité + « Supprimer mon compte »). Révoqué →
`/pro/connexion?motif=acces-retire` + « Votre accès à ce salon a été
retiré. ».

## 3. API & contract (consumed; already generated in schema.ts)
Members/invitations families · public accept/decline · the 202 branches ·
GET/PUT /providers/{id}/subscription · /me/provider `membership`. New BFF
routes: /api/pro/members*, /api/pro/invitations*, /api/pro/salon-subscription,
/api/pro/auth/invitations/accept|decline. Legacy /api/pro/subscription
(/me/subscription) removed.

## 4. Security
202 NEVER sets cookies (regression-tested) · proof kept in memory only ·
httpOnly cookies unchanged · UI gating is convenience (server 403s; deep links
render error states) · no PII in URLs (the revoked banner is generic) ·
/pro stays noindex.

## 5. Testing
Unit: team helpers (every machine code), offer cards/banners, checklist offer
key, the 202 BFF passthrough (no set-cookie), nav filtering per role,
actionsForMembership. RTL: login invitations step, invite dialog, revoked
context path. E2e (hermetic stub): the team layer (stateful members/
invitations/offer + 202 bridge + role tokens `pro-{role}-access` + revoked
set) — journeys: roster/invite/gates/revoke/offer arc/publish gate/login
bridge (R5a ≈ +7) and manager/réception/staff/revoked/identity block
(R5b ≈ +5). Suite 55 → ≈67.

## 6. Rollout
R5a then R5b (immediately — in the window a web member sees an owner-shaped
sidebar whose pages 403 into error states). Parity note: the web member
profile is the slim identity view + account deletion; data export stays
owner-only.

## 7. Open questions
None — pricing/UX decisions carried from R3/R4 sign-offs.
