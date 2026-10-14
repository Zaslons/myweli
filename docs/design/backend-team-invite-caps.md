# Invitations d'équipe : plafonds durables, l'adresse démo, l'acceptation qui revérifie — spec

| | |
|---|---|
| **Statut** | **Construit le 2026-10-14** sur `fix/team-invite-caps` — non fusionné, non déployé. |
| **Module** | `access` (équipe, R2b) · sécurité (T37, T69) |
| **Origine** | [backend-team-reinvite.md](backend-team-reinvite.md) §11 (questions 2 et 3), et deux constats de la cartographie qui a suivi (l'adresse démo, la course acceptation/révocation). Décision du propriétaire, le 2026-10-14 : « do as you think is better ». |
| **Régit** | `backend/lib/src/security/identity_limits.dart` (politique) · `backend/lib/src/access/team_service.dart` (`invite`, `accept`) · `backend/lib/src/access/membership_repository.dart` + `backend/lib/src/db/postgres_membership_repository.dart` (`activate`) · `backend/lib/src/dependencies.dart` · `infra/gcp/service.yaml`, `service-staging.yaml` · `infra/gcp/92-identity-limit-alert.sh` (texte du runbook) |
| **Skills consultés** | myweli-backend-guardrails · myweli-verification-guardrails |

## 1. Ce qui ne va pas aujourd'hui, vérifié

1. **Le plafond quotidien du salon (20) est compté par instance.**
   `TeamService._inviteCounts` est une `Map` du processus. Le service tourne
   jusqu'à 4 instances (`maxScale`) et redémarre à froid : le plafond réel est
   « 20 par instance et par démarrage ». `rate_limiter.dart` le dit déjà
   (« the defect `LoginThrottle` and `TeamService._inviteCounts` still carry »).
2. **Aucun plafond par adresse.** Depuis #596, réinviter une ligne révoquée
   marche — c'était voulu — et la boucle « révoquer → réinviter » sur une même
   adresse n'est bornée que par les 20 du salon, chaque réinvitation
   rechargeant 3 renvois : jusqu'à ~80 e-mails par jour vers une personne, par
   instance ([backend-team-reinvite.md](backend-team-reinvite.md) §6).
3. **N'importe quel salon peut inviter l'adresse démo** `revue@myweli.test`.
   `invite` ne refuse que lorsque le salon **qui invite** appartient au compte
   démo. Une invitation à cette adresse — avec un nom de salon choisi par
   l'expéditeur — apparaît dans « Invitations » du compte public des relecteurs
   de stores, qui peuvent l'accepter. Aucun e-mail ne part (le `.test` est
   refusé à l'envoi) ; la carte, elle, s'affiche. La remise à zéro hebdomadaire
   ne touche que les salons du compte démo.
4. **`activate` ne revérifie pas l'état.** `accept` lit la ligne (invitée,
   valide), puis `activate` écrit `status = 'active' WHERE id = @id`. Une
   révocation du propriétaire **entre** les deux est annulée : la personne
   révoquée devient membre active. Étroit, mais c'est désormais le chemin
   principal d'un ancien membre réinvité (§11 de la spec précédente).

## 2. Ce que voit l'utilisateur

Rien de nouveau. Au-delà d'un plafond, le propriétaire reçoit le refus qui
existe déjà : 429 `invite_rate_limited` → « Trop d'invitations envoyées
aujourd'hui. Réessayez demain. » (app et web le traduisent déjà). Inviter
`revue@myweli.test` répond `invalid_input` (une adresse qui ne peut pas être
invitée). Une acceptation qui arrive après une révocation répond `not_found`
(« Introuvable. Actualisez et réessayez. » / la carte disparaît).

## 3. Contrat d'API

`POST /me/provider/members` : la ligne 429 précise les **deux** plafonds
quotidiens (par salon, par salon et adresse) et l'adresse démo refusée en 400.
Les acceptations (`/me/provider/invitations/{id}/accept`,
`/auth/provider/invitations/accept`) : `404 not_found` aussi quand
l'invitation a été révoquée ou a expiré entre la lecture et l'écriture.

## 4. Données

**Aucune migration.** Les compteurs vivent dans `identity_rate_limits` (0034),
la table du limiteur partagé, déjà purgée chaque jour.

## 5. Le changement

### 5.1 Deux seaux quotidiens, sur le limiteur partagé

| Seau | Clé | Plafond / jour | Avertissement à 80 % |
|---|---|---|---|
| salon | `invite:salon:<providerId>` | `LIMIT_INVITE_SALON` = 20 | oui (16) |
| salon × adresse | `invite:addr:<providerId>:<sha256(providerId + "\n" + adresse)[0..32]>` | `LIMIT_INVITE_ADDRESS` = 3 | **non** |

