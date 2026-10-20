# Web Pro — Médias comme l'app : chaque geste s'enregistre, la suppression demande et se rattrape — spec

| | |
|---|---|
| **Statut** | **Construit le 2026-10-20** sur `feat/web-pro-medias-like-app` (depuis `main`) ; ce qui a été vu : §5. Validé le même jour — décision du propriétaire : **comme l'app** (option a, §2) · **Mergé (#657) le 2026-10-20** — web en production à la fusion |
| **Owner** | Sadreddine |
| **Last updated** | 2026-10-20 |
| **PRD ref / phase** | Médias du salon · parité web ↔ app Pro · V1 |
| **Module** | web Pro — `/pro/medias` (`MediasClient`), `lib/useToast` + `components/Toast` (le toast avec action), `lib/pro/medias.ts` |
| **Origine** | [parity-audit-web-pro-2026-10.md](parity-audit-web-pro-2026-10.md) §4 (P2) : « Médias : changements perdus sans avertissement, suppression sans confirmation » |
| **Skills checked** | myweli-web-guardrails ✓ · myweli-dev-guardrails ✓ · aucun changement serveur |

## 1. Le constat

- **L'app** (`pro_photos_screen.dart`, `pro_before_after_screen.dart`,
  `pro_gallery_provider.dart`) : ajouter, déplacer, choisir la couverture,
  supprimer — **chaque geste s'enregistre** (pas de bouton « Enregistrer »).
  Supprimer demande d'abord : « Supprimer cette photo ? » — « Elle disparaîtra
  de votre galerie publique. » — « Supprimer la photo » ; puis « Photo
  supprimée » avec **« Annuler »** pendant 10 s. Même chose pour une paire :
  « Supprimer cette paire ? » — « L’avant/après disparaîtra de votre galerie
  publique. » — « Supprimer la paire » ; « Avant/après supprimé ».
- **Le web** (`MediasClient.tsx`) : tout est préparé localement puis
  « Enregistrer » ; « Supprimer » retire sans rien demander ; quitter la page
  perd tout ce qui n'a pas été enregistré, sans avertir.

## 2. Options (Q)

- (a) **Comme l'app** : chaque geste s'enregistre ; supprimer demande (une
  fenêtre, les mots de l'app) puis « Annuler » 10 s (le toast avec action,
  §15) ; plus de bouton « Enregistrer » ni de perte possible.
- (b) Garder « Enregistrer » ; ajouter la confirmation de suppression et un
  avertissement en quittant avec des changements non enregistrés (texte
  nouveau à valider).

## 3. Le parcours retenu (a)

- **Ajouter** une photo : téléversée puis enregistrée (la galerie avec elle) ;
  échec → « Échec de l’envoi » (l'app).
- **★ / ↑ / ↓** : la galerie réordonnée est enregistrée ; échec → elle revient
  telle que le serveur l'a, « Échec du déplacement » (l'app).
- **Supprimer** : une fenêtre (`Modal`) — « Supprimer cette photo ? » /
  « Elle disparaîtra de votre galerie publique. » / « Annuler » (prend le
  focus, SYSTEM §15) et « Supprimer la photo » ; puis la galerie sans elle est
  enregistrée et le toast dit « Photo supprimée » avec **« Annuler »**, 10 s
  (§15 : le toast est le seul chemin du retour) ; « Annuler » la remet **à sa
  place dans la galerie telle qu'elle est alors** — un geste annulé, jamais un
  instantané (§15) ; échec → « Restauration impossible. ». Suppression
  refusée → la photo reste, « Suppression impossible. ».
- **Avant / Après** : « Ajouter la paire » l'enregistre ; supprimer une paire
  — « Supprimer cette paire ? » / « L’avant/après disparaîtra de votre galerie
  publique. » / « Supprimer la paire » — puis « Avant/après supprimé » et
  « Annuler ».
- Plus de bouton « Enregistrer », plus rien à perdre en quittant la page.
- Pendant un enregistrement, les contrôles attendent (pas deux écritures qui
  se croisent).
- **Le toast avec action** : `useToast.show(message, kind, action?)` ; avec
  une action, 10 s (§15) ; le bouton est dans la zone `role="status"`.

## 4. Les tests (rouges d'abord)

Chaque geste enregistré ; la question de l'app, « Annuler » qui prend le
focus ; « Supprimer la photo » puis « Annuler » qui la remet ; l'annulation
dans la galerie actuelle (pas un instantané) ; les refus qui reviennent en
arrière avec les mots de l'app ; les paires ; le toast d'action 10 s. Le test
de l'étoile et le parcours e2e Médias perdent « Enregistrer ».

## 5. Construit — ce qui a été vu

- **Rouge d'abord** : 13 tests (12 de page, le toast d'action 10 s) ; le test
  de l'étoile et le parcours e2e Médias ont perdu « Enregistrer » (le parcours
  vérifie maintenant qu'un rechargement garde l'ajout, puis supprime et
  annule).
- Le test du toast cherchait la pastille par son texte : le message reste le
  texte propre de la pastille, le bouton à côté.
- **Mutations vues rouges** : supprimer sans demander, l'annulation qui
  rejoue un instantané, pas de retour en arrière sur un refus, le toast
  d'action à 3 s ; « Annuler » qui ne prend pas le focus — équivalente tant
  que « Annuler » est le premier bouton (le `Modal` donne le focus au premier),
  vue rouge avec le bouton destructeur en premier ; e2e : le « Annuler » du
  toast sans son plancher (20 px).
- **Vu dans le navigateur** (stub) : la question de l'app, puis « Photo
  supprimée · Annuler », la photo revenue.
- **Vérifié** : typecheck et lint propres, **1 581** tests unitaires ; e2e
  (pro, axe — la question et le toast ouverts —, cibles, reflow, couches)
  **105** + 3 verts.
