# Lot 8 : les questions produit — l'annulation, le téléphone du compte Pro, Profil hors ligne, le libellé V2, la connexion par téléphone, la suppression — spec

| | |
|---|---|
| **Statut** | **Validé le 2026-10-22** — relu sur main (`0a92503d`). Les six recommandations : Q1 **garder la confirmation** ; Q2 **rien maintenant** ; Q3 **une petite copie hors ligne** ; Q4 **« Total réalisé »** ; Q5 **retirer la connexion Pro par téléphone** ; Q6 **accepter, et le test de la relance**. Deux PR (§3) ; la première demande un déploiement du serveur. |
| **Owner** | Sadreddine |
| **Last updated** | 2026-10-22 |
| **PRD ref / phase** | V1 — comptes et accès (Pro), retours d'action (SYSTEM.md §15), hors ligne (§12), V2 (analyses) |
| **Module** | selon les réponses : `backend/` (B8.5, B8.6), `mobile/` (B8.3, B8.4, B8.5), `web/` (B8.5) ; B8.1 et B8.2 ne construisent rien si la recommandation est suivie |
| **Origine** | [BACKLOG.md](../BACKLOG.md) lot 8 : B8.1–B8.6 (décisions 27–32) |
| **Skills checked** | myweli-dev-guardrails ✓ · myweli-backend-guardrails ✓ · myweli-web-guardrails ✓ |

## 1. Le constat — relu sur le vrai chemin de code (main `0a92503d`)

Les six points sont **réels**. Trois ont besoin d'une correction par rapport
au BACKLOG :
- **B8.2** : le téléphone du compte Pro **n'est plus un identifiant de
  connexion** depuis la migration 0023 ; son unicité a été retirée. Le
  « 409 sur un numéro pris par un autre compte » n'a donc rien à protéger.
- **B8.5** : c'est **plus grave** qu'annoncé. La connexion Pro par téléphone
  s'ouvre avec le même interrupteur que celle des clients, et elle prend le
  premier compte qui porte le numéro.
- **B8.6** : la moitié « dire « réessayez » après une 5xx » est déjà vraie,
  dans l'app comme sur le web. Il ne manque que le test de la relance.

| # | Ce qui est vrai aujourd'hui | Où |
|---|---|---|
| B8.1 | Les trois actions sont confirmées, puis immédiates : « Annuler le rendez-vous ? » (client), « Révoquer l'accès ? » (équipe), « SUPPRIMER » à taper (compte). C'est l'échelle de SYSTEM §15 : réversible → tout de suite, avec « Annuler » dans le bandeau ; difficile à défaire → confirmation ; irréversible → mot à taper. Les pages publiques promettent une suppression « immédiate et définitive » | `screens/appointments/appointment_detail_screen.dart:105` ; `screens/provider/team/team_screen.dart:458` ; `pro_profile_screen.dart:389` ; `web/app/suppression-compte/page.tsx:36` ; SYSTEM §15 |
| B8.2 | Le téléphone du compte est **une copie faite à l'inscription**. Il n'est affiché ni modifiable nulle part. Il sert à trois choses : pré-remplir le téléphone d'« Ajouter un salon » (modifiable dans ce formulaire), la section `account` de l'export, et la connexion par téléphone en sommeil. Le numéro que les clients voient est celui **du salon**, modifiable dans « Profil du salon ». Depuis 0023 (`pro-auth-social`), l'identité Pro est l'e-mail vérifié, Google ou Apple : la contrainte `provider_users_phone_number_key` a été retirée | `backend/lib/src/db/migrations.dart:552-566` ; `add_salon_screen.dart:67` ; `web/components/pro/AddSalonClient.tsx:76` ; `core/utils/data_export.dart` |
| B8.3 | Hors ligne au démarrage, la carte du salon dans Profil montre le nom (gardé avec l'adhésion), puis « Les informations du salon n'ont pas pu être chargées. Vérifiez votre connexion. » et « Réessayer ». L'adhésion et le marché sont gardés dans la session ; la fiche du salon ne l'est pas | `pro_profile_screen.dart:437-570` ; `providers/pro_auth_provider.dart:112-123` |
| B8.4 | L'écran V2 « Rapports » dit « Revenus ce mois », sur des chiffres écrits à la main. Il n'est pas routé et reste caché derrière `FeatureFlags.futureProviderFeatures`. Aujourd'hui, « Revenus prévus » (Accueil) compte les confirmés et les terminés ; « Total réalisé » (écran Revenus) compte les terminés. **Il n'existe aucune liste « avant d'activer la V2 »** où écrire le choix | `screens/provider/features/reports_analytics_screen.dart:15, 45` ; `earnings_screen.dart:191` ; `LAUNCH.md` §1.5 |
| B8.5 | **App** : `/pro/verify-otp` n'est pas routé ; `ProAuthProvider.verifyOtp` pose le compte et le push, **sans** relire l'adhésion ni « Mes salons », alors que toutes les autres connexions passent par `_login`, qui fait les deux. **Web** : deux routes BFF et deux fonctions (`requestOtpPro`, `verifyOtpPro`), utilisées par aucun écran. **Serveur** : les routes Pro `otp/request` et `otp/verify` s'ouvrent avec **le même interrupteur `AUTH_METHODS` que celles des clients** ; et `verify` lit `SELECT * FROM provider_users WHERE phone_number = @p`, **sans unicité depuis 0023**. Le jour où l'on ajoute `phone` pour les clients (le retour du SMS), la connexion Pro par téléphone s'ouvre aussi, et un code envoyé à un numéro partagé par deux comptes ouvre le premier que la base rend | `pro_router.dart:71-73` ; `pro_auth_provider.dart:801-826, 845-870` ; `web/app/api/pro/auth/{request-otp,verify}/route.ts` ; `web/lib/api/pro.ts:91-115` ; `backend/routes/auth/provider/otp/*.dart:14-18` ; `postgres_provider_auth_repository.dart:433-436` |
| B8.6 | La suppression d'un compte Pro est une **suite d'étapes rejouables**, pas une transaction : salons dépubliés et coordonnées effacées, reconstruction du site, fichiers KYC, appareils, notifications, réponses gardées, jeton Apple, puis l'identité (et ses lignes d'équipe, dans la même transaction). Un test Postgres prouve qu'un échec à l'identité garde les lignes d'équipe. **Aucun test** ne prouve qu'une relance termine la suppression. Après une 5xx, le web dit « La suppression a échoué. Réessayez. » et l'app « Une erreur est survenue. Réessayez. » | `backend/lib/src/provider_account_service.dart:77-196` ; `test/db/postgres_repositories_test.dart:2658` ; `web/components/pro/CompteDangerSection.tsx:26-35` ; `pro_profile_screen.dart:393-406` |