- **Fenêtre** : 1 jour, flooré à l'époque — minuit UTC, minuit à Abidjan.
- **Le limiteur partagé** (`RateLimiter`, Postgres derrière `FailOpenRateLimiter`)
  remplace le compteur du processus : toutes les instances comptent ensemble.
  Il **échoue ouvert**, comme pour les réservations : une panne Postgres
  efface le plafond au lieu de bloquer les invitations, et le dit
  (`rate_limit_unavailable bucket=…`). Le budget d'envoi global des e-mails
  reste la borne de dernier recours.
- **Pourquoi par salon et pas par compte propriétaire** : un propriétaire
  Réseau qui fait entrer la même gérante dans cinq de ses salons le même jour
  est un cas honnête ; une clé par compte le refuserait au quatrième. Le
  revers : un propriétaire à N salons, chacun avec une offre vivante,
  multiplie le plafond par adresse par N — borné par les offres et le budget
  d'envoi, et journalisé.
- **L'adresse n'apparaît jamais en clair** dans la table ni dans les journaux
  (`rate_limited bucket=…` est journalisé à chaque refus). Le salon est dans
  l'entrée du hachage : la même adresse donne une empreinte différente dans
  chaque salon. **Pseudonyme, pas secret** : le hachage n'a pas de clé, et
  qui tient une adresse *candidate* peut la confirmer pour un salon donné.
  Le but tenu est « aucune coordonnée dans les journaux », pas l'anonymat
  (précisé après la revue).
- **Une boîte, un seau** (`canonicalInviteAddress`, ajouté après la revue) :
  le compteur — seulement lui — retire un `+étiquette` quel que soit le
  domaine, et chez Gmail les points et `googlemail.com`. Sans cela,
  `victime+1@gmail.com`, `v.ictime@gmail.com`… étaient chacun un seau neuf et
  le plafond par adresse ne bornait rien. L'adresse stockée et envoyée reste
  celle saisie. Les domaines « attrape-tout » restent hors de portée : le
  plafond du salon les borne.
- **Pas d'avertissement sur le seau d'adresse** : `warnAt(3) = 2`, l'alerte 94
  sonnerait à chaque deuxième invitation honnête d'une même adresse.
- **L'ordre** : toutes les vérifications existantes d'abord (verrou démo,
  adresse, rôle, fiche, doublon, offre, places) — un refus de leur part ne
  consomme rien ; puis le seau **salon** (un ensemble fermé), puis le seau
  **adresse** (ouvert) : un salon ne peut écrire que 20 nouvelles lignes
  d'adresse par jour. Puis l'écriture.
- **On compte les tentatives** (le principe du limiteur) : une course perdue
  (le dépôt retourne `null` → `member_exists`) est comptée. Le
  « remboursement » de #596 disparaît avec le compteur du processus. Une
  tentative refusée par le seau adresse a déjà consommé une unité du seau
  salon — voulu (une tentative est une tentative) : un propriétaire qui
  s'acharne sur une adresse refusée finit par épuiser la journée du salon et
  par déclencher l'avertissement à 80 % ; le runbook de l'alerte 94 le dit.
- **Les renvois ne sont pas comptés** : ils ont leur budget par ligne (3, remis
  à neuf par une réinvitation). Bilan par (salon, boîte) et par jour UTC :
  3 invitations × (1 + 3 renvois) = 12 e-mails, **plus** jusqu'à 3 renvois
  d'une invitation partie la veille — **15 au plus**, au lieu de ~80 par
  instance (le chiffre 12 de la première version était faux, relevé en
  revue).

### 5.2 L'adresse démo

`invite` refuse l'adresse démo (`isDemoIdentity`) avec `invalid_input`,
avant tout compteur. `demo_account_locked` serait faux : le salon qui invite
n'est pas le compte démo, et ce texte le lui dirait.

**Et côté invité** (après la revue) : une invitation à cette adresse écrite
**avant** ce refus resterait renvoyable et acceptable avec l'identifiant
public. Donc `pendingInvitationsFor` ne montre aucune carte au compte démo,
`accept` répond `not_found` à une invitation adressée au compte démo, et
`resend` répond `invalid_state` — la ligne reste inerte, quel que soit ce que
contient la base.

### 5.3 L'acceptation qui revérifie

`activate` n'écrit plus que si la ligne est **encore** une invitation valide :
`… WHERE id = @id AND status = 'invited' AND (expires_at IS NULL OR
expires_at > now()) RETURNING *` (les deux jumeaux). Sinon `null`, et
`accept` répond `not_found`. Une révocation qui s'intercale tient. L'audit
`members.accept` note le rôle **écrit** (`activated.role`), plus celui lu
avant : un changement de rôle peut tomber entre les deux.

### 5.4 Configuration et rétention

