# L'intégrité du serveur, lot 6 — spec

| | |
|---|---|
| **Statut** | **PR A construite le 2026-10-21** sur `fix/backend-batch-6` (#676 — B6.1, B6.2, B6.8, B6.9, B6.10 — §10), **pas déployée** ; PR B, C, D à suivre, puis un déploiement (demandé avant). Validé le même jour — Q1 (décision 17) : **effacer les numéros et l'adresse, garder le nom et l'historique** ; Q2 (décision 18) : **effacer le KYC de la démo à la remise** ; Q3 (décision 19) : **5–80 %** ; Q4 (décision 20) : **Propriétaire et Gérant, la même file marquée** ; Q5 : **Apple construit maintenant, inactif sans clé** ; Q6 : **le reste tel qu'écrit** (décision 22 : l'alerte, pas de recréation) |
| **Owner** | Sadreddine |
| **Last updated** | 2026-10-21 |
| **PRD ref / phase** | Serveur (V1) — BACKEND.md §3 (authz, refus par défaut, validation), §7 (modèle de menaces) · App Store 1.2 (signaler un contenu), 5.1.1(v) (suppression de compte) |
| **Module** | `backend/` (routes, services, dépôts, migrations, `infra/gcp/`) ; clients pour B6.5 et B6.6 (app Pro, web Pro) |
| **Origine** | [BACKLOG.md](../BACKLOG.md) lot 6 : B6.1–B6.10 (décisions 17, 18, 19, 20, 22) |
| **Skills checked** | myweli-backend-guardrails ✓ · myweli-dev-guardrails ✓ · myweli-web-guardrails ✓ |

## 1. Le constat — relu sur le vrai chemin de code (main `389db7c`)

Les dix points sont **réels**. Un seul a bougé depuis le backlog (B6.5).

| # | Défaut | Où |
|---|---|---|
| B6.1 | `POST /appointments` ne vérifie que la session : un jeton **Pro ou admin** réserve, écrit sous son propre identifiant (`appointments.user_id` est un texte sans clé étrangère) — un rendez-vous qu'aucun client ne voit et qui notifie le salon. `review.dart` refuse déjà tout rôle autre que `user` | `routes/appointments/index.dart:24-39`, `migrations.dart:71` |
| B6.2 | Accepter une invitation **morte** (expirée, retirée, adressée à un autre e-mail, ou à l'identité de démo) crée d'abord le compte Pro (`createMemberAccount`), puis refuse — et rien ne l'efface. À la connexion suivante, ce compte sans appartenance passe par l'auto-réparation de `GET /me/provider` : `ensureSalon` lui crée **un salon vide** | `routes/auth/provider/invitations/accept.dart:94-107`, `team_service.dart:355-367`, `routes/me/provider/index.dart:80-86` |
| B6.3 | Supprimer un compte propriétaire passe ses salons en `draft`, efface les pièces KYC, les appareils, les notifications — mais **le salon garde le téléphone, le WhatsApp, l'adresse et le numéro Mobile Money** de la personne | `provider_account_service.dart:105-118` |
| B6.4 | Le dépôt KYC n'a **aucun verrou de démo**, et la remise à zéro hebdomadaire de la démo (profil, agenda, clients, offre) **ne touche pas au KYC** : les pièces d'un relecteur restent dans `kyc/<compte>/`, et l'état reste « en attente » | `kyc_service.dart:43`, `demo_reset_service.dart:94-145` |
| B6.5 | **Le web a rejoint l'app le 2026-10-20** (curseur 5–80 %, `web-pro-deposit-app-rules.md`) ; reste : le **serveur** accepte 0–100 %, et le web garde un message mort « Pourcentage invalide (1–100 %) ». Et un **opérateur retiré du catalogue bloque tout enregistrement** — même acompte désactivé — par un `invalid_input` sans champ | `provider_catalog_service.dart:776-812`, `web/lib/pro/deposit.ts:88-112` |
| B6.6 | Le seul « Signaler » est celui du client (`principal.role != 'user'` → 403). L'écran « Avis » du salon, app et web, n'en a pas (App Store 1.2) | `routes/reviews/[id]/report.dart:16`, `routes/me/provider/reviews.dart` |
| B6.7 | Aucun appel de révocation Apple, aucun client n'envoie l'`authorizationCode` : après suppression, MyWeli reste dans « Apps utilisant l'identifiant Apple » (5.1.1(v)) | — (absent) |
| B6.8 | Trois gardes sans déclencheur vivant : (a) `ensureOwner` **diverge** — Postgres fait `ON CONFLICT (provider_id, email) DO UPDATE SET account_id` (une ligne d'un autre rôle, révoquée ou invitée, est rattachée au compte et **garde son rôle**), la mémoire ajoute une deuxième ligne ; (b) `ensureSalon`, chemin « déjà lié », écrit une ligne propriétaire **sans vérifier qui possède le salon** (T72, fermé à la route) ; (c) `changeRole` ne regarde pas le **statut** : un membre révoqué change de rôle | `postgres_membership_repository.dart:63-83`, `membership_repository.dart:237-260`, `salon_provisioning_service.dart:84-88`, `team_service.dart:231-270` |
| B6.9 | Le cron de maintenance répond `demoReset: false` **aussi bien** quand ce n'est pas le jour **que** quand la remise est refusée (`not_demo_owned`) ; la ligne `demo_reset REFUSED` n'a pas d'alerte | `maintenance_tick.dart:46-51`, `demo_reset_service.dart:111-117` |
| B6.10 | La suppression d'un compte **Pro** a son test sur le vrai schéma (« victime + témoin ») ; celle d'un compte **client** non | `test/db/postgres_repositories_test.dart:2095` |

## 2. Ce qui change

### 2.1 Réserver est un geste de client (B6.1)
`POST /appointments` → **403 `forbidden`** si le rôle n'est pas `user`, avant
toute lecture du corps (le modèle de `review.dart`). `GET` ne change pas (le
salon lit son agenda par ce même chemin). Contrat : le 403 du POST.

### 2.2 Une invitation morte ne crée plus de compte (B6.2)
`TeamService.checkAcceptable(invitationId, email)` — **lecture seule**, les
quatre contrôles d'`accept` (introuvable, autre adresse, identité de démo,
expirée) — tourne **avant** `createMemberAccount`. Si `accept` échoue quand
même (une course : retirée entre les deux), le compte qui vient d'être créé
est **supprimé** avant de répondre. Les réponses ne changent pas.

### 2.3 Le salon d'un propriétaire supprimé perd ses numéros (B6.3, décision 17)
Après la boucle de dépublication, pour chaque salon possédé :
`phoneNumber` et `address` vides, `whatsapp`, `depositMobileMoneyNumber` et
`depositMobileMoneyOperator` à `null`, `depositRequired` à `false` (un
acompte sans numéro n'a pas de sens). **Gardés** : le nom, l'historique
(rendez-vous, avis, fiches clients). Une méthode de dépôt `eraseContact`
(les deux jumeaux), dans la même transaction pour la colonne `address` et le
document. **Politique de confidentialité** : une phrase dans « Si vous êtes
professionnel » (§8).

### 2.4 La démo oublie le KYC d'un relecteur (B6.4, décision 18)
À la remise hebdomadaire, pour le **compte propriétaire de la démo** :
`resetKyc` — pièces vidées, état `pending`, motif de refus effacé — et les
objets `kyc/<compte>/` supprimés par la boucle de suppression existante (clé
préfixée, une erreur de stockage ne bloque pas). Le compte reste celui de la
démo (vérifié deux fois, comme le reste de la remise).

### 2.5 Une seule plage d'acompte, et un opérateur retiré ne bloque plus (B6.5, décision 19)
- **Le serveur** applique la plage choisie (Q3) **quand l'acompte est
  exigé et que le pourcentage change** : une valeur enregistrée avant reste
  acceptée telle quelle tant qu'on n'y touche pas (sinon, changer le délai
  d'annulation serait refusé à un salon qui a 90 % depuis des mois). Hors
  plage → `400 invalid_percentage`, sous le curseur.
- **Acompte désactivé** : l'opérateur n'est plus contrôlé contre le
  catalogue (il ne sert à rien) — l'enregistrement passe.
- **Acompte exigé**, opérateur retiré : `400 operator_unavailable` ; l'app et
  le web le disent **sous le champ opérateur** (« Cet opérateur n'est plus
  proposé. Choisissez-en un autre. »).
- Le web perd son message mort « (1–100 %) ».

### 2.6 Le salon peut signaler un avis (B6.6, décision 20)
- **Serveur** : `POST /me/provider/reviews/{id}/report` — derrière la même
  barrière d'appartenance que la lecture, et la capacité choisie (Q4) ;
  l'avis doit être **un avis de ce salon** (sinon 404). Il réutilise
  `ModerationService.report` ; migration : `review_reports.reporter_kind`
  (`user` | `salon`, défaut `user`), le salon enregistré comme rapporteur
  (unicité par avis et par salon). La file d'administration montre
  « Signalé par le salon ».
- **App Pro et web Pro** : « Signaler » sur chaque avis de l'écran « Avis »,
  avec les mots du client (« Signaler cet avis ? », « Raison (optionnel) »,
  « Merci. Notre équipe va examiner cet avis. », « Le signalement a échoué.
  Réessayez. »).

### 2.7 Révoquer le jeton Apple à la suppression (B6.7)
Selon Q5 :
1. **Toi** : une clé « Sign in with Apple » (`.p8`) dans Apple Developer,
   rangée dans Secret Manager (son identifiant, l'équipe, la clé).
2. Les clients envoient l'`authorizationCode` à la connexion Apple.
3. Le serveur l'échange contre un jeton de rafraîchissement, **gardé par
   compte** (migration, chiffré au repos par le stockage), et le **révoque**
   à la suppression (client et Pro). Sans clé configurée : rien n'est
   échangé ni révoqué, une ligne de journal le dit — rien ne casse.

### 2.8 Trois gardes (B6.8)
- **(a) `ensureOwner`, refus par défaut, pareil dans les deux jumeaux** :
  une ligne active de propriétaire pour ce compte → rendue ; **toute autre
  ligne** pour cette adresse dans ce salon (un autre rôle, révoquée,
  invitée) → **refus** (`StateError`, jamais une réécriture) ; aucune ligne →
  création. Un test « contrat des jumeaux » les fait passer tous deux par les
  mêmes cas.
- **(b) `ensureSalon`** : avant d'écrire la ligne propriétaire sur le chemin
  « déjà lié », vérifier que le salon n'a **pas d'autre propriétaire** ;
  sinon, refus et une ligne `ensure_salon REFUSED` (T72 en défense en
  profondeur).
- **(c) `changeRole`** sur un membre révoqué → **409 `member_revoked`**
  (contrat), à côté de B7.5 côté app.

### 2.9 Savoir quand la démo est perdue (B6.9, décision 22)
- La réponse du cron dit **pourquoi** : `demoReset: "ran" | "not_due" |
  "refused:not_demo_owned" | "no_snapshot"`.
- Une **alerte de journal** sur `demo_reset REFUSED`, copiée de
  `96-rebuild-hook-alert.sh` (script `infra/gcp/84-demo-reset-alert.sh`) — sa
  création sur GCP est une mutation : **demandée avant**.
- Pas de recréation automatique de l'identité (décision 22, recommandé).

### 2.10 La suppression d'un compte client sur le vrai schéma (B6.10)
Un test Postgres : une **victime** et un **témoin** (rendez-vous, avis,
favoris, appareils, notifications, signalements, idempotence), la
suppression par les vrais dépôts ; la victime n'a plus rien, le témoin a tout.
Tests seulement.

## 3. Le contrat (openapi.yaml)

- `POST /appointments` : **403 `forbidden`** (rôle autre que client).
- `PUT /providers/{id}/deposit-policy` : **400 `invalid_percentage`**,
  **400 `operator_unavailable`**.
- **Nouveau** `POST /me/provider/reviews/{id}/report` : 200
  `{status: "reported"}` · 400 `invalid_input` (raison > 500) · 401 · 403
  (pas membre, ou pas la capacité) · 404 (pas un avis de ce salon).
- `PATCH /me/provider/members/{id}` (rôle) : **409 `member_revoked`**.
- `POST /internal/cron/maintenance` : `demoReset` devient une chaîne.
- B6.7 : `authorizationCode` facultatif sur les connexions Apple (client et Pro).

## 4. Sécurité — le modèle de menaces (BACKEND.md §7)

- **B6.1** : nouvelle ligne — « un jeton non client écrit un rendez-vous
  invisible » (E), atténuée par le refus de rôle.
- **B6.2** : « un lien d'invitation mort fabrique un compte puis un salon »
  (T), atténuée.
- **B6.6** : nouveau point d'entrée ; barrière d'appartenance + capacité +
  « l'avis est de ce salon » (un salon ne signale pas les avis d'un autre) ;
  idempotent par avis et par salon, comme le signalement client l'est par
  avis et par client (ni l'un ni l'autre n'a de limite de débit aujourd'hui).
- **B6.7** : un secret de plus (la clé `.p8`), jamais dans le dépôt ; les
  jetons de rafraîchissement Apple sont des secrets au repos — supprimés avec
  le compte.
- **B6.8** : T72 gagne une deuxième barrière (b) ; (a) supprime une
  réécriture silencieuse de rôle.

## 5. Données et migrations

- `review_reports.reporter_kind text NOT NULL DEFAULT 'user'` (B6.6) ;
  l'unicité devient `(review_id, reporter_kind, reporter_user_id)`.
- B6.7 : `apple_refresh_tokens (account_kind, account_id, token, created_at)`,
  supprimé en cascade avec le compte.
- Toutes **additives**, réversibles, sous les délais de verrouillage du dépôt
  (`migration_timeouts`).

## 6. Les tests (rouges d'abord)

- Routes : B6.1 (user 201, provider 403, admin 403, anonyme 401) ; B6.2
  (chaque invitation morte : aucun compte créé ; la course : le compte
  supprimé) ; B6.6 (membre avec et sans capacité, avis d'un autre salon → 404,
  idempotent) ; B6.8(c) (409).
- Services : B6.3 (les champs effacés, le nom et l'historique gardés, les
  salons dont on n'est que membre intacts) ; B6.4 (pièces et objets effacés,
  le KYC d'un autre compte intact) ; B6.5 (plage, valeur ancienne gardée,
  opérateur retiré acompte off/on).
- Jumeaux : `ensureOwner` (a) — mêmes cas, mêmes réponses, Postgres et mémoire.
- Postgres : B6.10 ; les migrations (aller, retour).
- Clients : app et web — « Signaler » (B6.6), `operator_unavailable` sous le
  champ, le message mort retiré (B6.5).
- **Mutations** : chaque garde retirée, chaque champ non effacé, le KYC non
  effacé, la plage ignorée, le catalogue contrôlé acompte off, le
  « signaler » sans capacité ou sans « avis de ce salon », le cron qui ne dit
  pas pourquoi.

## 7. La livraison

**Quatre PR**, puis **un déploiement du serveur** (demandé avant, comme
toujours) :
- **(A) Les gardes** — B6.1, B6.2, B6.8, B6.9 (code + script d'alerte),
  B6.10. Aucune décision sauf la 22.
- **(B) Les données** — B6.3, B6.4, B6.5 (serveur + app + web). Décisions 17,
  18, 19.
- **(C) Les signalements du salon** — B6.6 (serveur + migration + app + web).
  Décision 20.
- **(D) Apple** — B6.7, selon Q5.

Les changements d'app partent avec la prochaine version des stores.

## 8. Les mots

- B6.3, politique de confidentialité (« Si vous êtes professionnel ») :
  « Si vous supprimez votre compte, votre salon est retiré de MyWeli. Son nom
  et son historique — rendez-vous et avis — restent, pour vos clients ; ses
  numéros de téléphone, WhatsApp et Mobile Money et son adresse sont
  effacés. »
- B6.5 : « Cet opérateur n'est plus proposé. Choisissez-en un autre. » ;
  hors plage : « Choisissez un pourcentage entre 5 et 80 %. » (selon Q3).
- B6.6 : les mots du client (§2.6) ; la file d'administration :
  « Signalé par le salon ».

## 9. Questions au propriétaire

- **Q1 (décision 17)** — Un propriétaire supprime son compte : **effacer le
  téléphone, le WhatsApp, le numéro Mobile Money et l'adresse du salon, et
  garder le nom et l'historique** (recommandé), ou laisser le salon tel quel ?
- **Q2 (décision 18)** — Le KYC d'un relecteur sur la démo : **l'effacer à la
  remise hebdomadaire** (recommandé — le relecteur peut essayer le parcours),
  ou **refuser** le dépôt KYC sur la démo, comme la mise en ligne et
  l'invitation ?
- **Q3 (décision 19)** — Une seule plage d'acompte : **5–80 %** (recommandé —
  celle de l'app et, depuis le 2026-10-20, du web), 1–100 %, ou une autre ?
- **Q4 (décision 20)** — Les signalements du salon : **la même file que ceux
  des clients, marqués « Signalé par le salon », réservés au Propriétaire et
  au Gérant** (recommandé — la capacité `profile.manage`), ou ouverts à tout
  membre ?
- **Q5** — Apple (B6.7) : **construire maintenant, inactif tant que la clé
  n'existe pas** (recommandé — tu crées la clé ensuite), ou attendre la clé ?
- **Q6** — Le reste tel qu'écrit : la décision 22 (l'alerte, pas de
  recréation), les quatre PR, les mots ?

**Décisions (2026-10-21).** Q1 à Q6 : les recommandations, telles qu'écrites.

## 10. PR A construite (B6.1, B6.2, B6.8, B6.9, B6.10) — ce qui a été vu

**Comme écrit**, avec ces précisions :
- **B6.2, la course** : le compte créé pour une invitation morte entre le
  contrôle et l'acceptation est supprimé **par `ProviderAccountService`**, le
  seul chemin d'effacement qui porte le verrou de la démo. Un premier jet
  appelait le dépôt directement : le test d'inventaire des verrous de la démo
  l'a refusé (« une nouvelle porte vers `deleteAccount` »). La route est
  inscrite dans l'inventaire comme appelante **du service**.
- **B6.2, ce que le contrôle préalable garde** : sans lui, la course
  supprimerait quand même le compte — mais le **code e-mail** serait consommé
  par `createMemberAccount`. Un test le montre : une invitation morte laisse
  le code vivant pour une invitation valide d'un autre salon.
- **B6.8a** : en Postgres, deux moitiés, chacune nécessaire — le compte déjà
  membre du salon sous **une autre adresse** est vérifié avant ; toute ligne
  pour **cette** adresse (et une insertion concurrente) est le
  `ON CONFLICT DO NOTHING` de l'insertion, qui ne rend alors rien : refus. Le
  premier jet vérifiait tout avant, et la clause d'insertion ne servait
  jamais — une mutation l'a montré. Le contrat des jumeaux a six cas
  (création, rendu, invitée, révoquée, autre rôle, autre adresse).
- **B6.8b** : `SalonProvisioningService` prend un `log` (comme la remise de la
  démo) pour sa ligne `ensure_salon REFUSED`.
- **B6.9** : `tickIfDue` rend aussi `outcome` ; le script
  `infra/gcp/84-demo-reset-alert.sh` est écrit et vérifié par les tests
  d'infrastructure (JSON valide, le texte filtré existe dans le code), **pas
  créé sur GCP** : c'est une mutation, demandée après le déploiement.
- **Modèle de menaces** : T75 (B6.1), T76 (B6.2), T77 (B6.8).

**Vérifié** : `dart analyze` à zéro ; la suite serveur entière **avec
Postgres** (2 071 tests, 2 ignorés) ; contrat (3 tests). **Mutations vues rouges
(18)** : la réservation à tout rôle ; le contrôle préalable retiré, la course
qui garde le compte, l'adresse et l'expiration non vérifiées ; le jumeau
mémoire qui ajoute, ou qui accepte une autre adresse ; Postgres qui
re-rattache, ou sans contrôle préalable ; `ensureSalon` sur le salon d'un
autre ; le rôle d'un révoqué qui change, `member_revoked` en 400 ; la remise
qui dit « ran » pour « pas le jour », « pas le jour » pour un refus ou pour
une absence d'instantané ; l'effacement client qui garde les favoris, les
réponses gardées, ou ne dépouille pas les rendez-vous. **Deux avaient d'abord
survécu** et ont corrigé l'ouvrage (ci-dessus).
