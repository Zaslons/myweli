# L'intégrité du serveur, lot 6 — spec

| | |
|---|---|
| **Statut** | **PR A fusionnée** (#676 — §10) ; **PR B fusionnée** (#677 — §11) ; **PR C fusionnée** (#678 — §12) ; **PR D fusionnée** (#679 — §13, §14 ; **inactive tant que la clé Apple n'existe pas**) ; **déployé en production le 2026-10-22** (image `1e3bd81`, révision `myweli-api-00045-8hs` — §15) ; reste l'alerte de la démo (84, demandée ensuite) et ta clé Apple. Validé le même jour — Q1 (décision 17) : **effacer les numéros et l'adresse, garder le nom et l'historique** ; Q2 (décision 18) : **effacer le KYC de la démo à la remise** ; Q3 (décision 19) : **5–80 %** ; Q4 (décision 20) : **Propriétaire et Gérant, la même file marquée** ; Q5 : **Apple construit maintenant, inactif sans clé** ; Q6 : **le reste tel qu'écrit** (décision 22 : l'alerte, pas de recréation) |
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
  *Construit autrement — l'unicité reste à deux colonnes, voir §12.*
- B6.7 : `apple_refresh_tokens (account_kind, account_id, token, created_at)`,
  supprimé en cascade avec le compte.
  *Construit autrement — `apple_tokens`, avec le client, sans clé étrangère ; voir §13.*
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

## 11. PR B construite (B6.3, B6.4, B6.5) — ce qui a été vu

**Comme écrit**, avec ces précisions et **un ajustement** :
- **B6.3** : l'effacement passe par `updateProfile` (les deux jumeaux fusionnent
  le document, et Postgres tient aussi la colonne `address`) — aucune méthode
  de dépôt nouvelle. Les tests de la route `DELETE /me/provider` simulaient le
  dépôt sans cette réponse : ils l'ont, et vérifient l'effacement. Le texte est
  sur **la politique de confidentialité** et sur **« Supprimer votre
  compte »** ; la date des documents passe au 21 octobre 2026, avec
  l'instantané du manifeste (`legalUpdatedAtWhenPending`) que sa garde exige.
  **À savoir** : ces pages partent avec le web (à la fusion), le serveur avec
  le déploiement — entre les deux, le texte décrit ce que le serveur ne fait
  pas encore. Aucune personne réelle n'est concernée aujourd'hui.
- **B6.4** : `submitKyc(compte, [])` remet déjà l'état (aucune pièce,
  `pending`, pas de motif) dans les deux jumeaux ; seule la suppression des
  objets est nouvelle, dans la même boucle que l'effacement d'un compte (clé
  préfixée, une erreur de stockage ne bloque pas).
- **B6.5, l'ajustement (T57)** : une garde existante l'a rappelé — **aucun
  opérateur hors du catalogue du pays n'est jamais enregistré**. Acompte
  désactivé, un opérateur retiré n'est plus *jugé* (l'enregistrement passe),
  mais il n'est pas *gardé* non plus : stocké `null`. Le contrat le dit.
- **B6.5, les clients** : le web perd « Pourcentage invalide (1–100 %) » ; sa
  règle devient celle de l'app et du serveur (5–80 %, jugée quand la valeur a
  changé), dite sous le curseur ; `operator_unavailable` sous la liste des
  opérateurs (après le `label`, pour ne pas devenir une partie de son nom).
  L'app : les deux fautes sous leurs contrôles (`InlineFeedback`, rien quand
  il n'y en a pas — la photo de l'écran ne bouge pas).

**Vérifié** : `dart analyze` et `flutter analyze` à zéro ; serveur avec
Postgres (2 079 tests, 2 ignorés) ; web (2 152) ; app (2 549) ; e2e entier sur
deux workers (269) ; types web régénérés du contrat. **Mutations vues rouges
(20)** : l'effacement absent, le WhatsApp gardé, l'acompte laissé actif ; le
KYC gardé, n'importe quel préfixe supprimé, l'état gardé ; pas de plage, une
valeur ancienne jugée, l'opérateur jugé acompte désactivé, un opérateur
inconnu gardé, `operator_unavailable` en `invalid_input` ; côté web, les deux
fautes en barre, le curseur qui garde sa faute, une valeur ancienne refusée,
l'ancienne plage 1–100, la page de suppression muette ; côté app, les deux
fautes en barre, le curseur qui garde sa faute.

