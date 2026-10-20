# Web Pro — le Profil comme l'app : liens selon le rôle, « Aide & Support », deux lignes d'offre au plus juste — spec

| | |
|---|---|
| **Statut** | **Construit le 2026-10-20** sur `fix/web-pro-profil-support` (au-dessus de #642) ; ce qui a été vu : §4. Validé le même jour — « Statistiques & avis clients » ; « Support prioritaire » ; « Aide & Support » — « Nous écrire » pour tous, vers `/support`, et les liens du Profil filtrés par rôle comme dans l'app · **Mergé (#655) le 2026-10-20** — web en production à la fusion |
| **Owner** | Sadreddine |
| **Last updated** | 2026-10-20 |
| **PRD ref / phase** | Accès d'équipe (R5b) · parité web ↔ app Pro · offres (companion path) · V1 |
| **Module** | web Pro — `ProfilClient` (vue complète et vue réduite), `lib/pro/subscription-plans.ts` |
| **Origine** | [parity-audit-web-pro-2026-10.md](parity-audit-web-pro-2026-10.md) §2 (« Statistiques & **gestion** des avis », « Support prioritaire **dédié** » sans aucune entrée d'aide) et §4 (P2 : liens montrés à un Manager qui n'y a pas droit ; aucune aide/support) |
| **Dépend de** | #642 (les lignes d'offre y ont été réécrites) — cette branche part de la sienne |
| **Skills checked** | myweli-web-guardrails ✓ · myweli-dev-guardrails ✓ · aucun changement serveur |

## 1. Le constat

- **L'app** (`pro_profile_screen.dart`) filtre chaque lien par capacité :
  Vérification (`salon.publish`), Abonnement (`subscription.manage`), Acompte
  (`deposit.manage`), Photos / Avant-Après (`catalogue.manage`) ; et propose à
  **tous** « Aide & Support » — « Nous écrire », vers
  `AppConfig.supportUrl` = `myweli.com/support`.
- **Le web** montre Vérification, Acompte, Abonnement et Photos à tout membre
  qui voit le Profil complet — un **Manager** (`profile.manage` sans les
  capacités du propriétaire) ouvre des pages qui le refusent. Aucune entrée
  d'aide, nulle part dans l'Espace Pro.
- **L'offre** (web seul — l'app ne vend pas) promet « Statistiques &
  **gestion** des avis » (les avis sont en lecture seule, web et app) et
  « Support prioritaire **dédié** » (Business).
- « Choisissez votre offre pour inviter votre équipe » (Équipe), relu : le
  serveur exige une offre vivante pour inviter (`offer_required`) et choisir
  une offre démarre l'essai — **la phrase est vraie**, elle reste.

## 2. Le changement

- Profil complet : chaque lien n'apparaît qu'avec sa capacité (celles de
  l'app) ; « Aide & Support » — « Nous écrire » en dernier, pour tous, vers
  `/support`.
- Profil réduit (Réception, Collaborateur) : « Aide & Support » aussi.
- Offre Pro : « Statistiques & avis clients ». Offre Business : « Support
  prioritaire ».

## 3. Les tests (rouges d'abord)

Les liens par rôle (propriétaire, Manager), « Aide & Support » et ses mots
dans les deux vues ; les deux lignes d'offre, et aucune ne dit plus
« gestion des avis » ni « dédié ».

## 4. Construit — ce qui a été vu

- **Rouge d'abord** : 5 tests (les liens par rôle, « Aide & Support » dans
  les deux vues, les deux lignes d'offre).
- **Mutations vues rouges** : Acompte pour tout Profil complet, la vue
  réduite sans « Aide & Support », l'ancienne ligne « gestion des avis ».
- **Vérifié** : typecheck et lint propres, **1 648** tests unitaires ; e2e
  (pro, rôles, axe, cibles, accueil) **55** verts.
