# Pro web — une coupure réseau n'est plus un chargement éternel — spec

| | |
|---|---|
| **Statut** | **Décidé le 2026-10-16** (le propriétaire a délégué le choix « racine ou composant par composant » à ce spec) — construit le même jour sur `fix/pro-network-failure` ; §11 dit ce qui a été vu rouge et ce que la revue a ajouté |
| **Owner** | Sadreddine |
| **Last updated** | 2026-10-16 |
| **PRD ref / phase** | Les quatre états de chaque page (SYSTEM.md §12, WEB-SYSTEM §12) · V1 — tableau de bord Pro web |
| **Module** | web Pro — `web/lib/api/pro.ts` (les appels navigateur → BFF Pro) et ses appelants |
| **ROADMAP entry** | [2026-10-16-pro-network-failure.md](../roadmap/entries/2026-10-16-pro-network-failure.md) |
| **Skills checked** | myweli-web-guardrails ✓ · myweli-dev-guardrails ✓ (aucun changement serveur, aucun contrat) · myweli-verification-guardrails (avant de dire « fait ») |
| **Après** | [#616](https://github.com/Zaslons/myweli/pull/616) ([acompte-off-parity.md](acompte-off-parity.md) D3) — fusionné d'abord, le 2026-10-16 (`84ee583b`), comme §8 le demande ; cette branche est rebasée dessus |

## 1. Le défaut, vu dans le code

Trouvé par un relevé en lecture seule pendant
[acompte-off-parity.md](acompte-off-parity.md) (§7, « Le même défaut que D3,
ailleurs ») ; relu ici appelant par appelant.

**Les wrappers lèvent.** `lib/api/pro.ts` appelle `fetch` 45 fois ; une seule
fonction l'attrape (`logoutPro`). Une coupure réseau fait rejeter `fetch`
(`TypeError: Failed to fetch`), et le rejet traverse le wrapper jusqu'à
l'appelant. Douze wrappers lisent en plus le corps d'une réponse 2xx avec un
`await res.json()` nu : un corps perdu en route rejette aussi.

**Les pages ne l'attrapent pas.** Chaque page Pro charge dans un `useEffect`
(fonction async immédiate) ou un `useCallback`, sans `try/catch`. Le rejet
saute `setLoading(false)` : la page reste sur son squelette **pour toujours**,
sans message ni « Réessayer », et la promesse rejetée n'est gérée par personne.
`app/error.tsx` ne voit rien : une frontière d'erreur React n'attrape pas un
rejet dans un effet.

| Page | Chargement | Lectures |
|---|---|---|
| Disponibilités | effet | `/me` |
| Profil | effet | `/me` |
| Médias | effet | `/me` |
| Mon abonnement | effet | `/me`, abonnement |
| Catalogue | `load` | `/me` |
| Fiche client | `load` | `/me`, fiche (visites : §3) |
| Clients | effet + `load` (recherche, filtre, « Charger plus ») | `/me`, clients |
| Équipe | effet | `/me`, membres (offre : §3) |
| Rendez-vous | effet | `/me`, rendez-vous (+ la Journée : §4) |
| Aujourd'hui | effet | `/me`, rendez-vous (stats, offre : §3) |
| Avis | `load` | `/me`, avis |
| Revenus | `init` + `loadPeriod` | `/me`, revenus |
| Vérification | `load` | `/me`, KYC |
| Aperçu du salon | `load` | `/me` |
| Détail d'un rendez-vous | `load` | `/me`, rendez-vous |

Aucune de ces pages ne construit un formulaire modifiable à partir d'une
lecture ratée (vérifié §3) : le défaut est le chargement éternel, pas un
écrasement. La seule qui le faisait, l'Acompte, est réparée par #616 (D3).

**Les enregistrements aussi.** `mutate()` et les autres écritures appellent
`fetch` nu : sur une coupure, l'état « occupé » n'est jamais relâché. Les cas
les plus visibles :

- **« Modifier le numéro »** (fiche client) : la fenêtre ne se ferme pas tant
  qu'elle enregistre (Échap, le fond et « Annuler » sont neutralisés) — une
  coupure y **enferme** le salon jusqu'au rechargement de la page.
- **Connexion Pro** : « Recevoir le code » / « Vérifier » restent désactivés.
- **Export du compte** : « Préparation… » pour toujours.
- **Journée** : un glisser-déposer raté ne dit rien (rejet non géré, pas de toast).
- Toutes les autres : « Enregistrer », « Supprimer », « Mettre en ligne »,
  les dialogues Équipe, la note client, la réservation manuelle, etc.

**Le téléversement aussi.** `lib/pro/upload.ts` demande la signature au BFF
avec un `fetch` nu : le bouton de photo (galerie, avant/après, employé, logo,
pièces KYC) tourne pour toujours. (Le `PUT` vers R2, lui, passe déjà par
`putToStorage`, qui ne lève jamais.)

**L'app** traite la coupure comme une réponse : chaque `api_*_service.dart`
rend `ApiResponse.error('Pas de connexion. Réessayez.')`, et l'écran affiche
son état d'erreur avec « Réessayer » (`client_list_screen.dart`,
`pro_journal_screen.dart`, …).

