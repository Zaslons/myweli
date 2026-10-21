# Le web Pro dit vrai quand une lecture échoue — spec

| | |
|---|---|
| **Statut** | **Validé le 2026-10-21** — Q1 : **le dire, « Inviter » reste utilisable** ; Q2 (décision 14) : **retenir le salon** ; Q3 (décision 15) : **une ligne « indisponible » + « Réessayer »**, « — » pour les tuiles ; Q4 : **les mots tels qu'écrits** · la décision 13 n'a plus d'objet (§1.1) |
| **Owner** | Sadreddine |
| **Last updated** | 2026-10-21 |
| **PRD ref / phase** | Espace Pro web (V1) — parité avec l'app Pro · WEB-SYSTEM §4–§8 (états, ARIA) · SYSTEM.md §17 (les deux phrases) |
| **Module** | web (`components/pro/*`, `lib/api/pro.ts`, `lib/pro/*`) — aucun changement serveur |
| **Origine** | [BACKLOG.md](../BACKLOG.md) lot 4 : B4.1–B4.5 (décisions 13, 14, 15) |
| **Skills checked** | myweli-web-guardrails ✓ · myweli-dev-guardrails ✓ |

## 1. Le constat — relu sur le vrai chemin de code (main `7f18fec`)

### 1.1 Ce qui a changé depuis le backlog (instantané du 2026-10-18)

- **« Mettre en ligne » ne lit plus l'offre** : depuis le 2026-10-19
  (`web-pro-golive-signup-like-app.md`, décision du propriétaire), la carte
  n'a plus d'étape « offre » ; le serveur démarre l'essai à la première mise
  en ligne et décide seul. **La décision 13** (« laisser cliquable et laisser
  le serveur décider ») **est donc déjà la réalité** — elle n'a plus d'objet.
- **« Voir le justificatif »** : le bloc d'acompte du panneau se charge seul et
  dit son échec (`web-pro-journal-panel-deposit.md` §2.3). Corrigé.
- **Mais le faux « Choisissez votre offre » existe ailleurs** : la page
  **Équipe** (`EquipeClient.tsx:100`) ne garde l'offre que si la lecture a
  réussi ; si elle échoue (réseau, 500), elle dit **« Choisissez votre offre
  pour inviter votre équipe. »** à un salon qui en a une — et la barre des
  places disparaît. C'est le B4.1 d'aujourd'hui, et la « barre des places » de
  B4.5.

### 1.2 Ce qui reste, vérifié

