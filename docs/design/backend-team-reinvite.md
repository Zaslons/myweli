# Réinviter un membre après une révocation ou une invitation expirée — spec

| | |
|---|---|
| **Statut** | **Construit le 2026-10-14** sur `fix/team-reinvite-unique` — non fusionné, non déployé. Fusion et déploiement : sur le mot du propriétaire. |
| **Module** | `access` (équipe, R2b) |
| **Origine** | La revue adverse du correctif de suppression ([backend-provider-deletion-member-fk.md](backend-provider-deletion-member-fk.md) §7) ; le propriétaire : « Do this task here ». |
| **Régit** | `backend/lib/src/access/team_service.dart` (`invite`) · `backend/lib/src/access/membership_repository.dart` + `backend/lib/src/db/postgres_membership_repository.dart` (`invite`) · `docs/api/openapi.yaml` (`POST /me/provider/members`, `…/resend`) · `mobile/lib/providers/pro_team_provider.dart` · `mobile/lib/services/mock/mock_pro_team_service.dart` · `web/tests/e2e/stub-api.mjs` |
| **Liés** | [team-access-r2b-invitations.md](team-access-r2b-invitations.md) (la machine à états) · [../modules/access.md](../modules/access.md) · [web-team-access-r5.md](web-team-access-r5.md) |
| **Skills consultés** | myweli-backend-guardrails · myweli-verification-guardrails |

## 1. Le défaut, vérifié avant d'écrire

`provider_members` porte `UNIQUE (provider_id, email)` (0027) : **une ligne
par (salon, adresse)**, comme le disent le code (`membership_repository.dart`,
en tête) et [access.md](../modules/access.md). `TeamService.invite` ne tient
pour doublon qu'une ligne **active** ou une invitation **encore valide**. Une
ligne **révoquée**, ou une invitation **expirée**, passe donc le contrôle et
atteint `PostgresMembershipRepository.invite` — un `INSERT` simple, sans
`ON CONFLICT` — qui lève 23505 ; rien ne l'attrape, et le client reçoit **500
`internal_error`**. Le jumeau en mémoire n'a pas de clé unique : il **ajoute
une seconde ligne**, et les tests (dont `team_service_test.dart`, « an EXPIRED
invitation can be re-sent as a new invite ») passent sur un comportement que
Postgres ne peut pas produire. **Aucun** test Postgres ne couvrait
`PostgresMembershipRepository`.

**Le chemin le plus courant** : le propriétaire « annule » une invitation en
attente avec « Révoquer l'accès » (offert sur les lignes invitées, app et
web), puis réinvite la même adresse — avec le bon rôle, par exemple. Autre
chemin : une invitation expirée **occupe toujours une place** (les places
comptent `active` + `invited`, expirées comprises) ; pour libérer la place, le
propriétaire révoque l'invitation expirée… puis la réinvite → 500.

**Effets de bord du 500** : le compteur quotidien d'invitations du salon (20
par jour, T37) est incrémenté **avant** l'`INSERT` — chaque nouvel essai en
consomme une ; ni e-mail ni journal d'audit (ils viennent après).

## 2. Ce que voit l'utilisateur

| Avant | Après |
|---|---|
| « Une erreur est survenue. Réessayez. » (app et web), à chaque essai | L'invitation part ; **la même ligne** redevient « Invitation envoyée · expire le … » |

Sur le web, la ligne bascule **en place** (le client remplace par
identifiant). Dans l'app, la liste ne montre plus de doublon fugitif (§5.3).
Aucun texte nouveau.

## 3. Contrat d'API

`POST /me/provider/members` — **inchangé dans sa forme**, précisé :

- une adresse dont la ligne est **révoquée**, ou dont l'invitation a
  **expiré**, est réinvitée **sur la même ligne** (même `id`) : rôle, fiche
  employé, durée de validité et budget de 3 renvois repartent à neuf ;
- `409 member_exists` : une ligne **active**, une invitation **encore
  valide**, ou la ligne du **propriétaire** (quel que soit son état) ;
- la réponse `201` a **la forme d'une ligne de la liste** : avec
  `artistName` et `expired` (jusqu'ici absents de la réponse, présents dans
  `GET`) — le web n'affichait « — » sous « Employé » qu'après un
  rechargement.

`POST /me/provider/members/{id}/resend` — la réponse `409 invalid_state` (une
ligne non invitée), renvoyée par le code et testée, est ajoutée au contrat.

## 4. Données

