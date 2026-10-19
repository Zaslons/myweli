# Web Pro — « Continuer avec Apple » et « S’inscrire avec Apple » — spec

| | |
|---|---|
| **Statut** | **Construit le 2026-10-19** — aucun texte nouveau (les mots de l'app et du web client) ; aucun changement serveur |
| **Owner** | Sadreddine |
| **PRD ref / phase** | Authentification Pro (pro-auth-social) · parité web ↔ app · V1 |
| **Module** | web Pro — connexion (`ProLoginOptions`), inscription (`ProRegisterClient`), BFF `/api/pro/auth/apple` + `/api/pro/auth/register` |
| **Origine** | [parity-audit-web-pro-2026-10.md](parity-audit-web-pro-2026-10.md) §3 n° 3 (P1) |
| **Skills checked** | myweli-web-guardrails ✓ · myweli-dev-guardrails ✓ · backend lu seulement |

## 1. Le constat

- **L'app Pro** propose Apple à la connexion (« Continuer avec Apple ») et à
  l'inscription (« S’inscrire avec Apple »), sur iPhone
  (`pro_login_screen.dart:75-76,271-277`, `pro_register_screen.dart:78-79,398-403`).
- **Le web Pro** : Google et e-mail seulement. Un salon inscrit avec Apple sur
  son iPhone **ne peut pas ouvrir le web** — or c'est là qu'il choisit son
  offre.
- **Tout le reste existe** : `POST /auth/provider/apple` (connexion) et
  `/auth/provider/register` acceptent `identityToken` + `nonce` ; la
  production accepte le jeton web (`APPLE_CLIENT_IDS` contient
  `com.myweli.signin`, `infra/gcp/service.yaml`) ; le web **client** a déjà
  le bouton, le script Apple et le nonce (`LoginOptions.tsx`).
- Par contrat, la connexion Apple ne renvoie **jamais** d'invitations en
  attente (202) — l'app le note (`api_auth_service.dart`) ; pas d'étape
  « Invitations » à prévoir.

## 2. Le parcours

- **Connexion** : « Continuer avec Apple » sous Google (même bouton que le web
  client). Succès → le tableau de bord. Compte inconnu → la phrase et le lien
  « Créer mon compte » que Google affiche déjà. Échec → « Connexion Apple
  impossible. » (le web client). Fenêtre fermée → rien.
- **Inscription** : « S’inscrire avec Apple » (le mot de l'app) sous Google ;
  les champs du salon sont vérifiés **avant** d'ouvrir Apple (comme Google) ;
  puis l'inscription avec le jeton, et les erreurs que l'inscription connaît
  déjà (« Un compte existe déjà pour cette identité. Connectez-vous. »…).
- Les deux boutons n'apparaissent que si `NEXT_PUBLIC_APPLE_CLIENT_ID` est
  défini (la règle du web client).

## 3. Architecture

- `lib/auth/apple.ts` : le script Apple, le nonce, `appleIdentity(clientId)`
  → `{ identityToken, nonce, fullName? }` ou `null` (fermé / échec) —
  **partagé** : le web client l'utilise aussi (le même code, sorti de
  `LoginOptions`).
- `redirectURI` = `${origin}/connexion` pour les deux espaces : en mode
  popup, Apple exige une adresse **enregistrée** pour le Services ID, et
  celle du web client l'est déjà — pas de changement dans la console Apple.
- `loginProWithApple`, BFF `/api/pro/auth/apple` ; le BFF d'inscription
  accepte `identityToken`.

## 4. Non vérifié — à confirmer par le propriétaire

- Que `NEXT_PUBLIC_APPLE_CLIENT_ID` est défini sur Vercel (sinon aucun bouton
  Apple, ni client ni Pro) et vaut `com.myweli.signin`.
- Qu'Apple accepte la popup depuis `/pro/connexion` avec cette adresse de
  retour (elle est celle du web client ; à essayer en production).