## 12. PR C construite (B6.6) — ce qui a été vu

**Comme écrit**, avec ces précisions et **deux écarts** :
- **L'unicité reste `(review_id, reporter_user_id)`** (écart au §5). Le
  rapporteur d'un salon est l'identifiant du salon (`provider_…`), celui d'un
  client est `user_…` : ils ne se rencontrent jamais, donc une colonne de plus
  dans la clé n'ajoute rien. Et l'image en service garde son
  `ON CONFLICT (review_id, reporter_user_id)` valide entre la migration et le
  déploiement. La migration `0041_review_reports_reporter_kind` n'ajoute donc
  que la colonne (`text NOT NULL DEFAULT 'user'`) : additive, sans index
  nouveau.
- **`ModerationService.reportBySalon`, à côté de `report`** (écart au §2.6,
  qui disait « réutilise »). Même limite (500 caractères → `invalid_input`),
  même dépôt (`addReport(…, reporterKind: 'salon')`). La différence, c'est le
  contrôle « un avis de ce salon » (sinon `not_found`), qui n'a pas sa place
  dans le signalement d'un client.
- **La route** : `routes/me/provider/reviews.dart` devient
  `reviews/index.dart`, pour que `reviews/[id]/report.dart` existe à côté.
  L'ordre de la route : 405 → 401 → rôle `provider` (403) → le salon résolu
  comme la lecture (`?salonId=` contre une appartenance active) → la capacité
  `profile.manage` (Propriétaire et Gérant) → le corps, facultatif.
- **La file** : chaque élément porte `reportedBySalon` (Postgres :
  `bool_or(reporter_kind = 'salon')`). La console d'administration le dit
  par une puce neutre, « Signalé par le salon », à côté du nombre de
  signalements.
- **Le web** : le BFF `POST /api/pro/reviews/{id}/report` ne transmet **que
  la raison**. Le salon est celui de la session, jamais un champ envoyé par
  le navigateur. Sur « Avis », « Signaler » n'apparaît qu'avec
  `profile.manage`. Le formulaire et les mots sont ceux du client. Un 401
  renvoie à la connexion, et une absence de réponse dit « Pas de connexion.
  Réessayez. ».
- **L'app** : `showInputDialog` (« Signaler cet avis ? », « Raison
  (optionnel) », 500 caractères), puis le message de réussite ou d'échec.
  **La photo de l'écran a parlé** : la première version donnait trois
  boutons noirs, plus forts que l'avis lui-même. « Signaler » a pris le
  style du client (`review_tile.dart` : compact, `labelSmall`,
  `textTertiary`). La photo `pro_reviews_w360.png` montre cette version
  discrète.

**Vérifié** : `dart analyze` et `flutter analyze` à zéro ; serveur avec
Postgres (2 097 tests, 2 ignorés) ; web (2 164) ; app (2 558) ; e2e entier
sur deux workers (269) ; types web régénérés du contrat. **Mutations vues
rouges (21)** :
- **côté serveur** :
  - la capacité ignorée ;
  - n'importe quel rôle ;
  - GET accepté ;
  - l'avis d'un autre salon ;
  - pas de limite de raison ;
  - le salon enregistré comme un client ;
  - la marque absente, puis la marque perdue quand un client signale après
    (mémoire) ;
  - le genre non stocké, et la file jamais marquée (Postgres) ;
- **côté web** :
  - tout le monde signale ;
  - un 401 qui ne renvoie pas à la connexion ;
  - une absence de réponse dite comme un échec ;
  - la raison perdue ;
  - le BFF qui transmet tout le corps ;