## 2. Décision : la racine, pas quinze `try/catch`

Deux façons de faire :

- **A — page par page**, comme l'Acompte (`try/catch` + `fail()`) : ~15
  chargements et ~30 enregistrements à envelopper, et chaque page future doit
  s'en souvenir.
- **B — à la racine** : les wrappers de `lib/api/pro.ts` **ne lèvent plus
  jamais**. « Pas de réponse » devient le **statut 0**, et la branche « pas
  200 » que chaque appelant a déjà le traite (§3).

**Choix : B.** Plus petit, et il couvre les pages à venir. Le mécanisme :

1. **`send()`** — le `fetch` du fichier, qui ne lève pas : un rejet devient
   `Response.error()`, la « network error » du standard Fetch (`status` 0,
   `ok` faux, corps vide). Toutes les branches `!res.ok` existantes la lisent
   comme une réponse non 2xx : statut 0, aucun code d'erreur (leur lecture de
   corps a déjà son `.catch(() => ({}))`).
2. **`readJson()`** — la lecture d'un corps 2xx, qui ne lève pas : illisible
   (coupé en route, pas du JSON, `null`) → `undefined`.
   - **Lectures** : 2xx illisible → **statut 0**. Jamais une liste vide
     inventée : aujourd'hui `.catch(() => ({}))` transforme un corps perdu en
     « Aucun rendez-vous », « Aucun avis », une équipe vide.
   - **Écritures** : 2xx illisible → `ok` (le serveur a agi), **sans** la
     charge utile. Les appelants qui en ont besoin ont déjà une branche pour
     son absence (`!r.member`, `!r.offer`, `!r.artist`, `!r.kyc`,
     `r.profile`…) — y compris `selectSalon`, dont le `{}` passé pour un
     profil faisait planter le changement de salon. Ce que ça coûte : §9.
3. **Le statut 0 n'est pas un nouveau code.** `ProMembershipContext`
   fabrique déjà `{ status: 0 }` pour une sonde qui a levé ; c'est désormais
   le wrapper qui le dit. Ses `.catch` deviennent inutiles et restent (ils
   ne coûtent rien et gardent le contexte si un wrapper régressait).
4. `logoutPro` ne change pas : il ne lève déjà pas, et sa distinction
   `'offline'` / `'failed'` est ce dont la session a besoin.

## 3. L'audit : chaque appelant sous le statut 0

**Lectures — toutes vont à leur état d'erreur.** Chaque page du tableau §1
teste `status !== 200` (ou `!== 404` puis `!== 200`) vers son `ErrorState`
et son « Réessayer ».

- **401** : chaque appelant teste `=== 401` → la redirection ne change pas ;
  0 n'est pas 401.
- **404 comme état** : l'abonnement (404 = pas encore d'offre), la fiche client
  (404 = introuvable), le détail d'un rendez-vous (404 = absent de la liste) —
  0 n'est pas 404 : une coupure donne l'erreur, jamais « choisissez une
  offre » ni « introuvable ».
