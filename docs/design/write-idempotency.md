# Une écriture dont la réponse se perd — la clé d'idempotence — spec

| | |
|---|---|
| **Statut** | **Déployé le 2026-10-21** (#666, `deadda7`, révision `myweli-api-00043-gqr`) — §11. Construit le même jour ; ce qui a été vu : §10. Validé le même jour — Q1 (décision 11) : **la clé d'idempotence** ; Q2 : **redemander une fois, sans rien dire** ; Q3 : **les quatre écritures** ; Q4 : **les mots tels qu'écrits** (§8) |
| **Owner** | Sadreddine |
| **Last updated** | 2026-10-21 |
| **PRD ref / phase** | Réservation, journal Pro, clients, équipe (V1) · règle BACKEND.md : « les mutations argent/réservation prennent une clé d'idempotence » |
| **Module** | backend (les quatre POST qui créent, une table, le cron quotidien) ; web (le BFF, le tunnel de réservation, la réservation manuelle, les notes, les invitations) ; app (les mêmes quatre écritures) |
| **Origine** | [BACKLOG.md](../BACKLOG.md) lot 2 : B2.1, décision 11 |
| **Skills checked** | myweli-backend-guardrails ✓ · myweli-web-guardrails ✓ · myweli-dev-guardrails ✓ |

## 1. Le constat — relu sur le vrai chemin de code

Une écriture que le serveur **a faite**, mais dont la réponse **ne revient
pas** (le réseau tombe au retour, le proxy du web répond 502, l'app ne reçoit
rien) :

| Écriture | Ce qui se passe aujourd'hui | Où |
|---|---|---|
| **Réserver** (client, web et app) | le client lit « La réservation a échoué. Réessayez. » ; s'il réessaie : **409 `slot_unavailable`** — « Ce créneau vient d'être pris » — son propre créneau ; avec « Sans préférence » et plusieurs fauteuils libres : **une seconde réservation** | `web/components/booking/BookingFlow.tsx:398-414`, `backend/routes/appointments/index.dart:163` |
| **Réserver pour un client** (Pro, web et app) | même chose : 409 ou un doublon | `backend/routes/providers/[id]/appointments.dart:96` |
| **Ajouter une note** sur la fiche client | réessayer **ajoute la note deux fois** (201 deux fois) | `…/clients/[clientId]/notes/index.dart:33-43` |
| **Inviter un membre** | réessayer répond **409 `member_exists`** — alors que l'invitation et son e-mail sont partis | `backend/routes/me/provider/members/index.dart:44-58` |

Et le cas voisin, déjà à moitié traité (#630) : la réponse **2xx** arrive mais
son corps est perdu — le web dit « Réservation envoyée » **sans le bloc
d'acompte** (il n'a ni l'identifiant ni le montant).

Le serveur n'a **aucune** idempotence aujourd'hui ; l'app ne réessaie jamais
seule (seulement après un 401, sans risque : rien n'a été fait) ; le web non
plus.

## 2. Les deux voies (Q1 — décision 11)

- **(a) La clé d'idempotence, côté serveur (recommandé).** Chaque envoi d'un
  formulaire porte un en-tête `Idempotency-Key` ; le serveur garde la première
  réponse réussie 24 h et la **rejoue** pour la même clé, au lieu de créer à
  nouveau ou de répondre 409. Couvre les quatre écritures, sur le web et dans
  l'app. Il faut un déploiement du serveur et une migration.
- **(b) Le web seulement.** Avant de dire « échoué », chercher son propre
  rendez-vous dans « Mes rendez-vous ». Ne couvre ni l'app, ni la réservation
  Pro, ni les notes, ni les invitations ; et « le mien » est une devinette
  (même salon, même heure).

La suite décrit **(a)**.

## 3. Le serveur

- **Les quatre POST** acceptent `Idempotency-Key` (facultatif : un client qui
  ne l'envoie pas se comporte comme aujourd'hui). Valeur : 8 à 128 caractères
  `[A-Za-z0-9_-]`, sinon 400 `invalid_idempotency_key`.
- **La portée** : le compte (le `sub` de la session) + la route exacte (avec
  ses identifiants) + la clé. Deux comptes ne peuvent pas se rejouer l'un
  l'autre.
- **Le parcours** :
  1. réserver la clé (`INSERT … ON CONFLICT DO NOTHING`, une ligne « en
     cours ») ;
  2. **déjà une réponse gardée** pour cette clé → la **rejouer** (même statut,
     même corps), en-tête `Idempotent-Replayed: true` ;
  3. **déjà en cours** (la même demande arrive deux fois en même temps) →
     **409 `request_in_progress`** ;
  4. **la même clé avec un autre corps** (une empreinte du corps est gardée)
     → **422 `idempotency_key_reused`** ;
  5. sinon, l'écriture ; **réussie** → la réponse est gardée avec la clé ;
     **refusée** (409 créneau pris, 400…) → la clé est libérée : un nouvel
     essai repart de zéro.
- **Une table** `idempotency_keys` (migration `0040`) : compte, route, clé,
  empreinte, statut, corps, date. **Purgée après 24 h** par le cron quotidien
  qui purge déjà deux tables (`/internal/cron/subscriptions`), et à la
  suppression du compte (l'effacement L1).
- **Rien d'autre ne change** : les envois de l'invitation, les notifications
  au salon, le décompte des places — tout cela n'a lieu qu'une fois, à
  l'écriture réelle ; un rejeu ne fait que relire la réponse.
- `openapi.yaml` : l'en-tête et les trois nouveaux codes sur les quatre
  opérations, dans la même PR. BACKEND.md §7 : une ligne de menace (les corps
  gardés 24 h, la portée par compte).

## 4. Les clients (web et app)

- **Une clé par envoi de formulaire** : créée au premier appui sur le bouton
  (« Réserver », « Créer », « Ajouter la note », « Envoyer l'invitation »),
  **réutilisée** à chaque nouvel essai de ce même envoi ; **une nouvelle** dès
  que le formulaire change (un autre créneau, un autre texte) ou après une
  réussite. Web : `crypto.randomUUID()` ; app : le paquet `uuid` (déjà là).
- **Le BFF du web** transmet l'en-tête sur ces quatre routes, et rien d'autre.
- **Une réponse perdue (Q2)** : le client **redemande une fois, tout de suite,
  avec la même clé** — le serveur rejoue la réservation faite, et l'écran
  continue comme si de rien n'était (« Réservation envoyée ✓ », **avec** le
  bloc d'acompte). Un 409 `request_in_progress` : attendre un instant et
  redemander (trois fois au plus). Si rien ne répond toujours : le message
  (§8), et « Réessayer » renvoie la même clé — sans risque.
- **Le corps perdu d'un 2xx** : même chose — redemander avec la même clé
  rapporte le corps, donc le bloc d'acompte.

## 5. Les états

| Situation | Ce que voit la personne |
|---|---|
| La réponse arrive | comme aujourd'hui |
| Elle se perd, le second essai l'obtient | comme aujourd'hui (le rejeu est invisible) |
| Elle se perd deux fois | le message de §8 ; « Réessayer » sans risque |
| Le créneau était vraiment pris par quelqu'un d'autre | « Ce créneau vient d'être pris. Choisissez-en un autre. » (inchangé) |
| Le formulaire change après un échec | une nouvelle clé : c'est une nouvelle demande |

## 6. Sécurité, vie privée, coûts

- Un rejeu ne sert que la réponse **que ce compte** a reçue (portée par
  compte) ; une clé devinée ne donne rien à un autre compte.
- Les corps gardés contiennent ce que la réponse contenait déjà (une
  réservation Pro : le nom et le téléphone du client) — 24 h, purgés, effacés
  avec le compte. La politique de confidentialité n'a pas à changer (même
  donnée, même finalité, moins de 24 h).
- Une ligne par écriture créatrice, purgée chaque jour : négligeable.

## 7. Les tests (rouges d'abord)

- **Serveur** : pour chacune des quatre routes — même clé → la même réponse,
  **une seule** création (une seule réservation, une seule note, une seule
  invitation, **un seul e-mail**) ; sans clé → comme aujourd'hui ; autre corps
  → 422 ; en parallèle → 409 `request_in_progress` ; un refus libère la clé ;
  autre compte, même clé → aucune fuite ; purge à 24 h ; effacement du
  compte ; dépôt Postgres ; migration ; contrat.
- **Web** : le BFF transmet l'en-tête (et seulement sur ces routes) ; le
  tunnel : réponse perdue → second essai même clé → « Réservation envoyée »
  avec l'acompte ; deux pertes → le message ; « Réessayer » garde la clé ; un
  créneau changé → une nouvelle clé. e2e : le stub perd la première réponse.
- **App** : les mêmes, sur les fournisseurs (réservation client, réservation
  Pro, note, invitation).
- **Mutations** : le rejeu qui recrée, la clé non libérée après un refus, la
  portée sans le compte, le client qui change de clé au nouvel essai.

## 8. Les mots (Q4)

- Une réservation (client) dont la réponse s'est perdue deux fois :
  **« Pas de connexion. Réessayez. »** — la phrase que l'app et le web disent
  déjà quand rien ne répond, et qui devient vraie : réessayer ne peut plus
  créer de doublon. « La réservation a échoué. Réessayez. » reste pour un vrai
  refus du serveur.
- Aucune autre phrase nouvelle : le rejeu et l'attente d'une demande « en
  cours » sont invisibles.

## 9. Questions au propriétaire

- **Q1 (décision 11)** — **(a) la clé d'idempotence** sur le serveur, pour le
  web et l'app (recommandé), ou **(b)** le web seulement (« Mes rendez-vous »
  avant de dire « échoué ») ?
- **Q2** — une réponse perdue : **redemander une fois tout de suite, avec la
  même clé, sans rien dire** (recommandé), ou montrer le message et laisser
  « Réessayer » le faire ?
- **Q3** — le périmètre : **les quatre écritures** (réserver, réserver pour un
  client, une note, une invitation — recommandé), ou seulement les deux
  réservations d'abord ?
- **Q4** — les mots (§8) : « Pas de connexion. Réessayez. » quand rien n'a
  répondu, à la place de « La réservation a échoué. Réessayez. » ?

**Décisions (2026-10-21).** Q1, Q2, Q3 et Q4 : les recommandations, telles qu'écrites.

## 10. Construit — ce qui a été vu

**Comme écrit**, avec ces précisions :
- **Le serveur** : `lib/src/idempotency/` (le magasin et `idempotent()`), le
  jumeau Postgres `lib/src/db/postgres_idempotency_store.dart`, la migration
  `0040_idempotency_keys`. La portée garde la **requête** de l'adresse avec le
  chemin : `?salonId=` choisit le salon d'une invitation, deux salons ne se
  rejouent donc pas l'un l'autre.
- **Une demande morte en route** : une clé restée « en cours » plus de
  **5 minutes** (au-delà du plafond de 300 s de Cloud Run, aucune demande ne
  tourne encore) est reprise — sinon chaque nouvel essai aurait entendu
  `request_in_progress` pendant 24 h.
- **Le magasin en panne n'empêche rien** : une erreur du magasin est une
  ligne `idempotency_unavailable` et l'écriture passe comme avant les clés
  (les quatre écritures ont besoin de la même base quelques lignes plus loin).
- **Le BFF du web** : une API qui ne répond pas du tout (la connexion vers
  elle coupée) est un **502** — elle sortait de la route en exception. C'est
  la « réponse perdue » que le navigateur redemande.
- **L'app** : comme le web, une réponse 2xx sans son corps est redemandée ;
  sans corps une seconde fois, l'app dit « Pas de connexion. Réessayez. » —
  elle a besoin du rendez-vous pour l'afficher, et « Réessayer » le rejoue.
  Le web, lui, garde « Réservation envoyée » sans le bloc d'acompte, comme
  avant.
- **La clé vit dans le fournisseur de l'app** (pas dans l'écran) : fermer et
  rouvrir la feuille de la même réservation garde la même clé.
- **Le cron** : la purge des clés monte sur `/internal/cron/subscriptions`,
  comme la spec le prévoit. C'est la **quatrième** tâche de ce cron, et son
  commentaire disait qu'une quatrième imposerait d'extraire
  `/internal/cron/maintenance` (un nouveau job Cloud Scheduler) : cette
  extraction est **due**, et laissée à une tranche à part (ci-dessous).

**Trouvé en construisant** :
- **§8 se trompait sur l'app** : il disait que l'app dit déjà « Pas de
  connexion. Réessayez. » quand rien ne répond. Le service des réservations
  (et celui du Pro) disait « Connexion au serveur impossible ». La décision Q4
  est appliquée là où elle porte — **la réservation du client, perdue deux
  fois** — ; la réservation Pro garde sa phrase (« aucune autre phrase
  nouvelle »). Aligner les deux phrases de l'app est le lot 3 (B3.1).
- **Une note revenue sans son texte**, même redemandée : relâcher la clé
  aurait fait d'un nouvel appui sur « Ajouter » une **seconde note**. La clé
  n'est relâchée qu'une fois la note affichée (web et app).
- **Deux trous vus par mutation** (serveur) : la lecture Postgres sans le
  compte — deux comptes ayant fini la même clé pouvaient recevoir la réponse
  l'un de l'autre ; et la réponse gardée dont le flux était déjà lu (le test
  lisait la copie mise en cache par dart_frog, pas ce que le serveur envoie).
  Deux tests de plus, les deux mutations rouges.
- **Le stub de l'e2e** répondait 201 à chaque POST : il rejoue maintenant par
  clé et dit combien de réservations chaque clé a créées
  (`GET /__stub/bookings?key=`).

**Mutations vues rouges** : serveur 23 (le rejeu qui recrée, la clé gardée
après un refus ou une exception, un refus gardé, la portée sans le compte ou
sans la requête, l'empreinte non vérifiée, ni expiration ni reprise, une
réponse finie relâchée, l'effacement de tout le monde, les deux effacements
oubliés, le cron qui ne purge pas, chacune des quatre routes sans la clé, le
flux de la réponse épuisé) ; web 20 (pas de second essai, un second essai
sous une **autre** clé, le corps perdu non redemandé, « en cours » non
attendu, un 502 pris pour un refus, un 500 redemandé, une clé neuve à chaque
fois, `settle` sans effet, chacune des quatre routes du BFF sans la clé, le
cœur du BFF qui transmet tout, l'API morte qui sort en exception des deux
côtés, la vieille phrase, la clé de note relâchée trop tôt, une clé faite du
seul créneau, une clé par appel) ; app 21 (les mêmes sur l'aide d'envoi, la
clé absente de chacun des quatre services, la vieille phrase, chacun des
quatre fournisseurs qui ne relâche jamais sa clé, une clé par appel, une clé
qui ignore l'adresse invitée).

**Vérifié** : serveur — format, analyse, 2 020 tests sur Postgres ; web —
types, lint, 2 000 unitaires, les e2e de la réservation, du Pro et de l'équipe
(50, dont la réponse perdue) ; app — analyse, la suite entière (2 566).

**Ce qui reste** (hors de cette tranche) :
- ~~extraire `/internal/cron/maintenance` (quatre tâches sur le cron des
  abonnements) — un job Cloud Scheduler de plus, à décider~~ — fait :
  [infra-cron-maintenance.md](infra-cron-maintenance.md) ;
- les deux phrases « rien n'a répondu » de l'app (B3.1).

## 11. En production — 2026-10-21

- **Fusionné** (`deadda7`, arbre identique à la tête de la PR) après un e2e
  rouge sur CI que la PR n'avait pas causé : deux workers laissaient
  `pro.spec.ts` compter la galerie partagée du stub pendant le
  « supprimer puis Annuler » d'`axe.spec.ts` (Expected 3, Received 2). Les deux
  tests qui ne regardent que les écrans répondent maintenant eux-mêmes à leurs
  enregistrements (`tests/e2e/_gallery.ts`) ; attendre la restauration ne
  suffisait pas — la fenêtre restait.
- **Déployé** juste après la fusion (le web part sur Vercel à la fusion, et sa
  redemande automatique n'est sûre qu'avec un serveur qui connaît la clé) :
  révision `myweli-api-00043-gqr`, l'empreinte de l'image égale à celle du tag
  `deadda7`, `/health` et `/providers` à 200. Retour arrière possible :
  `myweli-api-00042-468`.
- **La migration `0040`** : aucune ligne ne la nomme (les migrations tournent
  avant `serve()` et ne disent rien quand elles réussissent) ; la preuve est
  venue du cron d'entretien forcé (§11 d'[infra-cron-maintenance.md](infra-cron-maintenance.md)) :
  200 sans `idempotency_prune_failed`, donc la table existe.
- **L'app** atteint les personnes par les stores, plus tard : rien à faire ici.

