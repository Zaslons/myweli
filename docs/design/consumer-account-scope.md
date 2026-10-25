# App cliente — un compte qui sort emporte ses données : la déconnexion, la suppression, la session refusée — spec

| | |
|---|---|
| **Statut** | **Brouillon — en attente de validation** (Q1, Q2 au §8). Rien n'est construit. |
| **Owner** | Sadreddine |
| **Last updated** | 2026-10-25 |
| **PRD ref / phase** | FR-AUTH-003 (session, « explicit logout ») · FR-AUTH-005 (suppression du compte) · V1 |
| **Module** | app cliente — l'authentification et l'état des écrans (`AuthProvider`, les fournisseurs montés dans `main.dart`) |
| **Origine** | [hygiene-batch9.md](hygiene-batch9.md) §14 (PR F1) : « Les fournisseurs de l'app cliente ne sont pas vidés à la déconnexion […] Hors de B9.8 ; proposé à part. » · BACKLOG **B9.13** |
| **Base** | `feat/batch9-components` (PR F1, `365a79b0`) : F1 réécrit les mêmes fournisseurs (`listError`, la sélection gardée vers B) ; cette PR s'empile dessus. |
| **Skills checked** | myweli-dev-guardrails ✓ · aucun changement serveur, ni web |

## 1. Le constat — relu sur le vrai chemin de code (`365a79b0`)

**Les fournisseurs vivent toute l'app.** `main.dart:129-141` crée
`AppointmentProvider`, `FavoritesProvider`, `MessagingProvider`,
`NotificationsProvider`, `NotificationPreferencesProvider` (et
`ProviderProvider`, `LocalityProvider`) une fois, au-dessus de
`MaterialApp.router`. Rien ne les recrée quand le compte change.

**Les trois façons de sortir d'un compte, et ce que chacune vide :**

| Sortie | Où | Ce qui est vidé |
|---|---|---|
| « Déconnexion » | `profile_screen.dart:163-176` → `AuthProvider.logout()` | les favoris seuls (`clearFavorites()`), **avant** la déconnexion — vidés même quand elle échoue |
| « Supprimer mon compte » | `profile_screen.dart:200-212` → `AuthProvider.deleteAccount()` | les favoris seuls |
| La session refusée par le serveur | `refreshing_http_client.dart:131-135` (le jeton de renouvellement révoqué, expiré, réutilisé, ou le compte supprimé ailleurs) | **rien, et le compte reste affiché** — voir plus bas |

**Ce qui reste du compte A quand B se connecte sur le même téléphone**
(chaque ligne lue dans le fournisseur, puis chez qui la lit) :

| Fournisseur | Ce qu'il garde de A | Où B le voit |
|---|---|---|
| `AppointmentProvider` | `appointments`, `selectedAppointment`, `error`/`errorCode`/`listError`, la clé d'envoi `_bookingKey` | « Mes rendez-vous » (trois onglets), la bande « Derniers rendez-vous » de l'Accueil, le détail d'un rendez-vous, et **« Donner mon avis » sur la page d'un salon** (`provider_detail_screen.dart:1061` lit `latestCompletedAppointment`) — jusqu'à la réponse de B |
| `NotificationsProvider` | la liste, `loadFailed`, les « lu » en cours (`_writing`, `_confirmedDuringLoad`, `_loadsOut`) | la liste des notifications, « Tout marquer comme lu » |
| `NotificationPreferencesProvider` | les préférences de A, `loadedPrefs` | « Préférences » : les interrupteurs de A une image, puis tant que la lecture de B n'a pas répondu |
| `FavoritesProvider` | vidé — mais une lecture de A encore en route s'y écrit après | les cœurs, « Mes favoris » |
| `MessagingProvider` | `outbox` : les confirmations envoyées pour les rendez-vous de A (numéro, salon, heure) | personne ne l'affiche aujourd'hui ; la donnée est là |
| `ProviderProvider` | `_starsByVisit` : les étoiles que A a données, par rendez-vous | jamais (les ids de rendez-vous de A ne sont pas ceux de B) ; la donnée est là |
| `AuthProvider` lui-même | `updateErrorCode`, `emailDevCode` ; **un envoi de photo de profil en cours** | une photo envoyée par A et finie après la connexion de B est enregistrée **sur le profil de B** (`uploadAvatar` → `updateUser` → `PATCH /me` sous le jeton de B) |

