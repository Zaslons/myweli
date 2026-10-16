# Les exports ne prennent plus une réponse illisible pour une liste vide — spec

| | |
|---|---|
| **Statut** | **Approuvé le 2026-10-16** (propriétaire : « first fix the minor gap » — l'écart noté au landing de #621 : un 200 sans sa liste lu comme une liste vide) |
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

1. **Les BFF ne fabriquent plus un 200.** Une réponse 2xx du serveur dont le
   corps ne se lit pas (hors 204, qui n'a pas de corps et reste un 204)
   devient **502 `{ "error": "bad_gateway" }`**. Le navigateur reçoit un
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
  la cause réseau est fermée par la décision 1 ; il ne reste que le cas d'un
  serveur qui changerait son contrat.
- L'export de l'app salon n'a pas de section revenus alors que
  [pro-account-deletion-export.md](pro-account-deletion-export.md) les liste
  pour les deux surfaces — un écart de parité, pas ce défaut.
- Un favori dont le salon n'existe plus disparaît de l'export (choix de
  `FavoritesService.list`).

## 6. Déploiement

Web au merge (Vercel). App au prochain build. Serveur : rien.