| # | Défaut | Où |
|---|---|---|
| B4.1 | L'offre illisible sur Équipe dit « Choisissez votre offre » | `EquipeClient.tsx:100`, `:172–197` |
| B4.1 | L'historique d'une fiche client illisible dit **« Aucune visite enregistrée. »** à côté de « Visites 5 » | `ClientCardClient.tsx:114`, `:476` ; `getClientVisits` rend `items: []` sur un échec |
| B4.1 | « Charger plus » qui échoue **saute une page** : rien n'est ajouté, mais la page avance | `ClientCardClient.tsx:184–187` |
| B4.2 | Après un geste dans la Journée ou la Semaine (accepter, déplacer, annuler), **Calendrier** et **Liste** gardent les anciens rendez-vous jusqu'au rechargement ; « Nouveau rendez-vous » les relit, mais sans numéro de demande (une réponse lente peut écraser une plus récente) | `RendezVousClient.tsx:122`, `:437`, `:472`, `:546` |
| B4.3 | « Mettre en ligne » : `publishSalon` jette le code ; le compte de démonstration (403 `demo_account_locked`) et le salon suspendu (403 `provider_suspended`) lisent « La mise en ligne a échoué. Réessayez. » — et réessaient sans fin ; hors ligne aussi | `lib/api/pro.ts` `publishSalon`, `GoLiveCard.tsx:86` |
| B4.3 | « Mon abonnement », changer d'offre : seul `trial_used` est reconnu ; la démonstration lit « Le changement d'offre a échoué » | `AbonnementClient.tsx:76` |
| B4.4 | « Aujourd'hui » : accepter ou refuser une invitation avec une session morte affiche un échec au lieu d'aller à la connexion (la carte n'y reçoit pas `onUnauthenticated`) | `AujourdhuiClient.tsx:135`, `:176` |
| B4.4 | Un premier `/me` qui échoue dessine le menu **du propriétaire** à n'importe quel rôle (`awaitingProfile` part à `false`, `hasCap` retombe sur la forme propriétaire). Rien ne fuit — le serveur refuse les pages — mais le menu ment | `ProMembershipContext.tsx:172`, `:347` |
| B4.4 | Après un rechargement, « Votre accès à … a été retiré » perd le nom du salon (il ne vit qu'en mémoire) | `ProMembershipContext.tsx:167`, `lib/pro/team.ts:157` |
| B4.5 | La fiche client du panneau (Journée) disparaît en silence si sa lecture échoue | `JournalPanel.tsx:83` |
| B4.5 | Les suggestions de « Nouveau rendez-vous » : une recherche qui échoue est indistinguable de « aucun client » | `ManualBookingDialog.tsx:111` |
| B4.5 | Les tuiles de chiffres d'« Aujourd'hui » : « — » quand la lecture échoue | `AujourdhuiClient.tsx:72`, `:231` |

## 2. Ce qui change

### 2.1 Une lecture qui échoue le dit (B4.1, B4.5)

- **Équipe** : trois états pour l'offre — **présente**, **absente** (404 : la
  phrase d'aujourd'hui, « Choisissez votre offre… ») et **inconnue** (la
  lecture a échoué) : « Impossible de vérifier votre offre. » avec
  « Réessayer » (hors ligne : « Pas de connexion. Réessayez. », par
  `loadFailureMessage`). Le bouton « Inviter » reste utilisable (Q1) : le
  serveur revérifie l'offre (`offer_required`, déjà traduit).
- **Fiche client** : un état `visitsFailed` — l'historique dit
  « Historique indisponible. » avec « Réessayer », jamais « Aucune visite ».
- **« Charger plus »** : la page n'avance que sur un succès ; un échec dit
  « Le chargement a échoué. Réessayez. » sous le bouton, qui redemande **la
  même** page.
- **Le panneau de la Journée** : « Fiche client indisponible. » avec
  « Réessayer » (Q3).
- **Les suggestions** : « Recherche indisponible. » avec « Réessayer » sous
  le champ — la saisie reste libre, on peut toujours créer le client (Q3).
- **Les tuiles de chiffres** gardent « — » (Q3) : ce n'est pas une action.

### 2.2 Calendrier et Liste suivent la Journée et la Semaine (B4.2)

`RendezVousClient` : un `loadItems()` avec son propre numéro de demande (le
modèle de la Journée — une réponse plus vieille que la dernière demande est
ignorée), et un seul `refreshAfterChange()` passé à la grille de la Journée, à
celle de la Semaine et au `onCreated` du dialogue : il relit la vue ouverte
**et** la liste des rendez-vous.

### 2.3 Les refus disent leur raison (B4.3)

- `publishSalon` rend aussi `error`. « Mettre en ligne » :
  `demo_account_locked` → « Compte de démonstration — cette action est
  désactivée. » (`DEMO_ACCOUNT_LOCKED_MESSAGE`) ; `provider_suspended` → la
  phrase du salon qui existe (« Votre salon est suspendu. Contactez MyWeli pour
  le réactiver — vos rendez-vous sont intacts. ») ; rien n'a répondu → « Pas
  de connexion. Réessayez. » ; le reste, la phrase d'aujourd'hui.
- « Mon abonnement », changer d'offre : les mêmes trois cas.

### 2.4 La barrière de « rejoindre » (B4.4)

- **Les deux cartes d'invitations d'« Aujourd'hui »** reçoivent
  `onUnauthenticated` : une session morte mène à la connexion, comme dans la
  barrière.
- **`awaitingProfile` part à `true`** : tant qu'aucun profil n'est arrivé, la
  barre latérale garde son squelette ; un premier `/me` qui échoue lance la
  boucle existante `healProfile` (1, 2, 4… s) au lieu de dessiner le menu du
  propriétaire.
- **Le salon retenu** (Q2) : `{id, nom}` du salon où l'on agit, gardé dans
  `localStorage` à chaque profil reçu, **effacé à la déconnexion** ; après un
  rechargement, « Votre accès à {salon} a été retiré. », comme l'app. Un salon
  retenu qui n'est pas celui révoqué n'est pas nommé (l'identifiant doit
  correspondre).

## 3. Les états

| Situation | Avant | Après |
|---|---|---|
| Équipe, offre illisible | « Choisissez votre offre pour inviter votre équipe. » | « Impossible de vérifier votre offre. » + « Réessayer » |
| Fiche client, historique illisible | « Aucune visite enregistrée. » | « Historique indisponible. » + « Réessayer » |
| « Charger plus » échoue | une page sautée, en silence | « Le chargement a échoué. Réessayez. » ; la même page redemandée |
| Panneau, fiche illisible | rien | « Fiche client indisponible. » + « Réessayer » |
| Suggestions illisibles | comme « aucun client » | « Recherche indisponible. » + « Réessayer » |
| « Mettre en ligne », démo | « La mise en ligne a échoué. Réessayez. » | « Compte de démonstration — cette action est désactivée. » |
| « Mettre en ligne », salon suspendu | idem | « Votre salon est suspendu… intacts. » |
| « Mettre en ligne » hors ligne | idem | « Pas de connexion. Réessayez. » |
| Geste dans la Journée, puis Liste | l'ancienne liste | la liste à jour |
| Invitation, session morte | un échec | la connexion |
| Premier `/me` échoué | le menu du propriétaire | le squelette, puis le bon menu |
| Accès retiré, après rechargement | « Votre accès à ce salon a été retiré. » | « Votre accès à {salon} a été retiré. » |

Hors ligne, toute nouvelle phrase ci-dessus devient « Pas de connexion.
Réessayez. » (SYSTEM.md §17).

## 4. Accessibilité

Chaque phrase d'échec est un `role="alert"` (ou le `ErrorState` de section),
« Réessayer » est un vrai bouton, de 48 px, au clavier ; la phrase des
suggestions est reliée au champ par `aria-describedby`.

## 5. Sécurité et vie privée

Le salon retenu est le **nom public** du salon et son identifiant — rien de
plus — dans le navigateur de la personne, effacé à la déconnexion. Aucune
donnée de client.

## 6. Les tests (rouges d'abord)

- Unitaires (Vitest/RTL) pour chaque ligne du tableau §3, hors ligne et 500
  séparément ; « Charger plus » redemande la même page ; la liste relue après
  un geste de la grille, et une réponse plus vieille ignorée ; le salon retenu
  écrit, relu, effacé à la déconnexion, et ignoré s'il ne correspond pas.
- e2e : un geste dans la Journée, puis « Liste » montre le nouvel état.
- **Mutations** : chaque phrase remise à l'ancienne, l'offre inconnue prise
  pour absente, la page qui avance sur un échec, la liste non relue, le
  numéro de demande ignoré, `onUnauthenticated` retiré, `awaitingProfile` à
  `false`, le salon retenu jamais effacé.

## 7. La livraison

**Deux PR** : (A) B4.1, B4.3, B4.5 — les échecs dits et les refus nommés ;
(B) B4.2, B4.4 — Calendrier/Liste à jour et la barrière. Elles ne touchent pas
les mêmes fichiers.

## 8. Les mots (Q4)

- « Impossible de vérifier votre offre. »
- « Historique indisponible. »
- « Le chargement a échoué. Réessayez. »
- « Fiche client indisponible. »
- « Recherche indisponible. »
- Les autres phrases existent déjà (la démonstration, le salon suspendu, « Pas
  de connexion. Réessayez. », « Votre accès à {salon} a été retiré. »).

## 9. Questions au propriétaire

- **Q1 (remplace la décision 13)** — Équipe, quand l'offre n'a pas pu être
  lue : **le dire, avec « Réessayer », et laisser « Inviter » utilisable**
  (recommandé — le serveur revérifie l'offre), ou bloquer « Inviter » tant
  qu'elle n'est pas lue ?
- **Q2 (décision 14)** — **retenir le dernier salon** `{id, nom}` dans le
  navigateur pour nommer le salon après un rechargement, effacé à la
  déconnexion (recommandé), ou garder la phrase générique ?
- **Q3 (décision 15)** — **une ligne « indisponible » avec « Réessayer »**
  pour la fiche du panneau et les suggestions (l'offre d'Équipe est Q1), et
  « — » pour les tuiles de chiffres (recommandé) ; ou le silence ?
- **Q4** — les mots (§8), tels qu'écrits ?

**Décisions (2026-10-21).** Q1, Q2, Q3 et Q4 : les recommandations, telles qu'écrites.