**Les réponses en route.** Vider ne suffit pas : une lecture partie sous A
(3G lente) qui répond après la déconnexion écrit les données de A dans le
fournisseur vidé. `loadAppointments` (`appointment_provider.dart:108`)
affecte la liste sans regarder qui l'a demandée ; `bookAppointment`
**ajoute** le rendez-vous créé (`:171`) à la liste en place — celle de B
si B a déjà lu la sienne, et elle y reste jusqu'au prochain chargement.

**La session refusée ne sort de rien.** Quand le serveur refuse le
renouvellement, `RefreshingHttpClient._exchange` efface la session stockée
(`:134`) et rend le 401 d'origine. Mais `AuthProvider._user` et
`ApiAuthService._currentUser` (`api_auth_service.dart:354-356`, un cache en
mémoire) gardent A : le Profil affiche A, et chaque lecture du compte
répond « Non connecté » (`api_appointment_service.dart:211-213` — la session
n'a plus de jeton) ou « Veuillez vous reconnecter. », jusqu'au redémarrage
de l'app. Personne ne remet rien à zéro, parce que personne ne sait.

## 2. Ce qui change

### 2.1 Un seul contrat, comme `ProSalonScope`

Le précédent de la maison est `core/access/pro_salon_scope.dart` : chaque
magasin d'un salon implémente `SalonScoped.resetForSalonSwitch()`, s'inscrit
dans `main_pro.dart` par `ProSalonScope.track(...)`, et
`ProAuthProvider.switchSalon` appelle `ProSalonScope.resetAll()`. L'app
cliente reçoit son jumeau, au niveau du **compte** :

- `core/access/account_scope.dart` : `abstract class AccountScoped { void
  resetForAccountChange(); }` et `AccountScope.track(...)` /
  `AccountScope.resetAll()` (références faibles, comme le jumeau).
- `main.dart` : chaque fournisseur du compte est créé par
  `AccountScope.track(...)` — `AppointmentProvider`, `NotificationsProvider`,
  `NotificationPreferencesProvider`, `FavoritesProvider`, `MessagingProvider`,
  `ProviderProvider`. **Pas** `LocalityProvider` (les communes, les mêmes pour
  tous).
- `resetAll()` **continue quand un magasin lève** (consigné par `AppLogger`,
  comme `ProSalonScope.bookingCreated`) : une sortie de compte qui
  s'arrêterait au troisième magasin laisserait les trois suivants à A.

**Ce que chaque magasin oublie** (retour à « pas encore demandé », puis une
notification) :

| Magasin | Remis à zéro | Gardé |
|---|---|---|
| `AppointmentProvider` | la liste, la sélection et son id, `isLoading`, les trois erreurs, la clé d'envoi (`settle()`) | — |
| `NotificationsProvider` | la liste, `loadFailed`, `error`, `isLoading`, les « lu » en cours, le compteur des lectures | — |
| `NotificationPreferencesProvider` | les préférences (valeurs par défaut), `loaded`, `loadFailed`, `saving`, `error`, `isLoading` | — |
| `FavoritesProvider` | ce que fait `clearFavorites()` aujourd'hui, plus `isLoading` | — (`clearFavorites` disparaît : la remise à zéro le remplace) |
| `MessagingProvider` | `outbox` | — |
| `ProviderProvider` | `_starsByVisit` seulement | **tout le reste** : les salons, le salon ouvert, la commune choisie, le tri — publics, et les vider blanchirait l'Accueil sous la personne |
| `AuthProvider` (le sien) | `updateErrorCode`, `emailDevCode` | `error`/`otpErrorCode` : ce sont ceux de la connexion en cours |

**Ce qui n'est pas du compte et reste** : les histoires vues
(`StorySeenService`, des stories publiques), « déjà demandé la permission
des notifications » (`push_registration.dart:22`), la commune choisie —
trois réglages de l'appareil, pas de la personne.

### 2.2 Un seul déclencheur : le compte change

`AuthProvider` fait passer **chaque** changement de `_user` par un seul
endroit. Quand l'id du compte change — A → personne, personne → B, A → B —
`AccountScope.resetAll()` est appelé **dans le même bloc synchrone**, avant
la notification : aucune image ne voit le nouveau compte avec les données de
l'ancien. Les chemins :

- « Déconnexion » réussie ; une déconnexion qui échoue (le coffre du
  téléphone refuse) laisse A connecté **et** ses données — aujourd'hui elle
  vidait les favoris d'un compte encore connecté.
- « Supprimer mon compte » réussie ; refusée, rien ne bouge.
- La session refusée (§2.4).
- Toute connexion (Google, Apple, e-mail, téléphone) — d'un autre compte, ou
  du même : ce qui a pu tomber entre deux (une lecture de personne échouée)
  repart de zéro.
- La reprise au démarrage (personne → A) : rien n'est encore chargé, la
  remise à zéro ne coûte rien.

Le même compte (`updateUser`, la photo, le téléphone) ne remet rien à zéro.

Les écrans n'appellent plus rien à la main : `profile_screen.dart` perd ses
deux `clearFavorites()`.

### 2.3 Les réponses en route n'appartiennent plus à personne

Chaque magasin tient un **numéro de compte** (un entier, incrémenté par sa
remise à zéro). Une lecture ou une écriture le relève avant d'attendre ; à
la réponse, s'il a changé, **elle n'écrit rien** — ni données, ni erreur, ni
`isLoading` (une lecture de B peut être en cours). C'est la garde que F1 a
mise à `loadAppointmentById` (`_selectedId != id`), étendue au compte.

Une écriture déjà partie reste faite sur le compte de A — c'est juste, c'est
le sien ; seul son effet local est jeté.

**La photo de profil.** `uploadAvatar` revérifie le compte entre l'envoi du
fichier et le `PATCH /me` : une photo de A finie après la sortie n'est
enregistrée sur personne.

### 2.4 La session refusée devient une sortie

- `RefreshingHttpClient` **annonce** chaque session qu'il efface (le
  renouvellement refusé, une session illisible), par un flux statique qui
  porte l'identité de la session — la clé même de son vol unique
  (`_inflight`). Une panne de transport garde la session et n'annonce rien,
  comme aujourd'hui.