## 2. Les options, question par question

### 2.1 L'annulation des actions destructrices (B8.1, décision 27)
- **A — Garder la confirmation (recommandé).**
  - L'échelle de SYSTEM §15 place déjà ces trois actions au bon barreau.
  - Rien à construire.
- **B — Un « Annuler » de 10 s, et un délai de grâce pour la suppression.**
  - **Le serveur** : un état « en attente » pour l'annulation d'un
    rendez-vous et la révocation. Le créneau, la notification au client et
    la perte d'accès du membre attendent la fin de la fenêtre.
  - **La suppression** : un effacement différé (par exemple 30 jours), une
    reconnexion qui l'arrête, une purge planifiée.
  - **Les textes** : réécrire « immédiate et définitive » (page de
    suppression, politique, fiches des stores).
  - **Coût** : grand (L) — plusieurs PR, des migrations, des déploiements.

### 2.2 Le téléphone du compte Pro (B8.2, décision 28)
- **A — Rien maintenant ; décider avec le retour de la connexion par
  téléphone (recommandé).** Le numéro n'est lu par personne qui en souffre :
  le pré-remplissage se corrige dans le formulaire, et les clients voient le
  numéro du salon.
- **B — Un numéro de contact modifiable dès maintenant.**
  - `PATCH /me/provider/account/phone`, validé, avec un journal qui ne garde
    que les identifiants.
  - Une ligne « Téléphone du compte » dans Profil, app et web.
  - **Pas de 409** : le numéro n'est plus unique.
  - **Coût** : moyen (M), un déploiement.

### 2.3 La carte du salon hors ligne (B8.3, décision 29)
- **A — Garder une petite copie hors ligne (recommandé).**
  - Le nom, la catégorie, l'adresse, le téléphone : ce que la carte montre,
    rien de plus.
  - Rangée avec l'adhésion et le marché, aux mêmes moments ; remplacée à
    chaque lecture réussie et à chaque changement de salon ; effacée à la
    déconnexion et à la suppression du compte.
  - Ce sont des données publiques du salon (sa fiche).
  - **Coût** : petit (S), app seulement.
- **B — Garder « n'ont pas pu être chargées » et « Réessayer ».** Rien à
  construire.

### 2.4 Le libellé du graphique V2 (B8.4, décision 30)
- **A — « Total réalisé » (recommandé)** : un historique compte ce qui a été
  fait. C'est le mot de l'écran Revenus.
- **B — « Revenus prévus »** : le mot d'Accueil, qui compte aussi les
  confirmés à venir.
- **Dans les deux cas, rien ne se construit maintenant.** Le choix s'écrit :
  - dans une nouvelle liste « Avant d'activer `futureProviderFeatures` »,
    en LAUNCH §1.5 ;
  - et en commentaire sur l'écran V2.