- `inviteLimits` lit `LIMIT_INVITE_SALON` et `LIMIT_INVITE_ADDRESS`, déclarées
  dans `service.yaml` et `service-staging.yaml` (le test des manifestes exige
  que les deux ensembles soient égaux).
- `allowUnderLimit` prend deux paramètres facultatifs, `window` et `warn` ;
  leurs valeurs par défaut gardent le comportement des seaux existants.
- La purge quotidienne garde un jour : une fenêtre d'**un** jour est désormais
  **à la limite** (elle survit, parce que son début est toujours postérieur à
  « maintenant − 1 jour »). La durée devient une constante nommée,
  `kRateLimitRetention`, et un test exige `kInviteWindow <= kRateLimitRetention`.
- Les runbooks des alertes 92 (refus) et 94 (avertissement à 80 %) — dans
  `92-identity-limit-alert.sh` et `94-identity-warning-alert.sh` — nomment
  les seaux `invite:`, les deux variables, et la fenêtre d'un jour (le 94
  disait « une fois par heure »). **Les réappliquer** est une écriture sur le
  projet GCP : à faire avec le mot du propriétaire.

## 6. Sécurité

T37 se resserre (plafonds partagés par toutes les instances, plafond par
adresse) ; T69 gagne un refus (l'adresse démo ne reçoit plus de cartes) ; la
course acceptation/révocation (T38 — « une révocation prend effet à la requête
suivante ») est fermée. Aucun nouveau point d'entrée.

## 7. Performance

Deux `UPSERT` d'une ligne chacun par invitation, sur la table du limiteur
(délai de requête 2 s, échec ouvert). Rien sur les autres chemins.

## 8. Tests — vus rouges d'abord

- **Service** (un seul `InMemoryRateLimiter` partagé, horloge du test) : la
  boucle révoquer → réinviter s'arrête à 3 (4ᵉ → `invite_rate_limited`, pas de
  4ᵉ e-mail, la ligne reste révoquée) ; une autre adresse du même salon passe ;
  la même adresse dans un autre salon passe ; « ` A@B.com ` » et « a@b.com »
  partagent le seau ; 23:59:59Z refuse encore, 00:00:00Z le lendemain passe ;
  les renvois ne comptent pas ; deux `TeamService` sur un même limiteur
  partagent les deux plafonds (le défaut du compteur par instance) ; un refus
  du seau salon ne touche pas au seau adresse ; `member_exists`,
  `seat_limit`, `offer_required` et `demo_account_locked` ne consomment rien ;
  une course perdue est comptée ; le refus journalisé ne contient ni `@` ni
  l'empreinte nue de l'adresse ; aucun avertissement sur le seau adresse ;
  l'adresse démo refusée, sans ligne ni compteur.
- **Contrat des jumeaux** : `activate` sur une ligne révoquée ou expirée →
  `null`, la ligne inchangée.
- **Service** : une acceptation après révocation → `not_found`, la ligne reste
  révoquée.
- **Câblage** : `TeamService` est construit **avec** le limiteur et les
  plafonds ; les variables sont déclarées dans les deux manifestes ;
  `kInviteWindow <= kRateLimitRetention` ; `allowUnderLimit` honore `window`
  et `warn`.
- **Route** : `POST /me/provider/members` → 429 `invite_rate_limited`.
- **Ajoutés après la revue adverse, chacun vu rouge** : les alias d'une boîte
  partagent le seau (`+étiquette`, points Gmail, `googlemail.com`) ; une
  invitation démo antérieure est inerte (ni carte, ni acceptation, ni renvoi) ;
  l'audit d'acceptation note le rôle écrit ; le test de câblage ignore les
  commentaires et exige `limiter: rateLimiter` (un commentaire contenant
  « limiter: » le satisfaisait) ; un test d'abonnement creusé par la garde
  d'`activate` (date fixe en juillet) vérifie à nouveau sa mise en place.

## 9. Mise en service

PR → CI → fusion → déploiement (mot du propriétaire pour chacun) →
réappliquer le texte des alertes 92 et 94 (mot du propriétaire). Retour arrière sans
risque : aucune migration ; les lignes `invite:` d'une image plus récente sont
ignorées par une plus ancienne et purgées le lendemain.

## 10. Questions ouvertes

1. Le mock de l'app compte ses invitations sans jamais revenir à zéro et sans
   plafond par adresse ; le stub du web n'a aucun plafond. Fidélité à
   reprendre si un parcours les atteint.
2. L'acceptation publique (sans compte) crée le compte nu **avant**
   `accept` ; si l'acceptation échoue (expirée, révoquée), le compte reste sans
   ligne, et `GET /me/provider` lui créerait un salon. Antérieur ; à traiter
   avec le parcours « ancien membre réinvité » (côté clients).