- `AuthServiceInterface` gagne `Stream<void> get sessionEnded` : la session
  du client a pris fin **sans** déconnexion. `ApiAuthService` relaie
  l'annonce de **sa** session (pas celle du Pro, qui a sa clé) et oublie son
  `_currentUser`. `MockAuthService` peut la simuler (une couture de test) —
  les doublures savent échouer comme le serveur.
- `AuthProvider` l'écoute : connecté, le compte prend fin — `_user` à
  personne, la remise à zéro (§2.2), et un avis « session refusée » pour
  l'écran (§2.5). Déjà sorti, rien.

**Ce qu'elle ne fait pas** : désinscrire le téléphone des notifications —
l'appel demande une session vivante. Le jeton passe au prochain compte qui
se connecte ici (`ON CONFLICT (token) DO UPDATE SET user_id`,
`postgres_device_token_repository.dart:22`) ; d'ici là, une notification de A
peut encore arriver sur ce téléphone — celui dont A se servait.

### 2.5 Ce que la personne voit (Q1)

- **« Déconnexion » et « Supprimer mon compte »** : rien ne change à l'écran
  (la confirmation, puis la connexion ; « Compte supprimé » pour la
  suppression).
- **La session refusée — proposé (Q1 a)** : la personne reste où elle est.
  - Une barre (`AppSnackBar`, info) : **« Votre session a expiré.
    Reconnectez-vous. »**, avec l'action **« Se connecter »** →
    `/login?returnTo=<ici>`.
  - Sur un écran du compte — `/bookings`, `/appointment/…`,
    `/notifications`, `/profile/edit`, `/profile/data`,
    `/profile/notifications`, `/booking/confirm` — l'app va à
    `/login?returnTo=<cet écran>` avec la même barre : c'est ce que « Mes
    rendez-vous » fait déjà pour une personne non connectée
    (`my_bookings_screen.dart:45-52`). Une réservation en cours sur
    `/booking/confirm` reprend, ses paramètres dans `returnTo`, après la
    connexion.
  - Ailleurs (Accueil, salons, carte, Profil, « À propos ») l'écran se
    redessine en invité, comme il le fait déjà.
  - Un seul endroit l'écoute : un widget à la racine (`MaterialApp.builder`,
    sous le `ScaffoldMessenger`), pas chaque écran.

