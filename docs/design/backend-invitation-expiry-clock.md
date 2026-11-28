# L'expiration d'une invitation se lit à l'horloge du service — spec

| | |
|---|---|
| **Statut** | **Construit** (cette PR, ouverte le 2026-11-28, non fusionnée). Aucun changement en production : l'horloge du service y est l'horloge réelle. |
| **Module** | `access` (équipe, R2b) |
| **Origine** | Depuis le 2026-11-28 à 00 h 00 UTC, « Backend — Analyze & Test », un contrôle obligatoire, échouait sur `main` (`aaac273f`) et sur chaque PR (la PR A11y #909, run 46087213500) : plus rien ne pouvait fusionner. #914 (`2a96746b`, fusionnée le 2026-11-28 à 09 h 36 UTC) a rendu `main` vert en changeant le test seul : il lit désormais l'horloge réelle. Cette PR-ci corrige le défaut lui-même et pose le garde. |
| **Régit** | `backend/lib/src/access/membership_repository.dart` (`Member.isExpiredInvitationAt`) · `backend/lib/src/access/team_service.dart` (ses trois lectures) · `backend/test/access/team_service_test.dart` · `backend/test/access/invite_contract.dart` |
| **Liés** | [team-access-r2b-invitations.md](team-access-r2b-invitations.md) (la machine à états) · [backend-team-reinvite.md](backend-team-reinvite.md) · [backend-team-invite-caps.md](backend-team-invite-caps.md) §5.3 · [deleted-owner-salon-purge.md](deleted-owner-salon-purge.md) §6.7 (le test qui a sauté) |
| **Skills consultés** | myweli-backend-guardrails · myweli-verification-guardrails |

## 1. Le défaut, lu dans le code avant d'écrire

`TeamService` reçoit une horloge (`clock:`, gardée dans `_now`) : c'est elle
qui fixe la fin d'une invitation (`_now().add(invitationValidity)`, 7 jours).
Mais l'expiration se jugeait avec le getter `Member.isExpiredInvitation`, qui
lisait lui-même `DateTime.now()`. Le service fixait donc la fenêtre avec son
horloge et la jugeait avec celle du mur.

Le test B0.24 « an invitation the salon purge deleted mid-accept answers
not_found, never a 500 » fige l'horloge au 2026-11-21 et crée une invitation
qui expire le 2026-11-28 à 00 h 00 UTC. Passé cet instant réel,
`checkAcceptable` répond `invitation_expired` avant d'atteindre la relecture
que le test exerce : il attend `not_found`. C'était une bombe à retardement ;
elle a sauté à l'heure dite. Reproduit en local avec
`dart test test/access/team_service_test.dart -N "purge deleted mid-accept"`.

Trois lectures dans le service : le drapeau `expired` de la liste d'équipe,
le contrôle des doublons de `invite` et `checkAcceptable` (que `accept`
appelle). En production, les deux horloges sont l'horloge réelle : aucun
utilisateur ne voit de différence. Le défaut, c'est que l'horloge du service
n'était pas respectée.

## 2. Ce qui change

- Le getter devient `isExpiredInvitationAt(DateTime now)` : l'appelant dit ce
  qu'est « maintenant ». Le service passe `_now()` à ses trois lectures.
- **Aucune variante à l'horloge du mur n'est gardée.** Le getter n'avait pas
  d'autre appelant que le service, sauf le contrat de tests des dépôts. Le
  garder aurait laissé le piège en place pour le prochain appelant. Le
  contrat (`invite_contract.dart`) passe désormais `DateTime.now()`
  explicitement : les dépôts jugent une fenêtre à leur propre horloge
  (`now()` de Postgres, `DateTime.now()` du jumeau), et toutes ses
  expirations sont relatives à elle.
- Comportement inchangé à l'instant exact de la fin : expirée strictement
  après `expiresAt`, comme avant.

## 3. Ce qui ne change pas, et pourquoi

Les dépôts (`activate`, `pendingByEmail`, la réinvitation d'une ligne morte)
jugent toujours la fenêtre à leur horloge : celle de la base en production
(`expires_at > now()`). Leur passer l'horloge du service changerait la
production (l'horloge de l'application au lieu de celle de la base) : hors
sujet. Conséquence pour les tests : un test qui atteint `activate` avec une
horloge figée doit écrire une fin relative à l'horloge réelle. C'est déjà le
cas de tous (balayage, §5).

## 4. Les tests

- **Rouge d'abord :** le test B0.24 était rouge sur `main` (`aaac273f`) et
  passait avec ce correctif, sans toucher au test, quelle que soit la date
  réelle : sa relecture renvoie `null` avant `activate`. Entre-temps, #914 l'a
  fait lire l'horloge réelle ; son commentaire, qui disait l'expiration lue
  au mur, est mis à jour ici.
- **Le test qui l'aurait vu tout de suite :** « invitation expiry is judged by
  the service clock, whatever the wall clock says ». Deux horloges figées loin
  d'aujourd'hui, en 2001 et en 2101, une dans chaque sens. Invitation à J,
  puis à J+6 : drapeau `expired` faux, `member_exists`, `checkAcceptable` ok ;
  à J+8 : drapeau vrai, `invitation_expired`. Vu rouge contre l'ancien
  comportement (l'expiration lue au mur) : les deux cas échouent. Puis chaque
  lecture remise au mur seule, à son tour : chacune fait échouer au moins un
  cas (le contrôle des doublons, celui de 2001).
- **Un test qui ne passait que grâce au défaut :** « an expired invitation
  cannot be accepted » invitait huit jours en arrière et acceptait avec
  l'horloge du service encore huit jours en arrière. Il avançait seulement
  parce que l'expiration se lisait au mur. L'horloge avance maintenant
  jusqu'à aujourd'hui avant l'acceptation : le scénario réel.

## 5. Le balayage de `backend/test/`

Cherché : une date figée dont l'expiration est jugée à l'horloge du mur. Lu
côté code : chaque fichier de `lib/` qui reçoit une horloge **et** lit
`DateTime.now()`. Lu côté tests : chaque fin (`expiresAt`, `trialEndsAt`,
`paidUntil`) qui n'est pas relative à l'horloge réelle, et chaque test qui
fige son horloge et touche une invitation.

- **Aucun autre cas trouvé.** Les dépôts d'authentification écrivent et
  jugent la fin d'un code à l'horloge du mur, et leur horloge injectée ne
  sert qu'au délai de grâce du jeton, des deux côtés. Les abonnements, la
  validation et la purge reçoivent « maintenant » en paramètre. Les dates
  figées des tests Postgres (`trialEndsAt` 2026–2030) sont écrites puis
  relues, jamais jugées. Le remplissage de dev ne lit que `unpublished_at`.
  La remise à zéro de la démo juge à son horloge.
- Chaque test qui fait `invite` puis `activate` sur le jumeau (envoi de
  fichiers, abonnements, Postgres, analyses, admin) écrit déjà sa fin depuis
  l'horloge réelle. `salon_subscription_test.dart` le dit en commentaire.

Hors de cette classe et non traité ici : les rendez-vous datés de 2030 des
tests de réservation sont dans le futur exprès ; ils ne sont pas jugés comme
des expirations.
