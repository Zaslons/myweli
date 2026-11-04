# L'app Pro attend son salon : jamais l'heure d'Abidjan par défaut (spec)

| | |
|---|---|
| **Statut** | **Approuvé par le propriétaire le 2026-10-16** (« Build both layers: save the salon's details on the phone, and add the « Impossible de charger votre salon » screen as described in §4 of the spec. ») — **construit le 2026-10-16, fusionné** (#623) ; part avec le prochain build de l'app Pro (0.0.2). Écarts au texte, trouvés en construisant : §12. · **Mergé (#623) le 2026-10-16** — app au prochain build (après la revue Apple de 0.0.1) ; rien côté serveur |
| **Module** | `multi-pays` (heure du salon, MP2) × `access` (le chargement de la session Pro) |
| **Origine** | La même classe de défaut que le web Pro, corrigée par Zaslons/myweli#617 ([pro-appointment-detail-profile-gate.md](pro-appointment-detail-profile-gate.md) §6, qui la signalait pour l'app). |
| **Gouverne** | `mobile/lib/providers/pro_auth_provider.dart`, `mobile/lib/models/salon_market.dart` (nouveau), `mobile/lib/models/provider_session.dart`, les deux `AuthService` (cache), `mobile/lib/widgets/provider/pro_salon_gate.dart` (nouveau), `mobile/lib/main_pro.dart` (le `builder`). |
| **Backend** | **Aucun changement.** Pas de contrat, pas de migration. |

## 1. Le défaut, vu sur le vrai chemin (pas supposé)

`ProAuthProvider.salonTimezone` vaut `_activeSalon?.timezone`. `_activeSalon`
n'est rempli que par une réponse **réussie** de `GET /me/provider` : les cinq
endroits qui l'écrivent sont `_refreshMembership`, `switchSalon`,
`checkMembershipAlive` (deux branches) et `_membershipCameBack`. La session
persistée (`ProviderSession`) garde le compte, l'adhésion (avec `salonId` et
`salonName` repliés dedans) et la sélection R6, **pas le salon**.

Au démarrage, `_loadCurrentProvider()` restaure le compte et l'adhésion depuis
le cache, puis appelle `refreshMembership()`. Si `/me` échoue (réseau, 500,
503 d'un redémarrage), la branche d'échec « garde la forme en cache »… mais la
forme en cache n'a pas de salon : `_activeSalon` reste `null`. Rien ne bloque
ensuite : le splash route vers le tableau de bord dès que `ready` se termine
(ou à son délai de 1,5 s), et aucun écran Pro ne vérifie le salon. Chaque
appel `salonDateTime(…, tz: null)` / `toSalonTime(…, tz: null)` tombe alors
sur `locationOf(null)`, donc **Africa/Abidjan**.

Sonde jetable sur le code actuel (salon `provider1` passé à
`Africa/Libreville`, UTC+1 ; un rendez-vous à `09:00Z`, soit 10:00 au salon ;
« Reprogrammer » le 16 à 11:00) :

| démarrage | `activeSalon` | `salonTimezone` | carte du journal | envoyé |
|---|---|---|---|---|
| `/me` OK (contrôle) | `provider1` | `Africa/Libreville` | 10:00–11:00 | `2030-01-16T10:00Z` (11:00 au salon) ✔ |
| `/me` en échec | `null` | `null` | **09:00–10:00** | **`2030-01-16T11:00Z`** (midi au salon) ✘ |

Le serveur revalide le créneau, pas l'intention : un créneau décalé d'une heure
qui est libre est accepté. Tous les autres affichages Pro (journal,
aujourd'hui, détail, agenda, disponibilités, gains) montrent l'heure
d'Abidjan dans cet état, et la devise retombe sur FCFA.

**Les autres chemins, tracés :**

- **Connexion** (`_login`, `_bridgedLogin`, `acceptPendingInvitation`) :
  `refreshMembership()` puis `return _provider != null`. Si `/me` échoue, la
  connexion « réussit » et l'écran va au tableau de bord **sans salon**, et
  sans rien en cache (la déconnexion a tout vidé). Même défaut.
- **Bascule de salon R6** (`switchSalon`) : en cas de succès, la sélection et
  le salon changent ensemble ; en cas d'échec, l'ancien salon reste. Correct.
- **Repli R6** (`checkMembershipAlive`, et `_refreshMembership` au
  démarrage) : sur `403 forbidden` avec une sélection, la sélection est
  effacée puis `/me` redemandé. Si ce second appel échoue, `activeSalonId`
  désigne déjà le salon par défaut B alors que `_activeSalon` est encore le
  salon A : **l'heure de A sert pour B**. Variante plus rare du même défaut.
- **`verifyOtp` (téléphone)** : ne rafraîchit jamais l'adhésion, mais
  `/pro/verify-otp` n'est plus routé (connexion par téléphone en sommeil,
  `pro_router.dart`). Latent, hors de cette correction (§10).
- **Porte de réadmission** (`_enterRejoin`) : vide le salon exprès ; l'écran
  « Invitations » n'affiche aucune heure. Correct.

Un salon **chargé** dont `timezone` est `null` reste légitimement Abidjan :
c'est la valeur par défaut du serveur lui-même
(`backend/lib/src/salon_time.dart`). Seul un salon **non chargé** ne doit
jamais être deviné.

## 2. La règle

> **L'app Pro n'affiche ni n'écrit une heure de salon sans connaître le
> salon.** « Connaître » = détenir les faits de marché (fuseau, devise, pays,
> zone) **du salon dans lequel la session agit** (`activeSalonId`) : soit la
> dernière réponse `/me`, soit, au démarrage, la dernière réponse `/me`
> **gardée en cache pour ce même salon**. Un salon inconnu n'est jamais
> remplacé par Abidjan.

C'est la règle du web (#617 §2), adaptée à une app qui doit aussi marcher sur
un réseau lent : le web n'a pas de cache de session ; l'app en a un, et c'est
lui qui évite de bloquer le cas courant.

## 3. La correction, en deux couches

### 3.1 Couche 1 : les faits de marché du salon voyagent avec l'adhésion (aucun changement visible)

Un nouveau petit modèle `SalonMarket` (`salonId`, `timezone`, `currency`,
`countryCode`, `areaId`), tiré du `Provider` que renvoie `/me`. Il est
persisté dans `ProviderSession` (`salonMarket`, optionnel : une session
d'avant ce changement n'en a pas) par deux méthodes de
`AuthServiceInterface`, `cacheProviderSalonMarket` /
`getCachedProviderSalonMarket`, sur le modèle de `cacheProviderMembership`.

- Les cinq endroits qui prennent la forme de `/me` passent par **un seul**
  helper, `_takeShape(info)` : adhésion + salon + faits de marché, et les deux
  écritures de cache. Un futur sixième endroit ne pourra pas oublier les
  faits.
- Le démarrage restaure les faits avec l'adhésion, avant le rafraîchissement.
- `salonTimezone`, `salonCurrency`, `salonCountryCode` et `salonAreaId` ne
  répondent **que si `salonMarket.salonId == activeSalonId`**. Les faits d'un
  autre salon (le repli R6 raté, un cache resté d'avant) ne valent rien pour
  celui-ci. `invite_member_sheet.dart` fait déjà cette vérification pour
  `activeSalon`.
- Vidés comme l'adhésion : entrée dans la porte de réadmission, déconnexion,
  « accès retiré ».

Le cas reproduit au §1 (démarrage, `/me` en échec, un salon déjà vu sur ce
téléphone) est **entièrement** réglé par cette couche : l'app s'ouvre comme
aujourd'hui, à l'heure du salon.

**Pourquoi ce n'est pas « deviner ».** Le fuseau en cache est la réponse du
serveur pour ce salon précis, pas une valeur par défaut. Il ne change que si
le salon change de ville (fuseau dérivé de la ville côté serveur, menace T57),
et le premier `/me` réussi le corrige. C'est la même confiance que l'app
accorde déjà à l'adhésion en cache pour donner sa forme au premier écran.

### 3.2 Couche 2 : un salon inconnu bloque l'espace Pro (l'écran du §4)

Ce qui reste inconnu après la couche 1 : une **connexion** dont le `/me` a
échoué ; le **premier démarrage après la mise à jour** (le cache n'a pas
encore de faits) avec `/me` en échec ou plus lent que le délai du splash ; le
**repli R6** dont le second `/me` a échoué.

`ProAuthProvider.needsSalon` = connecté **et** hors porte de réadmission
**et** salon inconnu. Tant qu'il est vrai, l'espace Pro laisse place à un seul
écran (§4) au lieu de n'importe quelle page Pro. Il est posé **une fois**,
dans le `builder` de `MaterialApp.router` (`main_pro.dart`), au-dessus de
toutes les routes : une notification touchée qui ouvre
`/pro/appointment/:id` est couverte aussi. Exemptés : `/pro/splash`,
`/pro/login`, `/pro/register` (`ProRouter.launchPaths`) et
`/pro/invitations`.

L'écran **remplace** les pages au lieu de les recouvrir : rien en dessous ne
démarre de chargement avec un fuseau inconnu (le journal fige son « aujourd'hui »
au premier chargement). Quand le salon arrive, les pages se montent, à l'heure
du salon.

## 4. L'écran « salon non chargé » (à valider)

```
┌──────────────────────────────────────┐
│                                   ⎋  │   ← « Déconnexion » (icône + infobulle)
├──────────────────────────────────────┤
│                                      │
│              (icône wifi_off)        │
│                                      │
│   Impossible de charger votre salon  │
│                                      │
│   Les heures de vos rendez-vous en   │
│   dépendent. Vérifiez votre          │
│   connexion, puis réessayez.         │
│                                      │
│           [   Réessayer   ]          │
│                                      │
└──────────────────────────────────────┘
```

- **Réutilise** `EmptyState` (icône, titre, description, une action) dans un
  `Scaffold` ; « Déconnexion » en icône de la barre (infobulle
  « Déconnexion »), comme la porte de réadmission
  ([pro-rejoin-gate.md](pro-rejoin-gate.md) §3). Pas de retour, pas
  d'onglets, **pas de titre** (§12).
- **Les quatre états** (SYSTEM §12) :
  - **chargement** : la session stockée n'est pas encore lue, ou un
    rafraîchissement est en cours (démarrage passé le délai du splash,
    connexion, « Réessayer ») → `LoadingIndicator` plein écran, pas d'erreur
    qui clignote ; « Déconnexion » est grisée pendant ce temps ;
  - **erreur** : l'écran ci-dessus ;
  - **succès** : l'écran disparaît et la page demandée s'affiche ;
  - **vide** : sans objet.
- **« Réessayer »** relance `refreshMembership()` (un `/me`) ; l'écran passe
  en chargement. Un `not_a_member` passe par la règle de réadmission comme
  partout ailleurs (Invitations ou « accès retiré ») ; un `forbidden` sur une
  sélection retombe sur le salon par défaut (R6).
- **« Déconnexion »** est la sortie quand réessayer ne peut pas réussir
  (SYSTEM §12 : un compte que `/me` refuse en `403 forbidden` sans
  sélection). Déconnexion normale, page de connexion, sans le bandeau
  « accès retiré ».
- **Texte** (formule §17 : quoi → pourquoi → que faire) : titre
  « Impossible de charger votre salon » ; description « Les heures de vos
  rendez-vous en dépendent. Vérifiez votre connexion, puis réessayez. » ;
  bouton « Réessayer » ; barre « Déconnexion ».
- **Accessibilité** (§13) : cibles ≥ 48 px (AppButton, TextButton de la
  barre), 200 % de texte (EmptyState défile déjà), titre annoncé.

**Fréquence attendue** : rare. Il faut que `/me` échoue juste après une
connexion réussie, ou au tout premier démarrage d'une nouvelle version, ou
pendant un repli R6. Le démarrage hors ligne habituel (couche 1) ne le montre
pas.

**Rejeté :**
- *Le cache seul, sans écran* : les trois cas ci-dessus continueraient de
  deviner Abidjan, et d'écrire une heure fausse pour un salon hors de la CI.
- *L'écran seul, sans cache* : chaque démarrage sur un réseau mauvais
  bloquerait l'app, alors qu'elle sait déjà quel est le salon.
- *Un écran par page, comme le web* : l’app a une douzaine d’écrans qui lisent
  l'heure du salon et des notifications qui ouvrent n'importe lequel ; un seul
  point de passage ne peut pas en oublier un.

## 5. Architecture

`models → services (interface + mock + api) → providers → widgets`, rien de
sauté. `SalonMarket` est un modèle immuable (`equatable`, `fromJson` /
`toJson`). Le mock garde ses faits en mémoire comme son adhésion. Le gate est
un widget (`widgets/provider/pro_salon_gate.dart`) qui lit `ProAuthProvider` et
l'emplacement de `GoRouter` ; aucune route nouvelle, aucun `redirect`.

## 6. Sécurité

Rien de sensible : fuseau, devise, pays, zone d'un salon, tous publics. Ils
vont dans le même blob `flutter_secure_storage` que la session. L'autorité ne
change pas : le serveur résout le salon à chaque requête (T38, T55) ; le cache
ne sert qu'à l'affichage et au calcul de l'instant envoyé, que le serveur
revalide.

## 7. Performance

Une écriture de stockage sécurisé de plus par `/me` réussi (une par démarrage,
une par bascule). Aucune requête en plus. Le démarrage n'attend rien de
nouveau : la restauration lit le même blob.

## 8. Tests (rouges d'abord, sur le code actuel)

- **Fournisseur** (`test/unit/pro_auth_salon_market_test.dart`) :
  démarrage `/me` en échec avec des faits en cache → `salonTimezone` =
  Libreville ; cache d'avant (sans faits) → `needsSalon` ; un `/me` réussi et
  une bascule écrivent les faits du bon salon ; repli R6 raté → les faits de A
  ne répondent pas pour B ; connexion `/me` en échec → `needsSalon` ; un salon
  chargé sans fuseau → connu (Abidjan légitime) ; réadmission et déconnexion
  vident les faits et leur cache.
- **Cache** (`api_auth_service_test.dart`) : écrit, relu, vidé ; une session
  JSON d'avant ce changement se lit sans faits.
- **Journal** (le défaut du §1, en test) : démarrage `/me` en échec, faits
  Libreville en cache → la carte dit 10:00 et « Reprogrammer » 11:00 envoie
  `10:00Z`. Le contrôle `/me` OK passe avant et après.
- **Gate** (`test/widget/pro_salon_gate_test.dart`) : `needsSalon` → l'écran,
  aucune page Pro ; « Réessayer » avec `/me` revenu → la page, à l'heure du
  salon ; chargement pendant le rafraîchissement ; « Déconnexion » → connexion ;
  exempté sur le splash et « Invitations » ; cibles ≥ 48 px et 200 %.
- **Épingle source** : `main_pro.dart` pose `ProSalonGate` dans son `builder`.
- **Mutations** sur le travail commité, chacune vue rouge : la vérification
  `salonId == activeSalonId` retirée ; la restauration des faits retirée ;
  l'écriture du cache retirée de `_takeShape` ; le gate retiré du `builder` ;
  `needsSalon` qui ignore la porte de réadmission ; l'écran qui recouvre au
  lieu de remplacer.
- **Image de référence** de l'écran (générée sous Linux, regardée).

**Vu, pas supposé :**

- Sur le code d'avant : démarrage `/me` en échec → `salonTimezone` `null`
  (attendu Libreville) ; repli R6 raté → `'Africa/Libreville'` pour le salon
  par défaut (attendu `null`) ; journal → carte `09:00` et `11:00Z` envoyé.
  Le contrôle `/me` OK, vert avant et après.
- 32 tests nouveaux (14 fournisseur, 4 cache, 14 widget dont l'épingle).
- **23 mutations sur le travail commité, toutes rouges** : la vérification
  d'identifiant, la restauration, l'écriture du cache, le gate retiré du
  `builder`, `needsSalon` sans la porte de réadmission, le gate qui recouvre,
  l'ordre de `switchSalon`, la notification du repli raté, l'attente de la
  lecture de session (dans le gate et dans `salonLoading`), le rafraîchissement
  en cours, la première notification de « Réessayer », les chemins exemptés,
  le cache vidé à la réadmission et à la déconnexion (mémoire, mock, API),
  `toJson` / `copyWith` de la session, `SalonMarket.of` sans fuseau,
  l'écoute du routeur, `salonTimezone` revenu à la charge vivante, la
  notification après lecture de session.
- **Au premier passage, deux ont survécu**, sur des lignes dont rien ne
  dépendait : le gate distinguait lui-même attente et échec (l'écran le fait
  déjà), et `salonLoading` lisait `_isLoading`, dont le seul rôle réel était
  l'image avant la lecture de la session. Le gate est devenu ouvert/fermé,
  `salonLoading` dit « pas encore lu » en clair, un test tient cette première
  image, et le terme « sonde » (inobservable : sous le gate aucune page n'est
  construite) est retiré.
- Les deux images : seules elles ont bougé sous Linux (workflow « Goldens —
  regenerate »), les 52 autres identiques à l'octet.

## 9. Déploiement

App Pro seulement, avec le prochain build. Pas de drapeau : le premier
démarrage après la mise à jour remplit le cache au premier `/me` réussi.

## 10. Hors de cette correction (relevé en traçant)

- `verifyOtp` (connexion par téléphone, en sommeil) ne rafraîchit pas
  l'adhésion. À traiter si `/pro/verify-otp` est routé de nouveau.
- Repli R6 raté : les magasins par salon gardent les données de A (le
  `ProSalonScope.resetAll()` n'a lieu qu'en cas de succès). L'écran du §4 les
  cache ; les pages rechargent au montage. Un `resetAll` dès que la sélection
  tombe serait plus net.

## 11. Question ouverte

- ~~L'écran du §4 : d'accord ?~~ Oui, le 2026-10-16 (statut).

## 12. Ce qui a été construit, et où cela s'écarte du texte

- **Pas de nom de salon dans la barre.** La maquette du §4 le mettait en
  titre ; SYSTEM §13.3 l'interdit (une donnée réelle n'a pas de budget de
  largeur dans une barre : « Institut de Beauté Cocody Riviera » finirait en
  ellipse). Le message dit « votre salon ».
- **Le gate attend aussi la lecture de la session** (`sessionRestored`).
  Avant elle, « déconnecté » veut dire « pas encore lu » : un test a montré
  une page construite avec un fuseau `null` dans ce premier instant. Dans
  l'app le splash couvre ce moment ; le gate ne compte plus dessus. Le
  fournisseur notifie maintenant dès la session lue, pour que le premier
  écran prenne la forme en cache sans attendre `/me`.
- **`switchSalon` écrit la sélection, puis la forme, l'une après l'autre.**
  Les deux font lire-modifier-écrire sur le même blob de session ; lancées
  ensemble, l'une effaçait l'autre. Les champs, eux, changent ensemble avant
  toute attente.
- **Un repli R6 raté notifie** : rien d'autre ne changeait à l'écran, et le
  gate n'aurait rien su.
- **Le gate remplace le `Router`, vérifié** : une sonde a démonté puis
  remonté le `Router` de go_router avec une pile poussée (`/a → /b/1`, puis
  `/b/2` poussé pendant le démontage) ; la pile revient entière, et les pages
  sont reconstruites.
