# Web — un salon trouve et ouvre son Espace Pro — spec

| | |
|---|---|
| **Statut** | **Construit le 2026-10-19** (branche `feat/web-pro-access`, empilée sur `feat/web-pro-notifications`) — les portes P1–P4, **pas de prix**, le texte des §3–§5 tel qu'écrit ; §11 dit ce qui a été vu rouge · web au merge, la ligne backend au prochain déploiement du serveur |
| **Owner** | Sadreddine |
| **Last updated** | 2026-10-19 |
| **PRD ref / phase** | Acquisition salon (web) · la voie compagnon : l'offre se choisit **sur le web** ([pro-companion-path.md](pro-companion-path.md)) · V1 |
| **Module** | web public (en-tête, pied de page, accueil, nouvelle page `/professionnels`), web Pro (connexion, inscription) ; backend : un slug réservé |
| **ROADMAP entry** | [2026-10-19-web-pro-access.md](../roadmap/entries/2026-10-19-web-pro-access.md) |
| **Skills checked** | myweli-web-guardrails ✓ · myweli-dev-guardrails ✓ · myweli-backend-guardrails ✓ (une ligne : `reservedPublicSlugs`) |

## 1. Le constat — relu sur `main`

1. **Aucune porte.** L'en-tête public (`Header.tsx`) : logo, cloche, « Mon
   compte ». Le pied de page : documents légaux, réseaux sociaux. L'accueil :
   rien pour les salons. `grep` de `/pro` hors du tableau de bord : **aucun
   lien**. Un salon doit *deviner* `myweli.com/pro`.
2. **Et il en a besoin plus qu'ailleurs** : depuis la voie compagnon (App Store
   3.1.3(f), les deux stores), **l'app Pro ne vend rien** — l'offre se choisit
   **uniquement** sur le web. Le web est le seul chemin d'achat, et il n'a pas
   d'entrée.
3. **Les pages de connexion et d'inscription Pro sont des impasses** :
   `SiteChrome` se cache sur tout chemin qui *commence* par `/pro`, donc
   `/pro/connexion` et `/pro/inscription` n'ont ni logo ni lien vers le site.
   (Et ce test de préfixe cacherait aussi l'en-tête d'une future page
   `/professionnels` — il faut le resserrer.)
4. **Rien n'explique MyWeli Pro** à un salon qui ne le connaît pas : pas de
   page « pour les salons », donc rien à indexer pour « logiciel de
   réservation salon de coiffure Abidjan ».
5. **Droit — le consentement manque côté Pro** : l'inscription Pro de **l'app**
   affiche « En créant votre compte professionnel, vous acceptez nos
   Conditions d’utilisation et notre Politique de confidentialité » (liens) ;
   celle **du web** n'affiche **rien**, alors que le salon est la partie qui
   contracte avec nous et téléverse des pièces d'identité. Le web client dit
   « En continuant, vous acceptez nos conditions d’utilisation. » **sans lien**
   et sans la politique de confidentialité.

## 2. Les règles suivies

- **Lois de l'UX** : *Jakob* — les concurrents placent l'entrée pro en haut à
  droite (« Vous êtes un professionnel ? » / « Pour les pros ») : on fait
  pareil ; *Hick* — deux choix, pas plus : « Inscrire mon salon » / « Se
  connecter » ; *Fitts* — cibles ≥ 48 px, l'action principale la plus grande ;
  *Miller* — six avantages au plus, en blocs ; *von Restorff* — un seul bouton
  plein par écran ; *esthétique-utilisabilité* — l'identité de la marque, pas
  un gabarit SaaS.
- **Accessibilité (WCAG 2.2 AA)** : repères `header/nav/main/footer`, un seul
  `h1`, ordre des titres, focus visible, contraste, reflow 320 px, texte 200 %.
