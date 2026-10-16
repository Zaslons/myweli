# Web client — une écriture ratée revient en arrière et le dit — spec

| | |
|---|---|
| **Statut** | **Décidé le 2026-10-16** — la suite du §9 de [web-consumer-network-failure.md](web-consumer-network-failure.md) (« les écritures optimistes qui ne reviennent pas en arrière ») ; construit le même jour sur `fix/consumer-optimistic-revert` ; §11 dit ce qui a été vu rouge |
| **Owner** | Sadreddine |
| **Last updated** | 2026-10-16 |
| **PRD ref / phase** | Le retour d'une action (SYSTEM.md §15, WEB-SYSTEM §7) · V1 — web client (Mon compte, favoris, notifications, recherche, page salon) |
| **Module** | web client — `components/account/AccountClient.tsx`, `components/account/NotificationsClient.tsx`, `components/provider/FavoriteButton.tsx`, `components/discovery/RechercheClient.tsx` ; `lib/api/account.ts` (deux formes de retour), `lib/api/network.ts` (une phrase) |
| **ROADMAP entry** | [2026-10-16-consumer-optimistic-revert.md](../roadmap/entries/2026-10-16-consumer-optimistic-revert.md) |
| **Skills checked** | myweli-web-guardrails ✓ · myweli-dev-guardrails ✓ (aucun changement serveur, aucun contrat) · myweli-verification-guardrails (avant de dire « fait ») |
| **Dépend de** | [#620](https://github.com/Zaslons/myweli/pull/620) (`fix/consumer-network-failure`), fusionné le 2026-10-16. La branche est partie de sa tête, puis a été rebasée sur `main` à sa fusion, sans conflit. Il apporte le statut 0 (`send()` / `readJson()`) et `NO_CONNECTION_MESSAGE`, sans quoi un échec réseau lèverait au lieu d'être lu ici. |

## 1. Le défaut, vu dans le code

Depuis #620, aucun wrapper ne lève : une coupure est le statut 0, un refus
est son statut. Mais quatre gestes ne lisent pas la réponse, ou la lisent sans
rien en dire. C'était déjà vrai sur un 5xx avant #620 :

| # | Geste | Ce que fait le code | Ce que voit la personne |
|---|---|---|---|
| 1 | Mon compte → « Retirer des favoris » (`removeFav`) | retire la carte, puis `await removeFavorite(id)` sans lire le résultat | la carte est partie. Au prochain chargement, le favori est toujours là |
| 2a | Notifications → toucher une notification (`open`) | la marque lue, puis `markNotificationRead(n.id)` sans `await` ni lecture | elle a l'air lue. Au retour, elle ne l'est pas |
| 2b | Notifications → « Tout lire » (`readAll`) | marque tout lu, puis `await markAllNotificationsRead()` sans lire le résultat | le bouton disparaît, plus rien n'est en gras. Au retour, tout est non lu |
| 3a | Page salon → ♥ (`FavoriteButton.toggle`) | attend la réponse (non optimiste), `if (r.ok) setFav(next)` | le bouton reprend son état d'avant sans un mot : le clic semble ignoré |
| 3b | Recherche → ♥ d'une carte (`toggleFavorite`) | attend la réponse, `if (!r.ok) return` | pareil. Un 401 (session expirée après la sonde) est muet lui aussi |
| 4 | Mon compte → nom → « OK » (`saveName`) | `if (!r.ok) return` | l'éditeur reste ouvert, le bouton revient, sans un mot |

`markNotificationRead` / `markAllNotificationsRead` ne rendent que `{ ok }` :
l'appelant ne pourrait pas distinguer une coupure d'un refus.

## 2. Ce que fait l'app (parité)

- **Le ♥** (`favorites_provider.dart` `toggleFavorite`, appelé par
  `provider_card.dart`, `provider_detail_screen.dart`, `map_screen.dart`)
  n'est **pas optimiste** : il attend la réponse et ne change l'état que sur
  un succès. L'issue est toujours dite : `AppSnackBar.outcomeOn` sur un
  succès (« Ajouté aux favoris » / « Retiré des favoris », avec « Annuler »),
  et sur un échec `favoritesProvider.error ?? 'Une erreur est survenue.
  Réessayez.'`. `error` vaut **« Pas de connexion. Réessayez. »** sans
  réponse (`api_favorites_service.dart` `_networkError`), sinon le message
  du serveur. La carte de la carte (le sheet) l'annonce
  (`Helpers.announce`), même phrase.
- **L'app n'a pas de liste « Retirer des favoris »**. « Mes favoris sur la
  carte » ouvre la carte, et l'on retire par le ♥. Le geste web le plus
  proche est donc le ♥ : mêmes phrases.
- **Le nom** (`edit_profile_screen.dart`) : sur un échec, l'écran reste ouvert
  (pas de `pop`) et dit `authProvider.error ?? 'Erreur lors de la mise à
  jour'` (snackbar d'erreur).
- **Les notifications** (`notifications_provider.dart` `markRead` /
  `markAllRead`) sont optimistes **et ne reviennent pas non plus en arrière**.
  `notifications_list.dart` appelle `markRead` sans attendre. Le web va
  donc ici plus loin que l'app. L'écart inverse est consigné au §9.

## 3. Décision

**Une écriture ratée remet l'écran tel qu'il était et dit pourquoi, à
l'endroit du geste.** Rien d'autre ne change : ce qui était optimiste le
reste, ce qui attendait la réponse l'attend toujours. Un succès reste muet
quand l'écran le montre déjà (la carte partie, le cœur plein).

### 3.1 Les phrases

`writeFailureMessage(status, otherwise)` (`lib/api/network.ts`) : le statut 0
donne `NO_CONNECTION_MESSAGE` (« Pas de connexion. Réessayez. », la phrase de
l'app), tout autre statut donne la phrase de l'écran.

| Geste | Statut 0 | Autre échec |
|---|---|---|
| Retirer un favori, ♥ du salon, ♥ de la recherche | « Pas de connexion. Réessayez. » | « Une erreur est survenue. Réessayez. » (le repli de l'app sur le ♥) |
| Toucher une notification, « Tout lire » | « Pas de connexion. Réessayez. » | « Une erreur est survenue. Réessayez. » |
| Le nom (« OK ») | « Pas de connexion. Réessayez. » | « L’enregistrement a échoué. Réessayez. » (la phrase du numéro de contact, dans la même carte) |

Un **401** sur le ♥ mène à la connexion, sur la page salon comme sur la
recherche : c'est déjà le cas pour le visiteur anonyme et pour le ♥ du salon.
Ailleurs dans Mon compte, un 401 reçoit la phrase générique, comme le numéro
et la suppression.

### 3.2 Où et comment

Partout, un `<p role="alert">` (WEB-SYSTEM §7 : une erreur insérée est
annoncée à l'insertion) **sous le geste**, en `text-bodyMedium text-error`
comme la phrase du numéro de contact et celle d'une préférence (les erreurs
`role="alert"` restent à 14 px, registre de WEB-SYSTEM §15, ligne 17). Un toast ne convient pas
ici. Le client web n'en monte aucun, toutes ses erreurs d'écriture sont des
`role="alert"` en ligne (le numéro, la suppression, la préférence), et
l'erreur doit rester lisible tant qu'on ne réessaie pas, pas six secondes.

1. **Retirer un favori.** La carte disparaît tout de suite (inchangé). Elle
   est **masquée**, pas retirée : un ensemble `removing` la cache, et la liste
   `favorites` ne la perd que sur un succès. Sur un échec, elle réapparaît à
   **sa** place, avec la phrase sous son bouton. C'est la règle de SYSTEM §15
   (« ré-insérer l'élément dans la collection **courante**, jamais un
   instantané ») tenue par construction : deux retraits en vol sont
   indépendants, et l'un qui échoue ne ressuscite pas l'autre. Le focus
   revient sur son « Retirer des favoris » s'il était tombé sur `<body>` (le
   bouton a été démonté). Un nouvel essai cache la carte avec sa phrase. Un
   succès l'emporte, un échec remplace la phrase. Le dernier favori en vol
   montre « Aucun favori » le temps de la réponse, comme aujourd'hui.
2. **Toucher une notification.** Elle passe lue (inchangé), et la navigation
   n'attend pas l'écriture (inchangé). Si la page est toujours là quand
   l'échec arrive (une notification sans lien, ou une réponse plus rapide que
   la navigation), **cette** notification redevient non lue (gras + pastille)
   et la phrase s'affiche sous elle. Si la page est partie, il n'y a rien à
   dire : au retour, le fil la montre non lue, ce qui est vrai. Un nouvel
   essai efface la phrase. Il n'y a qu'une phrase à la fois sur la page :
   le geste suivant remplace la précédente.
3. **« Tout lire ».** Tout passe lu, le bouton disparaît (inchangé). Sur un
   échec, **seules les notifications que ce geste a marquées** redeviennent
   non lues. Une notification déjà lue avant le geste le reste : on n'annule
   que ce geste. Le bouton revient, la phrase s'affiche sous la ligne
   « Notifications | Tout lire », et le focus revient sur « Tout lire » s'il
   était tombé sur `<body>`. Un nouvel essai efface la phrase.
4. **Le ♥ du salon.** Il attend la réponse, comme l'app. Sur un échec, il
   garde son état et la phrase s'affiche dessous. Le focus revient sur lui
   s'il était tombé sur `<body>` : le bouton est désactivé pendant l'appel,
   et un navigateur peut alors sortir le focus. Un nouvel essai efface la
   phrase.
5. **Le ♥ de la recherche.** Pareil, sous **la** carte concernée (une phrase
   par carte, effacée au nouvel essai de cette carte). Un 401 mène à la
   connexion avec `returnTo` (la même sortie que le visiteur anonyme).
6. **Le nom.** L'éditeur reste ouvert avec le brouillon (inchangé), et la
   phrase s'affiche sous sa ligne. « Annuler » la referme avec l'éditeur,
   « Modifier le nom » rouvre un éditeur propre, et un nouvel « OK » l'efface
   le temps de l'appel. Le focus revient sur « OK » s'il était tombé sur
   `<body>` (le bouton est désactivé pendant l'appel).

### 3.3 Le contrat des wrappers

`markNotificationRead` et `markAllNotificationsRead` rendent désormais
`{ ok, status }`, comme `addFavorite` / `removeFavorite` / `updateName`. La
table de `tests/consumer-api-network.test.ts` perd leur `noStatus` et exige
donc le statut 0 sans réseau.

## 4. Les états

Aucun état de page nouveau. Les quatre états des pages sont ceux de #620.
Ce qui s'ajoute, c'est l'état « l'écriture a échoué » de chaque geste :
l'écran d'avant, plus une phrase.

## 5. Accessibilité

- `role="alert"` à l'insertion (§7). Chaque phrase est dans le DOM sous son
  geste, pas dans une région lointaine.
- Le focus ne se perd pas : là où le geste démonte ou désactive son bouton,
  le focus revient sur ce bouton **seulement** s'il est tombé sur `<body>`.
  On ne le vole jamais à un autre élément, comme `onLogout` et
  `ProLogoutButton`.
- La pastille « Non lu » et le gras reviennent ensemble : l'état est
  lisible sans la couleur.

## 6. Contrat, sécurité, performance

Aucun changement d'API, de contrat, de serveur ni de BFF. Deux wrappers
rendent un champ de plus (`status`). **Sécurité** : rien n'est ouvert. Un 401
sur le ♥ de la recherche mène à la connexion au lieu de se taire.
**Performance** : un `Set` d'identifiants par liste, pas de requête en plus.

## 7. Déploiement

Web au merge (Vercel), rien côté serveur. La branche partait de la tête de
#620. #620 fusionné (en un seul commit), elle a été rebasée sur `main`. Le
résultat est identique, octet pour octet, à l'arbre vérifié au §11.

## 8. Copie

Aucune phrase nouvelle. Toutes existent déjà dans le web ou l'app :
« Pas de connexion. Réessayez. », « Une erreur est survenue. Réessayez. »,
« L’enregistrement a échoué. Réessayez. ».

## 9. Hors périmètre, consigné

- **L'app** : `NotificationsProvider.markRead` / `markAllRead` sont
  optimistes et ne reviennent pas en arrière. `notifications_list.dart`
  appelle `markRead` sans attendre. Le même correctif côté Flutter est une
  tâche à part.
- **Le numéro de contact** (même carte que le nom) dit « L’enregistrement a
  échoué. Réessayez. » même hors ligne. Ce n'est pas faux, juste moins précis
  que le nom désormais. À aligner avec la même fonction.
- **Le succès du ♥ n'est pas annoncé** (l'app dit « Ajouté aux favoris » avec
  « Annuler »). Le bouton change déjà d'état (`aria-pressed`, libellé), donc
  un lecteur d'écran l'entend. Un toast de succès avec « Annuler » serait la
  rangée « with action » de §15, qui n'a aucun appelant web.
- **Un double clic sur le ♥ de la recherche** envoie deux requêtes (pas
  d'état « en vol » par carte). Inchangé.
- **`GENERIC_ERROR_MESSAGE`** existe aussi dans `lib/pro/team.ts`. Il faudra
  l'unifier quand `lib/api/pro.ts` s'alignera sur `lib/api/network.ts` (§9
  de #620).

## 10. Tests (rouges d'abord, contre le code d'avant)

`tests/consumer-optimistic-revert.test.tsx` simule un `fetch` qui **lève**
(statut 0) puis qui répond **500**, pour chaque écriture :

- **Retirer un favori** : la carte revient à sa place (l'ordre de deux
  cartes est tenu), la phrase est sous elle, le focus revient sur son bouton.
  Un succès la retire sans phrase. Un nouvel essai réussi efface la phrase.
- **Toucher une notification** : elle redevient non lue, la phrase est sous
  elle. Un succès la laisse lue, et un nouvel essai réussi efface la phrase.
- **« Tout lire »** : le bouton revient avec le focus, les non lues
  redeviennent non lues, une notification lue avant le reste (même lue
  seule pendant que « Tout lire » était en vol). Un succès les laisse lues,
  et un nouvel essai réussi efface la phrase.
- **Le ♥ du salon** : l'état ne bouge pas (ajout et retrait), la phrase. Le
  focus revient si le bouton l'avait perdu.
- **Le ♥ de la recherche** : le cœur ne bouge pas, la phrase est sous la
  carte. Un 401 mène à la connexion.
- **Le nom** : l'éditeur reste ouvert avec le brouillon, le nom affiché ne
  change pas, la phrase. « Modifier le nom » rouvre sans elle, et un nouvel
  « OK » l'efface pendant l'appel.
- **Wrappers** : la table de `consumer-api-network.test.ts` exige le statut
  0 pour `markNotificationRead` / `markAllNotificationsRead`.
- **Mutations** à voir rouges, une par garde : chaque retour en arrière
  retiré ; chaque phrase retirée ; la branche statut 0 retirée (la phrase
  générique hors ligne) ; « Tout lire » qui remet **tout** non lu (un
  instantané) ; le retrait qui ressuscite par instantané ; chaque retour de
  focus retiré ; le 401 de la recherche retiré ; « Annuler » qui garde la
  phrase ; le `status` retiré des deux wrappers.

## 11. Construit — vu rouge

- **Vu rouge contre le code d'avant** : 32 cas, soit 30 des 34 du nouveau
  fichier et les 2 lignes de la table des wrappers (`status` absent). Chacun
  a échoué pour la bonne raison : aucun `role="alert"` nulle part, la carte
  retirée qui ne revient pas, le 401 de la recherche muet. Les 4 verts sont
  les cas inchangés épinglés : un retrait réussi, une notification lue, un
  « Tout lire » réussi, le 401 du ♥ du salon.
- **Une erreur du test, trouvée en construisant** : `new Response('{}', {
  status: 204 })` lève (un 204 n'a pas de corps), et `send()` le lisait
  comme une coupure. Les cas « réussis » simulaient donc une coupure. Le
  double répond désormais `null` sur un 204.
- **Mutations : 32 sur 32 rattrapées.** Pour chaque geste : le retour en
  arrière retiré, la phrase retirée, la branche statut 0 retirée (la phrase
  générique hors ligne). Pour chaque nouvel essai : la phrase gardée. Pour
  chaque retour de focus : retiré. S'y ajoutent le retrait d'un favori
  réécrit en instantané (remis tel qu'avant le geste, donc ressuscitant une
  carte retirée entre-temps), « Tout lire » qui remet tout non lu, puis qui
  marque aussi ce qui était lu, le 401 de la recherche retiré,
  `markNotificationRead` / `markAllNotificationsRead` sans `status`, et
  `writeFailureMessage` qui ignore le statut 0.
- **Deux survivantes au premier passage, et c'était le test** : les retours
  de focus du ♥ du salon et de « OK » passaient sans le code. `blur()` sur
  un bouton **désactivé** ne fait rien dans jsdom (ce n'est plus une zone
  focalisable), donc le focus n'était jamais tombé. L'aide du test le fait
  maintenant tomber vraiment (un bouton jetable, focalisé puis retiré) et
  vérifie qu'il est sur `<body>` avant de continuer. Les deux mutations sont
  rattrapées depuis.
- **Trois lignes retirées pendant la construction, faute d'effet
  observable** : effacer la phrase au début d'un retrait (la carte est
  cachée avec sa phrase), sur « Annuler » (la phrase part avec l'éditeur,
  et « Modifier le nom » l'efface déjà), et au rechargement de la liste
  (aucun rechargement possible quand des cartes sont affichées).
- `npm run typecheck`, `npm run lint` et la suite complète sont verts.
