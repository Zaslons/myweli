# Web client — une coupure réseau n'est plus un chargement éternel — spec

| | |
|---|---|
| **Statut** | **Décidé le 2026-10-16** — la même décision que [web-pro-network-failure.md](web-pro-network-failure.md) (§2 : à la racine), appliquée côté client ; construit le même jour sur `fix/consumer-network-failure` ; §11 dit ce qui a été vu rouge · **Mergé (#620) le 2026-10-16** — web en production au merge (Vercel) ; rien côté serveur |
| **Owner** | Sadreddine |
| **Last updated** | 2026-10-16 |
| **PRD ref / phase** | Les quatre états de chaque page (SYSTEM.md §12, WEB-SYSTEM §12) · V1 — web client (Mon compte, rendez-vous, favoris, notifications, avis, réservation, connexion) |
| **Module** | web client — `web/lib/api/account.ts` et les autres appels navigateur → BFF côté client (`lib/auth/client.ts`, `lib/booking/client.ts`, `lib/booking/deposit.ts`, `lib/account/review-photos.ts`) et leurs appelants |
| **ROADMAP entry** | [2026-10-16-consumer-network-failure.md](../roadmap/entries/2026-10-16-consumer-network-failure.md) |
| **Skills checked** | myweli-web-guardrails ✓ · myweli-dev-guardrails ✓ (aucun changement serveur, aucun contrat) · myweli-verification-guardrails (avant de dire « fait ») |
| **Dépend de** | Rien. Le pendant Pro ([#619](https://github.com/Zaslons/myweli/pull/619)) n'est pas fusionné : ce changement **copie** son mécanisme (§2) sans en dépendre ; voir §8 pour les deux conflits de texte attendus. |

## 1. Le défaut, vu dans le code

Consigné par [web-pro-network-failure.md](web-pro-network-failure.md) §9
(« le web client, même classe de défaut ») ; relu ici appelant par appelant.

**Les wrappers lèvent.** `lib/api/account.ts` appelle `fetch` 17 fois, sans
un seul `try`. Une coupure fait rejeter `fetch` (`TypeError: Failed to
fetch`) et le rejet traverse le wrapper jusqu'à l'appelant. Cinq wrappers
lisent en plus le corps d'un 2xx avec un `await res.json()` nu (`getMe`,
`getAppointment`, `getNotifications`, `getNotificationPrefs`,
`updateNotificationPrefs`) : un corps perdu en route rejette aussi. Deux
autres (`listAppointments`, `getFavorites`) font l'inverse : un corps
illisible devient `{}`, donc **une liste vide que personne n'a envoyée**.

Les autres appels navigateur côté client ont le même défaut :

| Fichier | Appels nus | Ce qui reste bloqué |
|---|---|---|
| `lib/auth/client.ts` | Google, Apple, e-mail (code, vérification), numéro de contact | « Continuer avec e-mail », « Se connecter », « Continuer » |
| `lib/booking/client.ts` | `createBooking` (+ `requestOtp` / `verifyOtp`, sans appelant) | « Confirmer la réservation » |
| `lib/booking/deposit.ts` | la signature, l'attache de la preuve | « Envoyer la preuve » (acompte) |
| `lib/account/review-photos.ts` | la signature, le signalement | « Ajouter une photo » (avis), « Signaler » |

`fetchSlots` (`lib/booking/client.ts`) attrape déjà le rejet (A14d) ; mais un
2xx illisible y devient `ok` avec **aucun créneau** — « Aucun créneau
disponible » pour une réponse perdue. `lib/use-localities.ts` lève, mais son
hook attrape (`.then(ok, err)` → `error`) : pas de défaut. `putToStorage`
(`lib/upload-telemetry.ts`) ne lève jamais.

**Les pages ne l'attrapent pas.** Chaque page client charge dans un
`useEffect` ou un `useCallback`, sans `try/catch`. Le rejet saute
`setLoading(false)` : la page reste sur son squelette **pour toujours**, sans
message ni « Réessayer ». `app/error.tsx` ne voit rien : une frontière
d'erreur React n'attrape pas un rejet dans un effet.

| Page / îlot | Chargement | Lectures |
|---|---|---|
| Mon compte (`/mon-compte`) | effet | `/me`, rendez-vous, favoris |
| Détail d'un rendez-vous (`/mon-compte/[id]`) | `load` | le rendez-vous |
| Notifications (`/mon-compte/notifications`) | `load` | le fil, les préférences |
| Mes données (`/mon-compte/donnees`) | `load` | `/me`, rendez-vous, favoris |
| Réserver — étape « Confirmation » | effet (sonde de session) | `/me` |
| Cloche de l'en-tête, « Vos rendez-vous ici », ♥ du salon, ♥ de la recherche | effet | notifications / rendez-vous / favoris — silencieux, ne rendent rien sur un échec |

**Les enregistrements aussi** : sur une coupure, l'état « occupé » n'est
jamais relâché — « Annuler le rendez-vous », « Confirmer le report »,
« Envoyer l'avis », « Supprimer définitivement », « OK » (le nom),
« Enregistrer » (le numéro), « Confirmer la réservation », la connexion, le ♥.

**L'app** traite la coupure comme une réponse : `api_*_service.dart` rend
`ApiResponse.error('Pas de connexion. Réessayez.')` (`_networkError`), et
l'écran affiche son état d'erreur avec « Réessayer ».

## 2. Décision : la racine, comme le Pro

La même que [web-pro-network-failure.md](web-pro-network-failure.md) §2, pour
les mêmes raisons (plus petit, couvre les pages à venir) :

1. **`send()`** — un `fetch` qui ne lève pas : un rejet devient
   `Response.error()` (statut 0, `ok` faux, corps vide). Chaque branche
   `!res.ok` existante le lit comme une réponse non 2xx de plus, sans code.
2. **`readJson()`** — la lecture d'un corps 2xx, qui ne lève pas :
   illisible (coupé, pas du JSON, `null`) → `undefined`.
   - **Lectures** : 2xx illisible → **statut 0**, jamais une liste vide
     inventée.
   - **Écritures** : 2xx illisible → `ok` (le serveur a agi) sans la charge
     utile (`prefs`, `appointment`, `user`).
3. **Un seul endroit** : `lib/api/network.ts` porte `send`, `readJson` et
   `NO_CONNECTION_MESSAGE` (« Pas de connexion. Réessayez. », la phrase de
   l'app). Tous les fichiers du §1 l'importent. `lib/pro/team.ts` réexporte
   la phrase au lieu de la répéter. `lib/api/pro.ts` garde sa propre copie
   tant que #619 n'est pas fusionné ; l'aligner ensuite est une ligne (§9).

## 3. L'audit : chaque appelant sous le statut 0

Le changement racine transforme « bloqué pour toujours » en « la branche pas
200 ». Pour la plupart des appelants, cette branche dit déjà vrai. **Sept
appelants disent faux** sous le statut 0, et changent ici.

### 3.1 Ceux qui disent déjà vrai — inchangés

- **401** : chaque appelant teste `=== 401` → la redirection vers
  `/connexion` ne change pas ; 0 n'est pas 401.
- **Mon compte** : `/me` ou rendez-vous ≠ 200 → son `ErrorState` +
  « Réessayer » (le h1 « Mon compte » est celui de la page).
- **Notifications** : le fil ≠ 200 → `ErrorState` « Notifications » ; les
  préférences ≠ 200 → « Préférences indisponibles. » + « Réessayer ». Le
  bouton de préférence : `!ok` → retour en arrière + « Impossible
  d'enregistrer. Réessayez. »
- **Écritures à phrase générique, vraie sur une coupure** : « L'annulation a
  échoué. Réessayez. », « Le report a échoué. Réessayez. »
  (`conflictMessage(undefined)` → le repli), « L'envoi a échoué.
  Réessayez. » (avis), « Échec de l'envoi de la photo. Réessayez. »,
  « La suppression a échoué. Réessayez. » (`future_bookings` intact),
  « L'enregistrement a échoué. Réessayez. » (numéro), « Votre numéro n'a pas
  pu être enregistré. Réessayez. », « La réservation a échoué. Réessayez. »,
  « Le signalement a échoué. Réessayez. », « Connexion Google
  impossible. », « Connexion Apple impossible. » (le rejet y était avalé en
  silence par le `catch` des annulations de la fenêtre Apple).
- **Les îlots silencieux** (cloche, « Vos rendez-vous ici », ♥) : déjà rien
  sur un 5xx ; ils ne rejettent plus.

### 3.2 Ceux qui disent faux — sept changements

| Appelant | Aujourd'hui (rejet) | Statut 0 sans changement | Changement |
|---|---|---|---|
| **Détail d'un rendez-vous** | « Chargement… » pour toujours | « **Rendez-vous introuvable** — Ce rendez-vous n'existe pas ou n'est plus accessible. » : tout ≠ 200 y menait | 404 / 403 → introuvable (le serveur dit 403 pour le rendez-vous d'un autre, BACKEND §3.3) ; **tout autre échec** → `ErrorState` « Rendez-vous » + « Réessayer » + « ← Mes rendez-vous » |
| **Mes données** | « Chargement… » pour toujours | un export **avec 0 rendez-vous et 0 favori** — le statut des deux listes était ignoré : un document téléchargeable qui ment | les trois lectures doivent répondre 200, sinon `ErrorState` « Mes données » — sa phrase nomme depuis ce qui manque, et un 401 sur n'importe laquelle mène à la connexion ([consumer-export-completeness.md](consumer-export-completeness.md)) |
| **Mon compte — Favoris** | squelette pour toujours | « **Aucun favori** » — le statut était ignoré (le défaut que le commentaire de la liste décrit pour un salon arrêté) | favoris ≠ 200 → la section dit « Favoris indisponibles. » + « Réessayer » (le motif des préférences de notification) ; les rendez-vous restent affichés |
| **Mon compte — « Se déconnecter »** | rien (rejet non géré) | **retour à l'accueil, la session vivante** : `logout()` ne rendait rien et la page naviguait sans regarder | `logout()` rend `'ok' \| 'offline' \| 'failed'` (le `LogoutOutcome` du Pro) ; seul `'ok'` quitte la page ; sinon « Pas de connexion. Réessayez. » ou la phrase générique, et le bouton revient |
| **Réserver — « Confirmation »** | « Chargement… » pour toujours | **le formulaire de connexion** à quelqu'un de connecté : tout ≠ 200 valait « pas de session » | 401 → la connexion (inchangé) ; tout autre échec → une erreur de section + « Réessayer » qui relance la sonde |
| **Connexion — « Continuer avec e-mail » / « Se connecter »** | bouton bloqué | « E-mail invalide ou envoi impossible. » (accuse l'e-mail) ; « **Code incorrect ou expiré.** » **sous le champ** — faux | statut 0 → « Pas de connexion. Réessayez. » au niveau du formulaire ; le champ n'est pas accusé (la même décision que la connexion Pro, #619 §3) |
| **Acompte — « Envoyer la preuve »** | bouton bloqué | « L'envoi a échoué. **Vérifiez l'image** et réessayez. » — accuse l'image | la signature ou l'attache sans réponse → « Pas de connexion. Réessayez. » ; un refus (format, stockage) garde la phrase actuelle |

Pour cela, `uploadDepositProof` rend `{ ok: true, key } | { ok: false,
offline }` (un seul appelant, `DepositProof`), et `attachDepositProof`,
`requestEmailOtp`, `postLogin` (`LoginResult`) et `updateContactPhone`
rendent leur `status` (ajout ; aucun appelant ne casse).

## 4. Les états ajoutés

- **Détail — erreur** : le h1 « Rendez-vous » (via `ErrorState title`), la
  phrase partagée « Une erreur est survenue. Réessayez. », « Réessayer »
  (recharge le rendez-vous, squelette pendant le chargement), puis le lien
  « ← Mes rendez-vous » — §12 : jamais une impasse.
- **Favoris — erreur** : `ErrorState` sans titre (le h2 « Favoris » reste),
  « Favoris indisponibles. », « Réessayer » recharge la page (comme les
  préférences de notification).
- **Réserver — sonde ratée** : `ErrorState` sans titre (le h2
  « Confirmation » reste), la phrase partagée, « Réessayer » relance
  `getMe` ; pendant ce temps « Chargement… ».
- **« Se déconnecter »** : occupé pendant l'appel (`isLoading`) ; l'erreur en
  `role="alert"` sous le bouton ; le focus revient au bouton si le
  désactiver l'avait perdu (comme `ProLogoutButton`).

## 5. Téléversement

`lib/booking/deposit.ts` et `lib/account/review-photos.ts` : la demande de
signature passe par `send()` ; **pas de réponse → pas de rapport Sentry**
(même décision que le Pro, #619 §5 : même origine, c'est le réseau de la
personne, pas un CORS ni le stockage). Un refus de la signature ou du
stockage reste signalé comme avant.

## 6. UX

Aucun composant nouveau. Une seule phrase nouvelle, calquée sur une phrase
existante : « Favoris indisponibles. » (« Préférences indisponibles. »).
Les autres sont déjà là : « Pas de connexion. Réessayez. » (l'app, la
connexion Pro), « Une erreur est survenue. Réessayez. » (`ErrorState`).

## 7. Contrat, sécurité, performance

Aucun changement d'API, de contrat, de serveur ni de BFF. **Sécurité** : la
déconnexion n'affiche plus jamais un écran « déconnecté » au-dessus d'une
session vivante (les cookies httpOnly ne s'effacent que par la réponse du
BFF) — un cybercafé, un téléphone prêté ; un 401 reste un 401 ; le statut 0
n'ouvre rien. Performance : un `try` de plus par appel.

## 8. Déploiement

Web au merge (Vercel) ; rien côté serveur. **Indépendant de #619** — aucun
fichier en commun hors docs. Deux conflits de texte attendus, quel que soit
l'ordre : la ligne de tête de l'index des specs (`docs/design/README.md`,
les deux branches en ajoutent une), et peut-être `docs/WEB.md` §3 (les deux
règles sont voisines). Après les deux : `lib/api/pro.ts` peut importer
`send` / `readJson` de `lib/api/network.ts` (§9).

## 9. Hors périmètre, consigné

- **Les écritures optimistes qui ne reviennent pas en arrière**, déjà
  silencieuses sur un 5xx : « Retirer des favoris » (Mon compte) retire la
  carte sans attendre et ne la remet pas ; « Marquer comme lu » / « Tout
  lire » ; le ♥ du salon et de la recherche ne disent rien d'un échec ;
  « OK » (le nom) referme sans un mot. Elles ne bloquent plus et ne lèvent
  plus ; les rendre bavardes est une tâche à part.
- **Le ♥ de la recherche** traite une sonde ratée comme « anonyme » (choix
  documenté dans `RechercheClient`) : un clic mène à la connexion.
- **Le mot de l'app** sur une lecture ratée (« Pas de connexion » plutôt que
  la phrase générique) — même réserve que le Pro (#619 §9).
- **Une écriture faite dont la réponse s'est perdue** : la réservation peut
  exister alors que la page dit « La réservation a échoué » ; un nouvel essai
  répond alors « Ce créneau vient d'être pris ». La fenêtre — requête partie,
  réponse perdue — est étroite ; « Mon compte » montre la vérité. Un 2xx au
  corps perdu, lui, passe à « Réservation envoyée ✓ » sans le bloc
  d'acompte (joignable depuis le détail, K2).
- **Un 5xx sur « Se connecter »** dit encore « Code incorrect ou expiré. » :
  ce changement ne corrige que le statut 0, comme le Pro.
- **Aligner `lib/api/pro.ts` sur `lib/api/network.ts`** une fois #619
  fusionné.

## 10. Tests (rouges d'abord, contre le code d'avant)

- **Unité, table** (`tests/consumer-api-network.test.ts`) : **chaque**
  fonction exportée de `lib/api/account.ts`, `lib/auth/client.ts`,
  `lib/booking/client.ts`, `lib/booking/deposit.ts` et
  `lib/account/review-photos.ts` — `fetch` rejette → la promesse se résout
  (statut 0 / `ok` faux / `'offline'` / `null`) ; 2xx illisible → lectures
  statut 0, écritures `ok` sans charge utile. Une garde par module exige que
  la table couvre tous ses exports (les fonctions pures de `review-photos`
  sont nommées comme telles). La signature sans réponse : aucun rapport.
- **Composant, pages** (`tests/consumer-network-pages.test.tsx`) : Mon
  compte, le détail, les notifications, Mes données, l'étape
  « Confirmation » — tout rejette → l'erreur et « Réessayer », jamais le
  squelette ; et chaque cas du §3.2 : le détail jamais « introuvable » (404
  et 403 le restent), l'export jamais à 0, jamais « Aucun favori », jamais le
  formulaire de connexion ; « Réessayer » ramène la page. Les îlots
  silencieux ne rendent rien et ne rejettent pas.
- **Composant, enregistrements** (`tests/consumer-network-saves.test.tsx`) :
  « Se déconnecter » sans réseau → pas de navigation, la phrase, le bouton
  revient (et sur un 500) ; annuler, reporter, l'avis, sa photo, la
  suppression, le numéro, la réservation, la préférence, le ♥, le
  signalement → la phrase d'échec et le bouton revient ; la connexion →
  « Pas de connexion. Réessayez. », le champ du code n'est pas accusé ;
  l'acompte → « Pas de connexion. Réessayez. », jamais « Vérifiez l'image ».
- **Mutations** à voir rouges : retirer le `catch` de `send()` ; celui de
  `readJson()` ; remettre `.catch(() => ({}))` sur une lecture de liste ;
  chaque changement du §3.2 retiré un à un ; le rapport Sentry remis sur une
  signature sans réponse.

## 11. Construit — vu rouge

- **Vu rouge contre le code d'avant** : la table des wrappers 42 cas sur 72
  (chaque wrapper rejetait ; `listAppointments` et `getFavorites` inventaient
  une liste vide d'un corps illisible, `fetchSlots` « aucun créneau » ; les
  cinq gardes de couverture passent déjà, comme elles le doivent) ; les pages
  et les îlots 19 sur 25 (chacune sur son squelette ou « Chargement… », trois
  îlots qui laissaient un rejet non géré ; les six verts sont les cas
  inchangés épinglés : 404, 403, 401, « Aucun favori » envoyé par le serveur,
  l'export complet, la connexion sur un 401) ; les enregistrements 18 sur 21
  (les trois verts : la déconnexion réussie, le code faux, l'image refusée).
- **Le test existant** `tests/booking-deposit.test.ts` suit les nouvelles
  formes (`uploadDepositProof` → `{ ok, key }` / `{ ok: false, offline }`,
  `attachDepositProof` rend son `status`).
- **Mutations** : 22 sur 22 rattrapées — le `catch` de `send()` (30 cas
  rouges) et de `readJson()` (14) ; `listAppointments` remis à
  `.catch(() => ({}))` ; `getMe` qui prend un 200 illisible pour un 200 ;
  `logout()` qui lit le statut 0 comme `failed`, puis toute réponse comme
  `ok` ; `postLogin` sans son statut ; `fetchSlots` qui reprend un corps
  perdu pour « aucun créneau » ; les deux signatures sans réponse remises au
  rapport Sentry ; le détail qui redit « introuvable » sur tout échec, puis
  qui ne remet jamais son erreur à faux ; « Mes données » qui ignore les
  listes ; les favoris dont l'échec est ignoré ; la déconnexion qui navigue
  sans regarder, puis qui dit la phrase générique hors ligne ; la sonde de
  « Confirmation » lue comme « déconnecté », puis « Réessayer » qui ne la
  relance pas ; la connexion (« Continuer », « Se connecter ») sans branche
  statut 0 ; l'acompte qui redit « Vérifiez l'image » sur la signature, puis
  sur l'attache. Et la garde de couverture : un wrapper ajouté à
  `account.ts` sans ligne dans la table la fait tomber.
- **Suite complète** : 1195 tests sur 1195, `tsc` et le lint propres ;
  `next build` passe contre l'API bouchon de la CI. Non lancés en local :
  l'e2e Playwright et Lighthouse (la CI les lance).
- **Non couvert par un test de composant** : le ♥ de la recherche
  (`RechercheClient`, carte et recherche à monter) — son comportement visible
  ne change pas (`.finally`), la table tient `getFavorites`.