- **La sonde d'appartenance** (`ProMembershipContext`) : 403 `not_a_member` /
  `forbidden` inchangés ; 0 → « autre » (on garde l'état connu), comme
  aujourd'hui avec son `.catch`. `refreshSalons` (`getMySalons` sans
  `.catch`) : 0 → rien ne change, là où un corps perdu vidait la liste des
  salons.
- **Aucun appelant ne lit « pas 200 » comme un formulaire vide modifiable** —
  sauf l'Acompte sur `main` (`depositToForm(undefined)`), que #616 corrige.
  D'où la dépendance §8.
- **Lectures secondaires, déjà silencieuses sur un 5xx, inchangées** :
  l'en-tête de places (Équipe), les stats et l'offre (Aujourd'hui), les visites
  (fiche client — liste vide), la mini-fiche (panneau de la Journée), les
  suggestions de la réservation manuelle, la carte d'invitations (masquée,
  comme l'app), le justificatif d'acompte (« Voir le justificatif » ne fait
  rien). Elles ne tournent plus pour toujours et ne lèvent plus ; les rendre
  bavardes est hors périmètre (§9).

**Écritures — trois appelants changent, les autres disent déjà vrai.** La
plupart retombent sur une phrase générique (« L'enregistrement a échoué.
Réessayez. », « Création impossible. Réessayez. », « La mise en ligne a
échoué. Réessayez. », `teamErrorMessage(undefined)`…), vraie sur une coupure.
Celles qui affirment une cause doivent connaître le statut 0 :

| Appelant | Aujourd'hui (rejet) | Statut 0 sans changement | Changement |
|---|---|---|---|
| Carte d'invitations (accepter / refuser) | `catch` → « Pas de connexion. Réessayez. » | `invitationActionError(undefined)` → la phrase générique | `status === 0` → « Pas de connexion. Réessayez. » (déjà épinglé par `pro-invitations-card.test.tsx`) |
| Connexion — « Vérifier » | bouton bloqué | « Code incorrect ou expiré. » **sous le champ** — faux | `status === 0` → « Pas de connexion. Réessayez. » (niveau formulaire) |
| Connexion — « Recevoir le code » | bouton bloqué | « E-mail invalide ou envoi impossible. » — accuse l'e-mail | idem |

`requestEmailOtpPro` et `verifyEmailOtpPro` rendent pour cela leur `status`
(ajout ; aucun appelant ne casse). « Pas de connexion. Réessayez. » est la
phrase de l'app, déjà `NO_CONNECTION_MESSAGE` (`lib/pro/team.ts`).

Le sélecteur de salon dit « Changement impossible — votre accès à ce salon a
**peut-être** été retiré. » : la phrase se couvre déjà ; elle reste (§9).

## 4. Rendez-vous — la Journée, qui ne savait pas échouer

La vue par défaut de `/pro/rendez-vous` charge le jour par `loadJournal`, qui
fait `if (r.status === 200 && r.day) setJournalDay(r.day)` et **rien
d'autre**. Ce n'est pas seulement la coupure : un **500** laisse aussi le
squelette pour toujours, et un changement de jour raté laisse **la grille du
jour précédent sous l'en-tête du nouveau** (ce que le dédoublonnage de
requêtes, juste au-dessus, existe pour empêcher). La racine n'y peut rien :
il faut une branche d'erreur.

- Tout échec (≠ 200, 0 compris) **vide le jour** et affiche un `ErrorState`
  de section (sans titre : le h1 « Rendez-vous » de la page reste) ;
  « Réessayer » recharge **le jour affiché**.
- Pendant le rechargement : le squelette.
- Parité : l'app fait `_day = null` + `_error` et montre « Réessayer »
  (`pro_journal_provider.dart` `load`, `pro_journal_screen.dart` `_body`).
- Une requête dépassée (un jour plus récent a été demandé) ne touche ni au
  jour ni à l'erreur — la règle existante du dédoublonnage.
