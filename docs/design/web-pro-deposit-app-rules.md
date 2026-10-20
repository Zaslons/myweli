# Web Pro — l'Acompte avec les règles et les explications de l'app — spec

| | |
|---|---|
| **Statut** | **Construit le 2026-10-20** sur `feat/web-pro-deposit-app-rules` (au-dessus de #639) ; ce qui a été vu : §5. Validé le même jour — décision du propriétaire : **le web prend les règles de l'app** (curseur 5–80 % par pas de 5, délai 12 / 24 / 48 h, les trois explications) ; une valeur enregistrée hors de ces choix s'affiche telle quelle jusqu'à ce qu'on la change ; le serveur garde sa plage |
| **Owner** | Sadreddine |
| **Last updated** | 2026-10-20 |
| **PRD ref / phase** | Acompte (no-custody, capture d'écran) · parité web ↔ app Pro · V1 |
| **Module** | web Pro — `/pro/acompte` (`AcompteClient`, `lib/pro/deposit.ts`) |
| **Origine** | [parity-audit-web-pro-2026-10.md](parity-audit-web-pro-2026-10.md) §4 (P2) : « règles différentes (web 1–100 % / 0–720 h, app 5–80 % / 12-24-48 h), sans l'exemple ni « MyWeli ne le traite pas » » |
| **Dépend de** | #639 (les mots « Acompte sur votre Mobile Money » de l'exemple) — cette branche part de la sienne |
| **Skills checked** | myweli-web-guardrails ✓ · myweli-dev-guardrails ✓ · aucun changement serveur |

## 1. Le constat

- **L'app** (`deposit_settings_screen.dart`) : « Exiger un acompte » —
  « Limite les rendez-vous manqués » ; **curseur** 5–80 % par pas de 5 avec
  sa valeur ; **un exemple** sur une prestation de 20 000 (« Acompte sur
  votre Mobile Money », « Solde au salon ») ; **« Recevoir l’acompte »** —
  « Le client envoie l’acompte directement sur ce compte Mobile Money.
  MyWeli ne le traite pas. » ; **« Politique d’annulation »** — « Au-delà de
  ce délai… » et trois choix **12 h / 24 h / 48 h**.
- **Le web** : deux champs libres (1–100 %, 0–720 h, ce que le serveur
  accepte), aucune des explications.

## 2. Le web, dans l'ordre de l'app

1. « Exiger un acompte » (la case du web) + « Limite les rendez-vous manqués ».
2. Activé : « Pourcentage de l’acompte » et sa valeur (« 30 % »), un
   **curseur** natif (`input type="range"`, 5–80, pas de 5, nommé « Pourcentage
   de l’acompte », `aria-valuetext` « 30 % »).
3. Activé : « Exemple sur une prestation de 20 000 FCFA » (la devise du
   salon) — « Acompte sur votre Mobile Money » / « Solde au salon », calculés
   comme l'app (`round(total × pourcentage)`).
4. « Recevoir l’acompte » — la phrase de l'app — puis l'opérateur et le
   numéro (les contrôles du web).
5. « Politique d’annulation » — la phrase de l'app — et les trois choix, un
   **groupe de boutons radio** (`role="radiogroup"` nommé par le titre) ;
   chaque choix ≥ 48 px.
6. « Enregistrer ».

**Une valeur d'avant** (le web acceptait 1–100 % et 0–720 h) : un
pourcentage hors du curseur s'affiche tel quel (« 100 % ») et le curseur se
place à sa borne — il ne change qu'au premier geste ; un délai hors des trois
choix devient **un quatrième choix, coché** (« 72 h »), jusqu'à ce qu'on en
prenne un autre. Rien n'est réécrit sans geste.

## 3. Ce qui ne change pas

Le chargement et ses erreurs, la vérification (T52), l'opérateur, le numéro
et ses règles, ce qui est envoyé quand l'acompte est coupé (acompte-off-parity
D1), le serveur.

## 4. Les tests (rouges d'abord)

- **Pur** : les bornes et le pas, l'exemple (30 % → 6 000 / 14 000 ;
  37,5 % → 7 500 / 12 500), les choix de délai (72 → 12, 24, 48, 72).
- **Composant** : le curseur et sa valeur ; le bouger change l'exemple et
  l'envoi ; les trois explications ; les choix de délai, 48 h envoyé ; un
  délai de 72 h coché tel quel ; 100 % affiché tel quel et renvoyé tel quel
  sans geste ; plus aucun champ libre.
- Les tests qui tapaient dans les anciens champs passent par le curseur.
- **e2e** : le parcours Acompte par le curseur et un choix de délai ; axe,
  cibles, reflow.

## 5. Construit — ce qui a été vu

- **Rouge d'abord** : 9 tests purs, 7 de page ; les tests de l'ancien champ
  passent par le curseur. Le repli « un pourcentage illisible caché envoie
  celui chargé » ne se démontre plus en tapant « abc » (un curseur ne le
  permet pas) mais sur une valeur d'avant (0,4 %, sous le 1 % que le champ
  permettait).
- **Vu dans le navigateur à 320 px** : « 30 % » et « 6 000 FCFA » se
  coupaient avant leur unité — la matrice de reflow compte un retour à la
  ligne comme un succès ; les valeurs restent sur une ligne.
- La case « Exiger un acompte » portait d'abord sa phrase dans son nom
  accessible (« Exiger un acompteLimite… ») : la phrase est sa description
  (`aria-describedby`).
- **Mutations vues rouges** : l'ancienne plage du web, l'exemple figé, un
  délai d'avant perdu, « MyWeli ne le traite pas » retiré, une valeur d'avant
  affichée à la borne (unitaires) ; les choix de délai sans leur plancher de
  48 px (e2e : 22 px).
- **Vérifié** : typecheck et lint propres, **1 599** tests unitaires ; e2e
  (pro, axe — `/pro/acompte` scanné pour la première fois —, cibles, reflow)
  **109** verts.
- **Hors de cette tranche** : dans l'app, un délai d'avant (72 h) ne coche
  aucun choix (rien ne le montre) ; seul l'ancien web pouvait en écrire un, et
  il n'y a pas encore de salon réel.