**Aucune migration.** La règle « une ligne par (salon, adresse) » existe déjà ;
le correctif s'y conforme au lieu de la heurter.

## 5. Le changement

### 5.1 Le dépôt — un seul énoncé, les deux jumeaux

`invite(...)` crée l'invitation **ou ranime la ligne morte** de la même
adresse, et retourne `null` si une ligne **vivante** la tient (une invitation
concurrente a gagné). En Postgres :

```sql
INSERT INTO provider_members (id, provider_id, email, role, artist_id,
  status, invited_by, invited_at, expires_at)
VALUES ('mem_' || gen_random_uuid(), @p, lower(@e), @r, @a,
  'invited', @b, now(), @x)
ON CONFLICT (provider_id, email) DO UPDATE SET
  role = EXCLUDED.role, artist_id = EXCLUDED.artist_id, status = 'invited',
  invited_by = EXCLUDED.invited_by, invited_at = now(),
  expires_at = EXCLUDED.expires_at, resends_left = 3,
  accepted_at = NULL, revoked_at = NULL
WHERE provider_members.role <> 'owner'
  AND (provider_members.status = 'revoked'
       OR (provider_members.status = 'invited'
           AND provider_members.expires_at <= now()))
RETURNING *
```

- **Atomique** : une instruction, pas de transaction. Deux invitations
  simultanées de la même adresse : la seconde attend la première, retrouve une
  ligne vivante, la clause `WHERE` est fausse, zéro ligne → `null` → 409. Plus
  de 23505 sur cette clé.
- **`resends_left = 3` explicite** : la valeur par défaut ne vaut qu'à
  l'insertion.
- **`account_id` gardé** : l'effacer ferait passer `hasAnyMembership` à faux
  pour un ancien membre sans autre ligne, et `GET /me/provider` lui créerait
  un salon orphelin (le défaut que #594 a nommé). `activate` le réécrit à
  l'acceptation. Avec #594, supprimer ce compte supprime aussi l'invitation
  ranimée — la personne a effacé son compte.
- **Jamais la ligne du propriétaire** (`role <> 'owner'`) : une ligne
  « owner » révoquée existe en production (la suppression ratée du 14,
  [backend-provider-deletion-member-fk.md](backend-provider-deletion-member-fk.md)
  §9) ; la ranimer en « manager » donnerait au propriétaire des droits de
  manager par l'auto-réparation.
- **`grants`/`denies`** : non touchés — aucune ligne de code ne les lit ni ne
  les écrit (colonnes réservées).

Le jumeau en mémoire fait la même chose : il cherche la ligne (salon, adresse),
la **remplace par une ligne neuve sous le même identifiant** si elle est morte
(`copyWith` ne sait pas remettre un champ à `null`), retourne `null` si elle
est vivante, et n'ajoute une ligne qu'en l'absence de toute ligne. Les deux
jumeaux passent **le même contrat de tests** (§8).

### 5.1 bis Refuser une réinvitation

`decline` supprimait la ligne sans condition. Une ligne ranimée garde
l'`account_id` de l'ancien membre : la supprimer lui retirait sa dernière
ligne, `hasAnyMembership` passait à faux, et `GET /me/provider` lui créait un
salon — le danger même que garder `account_id` devait écarter (relevé par la
revue adverse). Désormais `decline` (les deux jumeaux) **supprime une ligne
qui n'a jamais appartenu à un compte**, et **remet en « révoquée »** celle d'un
ancien membre. Le propriétaire peut toujours le réinviter ; la ligne reste
morte. Les deux énoncés Postgres ont des prédicats exclusifs
(`account_id IS NULL` / `IS NOT NULL`, et `status = 'invited'`) : leur ordre
est sans effet, et une acceptation qui s'intercale change le statut — aucun
des deux ne s'applique. Le contrat d'API le dit (`/…/decline`).

### 5.2 Le service

- **Clé** : `email.trim().toLowerCase()`. `isValidEmail` acceptait « ` a@b.co` »
  (il retire les espaces avant de tester), mais la clé gardait l'espace — un
  appel direct à l'API contournait le contrôle de doublon. Les deux clients
  retiraient déjà les espaces.
- **Doublon** : la ligne de l'adresse est lue une fois. Propriétaire (tout
  état), active, ou invitation valide → `member_exists`. Sinon, morte ou
  absente → on continue, en sachant laquelle (`revoked` / `expired` / neuve).
