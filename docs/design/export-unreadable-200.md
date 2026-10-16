# Les exports ne prennent plus une réponse illisible pour une liste vide — spec

| | |
|---|---|
| **Statut** | **Approuvé le 2026-10-16** (propriétaire : « first fix the minor gap » — l'écart noté au landing de #621 : un 200 sans sa liste lu comme une liste vide) — **construit le même jour** sur `fix/export-unreadable-200` ; §7 dit ce qui a été construit autrement qu'écrit (la décision 1 ne vaut que pour une **lecture**) · **Mergé (#630) le 2026-10-16** — web en production au merge (Vercel) ; app au prochain build (après la revue Apple de 0.0.1) ; rien côté serveur |
| **Owner** | Sadreddine |
| **Last updated** | 2026-10-16 |
| **PRD ref / phase** | FR-AUTH-005 « Mes données » · export du salon (R5 §6, T39) · V1 |
| **Parties** | [consumer-export-completeness.md](consumer-export-completeness.md) (#621) · [web-pro-export-completeness.md](web-pro-export-completeness.md) (#618) · [app-pro-export-completeness.md](app-pro-export-completeness.md) (#622) · [web-consumer-network-failure.md](web-consumer-network-failure.md) (#620) |
| **ROADMAP entry** | [2026-10-16-export-unreadable-200.md](../roadmap/entries/2026-10-16-export-unreadable-200.md) |
| **Skills checked** | myweli-web-guardrails ✓ · myweli-dev-guardrails ✓ (pas de changement serveur ni de contrat) |

## 1. Le défaut, vu dans le code

Les quatre exports (« Mes données » web et app, l'export du salon web et app)
promettent des données **complètes** : une lecture ratée les fait refuser.
Mais plusieurs lectures prennent une réponse **200 lisible dont la liste
manque** pour une liste vide, réussie — et l'export livre la section vide
comme si elle était complète. Le serveur envoie **toujours** ces clés
(`items`, `providers`, l'objet utilisateur avec son `id`, `transactions`) :
une clé absente n'est jamais « le serveur a dit vide ».

**La cause principale, côté web, est un saut plus haut que #620** : les deux
BFF (`web/lib/bff.ts` `callApi`, `web/lib/bff-pro.ts`) font
`res.json().catch(() => ({}))` en gardant le statut du serveur. Un corps perdu
entre le serveur et la fonction Vercel (tronqué, ou une page HTML d'un proxy)
arrive donc au navigateur comme un **200 `{}`** parfaitement lisible — et la
garde de #620 (`readJson` → statut 0) ne se déclenche jamais. Puis
`/api/me/favorites` fabrique `{ favorites: [] }` (`b.providers ?? []`) et
`enrichAppointments` fabrique `items: []` (`b.items ?? []`).

Lectures concernées (audit en lecture seule, 2026-10-16) :

| Export | Section | Ce qui la rend « complète » à tort |
|---|---|---|
| web « Mes données » | profil | `getMe` prend tout JSON non nul pour l'utilisateur (`{}`, `[]`, `"x"`) |
| web « Mes données » | rendez-vous | BFF `b.items ?? []` + `listAppointments` `body.items ?? []` |
| web « Mes données » | favoris | BFF `b.providers ?? []` + `getFavorites` `b.favorites ?? []` (#620 l'avait épinglé : « the server said so ») |
| app « Mes données » | favoris | `getFavoriteProviders` `(body['providers'] as List?) ?? const []` |
| web salon | rendez-vous | `listProAppointments` `body.items ?? []` |
| web salon | revenus | `getEarnings` sans contrôle de forme : `{}` fait échouer l'assemblage **sans message** (aucun `catch`), `{"transactions":"x"}` est livré |
| app salon | équipe | `getArtists` `(… as List?) ?? const []` |
| app salon | fichier clients | `SalonClientsPage.fromJson` `items ?? []` / `total ?? 0` : une page 1 `{"pageSize":50}` devient une base vide « entière » |

Déjà stricts (aucun changement) : rendez-vous, fiche et services de l'app
salon et les rendez-vous de l'app client (casts non nullables, attrapés en
erreur) ; le parcours clients du web (garde `pageSize` + `wholeClientBase`).

## 2. Décisions

1. **Les BFF ne fabriquent plus un 200 pour une lecture.** Une réponse 2xx
   du serveur à une **lecture** (GET) dont le corps ne se lit pas (hors 204,
   qui n'a pas de corps et reste un 204) devient **502
   `{ "error": "bad_gateway" }`**. Une **écriture** garde son 2xx, avec `{}` :
   le serveur a agi, et la règle de #620 tient — « une écriture reste ok sans
   son contenu » ; la lui faire perdre ferait réessayer une réservation
   enregistrée jusqu'au 409 sur le propre créneau du client (§7). Le navigateur reçoit un
   échec, que tous les écrans traitent déjà comme tel (#619/#620 : tout sauf
   200 est une erreur). Les réponses d'erreur gardent leur statut (leur corps
   illisible reste `{}`, comme aujourd'hui). Les routes BFF qui remodèlent un
   200 (`/api/me/favorites`, `enrichAppointments`) répondent 502 quand la
   liste attendue manque ou n'est pas une liste, au lieu d'en fabriquer une
   vide.
2. **Les lectures d'un export exigent leur forme.** Une réponse 200 dont la
   liste (ou l'objet) attendue manque ou n'a pas le bon type est une lecture
   **ratée** (statut 0 côté web, `ApiResponse.error` côté app), donc un refus
   de l'export — jamais une section vide. Seules les lectures listées au §1
   changent ; elles servent aussi d'autres écrans, qui montreront leur état
   d'erreur au lieu d'un « Aucun … » mensonger — le principe même de #620
   (« jamais une liste vide que personne n'a envoyée »). Le test de #620 qui
   épinglait l'inverse pour `getFavorites` est inversé ; `getNotifications`,
   qui n'alimente aucun export, garde sa lecture (consigné au §5).
3. **L'export web du salon n'échoue plus en silence** : une erreur pendant
   l'assemblage du fichier est un refus avec le message de l'export, comme
   une lecture ratée.

## 3. UX

Aucun texte nouveau. Une lecture illisible donne le refus existant de chaque
export (« Impossible de charger … Vos données ne sont proposées que
complètes … » / l'alerte de l'export du salon), et les autres écrans qui
partagent ces lectures montrent leur état d'erreur avec « Réessayer ».

## 4. Tests (rouges d'abord, contre le code d'avant)

- **BFF** (`callApi`, `bff-pro`) : un 200 au corps HTML ou tronqué → 502
  `bad_gateway` ; un 204 reste 204 ; une erreur au corps illisible garde son
  statut ; `/api/me/favorites` et `enrichAppointments` sans leur liste → 502.
- **Lectures web** : `getMe` sur `{}`, `[]`, `"x"` → statut 0 ;
  `listAppointments` / `getFavorites` / `listProAppointments` sur `{}`,
  `{ items: null }`, `{ items: "x" }` → statut 0 ; `getEarnings` sans
  `transactions` en liste → statut 0.
- **Exports web** : chaque lecture → 200 `{}` refuse l'export (pas de
  fichier, le message) ; l'export du salon qui lève à l'assemblage montre le
  refus.
- **App** : `getFavoriteProviders` / `getArtists` sur `{}` →
  `ApiResponse.error` ; `SalonClientsPage.fromJson` sans `items` ou sans
  `total` → erreur ; les deux écrans d'export refusent.
- **Mutations** sur chaque garde nouvelle.

## 5. Hors périmètre, consigné

- Les autres lectures de listes qui lisent encore `?? []` (notifications,
  invitations, équipe Pro, avis, visites d'un client, pages publiques) :
  la cause réseau est fermée par la décision 1 — pour les BFF `callApi` /
  `callApiPro` et pour les deux proxys publics `/api/availability` et
  `/api/localities` (§7) ; il ne reste que le cas d'un serveur qui
  changerait son contrat.
- App, inchangé : une réponse 200 qui n'est pas un objet (`[]`, `null`) ou
  dont un élément est cassé (`items: [null]`) lève encore une `TypeError` ;
  la liste « Clients » l'affiche par `e.toString()` (le motif des 67 sites
  `_error = e.toString()` de l'app), l'export la refuse. Et les lectures des
  favoris et de l'équipe disent encore « FormatException » pour un corps
  coupé — seule la lecture des clients dit « Erreur » dans ce cas.
- L'export de l'app salon n'a pas de section revenus alors que
  [pro-account-deletion-export.md](pro-account-deletion-export.md) les liste
  pour les deux surfaces — un écart de parité, pas ce défaut.
- Un favori dont le salon n'existe plus disparaît de l'export (choix de
  `FavoritesService.list`) ; un test garde que ce cas (plus d'ids que de
  salons) reste une réponse lue.
- Le refus de l'export web du salon après une erreur d'assemblage nomme les
  trois lectures, alors qu'elles ont réussi — un texte dédié (« le fichier
  n'a pas pu être assemblé ») demanderait une phrase nouvelle.
- « Mes données » (web) construit son document au rendu : une liste dont un
  élément est malformé (`items: [null]`) ferait tomber la page sur sa
  frontière d'erreur au lieu du refus — les gardes ferment la liste absente,
  pas un élément cassé.

## 6. Déploiement

Web au merge (Vercel). App au prochain build. Serveur : rien.

## 7. Construit — ce qui diffère de ce qui était écrit

- **Une lecture seulement** (décision 1 amendée) : écrite telle quelle, la
  règle valait pour toute réponse 2xx, écritures comprises. La revue l'a
  vu : un `POST /appointments` 201 enregistré mais dont le corps se perd
  serait annoncé comme un échec, et le client réessaierait jusqu'au 409 sur
  son propre créneau — l'inverse de la règle de #620 pour les écritures.
  `lostBodyIsBadGateway` (une seule règle pour les deux BFF) ne rend un 502
  que pour un GET ; un POST, PATCH, PUT ou DELETE garde son statut, `{}`
  pour corps.
- **La lecture des clients de l'app répond « Erreur »** au lieu de laisser
  passer l'exception : `SalonClientsPage.fromJson` refuse une page sans
  `items` ou sans `total`, et `ApiProClientsService.listClients` en fait —
  comme d'un corps coupé — l'erreur que les deux autres lectures donnent.
  La liste « Clients » n'affiche plus « FormatException: … », et le
  chargement des pages suivantes n'a pas besoin d'un `catch` qui avalait
  aussi les erreurs de programmation : une page ratée n'ajoute rien, garde
  la liste, et le défilement suivant redemande la même page.
- **L'export web du salon** : une erreur pendant l'assemblage du fichier est
  le refus de l'export ; son message nomme les trois lectures, faute d'un
  texte dédié (aucun texte nouveau, §3) — consigné au §5.
- **Les deux proxys publics** (revue finale) : `/api/availability` et
  `/api/localities` ne passent pas par `callApi` et faisaient le même 200
  `{}` d'un corps perdu — « aucun créneau ce jour-là », et un arbre des
  localités vide que `lib/use-localities.ts` garde pour la visite. Ce sont
  des lectures : un 502 aussi, par la même règle ; une erreur garde son
  statut (404 = « disparu » pour la réservation).
- **Ce qui reste comme avant, exprès** : `getNotifications` et l'équipe Pro
  (`getTeamMembers`) lisent encore un 200 sans `items` comme une liste
  vide ; le test de #620 a été séparé pour le dire (§5).

**Vu rouge** : chaque test nouveau d'abord contre le code d'avant — web :
19 tests BFF, 15 + 12 lectures, 3 + 4 exports ; app : 4 + 3 + 10 parses,
3 écrans ; puis les 8 cas d'écriture et la lecture des clients ajoutés à
l'intégration. **Mutations** sur le code commité, l'arbre vérifié propre
après chacune : 15 + 8 côté web (constructeur et revue), 8 + 3 côté app,
puis 7 à l'intégration — dont les 5 que la revue avait vues survivre (le
`total` repris des lignes, une page sautée, une page ratée qui remplace la
liste par l'erreur, un garde des favoris trop strict, le GET seul) — et 4
sur les proxys publics et la casse de la méthode : toutes rattrapées. La
revue finale a refait 8 mutations (7 rattrapées ; la casse, non épinglée
alors, l'est depuis).
