# Web — le comparateur Avant/Après (drag-reveal) — design spec

| | |
|---|---|
| **Status** | Built |
| **Module** | `discovery` (page salon publique) — FR-DISC-006 |
| **Surface** | `web/components/provider/BeforeAfter.tsx` (+ nouvelle feuille cliente) |
| **Origin** | Demande propriétaire 2026-08-27 : « je veux que l'avant-après marche sur le web comme sur le mobile, où on peut glisser » — et la règle de parité : le web ne livre pas moins que l'app |
| **Mobile de référence** | `mobile/lib/widgets/providers/before_after_section.dart` (spec : [provider-before-after.md](provider-before-after.md) §6) |
| **Contract** | AUCUN changement — `beforeAfters` est déjà sur le fil |

## 1. Goal & scope

Le composant web actuel est une grille statique côte à côte dont la propre
docstring dit « drag-reveal slider deferred ». Le différé se termine : le
même geste que l'app — un curseur révèle l'avant sur l'après — plus ce que
le web peut faire de mieux que l'app (un vrai chemin clavier).

Hors scope : tout changement d'éditeur pro, tout changement serveur.

## 2. UX & interaction

### Le mécanisme (parité mobile, décisions pinnées)

- **Départ au centre (50 %)** — l'état que le SSR rend.
- L'image **après** est la base pleine largeur ; l'image **avant** est au-
  dessus, rognée depuis la gauche — `style={{clipPath: 'inset(0 X% 0 0)'}}`
  inline (les valeurs Tailwind arbitraires sont des erreurs de lint ; le
  style inline est le chemin sanctionné). Poignée : règle blanche 2px +
  pastille, positionnées par `style={{left}}` — **décoratives,
  `aria-hidden`**.
- **Le contrôle est un `<input type="range">` natif (0–100)**, transparent,
  plein cadre au-dessus de la pile. Pointeur, tactile, clic-saute-à-la-
  position et clavier (flèches) sont natifs — c'est le comportement absolu
  du slider mobile, sans ARIA artisanal ni `setPointerCapture`, et
  `jsx-a11y/strict` passe structurellement. (`role="slider"` sur div =
  repli seulement si la zone de frappe du pouce natif échoue quelque part.)
- `aria-label` français « Comparateur avant/après » ; la valeur est le %
  (le sémantisme du `Semantics(slider:)` mobile — value « NN % »).
- **Pastilles « Avant » / « Après »** aux coins bas — `aria-hidden`, le
  raisonnement `ExcludeSemantics` du mobile : le label du slider dit déjà
  avant/après, les pastilles ne doivent pas fuir dans son nom accessible.
- **Légende** sous le comparateur (`figcaption`), comme aujourd'hui.
- **Vignettes seulement si >1 paires** : boutons (image « après » 72×56),
  `aria-pressed`, bordure token sélectionnée — la bande du mobile.
- **Plein écran conservé (parité)** via un bouton explicite « Agrandir »
  → `Lightbox`/`Modal` (piège focus / Échap / restauration — WEB-SYSTEM §8,
  le contrat que `Modal.tsx` porte déjà). PAS de tap-sur-l'image : il se
  battrait avec le clic-saute-à-la-position du range.
- **Ligne d'aide** : « Glisser pour comparer » (la moitié « toucher pour
  agrandir » du mobile devient le bouton Agrandir, nommé).

### États

Aucune paire → la section ne rend rien (comportement actuel conservé).
Paire sans URL avant OU après → ignorée. Valeur bornée 0–100 (native).
Ratios d'images différents → conteneur à ratio fixe + `object-cover`
(les deux couches `next/image fill`, l'idiome actuel).

## 3. Architecture

`BeforeAfter.tsx` reste la coquille serveur (section + h2 + mapping) ; la
feuille **cliente** (`'use client'`) porte l'état — l'idiome frontière de
`Gallery.tsx`. Montage inchangé à `ProviderView.tsx`.

## 4. A11y (les portes qui lient)

`plugin:jsx-a11y/strict` en erreurs, zéro suppression ; l'e2e axe crawle
la page salon **sans exclusion de règle** — propre pour de vrai, pas
supprimé. Focus : anneau global `:focus-visible` (jamais `outline: none`),
ordre tab = ordre DOM.

## 5. Testing plan

RTL (`web/tests/before-after.test.tsx`) : valeur 50 au rendu ; flèches
droite/gauche bougent la valeur ; le `clip-path` inline suit la valeur ;
`aria-label` ; pastilles hors de l'arbre accessible ; vignettes seulement
si >1 + clic change de paire + `aria-pressed` ; « Agrandir » ouvre, Échap
ferme. E2E : `provider.spec.ts` (le figcaption « Avant » exact devient la
pastille + le rôle slider) ; axe. Mutations (~10) : départ à 0 ; clavier
perdu ; clip constant/mauvais côté ; `aria-label` retiré ; pastilles
exposées ; clic vignette inerte ; `aria-pressed` statique ; vignettes pour
une seule paire ; Échap inerte ; dérive de la ligne d'aide.

## 6. Definition of done

Gates web verts · axe vert · mutations rouges · vérifié au doigt et au
clavier sur la page déployée · ROADMAP entry · ce spec en Built.