- **côté app** :
  - tout le monde signale ;
  - la raison perdue ;
  - l'issue toujours une réussite ;
  - un refus pris pour une réussite ;
  - le salon choisi non envoyé ;
  - la puce d'administration jamais montrée.

**Trois ont d'abord survécu**, et chacune a demandé un test :
- un jeton client dont l'identifiant est celui d'un membre ;
- le salon qui signale avant un client ;
- `?salonId=` dans l'app.

## 13. PR D (B6.7) — le plan détaillé, avant le code

Relu sur main : **aucun** client n'envoie l'`authorizationCode` (app :
`api_auth_service.dart`, trois appels Apple ; web : `lib/auth/apple.ts` ne lit
que `id_token`) ; le serveur n'a ni échange, ni stockage, ni révocation ; les
deux suppressions (`UserErasureService.eraseUser`,
`ProviderAccountService.deleteAccount`) n'en savent rien. Le web a trois
connexions Apple (client, Pro, inscription Pro), l'app aussi.

**La clé (Q5 : inactif tant qu'elle n'existe pas).** Trois variables :
`APPLE_TEAM_ID`, `APPLE_KEY_ID`, `APPLE_PRIVATE_KEY` (le `.p8`, PKCS#8). Les
trois absentes → **inactif** : une ligne au démarrage, puis
`apple_token SKIPPED` / `apple_revoke SKIPPED` à chaque occasion, rien ne
casse. Une ou deux seulement, ou une clé illisible → **le démarrage refuse**
(une configuration à moitié faite ne doit pas avoir l'air de marcher).
`service.yaml` n'y touche pas : le montage du secret vient avec la clé (une
étape écrite dans DEPLOYMENT.md, à faire par toi).

**L'échange, à la connexion.** Les trois routes Apple
(`/auth/apple`, `/auth/provider/apple`, la branche Apple de
`/auth/provider/register`) acceptent un `authorizationCode` facultatif.
Après une connexion **réussie** seulement :
- `client_id` = l'audience du jeton d'identité **déjà vérifié** (l'identifiant
  de l'app iOS, ou le Services ID du web) — un code s'échange avec l'audience
  à laquelle Apple l'a donné ;
- le `client_secret` est un JWT ES256 signé par la clé (5 minutes de vie) ;
- `POST https://appleid.apple.com/auth/token` ; la réponse porte un
  `id_token` : **son `sub` doit être celui du jeton vérifié**, sinon rien
  n'est gardé (le code d'une autre personne ne se range pas sous mon compte —
  sinon ma suppression révoquerait l'accès de quelqu'un d'autre) ;
- le jeton de rafraîchissement est gardé par
  (type de compte, compte, `client_id`) — le dernier remplace le précédent ;
- **la connexion n'échoue jamais à cause d'Apple** : 5 secondes au plus,
  toute faute est une ligne de journal (`apple_token FAILED status=…`), jamais
  le code ni le jeton.
- **Le web** : Apple exige le `redirect_uri` de l'autorisation pour un code
  du web. Le BFF l'ajoute lui-même (`<son origine>/connexion`, ce que la page
  a donné à Apple) — jamais le navigateur. L'app n'en envoie pas.

**La révocation, à la suppression.** Juste avant que l'identité parte (les
deux chemins) : pour chaque jeton gardé, `POST /auth/revoke`
(`token_type_hint=refresh_token`), puis **les lignes sont effacées dans tous
les cas** — un secret gardé pour personne est pire qu'une révocation
manquée. Une faute d'Apple ne bloque pas la suppression : une ligne
`apple_revoke FAILED`, la personne peut retirer MyWeli dans ses réglages
Apple. Le compte de démo est verrouillé avant (rien ne part).

