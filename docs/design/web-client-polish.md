# Le web client, finitions : la connexion, le ♥, les exports — spec

| | |
|---|---|
| **Statut** | **Validé le 2026-10-21** — Q1 : **la phrase de l'app pour chaque code** ; Q2 (décision 16) : **le message et « Annuler »** ; Q3 : **l'app corrigée dans la PR A** ; Q4 : **« Mon compte » aussi, les mots tels qu'écrits** |
| **Owner** | Sadreddine |
| **Last updated** | 2026-10-21 |
| **PRD ref / phase** | Web client (V1) — parité avec l'app client · WEB-SYSTEM §6 (formulaires), §7 (zones annoncées) · SYSTEM.md §14 (une faute, un endroit), §15 (retours), §17 (les deux phrases) |
| **Module** | web (`components/auth`, `components/pro/ProLoginOptions.tsx`, `ProRegisterClient.tsx`, `components/discovery`, `components/provider`, `components/account`, `lib/api/account.ts`, `lib/account/export.ts`, `lib/pro/export.ts`) — aucun changement serveur |
| **Origine** | [BACKLOG.md](../BACKLOG.md) lot 5 : B5.1–B5.4 (décision 16) |
| **Skills checked** | myweli-web-guardrails ✓ · myweli-dev-guardrails ✓ |

## 1. Le constat — relu sur le vrai chemin de code (main `9e47aab`)

Les quatre points du lot sont **réels**. Deux phrases du backlog ne le sont
plus, et deux défauts voisins ont été trouvés en relisant.

### 1.1 Ce qui a changé depuis le backlog

- **« Annuler » ne serait pas le premier toast à action du web** (décision
  16) : `useToast` porte une action depuis Médias (`MediasClient.tsx:126`,
  10 s, SYSTEM §15). Le seul argument contre « Annuler » n'existe plus.
- **La zone annoncée n'est pas montée** sur les pages concernées (B5.4) : ni
  la recherche (`RechercheClient`) ni la page salon (`FavoriteButton`,
  `ProviderView`) ne montent de `<Toast>` — seules six pages Pro le font. Le
  B5.4 doit la monter, toujours rendue (WEB-SYSTEM §7).

### 1.2 Ce qui reste, vérifié

