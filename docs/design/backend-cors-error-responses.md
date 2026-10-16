# Les erreurs de l'API portent les en-têtes CORS — spec

| | |
|---|---|
| **Statut** | **Construit (#613) et déployé en production le 2026-10-16** — révision `myweli-api-00040-8tw` (image `cd21d03`) ; vu en service sur `api.myweli.com` |
| **Module** | backend — bord de la chaîne (CORS, observabilité, contrôle des requêtes) · T27 |
| **Origine** | Une sonde de la tranche [phone-leftovers.md](phone-leftovers.md) : `400=400 acao=null · 500=500 acao=null · 200 acao=https://myweli.com` |
| **Régit** | `backend/routes/_middleware.dart` (ordre) · `backend/lib/src/cors.dart` (en-têtes) · CI « Backend — boot smoke » (sonde) · `docs/BACKEND.md` §2 |

## 1. Le défaut, vérifié

- La chaîne racine plaçait `observabilityMiddleware` **à l'extérieur** de
  `corsMiddleware` (dans dart_frog, le dernier `.use` enveloppe tout). Quand un
  handler lève, CORS n'a aucune réponse à décorer : le 500 d'observabilité
  part **sans** en-têtes CORS. Idem pour le 400 de `querySanityMiddleware`,
  lui aussi hors de CORS — et pour le 400 `invalid_body` de
  [phone-leftovers.md](phone-leftovers.md) §3.
- Effet : un client navigateur qui appelle l'API directement (la console
  d'administration) voit une **erreur réseau opaque**, pas l'erreur.
- Le commentaire au-dessus de la chaîne donnait exactement cette raison… pour
  l'ordre qu'il n'appliquait pas.
- **Vu sur un vrai serveur** (build `dart_frog`, `ENV=dev`) :
  `GET /providers?q=%00` avec `Origin: http://localhost:3000` → `400`, aucun
  en-tête `access-control-*`.

## 2. Le correctif

- **CORS devient la couche la plus extérieure.** Ordre (de l'extérieur vers
  l'intérieur) : CORS → observabilité → contrôle des requêtes → porte d'origine
  (T70/T71) → fournisseurs → handler. Toute réponse à une origine autorisée —
  une erreur comprise — porte les en-têtes ; une origine non autorisée n'en
  reçoit **aucun** (liste fermée, jamais `*`).
- **`Access-Control-Expose-Headers: X-Request-Id`** : l'identifiant que chaque
  réponse porte (et qu'un utilisateur cite depuis un écran d'erreur) devient
  lisible par le navigateur ; CORS masque sinon tout en-tête non standard.
  L'identifiant n'est pas une donnée sensible.
- **Ce qui pouvait lever, désormais hors de toute prise** — trouvé par la
  revue adverse : CORS lit `request.method` pour reconnaître un pré-vol, et le
  getter de dart_frog **lève** pour un verbe hors de son énumération (PROPFIND,
  TRACE…). Dehors, rien ne l'attrapait : la réponse de dernier recours de shelf
  (500 en texte brut, sans identifiant) et un journal contenant la chaîne de
  requête. La lecture est gardée comme dans l'observabilité et la porte
  d'origine : un verbe inconnu n'est pas un pré-vol, il passe à l'intérieur, où
  le routeur répond 405. Vu sur un vrai serveur : `PROPFIND
  /providers?token=…` → 405 avec identifiant et en-têtes CORS, le secret absent
  du journal. La liste des origines (`webOrigins`), elle, est résolue et
  vérifiée au démarrage : elle ne peut pas lever à la requête.
- Un pré-vol `OPTIONS` est désormais répondu par CORS avant l'observabilité
  (sans identifiant ni journal) : il ne touche à rien — et il l'était déjà
  avant la porte d'origine.

## 3. Tests

- `test/security/cors_error_responses_test.dart` : le bord dans l'ordre déclaré
  → un 500 levé (et prouvé être le nôtre : le rapporteur reçoit le
  `StateError`) et le 400 de contrôle portent les en-têtes pour l'origine
  autorisée, et l'identifiant est exposé ; une origine hostile n'a rien ; une
  épingle de l'ordre dans `routes/_middleware.dart` (CORS = dernier `.use`) ;
  PROPFIND et TRACE ne sortent pas de la chaîne (vus rouges : levés hors de
  CORS).
  **Vu rouge** contre l'ancien ordre (3 échecs : ordre ×2, identifiant non
  exposé).
- **CI, sur le serveur compilé** (« Backend — boot smoke ») : la même requête
  doit répondre 400 **avec** `access-control-allow-origin` et
  `access-control-expose-headers: x-request-id`, et rien pour une origine
  hostile. Lancée en local d'abord : ancienne chaîne → aucun en-tête ; nouvelle
  → les deux.

## 4. Déploiement

Backend seulement ; aucune forme de réponse ne change. Production sur feu vert
du propriétaire.