### 2.5 La connexion Pro par téléphone en sommeil (B8.5, décision 31)
- **A — La retirer maintenant, et la reconstruire exprès au retour du SMS
  (recommandé).**
  - **Serveur** : les deux routes Pro, leurs méthodes de dépôt et le contrat.
  - **Web** : les deux routes BFF et les deux fonctions.
  - **App** : l'écran non routé et les méthodes du fournisseur et du
    service.
  - Les routes **clients** ne changent pas.
  - La reconstruction devra trancher l'identité : l'unicité du numéro, ou un
    choix de compte. Elle se fera avec B8.2.
  - **Coût** : moyen (M), **un déploiement du serveur**.
- **B — La garder, mais sur son propre interrupteur, éteint.** Ouvrir le SMS
  aux clients n'ouvre plus les Pro. Réparer et router au retour du SMS.
  - **Coût** : petit (S), un déploiement.
- **C — Ne rien toucher jusqu'au retour du SMS** (ce que proposait le
  BACKLOG). Le piège reste armé : le jour où l'on ajoute `phone` pour les
  clients, il s'ouvre.

### 2.6 La suppression Pro non atomique (B8.6, décision 32)
- **A — Accepter l'ordre rejouable, et ajouter le test de la relance
  (recommandé).**
  - **Le test** (Postgres) : un échec à l'identité, puis une relance, qui
    finit avec tout effacé.
  - **Coût** : petit (S), un test seulement. Les phrases « Réessayez » sont
    déjà là.
- **B — Une atomicité complète.** Les fichiers KYC vivent hors de la base :
  il faudrait une file de tâches et une reprise.
  - **Coût** : grand (L).

## 3. Ce qui se construit si les recommandations sont suivies

**Deux PR.** La première demande un déploiement du serveur, que tu
approuves.

- **(A) « Fermer la connexion Pro par téléphone »** : B8.5 (A) et B8.6 (A).
  - Serveur, contrat, web et app.
  - **Un déploiement.**
- **(B) « Profil hors ligne, et le mot de la V2 »** : B8.3 (A) et B8.4.
  - App, et LAUNCH.md.
- **B8.1 et B8.2** : rien ; leurs réponses s'écrivent dans le BACKLOG.

## 4. Le contrat

- **B8.5 (A)** : `/auth/provider/otp/request` et `/auth/provider/otp/verify`
  sortent du contrat. `web/lib/api/schema.ts` est régénéré.
- **Rien d'autre** si les recommandations sont suivies.

## 5. La sécurité

- **B8.5** : le piège du §1 (un numéro partagé ouvre le premier compte) est
  noté dans le modèle de menaces (BACKEND.md §7), fermé par (A) ou (B).
- **B8.3** : la copie hors ligne ne garde que des données publiques. Elle est
  rangée dans le stockage sécurisé, avec la session, et effacée avec elle.

## 6. Les tests (rouges d'abord)

- **B8.5 (A)** :
  - **serveur** : les deux routes Pro répondent 404 **même avec `phone`
    dans `AUTH_METHODS`** ;
  - **serveur** : les routes clients s'ouvrent toujours avec `phone`
    (contrôle) ;
  - **un test de source** : aucun appel à `otp/request` ou `otp/verify` côté
    Pro, dans l'app comme sur le web.
- **B8.6** : la relance après un échec à l'identité finit tout effacé
  (Postgres, et le double en mémoire).
- **B8.3** :
  - hors ligne au démarrage, la carte montre la copie, sans « Réessayer » ;
  - la copie est remplacée par une lecture réussie ;
  - elle est effacée à la déconnexion, et changée avec le salon ;
  - sans copie, le comportement d'aujourd'hui.
- **Les mutations** sur le travail enregistré, comme toujours.

## 7. Les mots

- **B8.3** : rien de nouveau. La carte hors ligne montre les faits gardés,
  comme en ligne.
- **B8.4 (A)** : « Total réalisé ».

## 8. Questions au propriétaire

- **Q1 (décision 27)** — L'annulation : **garder la confirmation**
  (recommandé), ou des états « en attente » côté serveur et un délai de
  grâce pour la suppression ?
- **Q2 (décision 28)** — Le téléphone du compte Pro : **rien maintenant,
  décider avec le retour de la connexion par téléphone** (recommandé), ou un
  numéro de contact modifiable dès maintenant ?
- **Q3 (décision 29)** — La carte du salon hors ligne : **une petite copie
  hors ligne** (recommandé), ou garder « Réessayer » ?
- **Q4 (décision 30)** — Le graphique V2 : **« Total réalisé »**
  (recommandé), ou « Revenus prévus » ?
- **Q5 (décision 31)** — La connexion Pro par téléphone : **la retirer
  maintenant** (recommandé), la mettre sur son propre interrupteur éteint,
  ou ne rien toucher ?
- **Q6 (décision 32)** — La suppression Pro : **accepter l'ordre rejouable
  et ajouter le test de la relance** (recommandé), ou une atomicité
  complète ?

**Décisions (2026-10-22).** Q1 à Q6 : les recommandations, telles
qu'écrites.