**Les données** : migration `0042_apple_tokens` —
`apple_tokens (account_kind, account_id, client_id, refresh_token,
created_at)`, clé primaire sur les trois premiers, `account_kind` ∈
{`user`, `provider`}. **Écart au §5** : pas de clé étrangère (deux tables
d'identité) — l'effacement est explicite dans les deux chemins, et un test
Postgres vérifie qu'il ne reste rien. Chiffrées au repos par Cloud SQL ; un
jeton seul ne sert à rien sans la clé `.p8` (le `client_secret`).

**L'app** : un point d'injection pour Apple (comme celui de Google), pour
que les trois entrées soient testables ; chacune envoie
`credential.authorizationCode`.

**Le contrat** : `authorizationCode` facultatif sur les trois corps ;
`redirectUri` facultatif (le BFF seul l'envoie). **Le modèle de menaces** :
T79.

**Aucun mot visible ne change** : rien n'est promis tant que la clé n'existe
pas.

**Tests (rouges d'abord)** : le secret signé (ES256, `kid`, `iss`, `sub`,
`aud`) vérifié par la clé publique ; l'échange (gardé ; `sub` différent →
rien ; 400 d'Apple → rien, la connexion passe ; sans clé → rien, sans appel) ;
les routes (code présent → échangé avec la bonne audience ; absent → aucun
appel ; connexion refusée → aucun appel) ; la révocation (chaque jeton, puis
rien ne reste ; faute d'Apple → effacé quand même ; sans clé → effacé, sans
appel) ; les deux suppressions l'appellent avant l'identité ; les jumeaux
(mémoire et Postgres) ; le démarrage (tout ou rien, clé illisible) ; le web
(le code passe, le BFF ajoute l'URL de retour) ; l'app (le code passe, trois
entrées).

## 14. PR D construite (B6.7) — ce qui a été vu

**Comme le §13**, avec ces précisions :
- **L'audience** : le résultat de la vérification ne la portait pas. Plutôt
  que de changer ce type partout (dix-huit endroits, faux compris), le
  vérificateur gagne `audienceOf(jeton)`. Il lit l'audience d'un jeton
  **déjà accepté**, et seulement si elle est dans la liste autorisée. Testé
  sur un vrai jeton signé.
- **Les champs du corps** : l'`authorizationCode` et le `redirectUri` sont lus
  **avec les autres champs, avant la connexion** (`appleCodeOf`). Un mauvais
  type JSON donne donc `400 invalid_body`, comme pour tout champ, et ne
  transforme jamais une connexion réussie en 400. Une valeur seulement
  inutilisable (vide, trop longue, une adresse sans https) est ignorée.
- **Le service n'est lu qu'avec un code** : une connexion sans code ne touche
  pas `AppleTokenService`. Les tests existants des routes Apple n'ont donc pas
  bougé.
- **Le `client_secret`** : la bibliothèque JWT pose son propre `iat` ; le nôtre
  est gardé (`noIssueAt`). Un test l'a montré.
- **Les clés dans les tests** : une paire P-256 est générée à chaque
  exécution, puis encodée en PKCS#8 comme le `.p8` d'Apple. Aucune clé n'est
  dans le dépôt. L'en-tête PEM est composé, pas écrit en toutes lettres, pour
  la même raison que les autres fixtures (gitleaks).
- **Le web** : les trois BFF reçoivent le code et y ajoutent **leur propre**
  `redirectUri` (`<origine>/connexion`, celle que la page a donnée à Apple).
  L'inscription Pro transmettait le corps du navigateur en entier : elle
  écarte désormais un `redirectUri` venu du navigateur, et le code quand
  l'identité est Google.
- **L'app** : un point d'injection `AppleCredentialProvider`, comme celui de
  Google, pour que les trois entrées Apple soient testées. Un code vide n'est
  pas envoyé.
- **Le démarrage** : en production sans clé, une ligne `NOTICE` à chaque
  démarrage. Une clé à moitié configurée arrête le démarrage, comme les
  autres secrets (`_assertConfiguredDependenciesResolve`).
- **Tes étapes** sont dans DEPLOYMENT.md (Phase C) : la clé, le secret, le
  montage épinglé, le déploiement. Chacune est une action sur le cloud, à me
  demander avant.

**Vérifié** : `dart analyze` et `flutter analyze` à zéro ; serveur avec
Postgres (2 160 tests, 2 ignorés) ; web (2 174) ; app (2 562) ; e2e entier sur deux
workers (269) ; types web régénérés du contrat. **Mutations vues rouges
(43)** — aucune n'a survécu au premier passage :
- **la clé** : acceptée à moitié ; les `\n` échappés gardés tels quels ;
- **le secret** : `sub` remplacé par l'équipe ; sans `kid` ; six mois de
  validité ;
- **l'échange** : le jeton d'un autre `sub` gardé ; le `redirect_uri` du web
  perdu ; un refus d'Apple lu comme une réponse ; plus de limite de temps ;
  une erreur qui remonte jusqu'à la connexion ;
- **la révocation** : les lignes gardées ; le mauvais client ; sans
  `token_type_hint` ; une erreur qui remonte ;
- **les champs** : n'importe quelle adresse de retour ; pas de limite de
  longueur ;
- **les deux versions du stockage** : les types de compte mélangés (mémoire) ;
  le premier jeton gardé au lieu du dernier, et l'effacement qui ignore le
  type (Postgres) ;
- **le vérificateur** : n'importe quelle audience acceptée ;
- **les routes** : le jeton gardé sous le mauvais type de compte (trois
  fois) ; jamais gardé (deux fois) ; gardé après une connexion refusée ;
- **les suppressions** : pas de révocation ; la révocation après la
  suppression de l'identité (client et Pro) ; le mauvais type de compte
  (Pro) ;
- **le web** : le code non lu ; pas d'adresse de retour ajoutée par le BFF ;
  le code perdu par chacun des deux BFF de connexion et par la fonction Pro
  qui appelle le sien ; l'adresse du navigateur gardée ; le code envoyé avec
  une identité Google ;
- **l'app** : jamais de code envoyé ; un code vide envoyé ; le code perdu
  par chacune des trois entrées.

## 15. Le déploiement (2026-10-22) — ce qui a été vu

Un seul déploiement du serveur pour les quatre PR (#676 à #679). La
production servait `46126a3`, et depuis rien d'autre n'avait changé côté
serveur. L'image `1e3bd81` (la fusion de #679) a été construite et vérifiée
par l'exécution liée à la fusion sur main (staging absent : construire,
publier, vérifier, ne rien déployer), puis **promue** par un lancement manuel
(`production`, `deploy`, `image_tag: 1e3bd81`).

**Vu par l'exécution** : la révision `myweli-api-00045-8hs` sert le digest
`sha256:2c078148…` construit depuis `1e3bd81` ; `/health`, `ENV=prod` ; la
base répond.

**Vu d'ici** : 100 % du trafic sur `00045-8hs` ; aucune erreur depuis la
mise en service. Trois requêtes que seule la nouvelle image peut répondre
ainsi :
- `GET /me/provider/reviews/x/report` → **405** (la route n'existait pas :
  404) ;
- le même en `POST` sans session → **401** ;
- `POST /auth/apple` avec un `authorizationCode` numérique → **400
  `invalid_body`** (l'ancienne image ignorait le champ : `invalid_token`).

**Les migrations 0041 et 0042** ne laissent pas de ligne dans le journal.
Elles s'exécutent avant que le port ne s'ouvre (`main.dart` :
`initializeDatabase()` avant `serve()`) : la ligne « Running on :8080 »
prouve qu'elles sont passées.

**La clé Apple** : le journal de démarrage dit
`NOTICE: no APPLE_TEAM_ID / APPLE_KEY_ID / APPLE_PRIVATE_KEY` — inactif,
comme prévu (Q5).

**Ce qui n'est pas vérifié en production**, et pourquoi :
- les écritures (un signalement, une suppression, un enregistrement
  d'acompte) : elles demandent de vrais comptes, et la production n'en a pas
  à abîmer ;
- la remise de la démo (B6.4) : elle tourne au prochain créneau de la
  semaine — c'est l'alerte (84) qui dira si elle est refusée.