| # | Défaut | Où |
|---|---|---|
| B5.1 | Valider le code : **toute** réponse non nulle qui n'est ni « compte suspendu » ni (Pro) « aucun compte » dit **« Code incorrect ou expiré. »** sous le champ — une limite de débit (429), une panne (500, 503), une réponse cassée (le BFF rend 502 `login_failed`) | `LoginOptions.tsx:128`, `ProLoginOptions.tsx:115` |
| B5.1 | Recevoir le code : **« E-mail invalide ou envoi impossible. »** pour tout refus — la limite d'envois (429 `otp_resend_limit`), une panne ; l'adresse est soupçonnée à tort | `LoginOptions.tsx:109`, `ProLoginOptions.tsx:91` |
| B5.1 | *Trouvé en relisant* — l'inscription Pro ne nomme que `otp_invalid` (un code expiré, bloqué ou absent dit la phrase générique), **et hors ligne elle dit « Une erreur est survenue »** au lieu de « Pas de connexion » ; « Recevoir un code » dit « Envoi du code impossible. Réessayez. » à tout, hors ligne compris | `ProRegisterClient.tsx:116-122`, `:142` |
| B5.2 | La recherche : si la lecture des favoris **échoue** (réseau, 500), `favIds` reste `null` — comme pour un visiteur anonyme — et un ♥ envoie **une personne connectée à la page de connexion** | `RechercheClient.tsx:97-108`, `:124` |
| B5.2 | Un double clic sur un ♥ envoie **deux** requêtes (le ♥ n'est désactivé que pendant la lecture initiale). Le serveur est idempotent, donc rien ne casse — mais avec B5.4 ce seraient deux annonces | `RechercheClient.tsx:121-145`, `:274` |
| B5.3 | Export du salon : une erreur **en assemblant** le fichier dit « Impossible de charger vos rendez-vous, vos clients et vos revenus… vérifiez votre connexion » — trois lectures qui ont réussi | `CompteDangerSection.tsx:124` |
| B5.3 | « Mes données » : `getFavorites` ne vérifie que le tableau ; un favori `null` fait **planter `load()`** (`f.favorites.map((p) => p.name)`, rejet non rattrapé) — la page reste sur son chargement pour toujours. Un rendez-vous `null` fait planter le **rendu** (`buildUserDataExport` appelé pendant le rendu) | `DataExportClient.tsx:67`, `:94` ; `lib/api/account.ts:113` |
| B5.4 | Un ♥ réussi (recherche, page salon) **ne dit rien** ; l'app dit « Ajouté aux favoris » / « Retiré des favoris », avec « Annuler » | `RechercheClient.tsx:139`, `FavoriteButton.tsx:58` ; app : `provider_card.dart:234`, `provider_detail_screen.dart:308` |

*Trouvé aussi, hors du web* : l'app fait la même erreur que B5.3 —
`data_export_screen.dart:105` et `pro_data_export_screen.dart:220` nomment
toutes les lectures quand l'assemblage échoue (Q3).

### 1.3 Ce que disent le serveur et l'app

- **Le serveur** (vérification d'un code e-mail) : `otp_invalid`,
  `otp_expired`, `otp_none`, `otp_locked` → 400 ; `invalid_input` (un code qui
  n'a pas 4 à 8 chiffres) → 400 ; `account_suspended` → 403 (client) ;
  `provider_not_found` → 404 (Pro) ; la porte d'entrée et les limites par
  identité → **429 `rate_limited`**. Recevoir un code : `invalid_email` → 400,
  **`otp_resend_limit` → 429**.
- **L'app** (`api_auth_service.dart:976`) garde une phrase **par code** et dit
  la phrase générique au reste : « Code incorrect. », « Code expiré. Demandez
  un nouveau code. », « Aucun code actif. Demandez un nouveau code. »,
  « Trop de tentatives. Demandez un nouveau code. », « Trop de demandes de
  code. Réessayez plus tard. », « Compte suspendu. ».

## 2. Ce qui change

### 2.1 La connexion dit ce qui s'est passé (B5.1)

Une seule table, `lib/auth/otp-failure.ts`, pour les trois écrans (connexion
client, connexion Pro, inscription Pro). Elle rend **où** dire (sous le champ,
ou sous le formulaire) et **quoi** :

**Valider le code**

| Réponse | Où | Phrase |
|---|---|---|
| `otp_invalid`, `invalid_input` | sous le code | « Code incorrect. » |
| `otp_expired` | sous le code | « Code expiré. Demandez un nouveau code. » |
| `otp_none` | sous le code | « Aucun code actif. Demandez un nouveau code. » |
| `otp_locked` | sous le code | « Trop de tentatives. Demandez un nouveau code. » |
| 429 (`rate_limited`) | formulaire | « Trop de tentatives. Réessayez plus tard. » |
| `account_suspended` | formulaire | « Compte suspendu. » (inchangé) |
| `provider_not_found` (Pro) | formulaire | la phrase d'aujourd'hui (inchangée) |
| rien n'a répondu (statut 0) | formulaire | « Pas de connexion. Réessayez. » |
| tout le reste (500, 502, 503…) | formulaire | « Une erreur est survenue. Réessayez. » |

**Recevoir le code** (« Continuer avec e-mail », « Renvoyer le code »,
« Recevoir un code »)

| Réponse | Où | Phrase |
|---|---|---|
| `invalid_email` | sous l'e-mail | « Saisissez une adresse e-mail valide. » (la phrase du contrôle local) |
| `otp_resend_limit` | formulaire | « Trop de demandes de code. Réessayez plus tard. » |
| autre 429 | formulaire | « Trop de tentatives. Réessayez plus tard. » |
| statut 0 | formulaire | « Pas de connexion. Réessayez. » |
| tout le reste | formulaire | « Une erreur est survenue. Réessayez. » |

L'inscription Pro passe par la même table : son code a déjà un champ
(« Code à 6 chiffres »), il reçoit ses fautes ; son téléphone garde
`invalid_phone` sous le champ et « compte existant » au formulaire.

### 2.2 Le ♥ de la recherche (B5.2)

- La lecture des favoris a **trois issues** : `ok` (on connaît les ♥),
  `anonyme` (401 : le ♥ mène à la connexion, comme aujourd'hui), `échec`
  (réseau, 500, réponse cassée). **Échec = comme la page salon** : le ♥
  s'affiche vide et tente l'écriture ; c'est **le 401 de l'écriture** qui
  décide de la connexion. Le serveur étant idempotent, ajouter un salon déjà
  favori le laisse favori.
- **Un ♥ à la fois par carte** : un ensemble `enCours` ; le ♥ de cette carte
  est désactivé tant que son écriture est en route (les autres restent
  utilisables).

### 2.3 Les exports (B5.3)

- **Une phrase à part** pour un fichier qui n'a pas pu être assemblé :
  **« Le fichier n'a pas pu être préparé. Réessayez. »** — l'export du salon
  (au lieu de nommer trois lectures réussies) et « Mes données ».
- **« Mes données » construit son document dans `load()`**, dans un
  try/catch : un document qui ne se construit pas dit la phrase ci-dessus avec
  « Réessayer », jamais un chargement sans fin ni une page cassée.
- **`getFavorites` vérifie chaque élément** : un objet avec un `id` et un
  `name` en texte ; sinon, statut 0 (« pas de réponse utilisable », la règle
  de `web-consumer-network-failure.md` §2). Cela sert aussi la recherche
  (§2.2 : une liste cassée est un `échec`, pas un visiteur anonyme), la page
  salon et « Mon compte ».

### 2.4 Le ♥ se dit (B5.4, décision 16)

- Sur la **recherche** et la **page salon** : après une écriture **réussie**,
  un toast « Ajouté aux favoris » / « Retiré des favoris » (succès, 3 s), dans
  un `<Toast>` monté en permanence sur la page (WEB-SYSTEM §7). Un échec garde
  sa phrase sous la carte ou le bouton, comme aujourd'hui — jamais un toast
  vert sur un échec.
- **Avec « Annuler »** si Q2 le retient (comme l'app) : l'action refait
  l'écriture inverse, avec les mêmes règles (en cours, 401, échec) ; le toast
  dure alors 10 s (SYSTEM §15). Le ♥ reste toujours un chemin de retour : la
  fenêtre de 10 s n'est pas un piège (WCAG 2.2.1).
- **« Mon compte »** (Q4) : « Retirer des favoris » fait disparaître la carte
  en silence ; il dit « Retiré des favoris » aussi (l'app : la rangée de
  favoris de l'Accueil a le même ♥ que partout). Avec « Annuler », la carte
  revient à sa place.

## 3. Les états

| Situation | Avant | Après |
|---|---|---|
| Code faux | « Code incorrect ou expiré. » | « Code incorrect. » (sous le champ) |
| Code expiré / absent / bloqué | « Code incorrect ou expiré. » | la phrase de l'app, sous le champ |
| Trop d'essais (429) | « Code incorrect ou expiré. » | « Trop de tentatives. Réessayez plus tard. » (formulaire) |
| Panne (500, 502, 503) en validant | « Code incorrect ou expiré. » | « Une erreur est survenue. Réessayez. » (formulaire) |
| Trop d'envois de code | « E-mail invalide ou envoi impossible. » | « Trop de demandes de code. Réessayez plus tard. » |
| Inscription Pro hors ligne | « Une erreur est survenue. Réessayez. » | « Pas de connexion. Réessayez. » |
| Recherche, lecture des ♥ échouée, ♥ | la page de connexion | l'écriture ; son 401 seul mène à la connexion |
| Double clic sur un ♥ | deux requêtes | une |
| Export du salon, assemblage raté | « Impossible de charger vos rendez-vous, vos clients et vos revenus… » | « Le fichier n'a pas pu être préparé. Réessayez. » |
| « Mes données », favori cassé | chargement sans fin | « Impossible de charger vos favoris… » + « Réessayer » |
| « Mes données », rendez-vous cassé | page cassée | « Le fichier n'a pas pu être préparé. Réessayez. » + « Réessayer » |
| ♥ réussi | rien | « Ajouté aux favoris » / « Retiré des favoris » (+ « Annuler » selon Q2) |

## 4. Accessibilité

- Une faute de champ est **sous le champ**, reliée par `aria-describedby`,
  avec `aria-invalid` (SYSTEM §14 règle 1) ; une faute de formulaire est un
  `role="alert"`.
- Le toast vit dans une zone `role="status"` **montée avant** que le texte
  arrive ; « Annuler » est un vrai bouton de 48 px, au clavier.
- Le ♥ désactivé pendant son écriture garde le focus (ou le reprend si le
  navigateur l'a lâché), comme `FavoriteButton` aujourd'hui.

## 5. Sécurité et vie privée

Aucune donnée nouvelle. Les phrases ne citent ni le serveur ni son message
(règle de l'app : le `message` du serveur n'est jamais montré). « Compte
suspendu » et « aucun compte » restent ce qu'ils sont aujourd'hui ; aucune
phrase ne dit si une adresse existe.

## 6. Les tests (rouges d'abord)

- **Unitaires** : la table §2.1 ligne par ligne, pour les trois écrans (le
  champ ou le formulaire, la phrase exacte) ; hors ligne et 500 séparés ; le ♥
  de la recherche — échec de lecture → l'écriture part, son 401 → connexion ;
  un double clic → une requête ; l'export du salon qui jette en assemblant →
  la phrase dédiée ; « Mes données » avec `[null]` en favoris → « vos
  favoris », avec un rendez-vous `null` → la phrase dédiée, et « Réessayer »
  qui relit ; le toast après un succès, jamais après un échec ; « Annuler »
  (si retenu) qui refait l'écriture inverse.
- **e2e** : un ♥ sur la recherche annonce « Ajouté aux favoris », puis le
  retire.
- **Mutations** : chaque phrase remise à l'ancienne, un code renvoyé au
  formulaire (ou l'inverse), l'échec de lecture pris pour anonyme,
  l'ensemble `enCours` retiré, l'export qui nomme les lectures, le document
  reconstruit pendant le rendu, la vérification des favoris retirée, le toast
  sur un échec.

## 7. La livraison

**Deux PR** :
- **(A) B5.1 + B5.3** — les mots des échecs : la connexion et les exports,
  et les deux écrans d'export de l'app (Q3).
- **(B) B5.2 + B5.4** — le ♥ : les mêmes fichiers (`RechercheClient`,
  `FavoriteButton`, `AccountClient`), après la décision 16.

## 8. Les mots

Nouveaux sur le web (tous déjà dans l'app, sauf un) :
- « Code incorrect. »
- « Code expiré. Demandez un nouveau code. »
- « Aucun code actif. Demandez un nouveau code. »
- « Trop de tentatives. Demandez un nouveau code. »
- « Trop de tentatives. Réessayez plus tard. »
- « Trop de demandes de code. Réessayez plus tard. »
- « Le fichier n'a pas pu être préparé. Réessayez. » *(nouveau partout)*
- « Ajouté aux favoris » · « Retiré des favoris » · « Annuler »

## 9. Questions au propriétaire

- **Q1** — La connexion : **la phrase de l'app pour chaque code**, sous le
  champ (recommandé — elle dit quoi faire : « Demandez un nouveau code »), ou
  garder « Code incorrect ou expiré. » pour les quatre codes et ne corriger
  que les échecs qui ne sont pas le code ?
- **Q2 (décision 16)** — Le ♥ réussi : **le message et « Annuler »**, comme
  l'app (recommandé — Médias a déjà un toast à action, et le ♥ reste un chemin
  de retour), ou le message seul ?
- **Q3** — L'app nomme aussi toutes les lectures quand l'assemblage d'un
  export échoue (`data_export_screen.dart`, `pro_data_export_screen.dart`) :
  **la corriger dans la PR A** avec la même phrase (recommandé — elle part avec
  la prochaine version des stores), ou la noter pour plus tard ?
- **Q4** — « Mon compte » : **dire « Retiré des favoris »** quand on retire un
  favori (recommandé — la carte disparaît en silence aujourd'hui), ou seulement
  la recherche et la page salon comme le backlog ? Et les mots (§8), tels
  qu'écrits ?

**Décisions (2026-10-21).** Q1, Q2, Q3 et Q4 : les recommandations, telles qu'écrites.