Le cas réel le plus probable : l'app rouverte après longtemps, la session
morte ; la première lecture du compte (la bande de l'Accueil) la découvre —
l'Accueil reste, la barre le dit.

## 3. Les états et cas limites

- **Une lecture en route à la sortie** (« Mes rendez-vous » sur 3G, puis
  Profil → Déconnexion) : sa réponse tombe dans le vide.
- **Une réservation en route à la sortie** : faite sur le compte de A, elle
  n'est pas ajoutée à la liste de B.
- **Deux annonces de fin** (deux services refusés ensemble) : une sortie,
  une barre — la seconde trouve le compte déjà sorti.
- **La fin pendant une « Déconnexion »** : la déconnexion finit, l'annonce
  ne trouve plus de compte ; pas de barre.
- **La fin pendant un envoi de réservation** : le `POST` a reçu un 401, il
  n'a rien créé ; la personne se reconnecte et revient sur l'écran de
  confirmation ; la clé d'envoi est neuve.
- **A se reconnecte** : tout est relu, rien de l'ancienne session ne
  s'affiche en attendant.
- **Un magasin lève dans sa remise à zéro** : consigné, les autres sont
  remis à zéro quand même ; la sortie n'échoue pas.
- **Une notification touchée pendant la déconnexion** (le tampon de
  `PushMessageHandler`, rejoué à la connexion) : inchangé, hors périmètre
  (§9).

## 4. Le contrat

Aucun changement serveur, ni d'`openapi.yaml`. La garde « portée par
compte » des clés d'envoi existe déjà côté serveur
([write-idempotency.md](write-idempotency.md)) ; la clé neuve après une
sortie est une hygiène, pas une correction.

## 5. La sécurité

- **Ferme une divulgation sur l'appareil** : les rendez-vous, notifications,
  préférences et favoris d'un compte affichés à un autre sur le même
  téléphone (MASVS-STORAGE, en mémoire) — et **une écriture d'un compte sur
  un autre** (la photo de profil).
- Le serveur reste l'autorité : un « Donner mon avis » sur le rendez-vous de
  A envoyé sous B est refusé par lui ; c'est l'affichage qui mentait.
- Rien n'est consigné du compte ; l'annonce ne porte que l'identité de la
  session (`'secure:myweli_session'`), pas un jeton.
- Pas de nouvelle ligne au modèle de menace du serveur (BACKEND.md §7) :
  aucune frontière serveur ne bouge.

## 6. Les tests (rouges d'abord)

**Unitaires**, un groupe par magasin :
- la remise à zéro ramène chaque champ du tableau §2.1 à « pas encore
  demandé » et notifie ;
- une lecture partie avant la remise à zéro qui répond après n'écrit rien
  (données, erreur, `isLoading`) — et une lecture de B partie entre les deux
  garde son `isLoading` ;
- une écriture partie avant : son effet local est jeté
  (`bookAppointment` n'ajoute rien, `markRead` ne repasse rien à lu…).

**`AccountScope`** : `track`/`resetAll`, la référence faible, un magasin qui
lève n'arrête pas les autres.

**`AuthProvider`** : la remise à zéro une fois par sortie (déconnexion,
suppression, fin de session), et à la connexion ; jamais pour une
déconnexion échouée, une suppression refusée, `updateUser` ; **avant** la
notification (un écouteur qui lit les magasins à la notification les trouve
vides) ; la photo finie après la sortie n'appelle pas `updateUser`.

**`RefreshingHttpClient` / `ApiAuthService`** : un renouvellement refusé
annonce la session (sur chacun de ses chemins d'effacement) ; un succès ou
une panne de transport, non ; `ApiAuthService.sessionEnded` relaie la
sienne, pas celle du Pro, et oublie `_currentUser`.

**Le câblage** : une épingle de source sur `main.dart` — chaque fournisseur
du tableau §2.1 est créé par `AccountScope.track`, `LocalityProvider` non.

**Le widget demandé** (`test/widget/account_switch_test.dart`) : A connecté,
son rendez-vous affiché dans « Mes rendez-vous » et sur l'Accueil ; Profil →
Déconnexion → connexion de B avec sa lecture **tenue** : à chaque image
pompée, le rendez-vous de A n'est nulle part (Accueil, « Mes rendez-vous »,
le détail de son id) ; la lecture de B échoue → toujours rien de A ; elle
répond → celui de B. Et la session refusée : la barre, et un écran du compte
qui part vers la connexion avec son `returnTo`.

**Les mutations**, sur le travail commis : chaque remise à zéro retirée (une
par magasin), chaque garde de numéro retirée (une par lecture et écriture
gardée), le déclencheur retiré de chaque sortie, la remise à zéro après la
notification au lieu d'avant, `resetAll` qui s'arrête à un magasin qui
lève, l'annonce retirée, le filtre de session de `ApiAuthService`, la
revérification de la photo, chaque `track` retiré de `main.dart`.

## 7. Les mots

- **« Votre session a expiré. Reconnectez-vous. »** — la barre de la session
  refusée (ce qui s'est passé → ce qu'il faut faire, §17). « Expiré » couvre
  le cas courant ; une session révoquée ou un compte supprimé ailleurs la
  reçoivent aussi : la personne n'a qu'une chose à faire.
- **« Se connecter »** — son action, le verbe du bouton du Profil.

## 8. Questions au propriétaire

- **Q1 — la session refusée : où va la personne ?**
  - **(a) Elle reste où elle est (recommandé).** La barre et son « Se
    connecter » ; seul un écran du compte part vers la connexion, avec son
    `returnTo`. Une personne qui regardait un salon n'en est pas arrachée —
    et l'écran de connexion atteint par `go` n'a pas de retour (§9).
  - (b) Toujours vers la connexion, avec `returnTo`, comme le bouton.
  - (c) Sans un mot : l'app passe en invité.
- **Q2 — la même faille côté Pro.** Lu dans le code, non vérifié à l'écran :
  `ProAuthProvider.logout()` (`pro_auth_provider.dart:1081-1110`) ne remet
  pas les magasins par salon à zéro, aucune connexion Pro non plus, et le
  fil des notifications Pro (`main_pro.dart:163-170`, du compte) n'est
  jamais vidé. **(a) À part, une PR à elle (recommandé)** — la tâche est
  l'app cliente, et le contrat construit ici (`AccountScoped`) servira tel
  quel ; (b) dans cette PR.

## 9. Hors périmètre — noté

- **Le Pro** (Q2).
- **L'écran de connexion atteint par `go` n'a pas de retour** : après
  « Déconnexion », la personne ne peut que se reconnecter ou quitter l'app
  (le démarrage suivant va à l'Accueil en invité). C'est vrai aujourd'hui du
  bouton et de « Mes rendez-vous » ; Q1 (a) ne l'étend pas.
- **Le tampon des notifications touchées** (`PushMessageHandler`) : une
  notification de A touchée pendant la déconnexion est rejouée à la
  connexion de B ; le serveur refuse son rendez-vous, l'écran dit
  « introuvable ». Le vider à la remise à zéro casserait la reprise au
  démarrage (personne → A), qui est son rôle.
- **Le renvoi sous une autre session** : `RefreshingHttpClient.send` rejoue
  une requête qui a reçu un 401 avec le jeton stocké s'il a changé
  (`:61-63`) — si A est sorti et B entré pendant ce vol, la requête de A
  repart sous B. Il faut que le jeton de A expire pendant la requête **et**
  qu'une connexion entière tienne dans ce vol ; la garde du §2.3 jette déjà
  la réponse. Noté, pas traité.
- **La doublure des rendez-vous ignore le compte**
  (`MockAppointmentService.getUserAppointments` rend tout) : en démo, B voit
  les rendez-vous semés, quels qu'ils soient. Fidélité de la doublure, pas
  cette faille ; le test du §6 utilise sa propre doublure.

## 10. Definition of done

- [ ] `flutter analyze` = 0 · format propre · la suite verte.
- [ ] Chaque garde vue rouge par mutation sur le travail commis (§6).
- [ ] Ce spec « construit » (§11), le BACKLOG (B9.13), une entrée dans
  `docs/roadmap/entries/`, l'index `docs/design/README.md`.
- [ ] Branche de fonctionnalité, PR ouverte pour revue ; aucune attribution
  à Claude.