- **Places** : ranimer une invitation **expirée** ne prend pas de place de
  plus (elle en occupe déjà une) — la vérification des places est sautée dans
  ce seul cas ; l'offre doit toujours être vivante. Ranimer une ligne
  **révoquée** prend une place : la vérification s'applique.
- **Compteur quotidien** : toujours vérifié et incrémenté avant l'écriture ;
  **rendu** si le dépôt retourne `null`.
- **Audit** : `members.invite`, avec `revived: 'revoked' | 'expired'` dans les
  métadonnées quand une ligne est ranimée — l'historique d'une adresse reste
  sous un seul identifiant.
- **Réponse** : la forme d'une ligne de la liste (`artistName`, `expired`) —
  un seul assembleur pour `list` et `invite`.

### 5.3 Les clients

- **App** (`ProTeamProvider.invite`) : la ligne retournée **remplace** celle de
  même identifiant au lieu de s'ajouter — sans quoi l'ancienne ligne et la
  nouvelle, même identifiant, s'affichaient ensemble jusqu'au rechargement.
- **Mock de l'app** (`MockProTeamService`, le backend de développement) : la
  même règle que le serveur — une ligne par adresse, ranimée sur place.
- **Web** : aucun changement de code — `EquipeClient` remplace déjà par
  identifiant. Le stub des tests e2e suit le serveur (ranime au lieu
  d'ajouter ; un refus d'ancien membre remet la ligne en « révoquée »), et le
  parcours complet de l'équipe se prolonge : révoquer, puis réinviter la même
  adresse → une seule ligne, « Invitation envoyée ».
- Le mock de l'app suit aussi la règle du refus.

## 6. Sécurité

- **Aucun nouveau point d'entrée.** L'acceptation exige toujours l'identifiant
  **et** la preuve de l'adresse (`accept` compare l'adresse prouvée à celle de
  la ligne) ; un identifiant réutilisé ne peut être accepté que par la personne
  invitée. L'e-mail d'invitation ne porte ni identifiant ni lien jeton.
- **T37, le budget d'envoi** : chaque réinvitation consomme une invitation du
  quota quotidien du salon (20) ; une ligne ranimée retrouve ses 3 renvois.
  Borne résiduelle, nouvelle maintenant que le 500 ne l'empêche plus : un
  propriétaire peut boucler révoquer → réinviter sur une même adresse, jusqu'à
  20 invitations (+ 3 renvois chacune) par jour et par instance. Le salon doit
  avoir une offre vivante, et chaque cycle est journalisé. Une limite par
  adresse est une question ouverte (§11).

## 7. Performance

Une lecture de la liste du salon (déjà faite) ; une instruction d'écriture.

## 8. Tests — vus rouges d'abord

- **Contrat partagé des deux jumeaux** (`backend/test/access/invite_contract.dart`),
  exécuté sur le jumeau en mémoire (`membership_test.dart`) **et** sur
  Postgres (`postgres_repositories_test.dart`) : adresse neuve → ligne neuve ;
  invitation valide → `null` ; ligne active → `null` ; ligne révoquée (d'un
  membre qui avait accepté) → **même identifiant**, `invited`, rôle/fiche
  nouveaux, `resends_left` 3, `accepted_at`/`revoked_at` vides, `account_id`
  gardé, une seule ligne pour l'adresse ; invitation expirée → idem ; ligne
  « owner » révoquée → `null`, intacte ; **deux invitations simultanées** de
  la même adresse, puis de la même ligne morte → un gagnant, une ligne, aucune
  erreur. **Vu rouge** : 7 cas sur 8 — 23505
  `provider_members_provider_id_email_key` sur Postgres, une seconde ligne en
  mémoire ; « adresse neuve » sert de témoin. Les deux cas simultanés, vus
  rouges par mutation (les dépôts de `main` remis en place, puis restaurés).
- **Refus** (contrat partagé + route) : refuser une invitation neuve la
  supprime (témoin) ; refuser la réinvitation d'un ancien membre laisse la
  ligne, « révoquée », même identifiant, même compte ; et `GET /me/provider`
  répond toujours 403 `not_a_member` sans créer de salon. **Vu rouge** sur le
  commit précédent : la route entrait dans `ensureSalon → createSalon` ; le
  contrat (les deux jumeaux) ne trouvait plus de ligne. Le mock de l'app : vu
  rouge (ligne supprimée).
- **Places d'une ligne révoquée** (`team_service_test.dart`) : un salon plein
  refuse de réinviter un membre révoqué (`seat_limit`), la ligne reste
  révoquée, aucun e-mail. Ajouté sur relevé de la revue (aucun test ne tenait
  la règle) ; **vu rouge par mutation** (`revived == null &&`).