- **Un 401** (la session est morte : le BFF n'a pas pu la rafraîchir) mène à
  la connexion, comme les autres lectures de la page — « Réessayer » ne
  pourrait qu'échouer encore (ajouté à la revue, §11).

## 5. Téléversement

`lib/pro/upload.ts` : la demande de signature passe par un `fetch` qui ne lève
pas ; un rejet → `null`, la branche que chaque appelant a déjà (« Échec de
l'envoi de la photo. », « Le téléversement a échoué. »…). **Pas de rapport
Sentry** pour ce cas : la signature est demandée au BFF, même origine — un
rejet là, c'est le réseau de la personne, pas le stockage ni un CORS, que la
télémétrie existe pour trouver (`lib/upload-telemetry.ts`).

## 6. UX

Aucun composant nouveau, aucun texte nouveau (« Pas de connexion.
Réessayez. » existe déjà). Ce qui change à l'écran : sur une coupure, chaque
page Pro montre son état d'erreur et « Réessayer » au lieu d'un squelette
éternel ; chaque bouton d'enregistrement revient avec sa phrase d'échec ; la
fenêtre « Modifier le numéro » se referme ; la Journée a un état d'erreur.

## 7. Contrat, sécurité, performance

Aucun changement d'API, de contrat, de serveur ni de BFF. La sécurité ne
bouge pas : un 401 reste un 401 (la redirection est intacte) ; le statut 0
n'ouvre rien — toutes les autorisations sont côté serveur. Performance : un
`try` de plus par appel.

## 8. Déploiement — après #616

Web au merge (Vercel). **#616 d'abord** : sur `main`, l'Acompte lit encore
une lecture ratée comme une politique vide (`depositToForm(undefined)`) ;
aujourd'hui une coupure y tourne pour toujours (aucune donnée en danger),
avec ce changement seul elle afficherait le formulaire vierge qu'un
« Enregistrer » écrit par-dessus la vraie politique. La table de tests
(§10) contient l'Acompte : la branche ne passe au vert que sur un `main` qui
contient #616.

**Fait** : #616 est fusionné (`84ee583b`) avant cette branche, rebasée
dessus.

## 9. Hors périmètre, consigné

- **Le mot de l'app** : sur une lecture ratée, le web dit « Une erreur est
  survenue. Réessayez. » (le `ErrorState` partagé), l'app « Pas de connexion.
  Réessayez. » quand c'est le réseau ; le sélecteur de salon soupçonne un
  accès retiré. Dire « Pas de connexion » demande à chaque page de garder le
  statut de son échec — une tâche à part :
  [web-pro-no-connection-copy.md](web-pro-no-connection-copy.md).
- **Le web client** (`lib/api/account.ts`) : 17 `fetch` nus, même classe de
  défaut côté consommateur — une tâche à part.
- **Les lectures secondaires silencieuses** (§3) — déjà silencieuses sur un 5xx.
- **Le détail d'un rendez-vous sans `/me`** (fuseau d'Abidjan) — sa propre
  tâche (`pro-appointment-detail-profile-gate.md`, en cours sur une autre branche) ; ce
  changement ne touche pas le composant.
- **L'export avec une section vide sans le dire** — sa propre tâche
  ([acompte-off-parity.md](acompte-off-parity.md) §7). Ce changement
  transforme le « Préparation… » éternel en ce comportement-là, déjà celui
  d'un 5xx.
- **Une écriture faite dont la réponse s'est perdue** (2xx, corps illisible) :
  les appelants qui ont besoin de la charge utile disent leur phrase d'échec
  alors que l'écriture a eu lieu ; un nouvel essai peut la refaire (une note
  deux fois, un 409 sur une invitation). La fenêtre — en-têtes reçus, corps
  perdu — est la plus étroite de toutes ; avant ce changement, ces mêmes cas
  levaient ou passaient `{}` pour la charge utile.
- `requestOtpPro` / `verifyOtpPro` (connexion par téléphone) n'ont plus
  d'appelant ; ils passent par `send()` comme les autres.

## 10. Tests (rouges d'abord, contre le code d'avant)