- **Droit** : *publicité véridique* — chaque avantage annoncé existe aujourd'hui
  (la règle de [promise-honesty-sweep.md](promise-honesty-sweep.md), tenue par
  son épingle) ; *consentement* — CGU + politique de confidentialité **liées**
  avant toute création de compte ; *données personnelles* — rien de nouveau
  collecté, aucun traceur (la politique publiée le dit).
- **SEO / AEO / GEO** (WEB-SYSTEM §12) : la page `/professionnels` est
  indexable, rendue côté serveur, avec `title`/meta/canonical/OG, une FAQ
  `FAQPage` en JSON-LD, dans le sitemap et `llms.txt`.

## 3. Les portes

| # | Où | Quoi |
|---|---|---|
| **P1** | **En-tête**, à droite, avant la cloche et « Mon compte » | Lien **« Espace pro »** → `/professionnels`. Visible à partir de 640 px : à 320–375 px, logo + « Espace pro » + cloche + « Mon compte » ne tiennent pas sur une ligne (mesuré au build) ; les téléphones ont P2 et P3 |
| **P2** | **Pied de page**, un groupe « Professionnels » au-dessus des liens légaux | « MyWeli Pro pour les salons » → `/professionnels` · « Inscrire mon salon » → `/pro/inscription` · « Connexion Espace pro » → `/pro/connexion` |
| **P3** | **Accueil**, une bande avant la FAQ | « **Vous êtes un salon ?** » · « Recevez vos réservations en ligne, 24 h/24, et gérez agenda, équipe et clientèle au même endroit. » · bouton secondaire « Découvrir MyWeli Pro » → `/professionnels` |
| **P4** | **`/pro/connexion`, `/pro/inscription`** | Un en-tête minimal : le logo MyWeli (→ `/`) et « Espace pro » ; pas la cloche ni « Mon compte » du client (deux espaces différents, une seule session à la fois à l'écran) |

## 4. La page `/professionnels`

Rendue côté serveur, statique, sans JS propre. Une seule action pleine.

1. **En-tête de page (h1)** : « **Le logiciel de réservation des salons de
   beauté en Côte d’Ivoire** » · sous-titre « Recevez des réservations en
   ligne 24 h/24, et gérez agenda, équipe, clientèle et acomptes au même
   endroit. » · **« Inscrire mon salon »** (plein) · « J’ai déjà un compte »
   (secondaire → `/pro/connexion`) · ligne « 3 mois offerts — sans carte
   bancaire. » *(vrai : l'essai démarre à la première mise en ligne, aucun
   moyen de paiement n'est demandé)*.
2. **Six avantages** (h2 « Tout ce qu’il faut pour votre salon ») — le texte
   des fiches de store, déjà validé et vrai :
   - **Votre agenda, tenu tout seul** — Les clients réservent sur vos créneaux
     réels ; vous ajoutez les rendez-vous pris au téléphone ou au comptoir.
     Vue journée, semaine, et par membre d’équipe.
   - **Votre vitrine sur myweli.com** — Photos, avant/après, logo, prestations
     et tarifs, horaires : votre page publique se remplit en quelques minutes.
   - **Votre clientèle, enregistrée d’elle-même** — Chaque réservation crée ou
     retrouve la fiche client : historique, notes, étiquettes.
   - **Vos acomptes, sans intermédiaire** — Le client paie l’acompte sur votre
     Mobile Money et joint sa preuve ; vous confirmez. MyWeli ne touche jamais
     vos fonds.
   - **Moins de rendez-vous manqués** — Rappels automatiques à vos clients
     dans l’app MyWeli (24 h et 2 h avant), et règles d’acompte.
   - **Votre équipe** — Invitez manager, réception et collaborateurs, chacun
     avec les accès de son rôle.
3. **Comment ça marche** (h2, trois étapes) : « Créez votre compte » ·
   « Ajoutez vos prestations, vos horaires et vos photos » · « Mettez votre
   salon en ligne — vos 3 mois offerts commencent ».
4. ~~Les offres~~ — **pas de section prix (décision du 2026-10-19)** : les
   offres et leurs prix restent derrière l'inscription (`/pro/abonnement`),
   comme aujourd'hui ; la page dit « 3 mois offerts — sans carte bancaire. »
5. **Questions fréquentes** (h2, `FAQPage`) :
   - « Combien coûte MyWeli Pro ? » → « Vos 3 premiers mois sont offerts,
     sans carte bancaire. Vous choisissez ensuite, depuis votre Espace Pro,
     l’offre adaptée à votre salon : la taille de votre équipe, le nombre de
     salons. »
   - « Mes clients paient-ils en ligne ? » → « Non. L’acompte éventuel est
     envoyé par Mobile Money directement sur votre numéro ; MyWeli ne prélève
     rien. »
   - « Faut-il installer une application ? » → « Non : tout se gère depuis
     myweli.com, sur ordinateur comme sur téléphone. » *(L'app MyWeli Pro n'est
     pas encore dans les stores et le web n'a pas d'adresse de store Pro — elle
     n'est nommée nulle part tant qu'on ne peut pas la télécharger.)*
   - « Puis-je gérer plusieurs salons ? » → « Oui, avec l’offre Réseau :
     chaque salon a sa propre offre et son propre essai. »
6. **Bande finale** : « Prêt à recevoir vos premières réservations ? » ·
   « Inscrire mon salon ».

**Métadonnées** : `title` « MyWeli Pro — logiciel de réservation pour salons
de beauté en Côte d’Ivoire » ; description (≤ 160) ; canonical ; OG ; JSON-LD
`FAQPage` + l'`Organization` existante. Ajoutée au **sitemap** et à
`llms.txt` (« For salons: /professionnels »).

## 5. Le consentement (droit)

Un composant web `LegalConsentText` — jumeau de celui de l'app : « {début},
vous acceptez nos [Conditions d’utilisation](/cgu) et notre [Politique de
confidentialité](/politique-confidentialite). » (liens soulignés, ≥ 48 px de
hauteur de ligne cliquable).

- **Inscription Pro** : « En créant votre compte professionnel, … » — au-dessus
  du premier moyen de création, visible sans défiler (la règle de l'app).
- **Connexion Pro** : « En continuant, … » (Google crée un compte en un geste).
- **Connexion client** : la phrase actuelle, sans lien, devient la même phrase
  liée — même composant.

## 6. Architecture

- `SiteChrome` : se cache sur `/pro` et `/pro/…`, plus sur `/professionnels`
  (test de préfixe resserré) ; sur `/pro/connexion` et `/pro/inscription`, un
  `ProAuthHeader` minimal (P4).
- `app/professionnels/page.tsx` — composant serveur ; le texte vient d'un
  module (`lib/pro/landing.ts`) pour que l'épingle d'honnêteté le lise.
- **Backend** : `'professionnels'` rejoint `reservedPublicSlugs`
  (`backend/lib/src/slug.dart`) — sinon un salon nommé « Professionnels »
  prendrait l'adresse et serait masqué par la route statique (le défaut que ce
  set existe pour empêcher). **À vérifier avant déploiement** : aucun salon en
  production n'a déjà ce slug.

## 7. États

Page statique : pas de chargement ni d'erreur propres. Les liens mènent à des
pages qui ont les leurs. Un salon **déjà connecté** qui ouvre `/professionnels`
voit la page ; « J’ai déjà un compte » mène à `/pro/connexion`, **qui
aujourd'hui ne redirige pas une session valide** (relu :
`ProConnexionClient` ne redirige qu'après une connexion réussie). Ajout :
la page de connexion lit `/api/pro/me` au montage et envoie une session valide
sur `/pro` — un salon connecté ne se reconnecte jamais pour rien.

## 8. Tests (rouges d'abord)

- RTL : l'en-tête porte « Espace pro » (et pas sur `/pro/…`) ; le pied de page,
  ses trois liens ; la bande de l'accueil ; `ProAuthHeader` sur
  connexion/inscription ; `LegalConsentText` sur les trois écrans, liens vers
  `/cgu` et `/politique-confidentialite`.
- La page : un `h1`, l'ordre des titres, les deux appels à l'action, le
  JSON-LD `FAQPage` valide, présente dans le sitemap.
- `SiteChrome` : visible sur `/professionnels`, cachée sur `/pro` et `/pro/x`.
- Épingle d'honnêteté : `lib/pro/landing.ts` est dans son champ (il l'est :
  `lib/`).
- Backend : `isReservedSlug('professionnels')`.
- e2e : la page dans axe + la matrice de reflow (320/375/1280) ; Lighthouse
  (page publique).

## 9. Déploiement

Web au merge (Vercel). La ligne backend part avec le prochain déploiement du
serveur (décision du propriétaire) ; avant cela, un salon pourrait encore
prendre le slug — risque faible, vérifié au §6.

## 10. Décisions à valider

1. Les portes P1–P4 (recommandé : les quatre).
2. **Les prix sur la page publique** : afficher les offres et leurs prix
   d'ancrage, ou « 3 mois offerts » sans prix.
3. Le texte des §3, §4 et §5.

## 11. Ce qui a été vu rouge

- Tests commités **avant** le code (`730c7326`) : RTL (les portes, la
  chrome par route, le groupe du pied de page, la bande, le consentement sur
  trois écrans, la redirection d'une session valide), la page
  `/professionnels` (un `h1`, les deux actions, six avantages, la FAQ et son
  `FAQPage`, **aucun prix**, les métadonnées), le sitemap ; backend : un
  salon « Professionnels » prenait `/professionnels`.
- **Une garde de plus que le spec** : un test backend tient **chaque route
  de premier niveau de `web/app`** dans `reservedPublicSlugs` — une page
  ajoutée sans sa réservation casse la CI, plus seulement celle-ci. Vu
  échouer en retirant `'professionnels'` (deux rouges), restauré.
- **L'épingle d'honnêteté lit la page** : son texte vit dans
  `lib/pro/landing.ts`, dans son champ (`lib/`).
- Trouvé en regardant à 375 px : « 24 h/24 » se coupait en « 24 / h/24 » —
  espace insécable dans la bande et le sous-titre (et un premier essai
  `\u00a0` dans du texte JSX aurait imprimé la séquence telle quelle :
  `&nbsp;` à cet endroit).
- **La matrice de reflow a parlé, et c'était le contrôle qui se trompait** :
  la première fois que `/pro/inscription` y est entré, « 2 items need 40 of
  38 » sur le sélecteur de pays du téléphone, à 320 et 375 px. Mesuré dans le
  navigateur plutôt que supposé : la flèche est un carré de 5 px tourné de
  45° — 6,8 px **peints**, 1 px dans un padding de 8 px, rien de coupé ; la
  mise en page tient exactement. `overflowingFlexRows` mesurait la boîte
  **transformée** (`getBoundingClientRect`) ; une transformation ne fait pas
  déborder une rangée flex. Le contrôle prend désormais la largeur de **mise
  en page** d'un enfant transformé — et attrape toujours un vrai débordement
  avec un enfant tourné (vérifié : 124 pour 100). Un premier essai
  `flex-shrink: 0` côté CSS ne changeait rien et a été retiré.
- Vérifié ici : typecheck, lint, **toute la suite unitaire web verte
  (1 641)**, backend analyse 0 et `multi_pays_test` vert ; dans le navigateur
  à 1280 et 375 px : la page, la bande, le pied de page, l'en-tête minimal et
  le consentement sur `/pro/inscription`, aucun défilement horizontal.

**Non vérifié** : Lighthouse sur `/professionnels` (la CI le lance) ; qu'aucun
salon en production n'ait déjà le slug `professionnels` (requête à faire
avant le déploiement du serveur — §6).