- **Service** (`team_service_test.dart`) : réinviter après révocation → 201,
  même identifiant, une ligne ; après expiration **avec le salon plein** → 201
  (pas de `seat_limit`) ; propriétaire révoqué → `member_exists` ; adresse
  avec espaces → doublon reconnu ; `null` du dépôt → `member_exists` et
  compteur rendu ; métadonnée `revived` ; réponse avec `artistName` et
  `expired`. Le test « EXPIRED invitation can be re-sent » affirme désormais
  une seule ligne, même identifiant. **Vu rouge** : 6 cas. Le cas
  « propriétaire » passait d'abord pour une mauvaise raison — en mémoire,
  l'auto-réparation de l'appelant ajoutait une ligne « owner » active, que le
  contrôle de doublon trouvait ; il porte désormais sur la ligne révoquée d'un
  **ancien** propriétaire, et il est rouge.
- **App** : l'invitation retournée remplace la ligne de même identifiant ; le
  mock ranime au lieu d'ajouter. **Vu rouge** : 3 cas.
- **Web** (Playwright, sur le stub) : révoquer puis réinviter → une ligne,
  « Invitation envoyée ». Vert ; **rouge avec le stub de `main`** (« Accès
  révoqué » toujours affiché). Lancé sur des ports libres par une copie
  temporaire de la configuration : le port 3000 était pris par le serveur de
  développement d'un autre projet.

## 9. Mise en service

PR → CI → fusion sur le mot du propriétaire → déploiement en production sur
son « go ». Retour arrière sans risque : aucune migration ; une image plus
ancienne ne fait que retrouver le 500.

**Avec #594, pas seulement une remise à jour** (relevé par la revue, la fusion
simulée) : `invite` devient nullable ici, et #594 ajoute un test qui lit
`.id` sur son résultat. Quelle que soit la PR fusionnée en second, elle doit :

1. dans `backend/test/db/postgres_repositories_test.dart`, test « a salon
   owner with a team is erased » de #594 : `mateInvite!.id` et
   `staffInvite!.id` (la fusion passe sans conflit, puis ne compile pas) ;
2. résoudre `salon_directory_test.dart` et `me_provider_test.dart` en
   gardant les deux intentions — `activate(inv2!.id, …)` d'ici,
   `revoke(inv2.id)` de #594 (de même pour `invited`) ;
3. garder les deux imports en tête de `postgres_repositories_test.dart`.

Sémantique : avec #594, supprimer le compte d'un ancien membre supprime aussi
son invitation ranimée (`ON DELETE CASCADE` sur `account_id`) — voulu, la
personne a effacé son compte. #595 ne touche pas à l'équipe.

## 10. Définition de « fait »

Les tests vus rouges puis verts ; suites backend, app (fichiers touchés) et web
(typecheck) vertes ; CI verte ; contrat et types du web régénérés.

## 11. Questions ouvertes

1. **L'ancien membre réinvité ne peut pas accepter depuis l'app ni le web.**
   Il a déjà un compte, donc le pont d'invitation (réservé aux adresses sans
   compte) ne se déclenche pas ; `GET /me/provider` répond 403 `not_a_member`
   (il a une ligne, aucune active), et les deux clients le **déconnectent**
   (« Votre accès a été retiré ») avant qu'il voie l'invitation. Le défaut est
   antérieur à ce correctif et touche aussi un ancien membre invité dans **un
   autre** salon. Les routes nécessaires existent déjà
   (`GET /me/provider/invitations`, `POST …/accept` sans adhésion active) : le
   correctif est côté clients — regarder les invitations en attente avant de
   déconnecter. **Parcours utilisateur à valider par le propriétaire avant
   d'être construit.**
2. ~~**Une limite de réinvitations par adresse** (§6) — à décider.~~
   **Décidée et construite le 2026-10-14** : 3 par jour et par (salon,
   adresse), sur le limiteur partagé —
   [backend-team-invite-caps.md](backend-team-invite-caps.md).
3. ~~`activate` ne revérifie pas le statut~~ — **fermé le 2026-10-14**
   ([backend-team-invite-caps.md](backend-team-invite-caps.md) §5.3).
4. L'app propose « Changer le rôle » sur une ligne révoquée (le serveur
   l'accepte) ; le web n'offre aucune action. Écart d'interface, antérieur.
