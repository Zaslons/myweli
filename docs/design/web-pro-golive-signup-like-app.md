# Web Pro — l'inscription et la mise en ligne comme l'app : l'adresse demandée, les huit étapes et leur progression — spec

| | |
|---|---|
| **Statut** | **Construit le 2026-10-20** sur `feat/web-pro-golive-signup-like-app` (au-dessus de #642) ; ce qui a été vu : §4. Validé le même jour — décisions du propriétaire : **l'adresse obligatoire sur le web aussi** ; **le web prend les huit étapes de l'app et sa barre** ; les deux vérifications de l'app alignées sur le serveur · **Mergé (#659) le 2026-10-20** — web en production à la fusion ; app au prochain build |
| **Owner** | Sadreddine |
| **Last updated** | 2026-10-20 |
| **PRD ref / phase** | Inscription Pro, mise en ligne (pro-salon-lifecycle, FR-PRO-ONB-001) · parité web ↔ app Pro · V1 |
| **Module** | web Pro — `ProRegisterClient`, `GoLiveCard`, `lib/pro/onboarding.ts` ; app Pro — `ProOnboardingProvider` |
| **Origine** | [parity-audit-web-pro-2026-10.md](parity-audit-web-pro-2026-10.md) §4 (P2) : « inscription : adresse obligatoire dans l'app, facultative sur le web » ; « la liste de mise en ligne : 6 étapes contre 8, sans barre ; GoLiveCard dit « mirrors the app » — faux » |
| **Dépend de** | #642 (la carte sans étape d'offre, l'inscription réécrite) — cette branche part de la sienne |
| **Skills checked** | myweli-web-guardrails ✓ · myweli-dev-guardrails ✓ · aucun changement serveur |

## 1. Le constat

- **Inscription** — l'app : « Adresse », obligatoire (« Indiquez l’adresse de
  l’entreprise. »), vérifiée avant Google, Apple et e-mail ; le web :
  « Adresse (optionnelle) ». La mise en ligne l'exige de toute façon.
- **Mise en ligne** — l'app : un écran de huit étapes (Profil de
  l’entreprise, Position sur la carte, Services (3 minimum), Équipe,
  Disponibilités, Acompte & annulation, Vérification (KYC), Photos (3
  minimum)), une barre et « N étapes sur T terminées » ; le bouton n'attend
  que les cinq que le serveur exige. Le web : une carte de cinq étapes, sans
  progression.
- **L'app se trompait sur deux étapes** par rapport au serveur qu'elle dit
  refléter : elle compte les services **inactifs** (le serveur : actifs
  seulement) et veut un créneau `isAvailable` (le serveur : un jour avec des
  horaires).

## 2. Le changement

- **Inscription web** : « Adresse » (sans « (optionnelle) »), obligatoire ;
  vide → sous le champ « Saisissez l’adresse de l’entreprise. » (le
  « Saisissez… » du formulaire web), vérifiée avec les autres champs avant
  tout envoi.
- **Carte de mise en ligne (web, brouillon)** : les huit étapes de l'app,
  dans son ordre et avec ses mots ; « Optionnel pour les indépendants »
  (équipe d'une entreprise « autre »), « Ajouter des photos du salon »,
  « En cours » (KYC envoyé, en attente) ; la barre (`role="progressbar"`,
  nommée par la ligne visible) et « N étapes sur T terminées » sur les étapes
  utiles (l'équipe optionnelle ne compte pas) ; chaque étape à faire garde son
  « Compléter » ; « Mettre en ligne » n'attend que les cinq du serveur ; sous
  le bouton, la phrase de l'app : « Complétez les étapes essentielles pour
  mettre votre profil en ligne. ». Acompte et KYC : une lecture chacun
  (`getDepositPolicy`, `getKycStatus`), comme l'app ; une lecture qui échoue
  laisse l'étape « à faire ».
- **App** : services actifs seulement ; un jour avec des horaires suffit.

Aucun mot nouveau.

## 3. Les tests (rouges d'abord)

Web : l'adresse (vide refusée sous le champ, plus de « (optionnelle) ») ; les
huit étapes, leurs liens, les cinq bloquantes, « En cours », l'indépendant, la
ligne de progression ; la carte. App : le service inactif, le jour aux
créneaux non disponibles. Les parcours d'inscription (unitaires et e2e)
remplissent l'adresse.

## 4. Construit — ce qui a été vu

- **Rouge d'abord** : web (l'adresse ; les huit étapes, leurs liens, les cinq
  bloquantes, « En cours », l'indépendant, la ligne ; la carte) ; app (le
  service inactif, le jour aux créneaux non disponibles — tous deux rouges
  pour la bonne raison).
- La barre est **nommée par la ligne visible** (`aria-labelledby`) : un nom
  propre (« Progression… ») aurait été un mot nouveau.
- `lib/format` gagne `pluralFr`, le jumeau de `Formatters.plural` (« 3 étapes
  sur 8 terminées » : le participe s'accorde avec un nombre qu'il n'écrit pas).
- Le parcours e2e de mise en ligne prouvait « la barrière est franchie » par
  « Au moins 3 prestations (N/3) » ; les mots de l'app n'ont pas de compte :
  une étape franchie est une ligne sans « Compléter ».
- **Mutations vues rouges** : toutes les étapes bloquantes, plus de
  « En cours », l'étape optionnelle comptée, l'adresse non vérifiée.
- **Vu dans le navigateur** (stub) : « 7 étapes sur 8 terminées », la barre,
  les huit lignes, la vérification à compléter, « Mettre en ligne » actif.
- **Vérifié** : web — typecheck et lint propres, **1 652** tests ; e2e
  (pro, axe, cibles, reflow, rôles) **121** verts ; app — analyse 0, tests de
  l'accompagnement et de l'écran verts.