- **Unité, table** (`tests/pro-api-network.test.ts`) : **chaque** fonction
  exportée de `lib/api/pro.ts` — `fetch` rejette → la promesse se résout
  (statut 0 / `ok` faux / `'offline'` / `null`) ; 2xx illisible → lectures
  statut 0, écritures `ok` sans charge utile. Une garde exige que la table
  couvre tous les exports : un wrapper nouveau doit y entrer.
- **Composant, table** (`tests/pro-network-pages.test.tsx`) : les 16 pages
  (le tableau §1 + l'Acompte) — toutes les lectures rejettent → le h1 de la
  page, l'alerte et « Réessayer », jamais le squelette ; `/me` répond et la
  lecture propre à la page rejette → pareil (l'abonnement : jamais l'écran
  « choisissez une offre »).
- **La Journée** : un 500 → l'erreur de section sous le h1 ; un rejet →
  pareil ; « Réessayer » → la grille ; un changement de jour raté ne garde pas
  la grille de la veille.
- **Enregistrements** : « Modifier le numéro » sans réseau → la phrase, le
  bouton revient, la fenêtre se ferme ; « Enregistrer » des Disponibilités
  et d'un service du Catalogue ; la connexion (« Vérifier » sans réseau →
  « Pas de connexion. Réessayez. », le champ du code n'est pas accusé) ; la
  carte d'invitations (tests existants).
- **Téléversement** : la signature rejette → `null`, aucun rapport.
- **Mutations** à voir rouges : retirer le `catch` de `send()` ; celui de
  `readJson()` ; remettre `.catch(() => ({}))` sur une lecture de liste ;
  retirer la branche d'erreur de la Journée ; retirer la branche statut 0 de
  la connexion et de la carte d'invitations ; retirer le `catch` de la
  signature.

## 11. Construit — vu rouge, et ce que la revue a ajouté

- **Vu rouge contre le code d'avant** : la table des wrappers 84 cas sur 125
  (chaque wrapper rejetait ; les lectures de liste inventaient une liste vide
  d'un corps illisible) ; les pages 27 sur 27 (chacune sur son squelette,
  avec 27 rejets non gérés) ; les enregistrements 5 sur 5 ; la Journée 3 sur
  3 ; la signature 3 sur 3.
- **Ce que l'audit avait prévu s'est produit** : sous le changement racine
  seul, les deux tests existants de la carte d'invitations (« Pas de
  connexion. Réessayez. ») sont tombés rouges — elle attrapait le rejet. La
  branche statut 0 les remet au vert.
- **Ajouté à la revue de la Journée** : « Réessayer » montre le squelette
  pendant qu'il charge (jamais la grille de la veille, un instant, au retour
  de `journalError` à faux) ; un **401** mène à la connexion (§4).
- **Mutations** : 14 sur 14 rattrapées — le `catch` de `send()` (63 cas
  rouges) et de `readJson()` (27) ; une lecture de liste remise à
  `.catch(() => ({}))` ; `getMyProvider` qui prend un 200 illisible pour un
  200 ; `selectSalon` qui passe `{}` pour un profil ; la Journée sans branche
  d'erreur, sans jour vidé, sans erreur remise à faux, sans redirection 401 ;
  la connexion (« Recevoir le code », « Vérifier ») et la carte d'invitations
  (accepter, refuser) sans branche statut 0 ; la signature sans `catch`.
- **Suite complète** sur la branche : 1216 tests, un seul rouge — la ligne
  Acompte « `/me` répond, la politique est coupée », attendue sans #616 (le
  formulaire vierge de D3). Sur une fusion locale avec #616 : 1241 sur 1241,
  `tsc` propre. Le seul conflit de la fusion est la ligne de tête de
  l'index des specs (les deux branches en ajoutent une). **Après la fusion
  de #616 et le rebase** : 1241 sur 1241, la ligne Acompte comprise.
- `next build` passe contre l'API bouchon de la CI ; `tsc` et le lint sont
  propres. Non lancés en local : l'e2e Playwright et Lighthouse (la CI les
  lance).
