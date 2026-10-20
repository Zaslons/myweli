# « Avis » — la note, le nombre et la répartition du salon entier, envoyés par le serveur — spec

| | |
|---|---|
| **Statut** | **Construit le 2026-10-20** sur `feat/reviews-server-summary` (depuis `main`) ; ce qui a été vu : §4. Validé le même jour — décision du propriétaire : **le résumé du serveur, web et app** · **Mergé (#658) le 2026-10-20** — web en production à la fusion ; app au prochain build ; serveur en production : révision `myweli-api-00042-468` (image `9f320d4`, `sha256:498778da…`), 100 % du trafic, le 2026-10-20 |
| **Owner** | Sadreddine |
| **Last updated** | 2026-10-20 |
| **PRD ref / phase** | Avis (consumer-reviews) · parité web ↔ app Pro · V1 |
| **Module** | backend `GET /me/provider/reviews` (`ReviewsService`, `ReviewsRepository.ratingDistribution`) ; web Pro `AvisClient` ; app Pro `ReviewsScreen`, `ProReviewsProvider`, `getMyReviews` |
| **Origine** | [parity-audit-web-pro-2026-10.md](parity-audit-web-pro-2026-10.md) §4 (P2) : « Avis : moyenne calculée sur la page chargée, total serveur » |
| **Skills checked** | myweli-backend-guardrails ✓ · myweli-web-guardrails ✓ · myweli-dev-guardrails ✓ |

## 1. Le constat

- **Web** (`AvisClient.tsx:88,107,110`) : la moyenne et les barres sont
  calculées sur les avis **chargés** (50 par page), à côté du **total** du
  serveur — au-delà de 50 avis, « 60 avis » et une note qui n'en compte que 50.
- **App** (`reviews_screen.dart:59-65,136,152-159`) : la moyenne, le nombre et
  les barres sur la **première page de 50**, la seule jamais chargée — juste
  jusqu'à 50, faux au-delà, sans le dire.
- **Le serveur** connaît déjà la bonne note : `provider.rating` (une
  décimale) et `reviewCount`, recalculés sur les avis **visibles** à chaque
  avis et chaque modération — c'est celle que les clients voient sur la page
  du salon. La liste `GET /me/provider/reviews` ne renvoie pourtant que
  `{items, page, pageSize, total}`.

## 2. Le changement

- **Serveur** : la réponse gagne `summary` — `{average, count,
  distribution: {"5", "4", "3", "2", "1"}}` sur **tous** les avis visibles du
  salon, la moyenne arrondie à une décimale comme `provider.rating`. Un
  nouveau `ReviewsRepository.ratingDistribution` (en mémoire et Postgres, les
  avis masqués exclus comme partout). Contrat : `ReviewSummary`, requis.
- **Web** : la carte (note, « N avis », barres) vient de `summary` ; un
  serveur qui ne l'envoie pas encore → le calcul local d'avant.
- **App** : `getMyReviews` rend la page avec son `summary` ; `ProReviewsProvider`
  le garde (et l'oublie à un changement de salon) ; la carte de `ReviewsScreen`
  passe par `reviewCard` (le résumé s'il est là, sinon les avis chargés). Le
  mock calcule son résumé de ses avis : les goldens ne changent pas.

Aucun texte nouveau.

## 3. Les tests (rouges d'abord)

Serveur : 60 avis, une page de 20 → le résumé compte les 60 (pages 1 et 3) ;
la décimale ; un avis masqué ne compte nulle part ; aucun avis → des zéros ;
Postgres ; contrat. Web : `statsFromSummary`, la page (« 60 avis », 4,2 et
pas 5,0, les barres) et le repli. App : le format reçu, `reviewCard`, le
provider.

## 4. Construit — ce qui a été vu

- **Rouge d'abord** : serveur (4 tests de la route, Postgres, contrat), web
  (`statsFromSummary`, la page), app (le format reçu, `reviewCard`, le
  provider). Le test Postgres a dû être réécrit : la table exige un salon
  existant, et le salon partagé des tests porte d'autres avis — il mesure
  l'écart.
- **Une mutation survivait** : l'écran de l'app qui ignore le résumé ne
  faisait rougir aucun test unitaire ; un test d'écran (« 4,2 », « 60 avis »
  sur 50 avis 5★ chargés) l'attrape maintenant.
- **Mutations vues rouges** : le résumé de la page au lieu du salon, sans
  arrondi, Postgres et mémoire qui comptent les masqués (serveur) ; le web
  qui ignore le résumé ; le provider qui le perd ; l'écran qui l'ignore (app).
- **Vérifié** : serveur — analyse 0, **1 757** tests + Postgres ; web —
  typecheck et lint propres, 203 tests des pages Pro, e2e **98** verts ; app —
  analyse 0, **1 844** tests unitaires et d'écran. Les goldens ne bougent pas
  (le mock calcule son résumé comme le serveur ; « 4,3 » dans les deux cas).
